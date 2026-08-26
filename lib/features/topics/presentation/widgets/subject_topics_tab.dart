import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/topics/data/models/topic.dart';
import 'package:study_organizer/features/documents/data/models/study_document.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';
import 'package:study_organizer/features/cognitive_reactor/presentation/widgets/layering_system_overlay.dart';
import 'package:study_organizer/features/cognitive_reactor/presentation/widgets/knowledge_xray_overlay.dart';

class SubjectTopicsTab extends StatelessWidget {
  final Subject subject;
  final List<StudyTopic> topics;
  final List<JarvisDocument> docs;

  const SubjectTopicsTab({
    super.key,
    required this.subject,
    required this.topics,
    required this.docs,
  });

  @override
  Widget build(BuildContext context) {
    return _topicsTab(context, topics, docs);
  }

    Widget _topicsTab(
    BuildContext ctx,
    List<StudyTopic> topics,
    List<JarvisDocument> docs,
  ) {
    if (topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.library_books_rounded,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text("No topics yet.", style: TextStyle(color: Colors.grey)),
            TextButton(
              onPressed: () => _showAddTopic(ctx),
              child: const Text("Add First Topic"),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConfusionCascadeCard(ctx, topics, subject.name),
        ElevatedButton.icon(
          onPressed: () => _showAddTopic(ctx),
          icon: const Icon(Icons.add),
          label: const Text("Add New Topic"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        ...topics.map((t) {
          final isMastered = t.stage >= 5;
          return Glass(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => LayeringSystemOverlay.show(ctx, t),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isMastered
                            ? Colors.green
                            : (t.stage == 0
                                  ? Colors.blue
                                  : const Color(0xFF6C63FF)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            isMastered
                                ? "Mastered"
                                : "Stage ${t.stage} • Layer ${t.currentLayer} • Next: ${t.nextReview != null ? intl.DateFormat('MMM d').format(t.nextReview!) : 'Now'}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          if (t.notes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                t.notes.length > 60
                                    ? '${t.notes.substring(0, 60)}...'
                                    : t.notes,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                  height: 1.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.timer_outlined,
                        color: Colors.cyanAccent,
                      ),
                      onPressed: () {
                        final pastExams = docs
                            .where((d) => d.type == 'past_exam')
                            .toList();
                        showDialog(
                          context: ctx,
                          barrierDismissible: false,
                          builder: (_) => KnowledgeXRayOverlay(
                            subject: subject,
                            topic: t,
                            pastExams: pastExams,
                          ),
                        );
                      },
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

    void _showAddTopic(BuildContext ctx) {
    final c = TextEditingController();
    final p = TextEditingController();
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text("New Topic"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              decoration: const InputDecoration(hintText: "Topic Name"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: p,
              decoration: const InputDecoration(
                hintText: "Prerequisites (comma separated)",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (c.text.isNotEmpty) {
                final prereqs = p.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                ctx.read<AppBloc>().add(
                  AddTopic(
                    StudyTopic(
                      subjectId: subject.id!,
                      title: c.text,
                      prerequisites: prereqs,
                    ),
                  ),
                );
                Navigator.pop(context);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}

Widget _buildConfusionCascadeCard(
  BuildContext context,
  List<StudyTopic> topics,
  String subjectName,
) {
  if (topics.isEmpty) return const SizedBox.shrink();

  // Need subject name. Let's try to extract from topics or pass it.
  // Wait, _buildConfusionCascadeCard could just be inside _SubjectDetailPageState or pass subjectName.
  // Actually, we can use Provider if Subject is accessible, but `topics.first.title` is there.
  // Let's just pass `subject.name` from inside `_topicsTab`!
  // But wait! My previous replacement added `_buildConfusionCascadeCard(ctx, topics)`.
  // I will just read subjectName from the first topic if we can't get it, or better yet, maybe we shouldn't pass it if it's not available.

  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.cyanAccent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ConfusionCascadeDialog(
              subjectName: subjectName,
              topics: topics,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: Colors.cyanAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confusion Cascade Mapper',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Trace topic prerequisites to find root weaknesses.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.cyanAccent,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ConfusionCascadeDialog extends StatefulWidget {
  final String subjectName;
  final List<StudyTopic> topics;

  const _ConfusionCascadeDialog({
    required this.subjectName,
    required this.topics,
  });

  @override
  State<_ConfusionCascadeDialog> createState() =>
      _ConfusionCascadeDialogState();
}

class _ConfusionCascadeDialogState extends State<_ConfusionCascadeDialog> {
  bool _loading = true;
  String _analysis = '';

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final result = await JarvisBrainService.analyzeConfusionCascade(
      subjectName: widget.subjectName,
      topics: widget.topics,
    );
    if (!mounted) return;
    setState(() {
      _analysis = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Glass(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_tree_rounded,
                  color: Colors.cyanAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'CASCADE MAPPER',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                if (!_loading && _analysis.isNotEmpty) ...[
                  IconButton(
                    onPressed: () => Share.share(_analysis),
                    icon: const Icon(
                      Icons.share,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                    tooltip: 'Share Report',
                  ),
                  IconButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final key = 'saved_reports_${widget.subjectName}';
                      final existing = prefs.getStringList(key) ?? [];
                      existing.insert(
                        0,
                        'Cascade Analysis|${DateTime.now().toIso8601String()}|$_analysis',
                      );
                      await prefs.setStringList(key, existing);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Report saved'),
                            backgroundColor: Color(0xFF00796B),
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.save,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                    tooltip: 'Save Report',
                  ),
                ],
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(height: 16),
                    Text(
                      'Tracing root prerequisites...',
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: _analysis,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.6,
                      ),
                      h1: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      em: const TextStyle(
                        color: Colors.lightBlue,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(color: Colors.cyanAccent),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Colors.cyanAccent, width: 3),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.fromLTRB(
                        12,
                        8,
                        12,
                        8,
                      ),
                      tableHead: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      tableBody: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      tableBorder: TableBorder.all(color: Colors.white24),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
