import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/subjects/data/models/topic.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/features/ai_assistant/data/services/jarvis_brain_service.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;

class NightBeforeOverlay extends StatefulWidget {
  final List<TaskModel> exams;

  const NightBeforeOverlay({super.key, required this.exams});

  @override
  State<NightBeforeOverlay> createState() => _NightBeforeOverlayState();
}

class _NightBeforeOverlayState extends State<NightBeforeOverlay> {
  bool _loading = true;
  String _studyPlan = '';
  List<StudyTopic> _weakTopics = [];
  List<MarkModel> _warnings = [];

  @override
  void initState() {
    super.initState();
    NovaAudioService.playAsset(
      'sounds/attention_critical_exam_detected_for_tomorrow.mp3',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBriefing();
    });
  }

  Future<void> _initializeBriefing() async {
    final state = context.read<AppBloc>().state;

    final subjectIds = widget.exams
        .map((e) => e.subjectId)
        .whereType<int>()
        .toSet();

    // Extract weak topics specifically for the upcoming subjects
    var eligibleTopics = state.topics
        .where(
          (t) =>
              subjectIds.contains(t.subjectId) && !t.isMastered && t.stage < 4,
        )
        .toList();
    eligibleTopics.sort((a, b) => a.stage.compareTo(b.stage));
    _weakTopics = eligibleTopics.take(5).toList();

    // Extract warnings specifically for the upcoming subjects
    _warnings = state.marks
        .where(
          (m) =>
              subjectIds.contains(m.subjectId) &&
              m.lossReason != null &&
              m.lossReason!.isNotEmpty,
        )
        .toList();
    _warnings.sort(
      (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
    );
    _warnings = _warnings.take(3).toList();

    // ── Deep Context Payload Construction ──
    final payloadBuf = StringBuffer();
    payloadBuf.writeln("CRITICAL EXAMS TOMORROW:");
    for (var e in widget.exams) {
      payloadBuf.writeln("- ${e.title} (Priority: ${e.priorityLabel})");
    }
    payloadBuf.writeln();

    for (var subId in subjectIds) {
      final subject = state.subjects.where((s) => s.id == subId).firstOrNull;
      if (subject == null) continue;

      payloadBuf.writeln("=== SUBJECT: ${subject.name} ===");

      // Topics
      final subTopics = state.topics
          .where((t) => t.subjectId == subId)
          .toList();
      if (subTopics.isNotEmpty) {
        payloadBuf.writeln("  [TOPICS & MASTERY]:");
        for (var t in subTopics) {
          final weakFlag = t.stage <= 2 ? "⚠️ WEAK" : "✅ OK";
          payloadBuf.writeln(
            "  - ${t.title} | Stage: ${t.stage} $weakFlag | Notes: ${t.notes.isNotEmpty ? t.notes : 'None'}",
          );
        }
      }

      // Mark Losses (Mark Surgeon)
      final subMarks = state.marks
          .where(
            (m) =>
                m.subjectId == subId &&
                m.lossReason != null &&
                m.lossReason!.isNotEmpty,
          )
          .toList();
      if (subMarks.isNotEmpty) {
        payloadBuf.writeln("  [PAST MISTAKES & LOSSES]:");
        for (var m in subMarks) {
          final lost = m.total - m.obtained;
          payloadBuf.writeln(
            "  - Exam: ${m.label} | Lost $lost marks | Reason: ${m.lossReason}",
          );
        }
      }

      // Exam mistakes
      final expMistakes = state.subjectNotes
          .where((n) => n.subjectId == subId && n.category == 'exam_mistake')
          .toList();
      if (expMistakes.isNotEmpty) {
        payloadBuf.writeln("  [EXAM MISTAKES & WEAKNESSES]:");
        for (var m in expMistakes) {
          payloadBuf.writeln("  - ${m.title}: ${m.content}");
        }
      }

      // Documents
      final subDocs = state.jarvisDocuments
          .where((d) => d.subjectId == subId)
          .toList();
      if (subDocs.isNotEmpty) {
        payloadBuf.writeln("  [AVAILABLE DOCUMENTS/NOTES]:");
        for (var d in subDocs) {
          final snippet = d.content.length > 1500
              ? d.content.substring(0, 1500) + "..."
              : d.content;
          payloadBuf.writeln("  - ${d.name} (${d.type}): $snippet");
        }
      }
      payloadBuf.writeln();
    }

    final plan = await JarvisBrainService.generateNightBeforePlan(
      payloadBuf.toString(),
    );

    if (!mounted) return;
    setState(() {
      _studyPlan = plan;
      _loading = false;
    });
  }

  // ── Save / Load protocols ─────────────────────────────────────────────────
  Future<void> _saveProtocol() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'saved_night_protocols';
    final existing = prefs.getStringList(key) ?? [];
    final examNames = widget.exams.map((e) => e.title).join(', ');
    final entry = jsonEncode({
      'exams': examNames,
      'date': DateTime.now().toIso8601String(),
      'content': _studyPlan,
    });
    existing.insert(0, entry);
    await prefs.setStringList(key, existing);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Protocol saved for review'),
          backgroundColor: Color(0xFF2ED573),
        ),
      );
    }
  }

  void _openSavedProtocols() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'saved_night_protocols';
    final saved = prefs.getStringList(key) ?? [];
    if (saved.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No saved protocols yet'),
            backgroundColor: Colors.grey,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D2B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'SAVED NIGHT PROTOCOLS',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ...saved.asMap().entries.map((e) {
                    final data = jsonDecode(e.value) as Map<String, dynamic>;
                    final exams = data['exams'] ?? 'Protocol';
                    final date = DateTime.tryParse(data['date'] ?? '');
                    final content = data['content'] ?? '';
                    final dateStr = date != null
                        ? '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
                        : '';
                    return ListTile(
                      leading: const Icon(Icons.shield_moon_rounded, color: Colors.redAccent, size: 20),
                      title: Text(
                        exams,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        dateStr,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showSavedProtocolDetail(exams, content);
                      },
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSavedProtocolDetail(String exams, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black87,
          appBar: AppBar(
            backgroundColor: Colors.black87,
            title: Text(
              exams,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w900),
            ),
            iconTheme: const IconThemeData(color: Colors.redAccent),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: MarkdownBody(
              data: content,
              selectable: true,
              builders: {
                'latex': LatexElementBuilder(
                  textStyle: const TextStyle(color: Colors.redAccent, fontSize: 15),
                ),
              },
              extensionSet: md.ExtensionSet(
                [LatexBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
                [LatexInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
              ),
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                h1: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 22),
                h2: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800, fontSize: 18),
                h3: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                em: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
                listBullet: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_moon_rounded,
                      color: Colors.redAccent,
                      size: 64,
                    ),
                    SizedBox(height: 24),
                    CircularProgressIndicator(color: Colors.redAccent),
                    SizedBox(height: 16),
                    Text(
                      'COMPILING NIGHT BEFORE PROTOCOL...',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shield_moon_rounded,
                                color: Colors.redAccent,
                                size: 36,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'NIGHT BEFORE PROTOCOL',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'WARNING: CRITICAL EVENTS TOMORROW',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Target Events
                          const Text(
                            'TARGETS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...widget.exams.map(
                            (e) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.1),
                                border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.3),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      e.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Weak Points
                          if (_weakTopics.isNotEmpty) ...[
                            const Text(
                              'IDENTIFIED VULNERABILITIES',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _weakTopics
                                  .map(
                                    (t) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.redAccent.withOpacity(
                                            0.5,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        t.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Mark Surgeon Warnings
                          if (_warnings.isNotEmpty) ...[
                            const Text(
                              'HISTORIC MARK SURGEON WARNINGS',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._warnings.map(
                              (w) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '• ',
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        w.lossReason!,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // AI Plan
                          const Text(
                            'NOVA TARGET BRIEFING',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Glass(
                            padding: const EdgeInsets.all(20),
                            child: MarkdownBody(
                              data: _studyPlan,
                              selectable: true,
                              builders: {
                                'latex': LatexElementBuilder(
                                  textStyle: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 15,
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
                                p: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                h1: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  letterSpacing: 1.2,
                                ),
                                h2: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  letterSpacing: 1.0,
                                ),
                                h3: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                strong: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                                em: const TextStyle(
                                  color: Colors.white70,
                                  fontStyle: FontStyle.italic,
                                ),
                                listBullet: const TextStyle(color: Colors.redAccent),
                                code: const TextStyle(
                                  color: Colors.black,
                                  backgroundColor: Colors.white70,
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.bold,
                                ),
                                blockquoteDecoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.1),
                                  border: const Border(
                                    left: BorderSide(color: Colors.redAccent, width: 3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Good luck sir. I\'ll leave you to it.',
                                  ),
                                  backgroundColor: Color(0xFF2ED573),
                                ),
                              );
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'I\'m Ready.',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Save & Review buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _studyPlan.length > 50 ? _saveProtocol : null,
                                  icon: const Icon(Icons.save_rounded, size: 16),
                                  label: const Text('SAVE PROTOCOL'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2ED573),
                                    side: const BorderSide(color: Color(0xFF2ED573)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openSavedProtocols,
                                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                                  label: const Text('SAVED'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(color: Colors.redAccent),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
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
      ),
    );
  }
}
