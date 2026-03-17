import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_event.dart';
import '../services/jarvis_brain_service.dart';
import '../widgets/glass.dart';

class ContaminationOverlay extends StatefulWidget {
  final Subject subject;
  final StudyTopic topic;

  const ContaminationOverlay({
    super.key,
    required this.subject,
    required this.topic,
  });

  @override
  State<ContaminationOverlay> createState() => _ContaminationOverlayState();
}

class _ContaminationOverlayState extends State<ContaminationOverlay> {
  bool _loading = true;
  List<String> _questions = [];
  int _currentQ = 0;
  final List<String> _answers = [];
  final TextEditingController _answerCtrl = TextEditingController();

  bool _grading = false;
  Map<String, dynamic>? _result;

  int _timeLeft = 120;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final qs = await JarvisBrainService.generateContaminationQuestions(
      widget.subject.name,
      widget.topic.title,
    );
    if (!mounted) return;
    setState(() {
      _questions = qs.take(3).toList();
      while (_questions.length < 3) {
        _questions.add(
          "Fallback question " + (_questions.length + 1).toString(),
        );
      }
      _loading = false;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          t.cancel();
          if (!_grading && _result == null) _submitAnswers();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answerCtrl.dispose();
    super.dispose();
  }

  void _nextQuestion() {
    final ans = _answerCtrl.text.trim();
    if (ans.isEmpty) return;

    _answers.add(ans);
    _answerCtrl.clear();

    if (_currentQ < _questions.length - 1) {
      setState(() {
        _currentQ++;
      });
    } else {
      _submitAnswers();
    }
  }

  Future<void> _submitAnswers() async {
    _timer?.cancel();
    setState(() {
      _grading = true;
    });

    final res = await JarvisBrainService.gradeContaminationAnswers(
      widget.subject.name,
      widget.topic.title,
      _questions,
      _answers,
    );

    if (!mounted) return;

    if (res['passed'] == false) {
      // Violent shatter: drop mastery stage to 3
      context.read<AppBloc>().add(UpdateTopic(widget.topic.copyWith(stage: 3)));
    }

    setState(() {
      _grading = false;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orangeAccent,
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'CONCEPT CONTAMINATION',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Topic: ${widget.topic.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),

              if (_loading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Colors.orangeAccent),
                    SizedBox(height: 16),
                    Text(
                      'NOVA is formulating trap questions...',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                )
              else if (_grading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Colors.orangeAccent),
                    SizedBox(height: 16),
                    Text(
                      'Strictly evaluating your understanding...',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                )
              else if (_result != null)
                _buildResultView()
              else
                _buildQuestionView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionView() {
    final mins = (_timeLeft ~/ 60).toString().padLeft(2, '0');
    final secs = (_timeLeft % 60).toString().padLeft(2, '0');
    return Glass(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${_currentQ + 1} of 3',
                style: const TextStyle(
                  color: Colors.white38,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$mins:$secs',
                style: TextStyle(
                  color: _timeLeft < 30 ? Colors.redAccent : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _questions[_currentQ],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _answerCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type your defense...',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_answerCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an answer')),
                );
                return;
              }
              _nextQuestion();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _currentQ < 2 ? 'Next Trap' : 'Submit for Grading',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    final passed = _result!['passed'] == true;
    final feedback = _result!['feedback'] ?? '';

    return Glass(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            passed ? Icons.shield_rounded : Icons.heart_broken_rounded,
            color: passed ? Colors.greenAccent : Colors.redAccent,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            passed ? 'CONTAMINATION SURVIVED' : 'MASTERY SHATTERED',
            style: TextStyle(
              color: passed ? Colors.greenAccent : Colors.redAccent,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            feedback,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          if (!passed)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Your mastery stage has been violently reduced to Level 3. Re-study and try again later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Return to Subject',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
