import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_event.dart';
import '../services/jarvis_brain_service.dart';
import '../widgets/glass.dart';

class LightningDrillOverlay extends StatefulWidget {
  final Subject subject;
  final StudyTopic topic;
  final String docsContext;

  const LightningDrillOverlay({
    super.key,
    required this.subject,
    required this.topic,
    required this.docsContext,
  });

  @override
  State<LightningDrillOverlay> createState() => _LightningDrillOverlayState();
}

class _LightningDrillOverlayState extends State<LightningDrillOverlay> {
  bool _loading = true;
  String _question = '';
  final TextEditingController _answerCtrl = TextEditingController();

  bool _grading = false;
  Map<String, dynamic>? _result;

  int _timeLeft = 60; // 60-Second Micro-Drill
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadQuestion();
  }

  Future<void> _loadQuestion() async {
    final q = await JarvisBrainService.generateLightningQuestion(
      widget.subject.name,
      widget.topic.title,
      widget.docsContext,
    );
    if (!mounted) return;

    if (q.contains('INSUFFICIENT_MATERIAL')) {
      setState(() {
        _question =
            'NOVA: I cannot generate a drill without study materials.';
        _loading = false;
        _timeLeft = 0; // stop timer immediately
      });
      return;
    }

    setState(() {
      _question = q;
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
          if (!_grading && _result == null) _submitAnswer();
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

  Future<void> _submitAnswer() async {
    _timer?.cancel();
    setState(() {
      _grading = true;
    });

    final res = await JarvisBrainService.gradeLightningAnswer(
      widget.subject.name,
      widget.topic.title,
      _question,
      _answerCtrl.text.trim(),
    );

    if (!mounted) return;

    if (res['passed'] == true) {
      // Reward: Advance stage if not mastered
      if (widget.topic.stage < 5) {
        context.read<AppBloc>().add(UpdateTopic(widget.topic.advanceStage()));
      }
    } else {
      // Penalty: reset review
      context.read<AppBloc>().add(
        UpdateTopic(widget.topic.copyWith(nextReview: DateTime.now())),
      );
    }

    setState(() {
      _grading = false;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Respond to soft keyboard via viewInsets bottom padding
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: Colors.yellowAccent,
                    size: 36,
                  ),
                  SizedBox(width: 12),
                  Text(
                    '60-SECOND DRILL',
                    style: TextStyle(
                      color: Colors.yellowAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.subject.name} • ${widget.topic.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),

              if (_loading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Colors.yellowAccent),
                    SizedBox(height: 16),
                    Text(
                      'NOVA is formulating a rapid-fire question...',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                )
              else if (_grading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Colors.yellowAccent),
                    SizedBox(height: 16),
                    Text(
                      'Grading response...',
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
    final secs = _timeLeft.toString().padLeft(2, '0');
    return Glass(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '00:$secs',
              style: TextStyle(
                color: _timeLeft <= 10 ? Colors.redAccent : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 48,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _question,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _answerCtrl,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type answer quickly...',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_answerCtrl.text.trim().isEmpty) return;
              _submitAnswer();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellowAccent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Fire',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    final passed = _result!['passed'] == true;
    final feedback = _result!['feedback'] ?? '';
    final String correctAnswer =
        (_result!['correct_answer'] ?? _result!['correctAnswer'] ?? '')
            .toString()
            .trim();

    return Glass(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: passed ? Colors.greenAccent : Colors.redAccent,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            passed ? 'DRILL PASSED' : 'DRILL FAILED',
            style: TextStyle(
              color: passed ? Colors.greenAccent : Colors.redAccent,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              Text(
                feedback,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              if (!passed && correctAnswer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Correct Answer:',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          correctAnswer,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              passed
                  ? 'Mastery stage advanced!'
                  : 'Scheduled for immediate review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: passed ? Colors.greenAccent : Colors.redAccent,
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
              'Close Drill',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
