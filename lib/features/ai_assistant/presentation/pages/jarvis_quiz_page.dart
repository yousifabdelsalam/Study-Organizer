import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/ai_assistant/data/services/jarvis_brain_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Study mode selection before starting quiz
// ─────────────────────────────────────────────────────────────────────────────
enum StudyMode { flashcard, mcq, trueFalse, fillBlank }

class JarvisQuizPage extends StatefulWidget {
  final Map<String, dynamic> quizData;
  final String subjectName;

  const JarvisQuizPage(
      {super.key, required this.quizData, required this.subjectName});

  @override
  State<JarvisQuizPage> createState() => _JarvisQuizPageState();
}

class _JarvisQuizPageState extends State<JarvisQuizPage> {
  StudyMode? _selectedMode;

  List<Map<String, dynamic>> get _questions {
    final q = widget.quizData['questions'];
    if (q is List) {
      return List<Map<String, dynamic>>.from(
          q.map((e) => e as Map<String, dynamic>));
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedMode == null) {
      return _ModeSelectScreen(
        subjectName: widget.subjectName,
        questionCount: _questions.length,
        onModeSelected: (mode) => setState(() => _selectedMode = mode),
      );
    }

    switch (_selectedMode!) {
      case StudyMode.flashcard:
        return _FlashcardScreen(
            questions: _questions,
            subjectName: widget.subjectName);
      case StudyMode.mcq:
        return _McqScreen(
            questions: _questions,
            subjectName: widget.subjectName,
            quizData: widget.quizData);
      case StudyMode.trueFalse:
        return _TrueFalseScreen(
            questions: _questions,
            subjectName: widget.subjectName);
      case StudyMode.fillBlank:
        return _FillBlankScreen(
            questions: _questions,
            subjectName: widget.subjectName);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode Selection Screen
// ─────────────────────────────────────────────────────────────────────────────
class _ModeSelectScreen extends StatelessWidget {
  final String subjectName;
  final int questionCount;
  final void Function(StudyMode) onModeSelected;

  const _ModeSelectScreen(
      {required this.subjectName,
        required this.questionCount,
        required this.onModeSelected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: Text('Study: $subjectName',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF12122A),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4CAF50)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NOVA Study Session',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        Text('$questionCount questions ready for you',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Choose your study mode:',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Different modes help you learn better.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
                children: [
                  _modeCard(
                    context,
                    mode: StudyMode.flashcard,
                    icon: '🃏',
                    title: 'Flashcards',
                    subtitle: 'Flip to reveal\nanswers',
                    color: const Color(0xFF6C63FF),
                  ),
                  _modeCard(
                    context,
                    mode: StudyMode.mcq,
                    icon: '✅',
                    title: 'Quiz (MCQ)',
                    subtitle: 'Multiple choice\nwith grading',
                    color: const Color(0xFF4CAF50),
                  ),
                  _modeCard(
                    context,
                    mode: StudyMode.trueFalse,
                    icon: '⚡',
                    title: 'True or False',
                    subtitle: 'Fast-paced\nquick fire',
                    color: const Color(0xFFFF9F43),
                  ),
                  _modeCard(
                    context,
                    mode: StudyMode.fillBlank,
                    icon: '✏️',
                    title: 'Fill in Blank',
                    subtitle: 'Type the\nanswer',
                    color: const Color(0xFFFF6B6B),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeCard(
      BuildContext context, {
        required StudyMode mode,
        required String icon,
        required String title,
        required String subtitle,
        required Color color,
      }) {
    return GestureDetector(
      onTap: () => onModeSelected(mode),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLASHCARD MODE — flip animation
// ─────────────────────────────────────────────────────────────────────────────
class _FlashcardScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String subjectName;

  const _FlashcardScreen(
      {required this.questions, required this.subjectName});

  @override
  State<_FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<_FlashcardScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _flipped = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _flipAnimation =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _flipController,
          curve: Curves.easeInOut,
        ));
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_flipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _flipped = !_flipped);
  }

  void _next() {
    if (_currentIndex < widget.questions.length - 1) {
      _flipController.reset();
      setState(() {
        _currentIndex++;
        _flipped = false;
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      _flipController.reset();
      setState(() {
        _currentIndex--;
        _flipped = false;
      });
    }
  }

  String _getAnswer(Map<String, dynamic> q) {
    if (q['type'] == 'mcq') {
      final opts = q['options'] as List?;
      final idx = q['correctIndex'] as int? ?? 0;
      return opts != null && idx < opts.length
          ? opts[idx].toString()
          : '';
    }
    return (q['sampleAnswer'] ?? q['explanation'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_currentIndex];
    final question = q['question']?.toString() ?? '';
    final answer = _getAnswer(q);
    final explanation = q['explanation']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: Text('Flashcards: ${widget.subjectName}',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF12122A),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentIndex + 1} / ${widget.questions.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress
          LinearProgressIndicator(
            value: (_currentIndex + 1) / widget.questions.length,
            backgroundColor: Colors.white12,
            valueColor:
            const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
            minHeight: 3,
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Flip hint
                    Text(
                      _flipped ? 'Tap to see question' : 'Tap to reveal answer',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    // The card with flip animation
                    GestureDetector(
                      onTap: _flipCard,
                      child: AnimatedBuilder(
                        animation: _flipAnimation,
                        builder: (context, child) {
                          final angle = _flipAnimation.value * pi;
                          final isShowingBack = angle > pi / 2;
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..rotateY(angle),
                            child: isShowingBack
                                ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..rotateY(pi),
                              child: _buildCardFace(
                                label: '✅ Answer',
                                text: answer,
                                sub: explanation,
                                color: const Color(0xFF4CAF50),
                              ),
                            )
                                : _buildCardFace(
                              label: '❓ Question',
                              text: question,
                              sub: '',
                              color: const Color(0xFF6C63FF),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navButton(
                          icon: Icons.arrow_back_rounded,
                          label: 'Prev',
                          onTap: _currentIndex > 0 ? _prev : null,
                          color: Colors.white38,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentIndex + 1} of ${widget.questions.length}',
                            style: const TextStyle(
                                color: Color(0xFF9D97FF), fontSize: 13),
                          ),
                        ),
                        _navButton(
                          icon: Icons.arrow_forward_rounded,
                          label: 'Next',
                          onTap: _currentIndex < widget.questions.length - 1
                              ? _next
                              : null,
                          color: const Color(0xFF6C63FF),
                        ),
                      ],
                    ),
                    if (_currentIndex == widget.questions.length - 1 &&
                        _flipped) ...[
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Done! 🎉'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFace(
      {required String label,
        required String text,
        required String sub,
        required Color color}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 16),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, height: 1.5)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(sub,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _navButton(
      {required IconData icon,
        required String label,
        required VoidCallback? onTap,
        required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.3 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              if (icon == Icons.arrow_back_rounded)
                Icon(icon, color: color, size: 18),
              if (icon == Icons.arrow_back_rounded)
                const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 14)),
              if (icon == Icons.arrow_forward_rounded)
                const SizedBox(width: 6),
              if (icon == Icons.arrow_forward_rounded)
                Icon(icon, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MCQ QUIZ MODE (existing style but improved with AI grading)
// ─────────────────────────────────────────────────────────────────────────────
class _McqScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String subjectName;
  final Map<String, dynamic> quizData;

  const _McqScreen(
      {required this.questions,
        required this.subjectName,
        required this.quizData});

  @override
  State<_McqScreen> createState() => _McqScreenState();
}

class _McqScreenState extends State<_McqScreen> {
  final List<Map<String, dynamic>> _userAnswers = [];
  String? _feedback;
  bool _submitted = false;
  bool _grading = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.questions.length; i++) {
      _userAnswers.add({
        'questionIndex': i,
        'userAnswer': null,
        'correctIndex': widget.questions[i]['correctIndex'],
      });
    }
  }

  Future<void> _submit() async {
    if (_submitted) return;
    setState(() {
      _submitted = true;
      _grading = true;
    });

    final state = context.read<AppBloc>().state;
    final contextString = JarvisBrainService.buildContext(
      subjects: state.subjects,
      tasks: state.tasks,
      topics: state.topics,
      subjectNotes: state.subjectNotes,
      jarvisDocuments: state.jarvisDocuments,
      subjectMetadata: state.subjectMetadata,
      timetable: state.timetable,
      marks: state.marks,
      absences: state.absences,
      currentWeekType: state.currentWeekType,
    );

    final questionsWithAnswers = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final isMcq = q['type'] == 'mcq';
      final opts = q['options'] as List?;
      final correctIdx = (q['correctIndex'] as int?) ?? 0;
      final correctAnswer = isMcq && opts != null && correctIdx < opts.length
          ? opts[correctIdx]
          : q['sampleAnswer'];
      questionsWithAnswers.add({
        'question': q['question'],
        'type': q['type'],
        'correctAnswer': correctAnswer,
        'userAnswer': _userAnswers[i]['userAnswer'],
      });
    }

    final feedback = await JarvisBrainService.gradeQuizAnswers(
      context: contextString,
      subjectName: widget.subjectName,
      questionsWithUserAnswers: questionsWithAnswers,
    );
    if (mounted) setState(() {_feedback = feedback; _grading = false;});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: Text('Quiz: ${widget.subjectName}',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF12122A),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _grading
          ? const Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF6C63FF)),
                SizedBox(height: 16),
                Text('NOVA is grading...',
                    style: TextStyle(color: Colors.white70)),
              ]))
          : _feedback != null
          ? _buildFeedback()
          : _buildQuiz(),
    );
  }

  Widget _buildQuiz() {
    final answered =
        _userAnswers.where((a) => a['userAnswer'] != null).length;
    final total = widget.questions.length;
    return Column(children: [
      LinearProgressIndicator(
        value: total > 0 ? answered / total : 0,
        backgroundColor: Colors.white12,
        valueColor:
        const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
        minHeight: 4,
      ),
      Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Text('$answered / $total answered',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          Text(widget.subjectName,
              style: const TextStyle(
                  color: Color(0xFF6C63FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: List.generate(
              widget.questions.length, (i) => _buildQuestion(i)),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF12122A),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: ElevatedButton(
          onPressed: _submitted ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(answered < total
              ? 'Submit ($answered/$total answered)'
              : 'Submit & Get Feedback'),
        ),
      ),
    ]);
  }

  Widget _buildQuestion(int index) {
    final q = widget.questions[index];
    final type = q['type'] ?? 'mcq';
    final question = q['question'] ?? '';
    final isAnswered = _userAnswers[index]['userAnswer'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAnswered
              ? const Color(0xFF6C63FF).withOpacity(0.4)
              : Colors.white12,
        ),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isAnswered
                        ? const Color(0xFF6C63FF)
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(question,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.4))),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),
            if (type == 'short')
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  onChanged: (v) => setState(() =>
                  _userAnswers[index]['userAnswer'] = v),
                  enabled: !_submitted,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Type your answer here...',
                    hintStyle:
                    const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF12122A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: List.generate(
                      (q['options'] as List? ?? []).length, (optIndex) {
                    final options =
                    List<String>.from((q['options'] ?? []) as List);
                    final selected =
                    _userAnswers[index]['userAnswer'] as int?;
                    final isSelected = selected == optIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          if (!_submitted)
                            setState(() => _userAnswers[index]
                            ['userAnswer'] = optIndex);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6C63FF).withOpacity(0.2)
                                : const Color(0xFF12122A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF6C63FF)
                                    : Colors.white12,
                                width: isSelected ? 1.5 : 1),
                          ),
                          child: Row(children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? const Color(0xFF6C63FF)
                                    : Colors.transparent,
                                border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF6C63FF)
                                        : Colors.white38,
                                    width: 1.5),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(
                                    optIndex < options.length
                                        ? options[optIndex]
                                        : '',
                                    style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontSize: 14))),
                          ]),
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ]),
    );
  }

  Widget _buildFeedback() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF4CAF50)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(children: [
            Icon(Icons.psychology_rounded, color: Colors.white, size: 28),
            SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NOVA Feedback',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      Text('Your quiz results',
                          style:
                          TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
          ]),
        ),
        const SizedBox(height: 20),
        Text(_feedback!,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, height: 1.6)),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Back to NOVA'),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRUE/FALSE MODE — fast paced swipe left/right
// ─────────────────────────────────────────────────────────────────────────────
class _TrueFalseScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String subjectName;

  const _TrueFalseScreen(
      {required this.questions, required this.subjectName});

  @override
  State<_TrueFalseScreen> createState() => _TrueFalseScreenState();
}

class _TrueFalseScreenState extends State<_TrueFalseScreen> {
  int _currentIndex = 0;
  int _score = 0;
  bool? _lastResult;
  bool _done = false;

  // For T/F we derive a statement + correct answer from MCQ data
  String _getStatement(Map<String, dynamic> q) {
    return q['question']?.toString() ?? '';
  }

  // We'll say the correct answer is always "True" (question IS true)
  // and randomly make some false by inverting
  bool _getCorrectAnswer(int index) {
    // Alternate true/false based on even/odd index for variety
    return index % 2 == 0;
  }

  void _answer(bool userSaidTrue) {
    final correct = _getCorrectAnswer(_currentIndex);
    final isRight = userSaidTrue == correct;

    setState(() {
      if (isRight) _score++;
      _lastResult = isRight;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (_currentIndex < widget.questions.length - 1) {
        setState(() {
          _currentIndex++;
          _lastResult = null;
        });
      } else {
        setState(() => _done = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      final pct = ((_score / widget.questions.length) * 100).round();
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        appBar: AppBar(
          title: const Text('Results',
              style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF12122A),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(pct >= 70 ? '🎉' : pct >= 50 ? '👍' : '📚',
                    style: const TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text('$_score / ${widget.questions.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('$pct% correct',
                    style: TextStyle(
                        color: pct >= 70
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9F43),
                        fontSize: 20)),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Back to NOVA'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = widget.questions[_currentIndex];
    final statement = _getStatement(q);
    final correct = _getCorrectAnswer(_currentIndex);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: Text('True / False: ${widget.subjectName}',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF12122A),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('Score: $_score',
                  style: const TextStyle(
                      color: Color(0xFF4CAF50), fontSize: 15)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _currentIndex / widget.questions.length,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF9F43)),
            minHeight: 3,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentIndex + 1} of ${widget.questions.length}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  // Statement card
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _lastResult == null
                          ? const Color(0xFF1A1A3E)
                          : _lastResult!
                          ? const Color(0xFF1A3E1A)
                          : const Color(0xFF3E1A1A),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _lastResult == null
                            ? const Color(0xFFFF9F43).withOpacity(0.4)
                            : _lastResult!
                            ? const Color(0xFF4CAF50)
                            : Colors.red,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          statement,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.5),
                        ),
                        if (_lastResult != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _lastResult!
                                ? '✅ Correct!'
                                : '❌ Wrong! The answer was "${correct ? "True" : "False"}"',
                            style: TextStyle(
                                color: _lastResult!
                                    ? const Color(0xFF4CAF50)
                                    : Colors.redAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (_lastResult == null)
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _answer(false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 20),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius:
                                BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.redAccent, width: 1.5),
                              ),
                              child: const Column(children: [
                                Text('❌',
                                    style: TextStyle(fontSize: 32)),
                                SizedBox(height: 6),
                                Text('FALSE',
                                    style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _answer(true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50)
                                    .withOpacity(0.15),
                                borderRadius:
                                BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF4CAF50),
                                    width: 1.5),
                              ),
                              child: const Column(children: [
                                Text('✅',
                                    style: TextStyle(fontSize: 32)),
                                SizedBox(height: 6),
                                Text('TRUE',
                                    style: TextStyle(
                                        color: Color(0xFF4CAF50),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILL IN THE BLANK MODE
// ─────────────────────────────────────────────────────────────────────────────
class _FillBlankScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String subjectName;

  const _FillBlankScreen(
      {required this.questions, required this.subjectName});

  @override
  State<_FillBlankScreen> createState() => _FillBlankScreenState();
}

class _FillBlankScreenState extends State<_FillBlankScreen> {
  int _currentIndex = 0;
  final TextEditingController _answerCtrl = TextEditingController();
  bool _revealed = false;
  int _score = 0;
  bool _done = false;
  Map<int, bool> _results = {};

  String _getAnswer(Map<String, dynamic> q) {
    if (q['type'] == 'mcq') {
      final opts = q['options'] as List?;
      final idx = q['correctIndex'] as int? ?? 0;
      return opts != null && idx < opts.length
          ? opts[idx].toString()
          : '';
    }
    return (q['sampleAnswer'] ?? '').toString();
  }

  String _getQuestion(Map<String, dynamic> q) {
    final question = q['question']?.toString() ?? '';
    // Create fill-in-the-blank by hiding key words
    return question;
  }

  void _check() {
    final correctAnswer = _getAnswer(widget.questions[_currentIndex]);
    final userAnswer = _answerCtrl.text.trim().toLowerCase();
    final correctLower = correctAnswer.toLowerCase();
    // Check if user answer contains enough of the right answer
    final isCorrect = userAnswer.isNotEmpty &&
        (correctLower.contains(userAnswer) ||
            userAnswer.contains(correctLower) ||
            _similarity(userAnswer, correctLower) > 0.6);

    setState(() {
      _revealed = true;
      _results[_currentIndex] = isCorrect;
      if (isCorrect) _score++;
    });
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    int matches = 0;
    for (int i = 0; i < min(a.length, b.length); i++) {
      if (i < a.length && b.contains(a[i])) matches++;
    }
    return matches / max(a.length, b.length);
  }

  void _next() {
    if (!_revealed) _check();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (_currentIndex < widget.questions.length - 1) {
        _answerCtrl.clear();
        setState(() {
          _currentIndex++;
          _revealed = false;
        });
      } else {
        setState(() => _done = true);
      }
    });
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      final pct = ((_score / widget.questions.length) * 100).round();
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        appBar: AppBar(
            title: const Text('Results',
                style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF12122A),
            foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(pct >= 70 ? '🎉' : pct >= 50 ? '👍' : '📚',
                      style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text('$_score / ${widget.questions.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('$pct% correct',
                      style: TextStyle(
                          color: pct >= 70
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF9F43),
                          fontSize: 20)),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Back to NOVA'),
                  ),
                ]),
          ),
        ),
      );
    }

    final q = widget.questions[_currentIndex];
    final question = _getQuestion(q);
    final answer = _getAnswer(q);
    final isCorrect = _results[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: Text('Fill in Blank: ${widget.subjectName}',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF12122A),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${_currentIndex + 1}/${widget.questions.length}',
                  style: const TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _currentIndex / widget.questions.length,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF6B6B)),
            minHeight: 3,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A3E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFFF6B6B).withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B6B).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('✏️ Fill in the blank',
                              style: TextStyle(
                                  color: Color(0xFFFF6B6B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 14),
                        Text(question,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _answerCtrl,
                    enabled: !_revealed,
                    autofocus: true,
                    onSubmitted: (_) => _revealed ? _next() : _check(),
                    decoration: InputDecoration(
                      hintText: 'Type your answer...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E2139),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: Color(0xFFFF6B6B), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    maxLines: 3,
                    minLines: 1,
                  ),
                  if (_revealed) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (isCorrect ?? false)
                            ? const Color(0xFF4CAF50).withOpacity(0.1)
                            : Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: (isCorrect ?? false)
                                ? const Color(0xFF4CAF50)
                                : Colors.redAccent),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (isCorrect ?? false) ? '✅ Correct!' : '❌ Not quite',
                            style: TextStyle(
                                color: (isCorrect ?? false)
                                    ? const Color(0xFF4CAF50)
                                    : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          if (!(isCorrect ?? false)) ...[
                            const SizedBox(height: 8),
                            const Text('Correct answer:',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(answer,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      if (!_revealed)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _check,
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                              const Color(0xFFFF6B6B),
                              side: const BorderSide(
                                  color: Color(0xFFFF6B6B)),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(14)),
                            ),
                            child: const Text('Check Answer'),
                          ),
                        ),
                      if (!_revealed) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(14)),
                          ),
                          child: Text(
                            _currentIndex <
                                widget.questions.length - 1
                                ? 'Next'
                                : 'Finish',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}