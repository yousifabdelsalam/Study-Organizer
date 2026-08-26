import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';

// Palette
const Color kHudBg = Color(0xFF080C16);
const Color kHudCyan = Color(0xFF00F0FF);
const Color kHudCyanDark = Color(0xFF005566);
const Color kHudOrange = Color(0xFFFF9F43);
const Color kHudMagenta = Color(0xFFFF00FF);
const Color kHudText = Color(0xFFD0F4FF);
const Color kHudBorder = Color(0xFF1A3A5A);

class ExamPrepHud extends StatefulWidget {
  final Subject subject;
  final String instructorFocus;

  const ExamPrepHud({
    Key? key,
    required this.subject,
    required this.instructorFocus,
  }) : super(key: key);

  @override
  State<ExamPrepHud> createState() => _ExamPrepHudState();
}

class _ExamPrepHudState extends State<ExamPrepHud>
    with TickerProviderStateMixin {
  bool _isArabic = false;

  // States
  bool _isLoadingEnigma = false;
  String _enigmaReport = "Awaiting protocol activation...";

  bool _isLoadingQuiz = false;
  String _quizReport = "Select a timeframe to generate predictions.";
  List<String> _quizPages = [];
  int _currentQuizPageIndex = 0;
  String _activeQuizTab = "5TH WEEK MID";

  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  // Action methods
  Future<void> _activateEnigmaProtocol() async {
    setState(() {
      _isLoadingEnigma = true;
      _enigmaReport =
          "Analyzing instructor patterns...\nScanning study materials...\nDecoding exam DNA...";
    });

    final state = context.read<AppBloc>().state;
    final subjectId = widget.subject.id ?? 0;

    final output = await JarvisBrainService.fullSubjectExamPrep(
      subjectName: widget.subject.name,
      doctorName: widget.subject.doctorName,
      instructorFocus: widget.instructorFocus,
      docs: state.jarvisDocuments
          .where((d) => d.subjectId == subjectId)
          .toList(),
      topics: state.topics.where((t) => t.subjectId == subjectId).toList(),
      marks: state.marks.where((m) => m.subjectId == subjectId).toList(),
      tasks: state.tasks.where((t) => t.subjectId == subjectId).toList(),
      timetable: state.timetable
          .where((e) => e.subjectId == subjectId)
          .toList(),
      language: _isArabic ? 'arabic' : 'english',
    );

    if (mounted) {
      setState(() {
        _isLoadingEnigma = false;
        _enigmaReport = output;
      });
    }
  }

  // ── Save / Load exams ────────────────────────────────────────────────────
  Future<void> _saveExam(String content, String examType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'saved_exams_${widget.subject.name}';
    final existing = prefs.getStringList(key) ?? [];
    final entry = jsonEncode({
      'type': examType,
      'date': DateTime.now().toIso8601String(),
      'content': content,
    });
    existing.insert(0, entry);
    await prefs.setStringList(key, existing);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Exam saved for later review'),
          backgroundColor: Color(0xFF00796B),
        ),
      );
    }
  }

  void _openSavedExams() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'saved_exams_${widget.subject.name}';
    final saved = prefs.getStringList(key) ?? [];
    if (saved.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No saved exams yet'),
            backgroundColor: kHudBorder,
          ),
        );
      }
      return;
    }
    final items = saved
        .map((s) {
          try {
            return jsonDecode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kHudBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '📋 SAVED EXAMS',
              style: TextStyle(
                color: kHudCyan,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          ...items.take(10).map((item) {
            final type = item['type'] ?? 'Unknown';
            final date = item['date'] ?? '';
            final content = item['content'] ?? '';
            String dateStr = '';
            try {
              final dt = DateTime.parse(date);
              dateStr =
                  '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (_) {}
            return ListTile(
              leading: const Icon(Icons.description, color: kHudOrange),
              title: Text(type, style: const TextStyle(color: kHudText)),
              subtitle: Text(
                dateStr,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullReportPage(
                      title: 'SAVED: $type',
                      subtitle: widget.subject.name,
                      content: content,
                      isArabic: _isArabic,
                      onShare: () => Share.share(content),
                    ),
                  ),
                );
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<String> _buildQuizPages(String raw) {
    if (raw.isEmpty) return ['No content generated.'];
    final pageSections = raw
        .split('---PAGE---')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (pageSections.length >= 2) {
      final pages = <String>[];
      pages.add(pageSections[0]);
      for (int i = 1; i < pageSections.length - 1; i++) {
        pages.addAll(_splitByQuestionMarkers(pageSections[i]));
      }
      pages.add(pageSections.last);
      return pages.where((p) => p.isNotEmpty).toList();
    }
    final qPages = _splitByQuestionMarkers(raw);
    if (qPages.length > 1) return qPages;
    return [raw];
  }

  List<String> _splitByQuestionMarkers(String text) {
    final parts = text.split(RegExp(r'---Q\d+---'));
    final trimmed = parts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return trimmed.length > 1 ? trimmed : [text];
  }

  void _openFullEnigmaReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullReportPage(
          title: 'AI ENIGMA BREAKDOWN',
          subtitle: widget.subject.name,
          content: _enigmaReport,
          isArabic: _isArabic,
          onShare: () => Share.share(
            '>>> JARVIS ENIGMA PROTOCOL // ' +
                widget.subject.name.toUpperCase() +
                '\n\n' +
                _enigmaReport,
          ),
          onSave: () => _saveExam(_enigmaReport, 'ENIGMA BREAKDOWN'),
        ),
      ),
    );
  }

  void _openFullQuizReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullReportPage(
          title: 'GENERATED EXAM: ' + _activeQuizTab,
          subtitle: widget.subject.name,
          content: _quizReport,
          isArabic: _isArabic,
          onShare: () => Share.share(
            '>>> JARVIS PREDICTED EXAM: ' +
                _activeQuizTab +
                ' // ' +
                widget.subject.name.toUpperCase() +
                '\n\n' +
                _quizReport,
          ),
          onSave: () => _saveExam(_quizReport, _activeQuizTab),
        ),
      ),
    );
  }

  Future<void> _generateQuiz(String typeStr) async {
    setState(() {
      _activeQuizTab = typeStr;
      _isLoadingQuiz = true;
      _quizReport =
          "Generating predicted $typeStr questions based on Enigma breakdown...";
      _quizPages = [_quizReport];
      _currentQuizPageIndex = 0;
    });

    final typeMap = {
      '5TH WEEK MID': 'week5',
      '10TH MID': 'week10',
      'FINAL': 'final',
    };
    final mode = typeMap[typeStr] ?? 'final';

    final state = context.read<AppBloc>().state;
    final subjectId = widget.subject.id ?? 0;

    final output = await JarvisBrainService.generatePredictedExam(
      subjectName: widget.subject.name,
      doctorName: widget.subject.doctorName,
      instructorFocus: widget.instructorFocus,
      docs: state.jarvisDocuments
          .where((d) => d.subjectId == subjectId)
          .toList(),
      examType: mode,
      language: _isArabic ? 'arabic' : 'english',
    );

    if (mounted) {
      setState(() {
        _isLoadingQuiz = false;
        _quizReport = output;

        // Split by ---PAGE--- and ---Q{n}--- markers for clean pagination
        _quizPages = _buildQuizPages(output);
        _currentQuizPageIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kHudBg,
      body: Stack(
        children: [
          // Subtle tech background grid
          Positioned.fill(child: CustomPaint(painter: _HudGridPainter())),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Header
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: kHudCyan),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'JARVIS EXAM PREPARATION INTERFACE // DR. ${widget.subject.doctorName.toUpperCase()}',
                          style: const TextStyle(
                            color: kHudCyan,
                            fontSize: 14,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.bolt, color: kHudOrange, size: 20),
                      const SizedBox(width: 4),
                      const Text(
                        'SYSTEM ONLINE',
                        style: TextStyle(
                          color: kHudOrange,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Main 3-Column Layout (Scrollable horizontally on small screens, Row on large)
                  Expanded(
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: kHudText,
                        fontFamily: 'Courier',
                        fontSize: 13,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth > 800) {
                            return Row(
                              children: [
                                Expanded(child: _buildLeftCard()),
                                const SizedBox(width: 16),
                                Expanded(child: _buildCenterCard()),
                                const SizedBox(width: 16),
                                Expanded(child: _buildRightCard()),
                              ],
                            );
                          } else {
                            // Single column scroll for mobile
                            return ListView(
                              children: [
                                SizedBox(height: 600, child: _buildLeftCard()),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 800,
                                  child: _buildCenterCard(),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(height: 800, child: _buildRightCard()),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CARD 1: LEFT CARD (Subject Details & Hex Button)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildLeftCard() {
    final state = context.watch<AppBloc>().state;
    final topics = state.topics
        .where((t) => t.subjectId == widget.subject.id)
        .toList();

    return _SciFiContainer(
      title: 'SUBJECT DETAILS:\n${widget.subject.name.toUpperCase()}',
      child: Column(
        children: [
          Expanded(
            child: topics.isEmpty
                ? const Center(
                    child: Text(
                      'No topics available.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: topics.length,
                    itemBuilder: (ctx, i) {
                      final topic = topics[i];
                      final progress = topic.stage / 5.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                topic.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: kHudCyan,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: _HudProgressBar(progress: progress),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 20),

          // Hexagonal Activate Protocol Button
          GestureDetector(
            onTap: _isLoadingEnigma ? null : _activateEnigmaProtocol,
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: kHudCyan.withOpacity(0.05),
                border: Border.all(
                  color: _isLoadingEnigma
                      ? kHudOrange
                      : kHudCyan.withOpacity(0.5),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isLoadingEnigma
                        ? Icons.hourglass_top
                        : Icons.power_settings_new,
                    color: _isLoadingEnigma ? kHudOrange : kHudOrange,
                    size: 40,
                    shadows: [BoxShadow(color: kHudOrange, blurRadius: 10)],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isLoadingEnigma
                        ? 'ANALYZING...'
                        : 'ACTIVATE EXAM\nPREP PROTOCOL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isLoadingEnigma ? kHudOrange : kHudCyan,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      shadows: [BoxShadow(color: kHudCyan, blurRadius: 10)],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CARD 2: CENTER CARD (AI Enigma Breakdown & Radar)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildCenterCard() {
    return _SciFiContainer(
      title: 'AI ENIGMA BREAKDOWN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: kHudMagenta.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: kHudMagenta.withOpacity(0.1), blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DOCTOR\'S PATTERN:',
                  style: TextStyle(color: kHudText, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.instructorFocus.isEmpty
                      ? 'Waiting for analysis...'
                      : widget.instructorFocus,
                  style: const TextStyle(
                    color: kHudMagenta,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Radar Animation
          Center(
            child: SizedBox(
              height: 160,
              width: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _radarController,
                    builder: (_, __) => CustomPaint(
                      painter: _RadarPainter(progress: _radarController.value),
                      size: const Size(160, 160),
                    ),
                  ),
                  const Icon(Icons.psychology, color: kHudCyan, size: 60),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Two glowing boxes
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: kHudCyan.withOpacity(0.7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PREDICTION:',
                        style: TextStyle(color: kHudText, fontSize: 10),
                      ),
                      Text(
                        'PROCESSING',
                        style: TextStyle(
                          color: kHudCyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: kHudMagenta.withOpacity(0.7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FOCUS AREAS:',
                        style: TextStyle(color: kHudText, fontSize: 10),
                      ),
                      Text(
                        'AWAITING',
                        style: TextStyle(
                          color: kHudMagenta,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Terminal Output (Markdown)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kHudCyan.withOpacity(0.05),
                border: Border.all(color: kHudCyan.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Directionality(
                  textDirection: _isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: MarkdownBody(
                    data: _enigmaReport,
                    builders: {
                      'latex': LatexElementBuilder(
                        textStyle: const TextStyle(color: kHudCyan),
                      ),
                    },
                    extensionSet: md.ExtensionSet(
                      [
                        LatexBlockSyntax(),
                        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                      ],
                      [
                        LatexInlineSyntax(),
                        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                      ],
                    ),
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: kHudText,
                        fontSize: 13,
                        height: 1.6,
                      ),
                      h1: const TextStyle(
                        color: kHudCyan,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: kHudOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: kHudMagenta,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      em: const TextStyle(
                        color: kHudMagenta,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(color: kHudCyan),
                      code: TextStyle(
                        color: kHudBg,
                        backgroundColor: kHudCyan,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                      ),
                      codeblockPadding: const EdgeInsets.all(8),
                      codeblockDecoration: BoxDecoration(
                        color: kHudCyan.withOpacity(0.1),
                        border: Border.all(color: kHudCyan),
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: kHudBorder.withOpacity(0.3),
                        border: const Border(
                          left: BorderSide(color: kHudOrange, width: 3),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.fromLTRB(
                        12,
                        8,
                        12,
                        8,
                      ),
                      tableHead: const TextStyle(
                        color: kHudCyan,
                        fontWeight: FontWeight.bold,
                      ),
                      tableBody: const TextStyle(color: kHudText, fontSize: 12),
                      tableBorder: TableBorder.all(color: kHudBorder),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Footer Controls
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _isArabic,
                    onChanged: (v) => setState(() => _isArabic = v),
                    activeColor: kHudCyan,
                    activeTrackColor: kHudCyan.withOpacity(0.3),
                  ),
                  const Text(
                    'عربي',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      color: kHudText,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _enigmaReport.length > 50
                        ? _openFullEnigmaReport
                        : null,
                    icon: const Icon(Icons.open_in_full_rounded, size: 12),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kHudMagenta,
                      side: const BorderSide(color: kHudMagenta),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                    label: const Text(
                      'FULL',
                      style: TextStyle(fontSize: 9, letterSpacing: 1),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _enigmaReport.length > 50
                        ? () => _saveExam(_enigmaReport, 'ENIGMA BREAKDOWN')
                        : null,
                    icon: const Icon(Icons.save_rounded, size: 12),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2ED573),
                      side: const BorderSide(color: Color(0xFF2ED573)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                    label: const Text(
                      'SAVE',
                      style: TextStyle(fontSize: 9, letterSpacing: 1),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openSavedExams,
                    icon: const Icon(Icons.folder_open_rounded, size: 12),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kHudOrange,
                      side: const BorderSide(color: kHudOrange),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                    label: const Text(
                      'SAVED',
                      style: TextStyle(fontSize: 9, letterSpacing: 1),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (_enigmaReport.length > 50) {
                        Share.share(
                          '>>> JARVIS ENIGMA PROTOCOL // ' +
                              widget.subject.name.toUpperCase() +
                              '\n\n' +
                              _enigmaReport,
                        );
                      }
                    },
                    icon: const Icon(Icons.share, size: 12),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kHudCyan,
                      side: const BorderSide(color: kHudCyan),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                    label: const Text(
                      'EXPORT',
                      style: TextStyle(fontSize: 9, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CARD 3: RIGHT CARD (Generated Quiz & Solutions)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildRightCard() {
    return _SciFiContainer(
      title: 'GENERATED QUIZ & SOLUTIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tabs
          Row(
            children: [
              _HudTab(
                title: '5TH WEEK MID',
                active: _activeQuizTab == '5TH WEEK MID',
                onTap: () => _generateQuiz('5TH WEEK MID'),
              ),
              const SizedBox(width: 8),
              _HudTab(
                title: '10TH MID',
                active: _activeQuizTab == '10TH MID',
                onTap: () => _generateQuiz('10TH MID'),
              ),
              const SizedBox(width: 8),
              _HudTab(
                title: 'FINAL',
                active: _activeQuizTab == 'FINAL',
                onTap: () => _generateQuiz('FINAL'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quiz output
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: kHudOrange.withOpacity(0.6)),
                borderRadius: BorderRadius.circular(12),
                color: kHudOrange.withOpacity(0.05),
              ),
              child: _isLoadingQuiz
                  ? const Center(
                      child: CircularProgressIndicator(color: kHudOrange),
                    )
                  : SingleChildScrollView(
                      child: Directionality(
                        textDirection: _isArabic
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: MarkdownBody(
                          data: _quizPages.isNotEmpty
                              ? _quizPages[_currentQuizPageIndex]
                              : _quizReport,
                          builders: {
                            'latex': LatexElementBuilder(
                              textStyle: const TextStyle(color: kHudCyan),
                            ),
                          },
                          extensionSet: md.ExtensionSet(
                            [
                              LatexBlockSyntax(),
                              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                            ],
                            [
                              LatexInlineSyntax(),
                              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                            ],
                          ),
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                              color: kHudText,
                              fontSize: 13,
                              height: 1.5,
                              fontFamily: 'Courier',
                            ),
                            h1: const TextStyle(
                              color: kHudOrange,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Orbitron',
                            ),
                            h2: const TextStyle(
                              color: kHudCyan,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Orbitron',
                            ),
                            listBullet: const TextStyle(color: kHudOrange),
                            code: TextStyle(
                              color: kHudBg,
                              backgroundColor: kHudOrange,
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.bold,
                            ),
                            codeblockPadding: const EdgeInsets.all(8),
                            codeblockDecoration: BoxDecoration(
                              color: kHudOrange.withOpacity(0.1),
                              border: Border.all(color: kHudOrange),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // Expand button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _quizReport.length > 50 ? _openFullQuizReport : null,
                icon: const Icon(Icons.open_in_full_rounded, size: 12),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHudOrange,
                  side: const BorderSide(color: kHudOrange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                label: const Text(
                  'FULL EXAM',
                  style: TextStyle(fontSize: 10, letterSpacing: 1),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _quizReport.length > 50
                    ? () => _saveExam(_quizReport, _activeQuizTab)
                    : null,
                icon: const Icon(Icons.save_rounded, size: 12),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHudCyan,
                  side: const BorderSide(color: kHudCyan),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                label: const Text(
                  'SAVE',
                  style: TextStyle(fontSize: 10, letterSpacing: 1),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openSavedExams,
                icon: const Icon(Icons.folder_open_rounded, size: 12),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHudMagenta,
                  side: const BorderSide(color: kHudMagenta),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                label: const Text(
                  'SAVED',
                  style: TextStyle(fontSize: 10, letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Pagination
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _currentQuizPageIndex > 0
                    ? () => setState(() => _currentQuizPageIndex--)
                    : null,
                icon: Icon(
                  Icons.arrow_back_ios,
                  size: 12,
                  color: _currentQuizPageIndex > 0 ? kHudCyan : Colors.grey,
                ),
                label: Text(
                  '< PREVIOUS',
                  style: TextStyle(
                    fontSize: 10,
                    color: _currentQuizPageIndex > 0 ? kHudCyan : Colors.grey,
                  ),
                ),
              ),
              Text(
                'PAGE ${_quizPages.isEmpty ? 0 : _currentQuizPageIndex + 1} OF ${_quizPages.length}',
                style: const TextStyle(color: kHudCyan, fontSize: 10),
              ),
              TextButton.icon(
                onPressed: _currentQuizPageIndex < _quizPages.length - 1
                    ? () => setState(() => _currentQuizPageIndex++)
                    : null,
                label: Text(
                  'NEXT >',
                  style: TextStyle(
                    fontSize: 10,
                    color: _currentQuizPageIndex < _quizPages.length - 1
                        ? kHudCyan
                        : Colors.grey,
                  ),
                ),
                icon: Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: _currentQuizPageIndex < _quizPages.length - 1
                      ? kHudCyan
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SciFiContainer extends StatelessWidget {
  final String title;
  final Widget child;
  const _SciFiContainer({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kHudBg.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHudBorder, width: 2),
        boxShadow: [
          BoxShadow(
            color: kHudCyan.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kHudCyan.withOpacity(0.2), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kHudCyan,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(16.0), child: child),
          ),
        ],
      ),
    );
  }
}

class _HudTab extends StatelessWidget {
  final String title;
  final bool active;
  final VoidCallback onTap;
  const _HudTab({
    required this.title,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? kHudCyan.withOpacity(0.2) : Colors.transparent,
            border: Border.all(color: active ? kHudCyan : kHudBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : kHudText,
              fontSize: 10,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _HudProgressBar extends StatelessWidget {
  final double progress;
  const _HudProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 4,
              width: constraints.maxWidth,
              color: kHudCyanDark,
            ),
            Container(
              height: 4,
              width: constraints.maxWidth * progress,
              color: kHudCyan,
            ),
            Positioned(
              left: (constraints.maxWidth * progress) - 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: kHudOrange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kHudOrange,
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Rings
    paint.color = kHudCyan.withOpacity(0.3);
    canvas.drawCircle(center, radius * 0.4, paint);
    canvas.drawCircle(center, radius * 0.7, paint);
    canvas.drawCircle(center, radius, paint);

    // Scanner
    final sweep = Paint()
      ..style = PaintingStyle.fill
      ..shader = SweepGradient(
        colors: [
          kHudCyan.withOpacity(0.0),
          kHudCyan.withOpacity(0.2),
          kHudCyan.withOpacity(0.6),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * 2 * math.pi,
      math.pi * 1.5, // 270 degree wider sweep
      true,
      sweep,
    );

    // Bright leading edge line
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = kHudCyan
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final edgeAngle = (progress * 2 * math.pi) + (math.pi * 1.5);
    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * math.cos(edgeAngle),
        center.dy + radius * math.sin(edgeAngle),
      ),
      edgePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _HudGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kHudCyanDark.withOpacity(0.1)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// FULL REPORT PAGE
// =============================================================================
class _FullReportPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String content;
  final bool isArabic;
  final VoidCallback onShare;
  final VoidCallback? onSave;
  const _FullReportPage({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.isArabic,
    required this.onShare,
    this.onSave,
  });
  @override
  State<_FullReportPage> createState() => _FullReportPageState();
}

class _FullReportPageState extends State<_FullReportPage> {
  double _fontSize = 13;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kHudBg,
      body: Column(
        children: [
          // Header bar
          Container(
            padding: EdgeInsets.fromLTRB(
              8,
              MediaQuery.of(context).padding.top + 4,
              8,
              8,
            ),
            decoration: const BoxDecoration(
              color: kHudBg,
              border: Border(bottom: BorderSide(color: kHudBorder, width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_rounded,
                    color: kHudCyan,
                    size: 18,
                  ),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: kHudCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.5,
                          fontFamily: 'Courier',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(color: kHudText, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Font size controls
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: kHudBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.text_decrease_rounded,
                          color: kHudText,
                          size: 16,
                        ),
                        onPressed: () => setState(
                          () => _fontSize = (_fontSize - 1).clamp(10, 22),
                        ),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                      ),
                      Text(
                        '${_fontSize.toInt()}',
                        style: const TextStyle(color: kHudText, fontSize: 11),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.text_increase_rounded,
                          color: kHudText,
                          size: 16,
                        ),
                        onPressed: () => setState(
                          () => _fontSize = (_fontSize + 1).clamp(10, 22),
                        ),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (widget.onSave != null)
                  IconButton(
                    icon: const Icon(
                      Icons.save_rounded,
                      color: Color(0xFF2ED573),
                      size: 20,
                    ),
                    onPressed: widget.onSave,
                    tooltip: 'Save for later',
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.share_rounded,
                    color: kHudCyan,
                    size: 20,
                  ),
                  onPressed: widget.onShare,
                ),
              ],
            ),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Directionality(
                textDirection: widget.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: MarkdownBody(
                  data: widget.content,
                  selectable: true,
                  builders: {
                    'latex': LatexElementBuilder(
                      textStyle: TextStyle(
                        color: kHudCyan,
                        fontSize: _fontSize,
                      ),
                    ),
                  },
                  extensionSet: md.ExtensionSet(
                    [
                      LatexBlockSyntax(),
                      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                    ],
                    [
                      LatexInlineSyntax(),
                      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                    ],
                  ),
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                      color: const Color(0xFFE0E0FF),
                      fontSize: _fontSize,
                      height: 1.75,
                    ),
                    h1: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: _fontSize + 6,
                      height: 2.2,
                    ),
                    h2: TextStyle(
                      color: const Color(0xFFBB86FC),
                      fontWeight: FontWeight.w800,
                      fontSize: _fontSize + 4,
                      height: 2.0,
                    ),
                    h3: TextStyle(
                      color: const Color(0xFF03DAC6),
                      fontWeight: FontWeight.w700,
                      fontSize: _fontSize + 2,
                      height: 1.9,
                    ),
                    h4: TextStyle(
                      color: const Color(0xFFFF9800),
                      fontWeight: FontWeight.w700,
                      fontSize: _fontSize + 1,
                    ),
                    strong: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: _fontSize,
                    ),
                    em: TextStyle(
                      color: const Color(0xFFCFCFFF),
                      fontStyle: FontStyle.italic,
                      fontSize: _fontSize,
                    ),
                    code: TextStyle(
                      color: const Color(0xFF80CBC4),
                      backgroundColor: const Color(0xFF1E1E3A),
                      fontSize: _fontSize - 1,
                      fontFamily: 'monospace',
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: kHudCyan.withOpacity(0.1),
                      border: Border.all(color: kHudCyan),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    codeblockPadding: const EdgeInsets.all(12),
                    blockquoteDecoration: BoxDecoration(
                      color: kHudBorder.withOpacity(0.3),
                      border: const Border(
                        left: BorderSide(color: kHudOrange, width: 3),
                      ),
                    ),
                    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    blockquote: TextStyle(
                      color: const Color(0xFFB0BEC5),
                      fontSize: _fontSize,
                      fontStyle: FontStyle.italic,
                    ),
                    listBullet: TextStyle(color: kHudCyan, fontSize: _fontSize),
                    tableHead: TextStyle(
                      color: kHudCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: _fontSize,
                    ),
                    tableBody: TextStyle(
                      color: kHudText,
                      fontSize: _fontSize - 1,
                    ),
                    tableBorder: TableBorder.all(color: kHudBorder),
                    horizontalRuleDecoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: kHudBorder, width: 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
