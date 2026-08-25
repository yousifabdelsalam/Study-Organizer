import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:intl/intl.dart' as intl;
import 'package:fl_chart/fl_chart.dart';
import 'package:study_organizer/features/subjects/data/models/topic.dart';
import 'package:study_organizer/features/subjects/data/models/subject_note.dart';
import 'package:study_organizer/features/ai_assistant/data/models/jarvis_document.dart';
import 'package:study_organizer/features/ai_assistant/data/services/jarvis_brain_service.dart';
import 'package:study_organizer/core/database/database_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_intelligence_engine.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/utils/helpers.dart';
import 'package:study_organizer/features/exams/presentation/widgets/knowledge_xray_overlay.dart';
import 'package:study_organizer/features/exams/presentation/pages/exam_prep_hud_page.dart';
import 'package:study_organizer/features/exams/presentation/widgets/post_exam_analyzer.dart';
import 'package:study_organizer/features/exams/presentation/widgets/layering_system_overlay.dart';

class SubjectDetailPage extends StatelessWidget {
  final Subject subject;
  const SubjectDetailPage({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(subject.name),
          bottom: TabBar(
            indicatorColor: Color(subject.color),
            labelColor: Color(subject.color),
            isScrollable: true,
            tabs: const [
              Tab(
                text: 'Attendance',
                icon: Icon(Icons.event_busy_rounded, size: 20),
              ),
              Tab(text: 'Marks', icon: Icon(Icons.grade_rounded, size: 20)),
              Tab(text: 'Tasks', icon: Icon(Icons.task_rounded, size: 20)),
              Tab(
                text: 'Study Topics',
                icon: Icon(Icons.menu_book_rounded, size: 20),
              ),
              Tab(text: 'Notes', icon: Icon(Icons.note_rounded, size: 20)),
              Tab(text: 'NOVA', icon: Icon(Icons.psychology_rounded, size: 20)),
            ],
          ),
        ),
        body: BlocBuilder<AppBloc, AppState>(
          builder: (ctx, state) {
            final abs = state.absences
                .where((a) => a['subjectId'] == subject.id)
                .toList();
            final marks = state.marks
                .where((m) => m.subjectId == subject.id)
                .toList();
            final tasks = state.tasks
                .where((t) => t.subjectId == subject.id)
                .toList();
            final topics = state.topics
                .where((t) => t.subjectId == subject.id)
                .toList();
            final notes = state.subjectNotes
                .where((n) => n.subjectId == subject.id)
                .toList();
            final docs = state.jarvisDocuments
                .where((d) => d.subjectId == subject.id)
                .toList();
            final instructorFocus = state.instructorFocusFor(subject.id ?? 0);
            final lCount = abs.where((a) => a['type'] == 'lecture').length;
            final sCount = abs.where((a) => a['type'] == 'section').length;
            final labCount = abs.where((a) => a['type'] == 'lab').length;

            return TabBarView(
              children: [
                _attendanceTab(ctx, abs, lCount, sCount, labCount),
                _marksTab(ctx, marks, abs, docs),
                _tasksTab(context, tasks, state.subjects),
                _topicsTab(ctx, topics, docs),
                _notesTab(ctx, notes),
                _JarvisTab(
                  subject: subject,
                  docs: docs,
                  instructorFocus: instructorFocus,
                ),
              ],
            );
          },
        ),
      ),
    );
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

  // ═══════════════ NOTES TAB ════════════════════════════════════════════════
  Widget _notesTab(BuildContext ctx, List<SubjectNote> notes) {
    final categories = <String>{};
    for (final n in notes) categories.add(n.category);
    if (categories.isEmpty) categories.add('General');
    final sortedCats = categories.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddNote(ctx),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Note'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(subject.color),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.note_add_rounded,
                    size: 48,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No notes yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ...sortedCats.map((cat) {
          final catNotes = notes.where((n) => n.category == cat).toList();
          if (catNotes.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cat == 'exam_mistake'
                            ? Colors.redAccent.withOpacity(0.15)
                            : Color(subject.color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        cat == 'exam_mistake'
                            ? '❌ Exam Mistakes (NOVA Strategy)'
                            : cat,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cat == 'exam_mistake'
                              ? Colors.redAccent
                              : Color(subject.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${catNotes.length} note${catNotes.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              ...catNotes.map((note) {
                final isMistake = note.category == 'exam_mistake';
                return Glass(
                  padding: const EdgeInsets.all(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showEditNote(ctx, note),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isMistake)
                              const Padding(
                                padding: EdgeInsets.only(right: 8.0),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                note.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isMistake
                                      ? Colors.redAccent
                                      : Colors.white,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onSelected: (action) {
                                if (action == 'edit') _showEditNote(ctx, note);
                                if (action == 'delete')
                                  _confirmDeleteNote(ctx, note);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_rounded,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_rounded,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (note.content.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            note.content.length > 250
                                ? '${note.content.substring(0, 250)}...'
                                : note.content,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMistake
                                  ? Colors.red.shade200
                                  : Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (note.updatedAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Updated ${intl.DateFormat('MMM d, h:mm a').format(note.updatedAt!)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        }),
      ],
    );
  }

  // ═══════════════ ALL OTHER TABS (unchanged) ════════════════════════════════

  Widget _attendanceTab(
    BuildContext ctx,
    List<Map<String, dynamic>> abs,
    int lC,
    int sC,
    int labC,
  ) {
    final s = subject;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: [
        Glass(
          child: Column(
            children: [
              const Text(
                'Attendance Overview',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 160,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ring('Lecture', lC, s.maxLectureAbs, Color(s.color)),
                    if (s.hasSection)
                      _ring('Section', sC, s.maxSectionAbs, Colors.teal),
                    if (s.hasLab)
                      _ring('Lab', labC, s.maxLabAbs, Colors.orange),
                  ],
                ),
              ),
            ],
          ),
        ),
        _absCard(
          ctx,
          'Lectures',
          lC,
          s.maxLectureAbs,
          'lecture',
          Color(s.color),
        ),
        if (s.hasSection)
          _absCard(
            ctx,
            'Sections',
            sC,
            s.maxSectionAbs,
            'section',
            Colors.teal,
          ),
        if (s.hasLab)
          _absCard(ctx, 'Labs', labC, s.maxLabAbs, 'lab', Colors.orange),
        if (abs.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Records',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          ...abs.map(
            (a) => Glass(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    a['type'] == 'lecture'
                        ? Icons.school_rounded
                        : a['type'] == 'section'
                        ? Icons.engineering_rounded
                        : Icons.science_rounded,
                    size: 18,
                    color: Color(s.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(a['type'] as String)[0].toUpperCase()}${(a['type'] as String).substring(1)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          a['date'] ?? '',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.red,
                      size: 18,
                    ),
                    onPressed: () =>
                        ctx.read<AppBloc>().add(DeleteAbsence(a['id'])),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ring(String label, int current, int max, Color color) {
    final p = max > 0 ? current / max : 0.0;
    final c = p >= 1.0
        ? const Color(0xFFFF4757)
        : p >= 0.75
        ? const Color(0xFFFF9F43)
        : color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 70,
          height: 70,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: p.clamp(0, 1),
                strokeWidth: 7,
                backgroundColor: Colors.grey.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(c),
              ),
              Center(
                child: Text(
                  '$current/$max',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: c,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(
          '${max - current} left',
          style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _absCard(
    BuildContext ctx,
    String label,
    int cur,
    int max,
    String type,
    Color color,
  ) {
    return Glass(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (max > 0 ? cur / max : 0.0).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: Colors.grey.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(
                      cur >= max ? const Color(0xFFFF4757) : color,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cur / $max',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: ctx,
                initialDate: DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 180)),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (date != null)
                ctx.read<AppBloc>().add(
                  AddAbsence(
                    subject.id!,
                    intl.DateFormat('yyyy-MM-dd').format(date),
                    type,
                  ),
                );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withOpacity(0.15),
              foregroundColor: color,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              '+ Add',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsenceColliderCard(
    BuildContext context,
    List<MarkModel> marks,
    List<Map<String, dynamic>> absences,
    List<JarvisDocument> docs,
  ) {
    if (absences.isEmpty || marks.isEmpty) return const SizedBox.shrink();

    return Glass(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Absence-Mark Collider',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'NOVA can analyze if your missed classes correlate to recent low marks and identify what topics you likely missed.',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => _AbsenceColliderDialog(
                  subjectName: subject.name,
                  absences: absences,
                  marks: marks,
                  docs: docs,
                ),
              );
            },
            icon: const Icon(Icons.analytics_rounded, size: 18),
            label: const Text('Run Collision Analysis'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withOpacity(0.2),
              foregroundColor: Colors.redAccent,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marksTab(
    BuildContext ctx,
    List<MarkModel> marks,
    List<Map<String, dynamic>> absences,
    List<JarvisDocument> docs,
  ) {
    final cats = <String, List<MarkModel>>{};
    for (final m in marks) cats.putIfAbsent(m.category, () => []).add(m);
    double totalObt = 0, totalMax = 0;
    for (final m in marks) {
      totalObt += m.obtained;
      totalMax += m.total;
    }
    final pct = totalMax > 0 ? totalObt / totalMax * 100 : 0.0;
    final catLabels = {
      'midterm1': '5th Week Mid',
      'midterm2': '10th Week Mid',
      'quiz': 'Quizzes',
      'assignment': 'Assignments',
      'project': 'Projects',
      'report': 'Reports',
      'final': 'Final',
      'other': 'Other',
    };
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: [
        Glass(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (pct / 100).clamp(0, 1),
                      strokeWidth: 7,
                      backgroundColor: Colors.grey.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(Color(subject.color)),
                    ),
                    Center(
                      child: Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(subject.color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${totalObt.toStringAsFixed(1)} / ${totalMax.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'GPA estimate: ${_estimateGrade(pct)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '${marks.length} entries',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildAbsenceColliderCard(ctx, marks, absences, docs),
        const SizedBox(height: 8),
        // Saved Reports History button
        GestureDetector(
          onTap: () => _showSavedReports(ctx, subject.name),
          child: Glass(
            child: Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  color: Color(0xFF6C63FF),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 Saved Reports',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'View previously saved analysis reports',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
        if (marks.isNotEmpty)
          Glass(
            child: SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                        '${r.toY.toStringAsFixed(1)}%',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < marks.length)
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                marks[idx].label.length > 6
                                    ? '${marks[idx].label.substring(0, 6)}..'
                                    : marks[idx].label,
                                style: const TextStyle(fontSize: 8),
                              ),
                            );
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    marks.length,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: marks[i].percentage.clamp(0, 100),
                          color: Color(subject.color),
                          width: max(8, 24 - marks.length * 1.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ...cats.entries.map((e) {
          final catTotal = e.value.fold<double>(0, (s, m) => s + m.obtained);
          final catMax = e.value.fold<double>(0, (s, m) => s + m.total);
          return Glass(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      catLabels[e.key] ?? e.key,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(subject.color),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${catTotal.toStringAsFixed(1)}/${catMax.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...e.value.map(
                  (m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            m.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          '${m.obtained.toStringAsFixed(1)}/${m.total.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${m.percentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: m.percentage >= 85
                                ? const Color(0xFF2ED573)
                                : m.percentage >= 60
                                ? const Color(0xFFFF9F43)
                                : const Color(0xFFFF4757),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.red,
                          ),
                          onPressed: () =>
                              ctx.read<AppBloc>().add(DeleteMark(m.id!)),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.only(left: 4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(
            onPressed: () => _showAddMark(ctx),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Mark'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(subject.color),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _estimateGrade(double pct) {
    if (pct >= 93) return 'A (4.0)';
    if (pct >= 89) return 'A- (3.7)';
    if (pct >= 84) return 'B+ (3.3)';
    if (pct >= 80) return 'B (3.0)';
    if (pct >= 76) return 'B- (2.7)';
    if (pct >= 73) return 'C+ (2.3)';
    if (pct >= 70) return 'C (2.0)';
    if (pct >= 67) return 'C- (1.7)';
    if (pct >= 64) return 'D+ (1.3)';
    if (pct >= 60) return 'D (1.0)';
    return 'F (0.0)';
  }

  void _showAddMark(BuildContext ctx) {
    final labelC = TextEditingController();
    final obtC = TextEditingController();
    final totC = TextEditingController(text: '100');
    String cat = 'midterm1';
    const catOptions = {
      'midterm1': '5th Week Midterm',
      'midterm2': '10th Week Midterm',
      'quiz': 'Quiz',
      'assignment': 'Assignment',
      'project': 'Project',
      'report': 'Report',
      'final': 'Final Exam',
      'other': 'Other',
    };
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Add Mark',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: cat,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                      items: catOptions.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => cat = v!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: labelC,
                      decoration: const InputDecoration(
                        labelText: 'Label (e.g. Quiz 1)',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: obtC,
                            decoration: const InputDecoration(
                              labelText: 'Obtained',
                              prefixIcon: Icon(Icons.star_rounded),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '/',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: totC,
                            decoration: const InputDecoration(
                              labelText: 'Total',
                              prefixIcon: Icon(Icons.star_border_rounded),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [10, 15, 20, 25, 30, 40, 50, 100].map((v) {
                        final selected = totC.text == v.toString();
                        return GestureDetector(
                          onTap: () => setS(() => totC.text = v.toString()),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Color(subject.color).withOpacity(0.2)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? Color(subject.color)
                                    : Colors.grey.withOpacity(0.3),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              '/ $v',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: selected
                                    ? Color(subject.color)
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (labelC.text.isEmpty || obtC.text.isEmpty) {
                          ScaffoldMessenger.of(c).showSnackBar(
                            const SnackBar(content: Text('Fill all fields')),
                          );
                          return;
                        }
                        final obt = double.tryParse(obtC.text) ?? 0;
                        final tot = double.tryParse(totC.text) ?? 100;

                        if (obt < tot) {
                          Navigator.pop(c);
                          _showMarkSurgeonPrompt(
                            ctx,
                            cat,
                            labelC.text.trim(),
                            obt,
                            tot,
                          );
                          return;
                        }

                        ctx.read<AppBloc>().add(
                          AddMark(
                            MarkModel(
                              subjectId: subject.id,
                              category: cat,
                              label: labelC.text.trim(),
                              obtained: obt,
                              total: tot,
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(subject.color),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMarkSurgeonPrompt(
    BuildContext ctx,
    String category,
    String label,
    double obtained,
    double total,
  ) {
    final reasonC = TextEditingController();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        '💉 The Mark Surgeon',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF4757),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You lost ${total - obtained} marks on $label. What exactly did you lose marks on? (e.g., "Skipped formula derivation", "Sign error in node analysis")',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonC,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Root Cause / Loss Reason',
                        prefixIcon: Icon(Icons.healing_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        ctx.read<AppBloc>().add(
                          AddMark(
                            MarkModel(
                              subjectId: subject.id,
                              category: category,
                              label: label,
                              obtained: obtained,
                              total: total,
                              lossReason: reasonC.text.trim().isEmpty
                                  ? null
                                  : reasonC.text.trim(),
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4757),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save Mark & Reason'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        ctx.read<AppBloc>().add(
                          AddMark(
                            MarkModel(
                              subjectId: subject.id,
                              category: category,
                              label: label,
                              obtained: obtained,
                              total: total,
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      child: const Text('Skip (Not recommended)'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tasksTab(
    BuildContext ctx,
    List<TaskModel> tasks,
    List<Subject> subs,
  ) {
    final pending = tasks.where((t) => !t.isCompleted && !t.isFailed).toList();
    final done = tasks.where((t) => t.isCompleted).toList();
    final failed = tasks.where((t) => t.isFailed).toList();
    if (tasks.isEmpty)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_rounded,
              size: 44,
              color: Colors.grey.withOpacity(0.3),
            ),
            const SizedBox(height: 6),
            const Text('No tasks', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    return _TasksTabContent(
      pending: pending,
      done: done,
      failed: failed,
      subs: subs,
      buildCard: (t) => _subjectTaskCard(ctx, t, subs),
      onShowDetails: (t) => _showSubjectTaskDetails(ctx, t, subs),
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

  void _showAddNote(BuildContext ctx) {
    final titleC = TextEditingController();
    final contentC = TextEditingController();
    final categoryC = TextEditingController(text: 'General');
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(c).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Add Note',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: categoryC,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children:
                          ['General', 'Lecture', 'Lab', 'Exam', 'Important']
                              .map(
                                (cat) => GestureDetector(
                                  onTap: () => setS(() => categoryC.text = cat),
                                  child: Chip(
                                    label: Text(
                                      cat,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    backgroundColor: categoryC.text == cat
                                        ? Color(subject.color).withOpacity(0.2)
                                        : null,
                                    side: BorderSide(
                                      color: categoryC.text == cat
                                          ? Color(subject.color)
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contentC,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Content',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (titleC.text.trim().isEmpty) {
                          ScaffoldMessenger.of(c).showSnackBar(
                            const SnackBar(content: Text('Enter a title')),
                          );
                          return;
                        }
                        ctx.read<AppBloc>().add(
                          AddSubjectNote(
                            SubjectNote(
                              subjectId: subject.id!,
                              title: titleC.text.trim(),
                              category: categoryC.text.trim().isEmpty
                                  ? 'General'
                                  : categoryC.text.trim(),
                              content: contentC.text.trim(),
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(subject.color),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save Note'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditNote(BuildContext ctx, SubjectNote note) {
    final titleC = TextEditingController(text: note.title);
    final contentC = TextEditingController(text: note.content);
    final categoryC = TextEditingController(text: note.category);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(c).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Edit Note',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: categoryC,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contentC,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Content',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (titleC.text.trim().isEmpty) return;
                        ctx.read<AppBloc>().add(
                          UpdateSubjectNote(
                            note.copyWith(
                              title: titleC.text.trim(),
                              category: categoryC.text.trim().isEmpty
                                  ? 'General'
                                  : categoryC.text.trim(),
                              content: contentC.text.trim(),
                              updatedAt: DateTime.now(),
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(subject.color),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteNote(BuildContext ctx, SubjectNote note) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Note?'),
        content: Text('Delete "${note.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ctx.read<AppBloc>().add(DeleteSubjectNote(note.id!));
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _subjectTaskCard(BuildContext ctx, TaskModel t, List<Subject> subs) {
    return Dismissible(
      key: Key('st${t.id}_${t.isCompleted}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          final ok =
              await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text('Delete Task?'),
                  content: Text('Delete "${t.title}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Color(0xFFFF4757)),
                      ),
                    ),
                  ],
                ),
              ) ??
              false;
          if (ok) ctx.read<AppBloc>().add(DeleteTask(t.id!));
          return ok;
        } else {
          final ok =
              await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    t.isCompleted ? 'Mark as Pending?' : 'Mark as Done?',
                  ),
                  content: Text(
                    '${t.isCompleted ? 'Mark as pending' : 'Mark as done'} "${t.title}"?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(
                        t.isCompleted ? 'Mark Pending' : 'Mark Done',
                        style: const TextStyle(color: Color(0xFF2ED573)),
                      ),
                    ),
                  ],
                ),
              ) ??
              false;
          if (ok) ctx.read<AppBloc>().add(ToggleTask(t.id!, !t.isCompleted));
          return false;
        }
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2ED573),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              t.isCompleted ? Icons.undo_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              t.isCompleted ? 'Undo' : 'Done',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4757),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
      child: Glass(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showSubjectTaskDetails(ctx, t, subs),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.priorityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => ctx.read<AppBloc>().add(
                    ToggleTask(t.id!, !t.isCompleted),
                  ),
                  onLongPress: () =>
                      ctx.read<AppBloc>().add(FailTask(t.id!, !t.isFailed)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.isFailed
                          ? const Color(0xFFFF4757)
                          : t.isCompleted
                          ? const Color(0xFF2ED573)
                          : Colors.transparent,
                      border: Border.all(
                        color: t.isFailed
                            ? const Color(0xFFFF4757)
                            : t.isCompleted
                            ? const Color(0xFF2ED573)
                            : t.priorityColor,
                        width: 2,
                      ),
                    ),
                    child: t.isFailed
                        ? const Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: Colors.white,
                          )
                        : t.isCompleted
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AText(
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: (t.isCompleted || t.isFailed)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (t.dueDate != null)
                        Text(
                          intl.DateFormat('MMM d, h:mm a').format(t.dueDate!),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: t.priorityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t.priorityLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: t.priorityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (t.isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ED573).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFF2ED573),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (t.isFailed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4757).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Failed',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFFF4757),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSubjectTaskDetails(
    BuildContext context,
    TaskModel t,
    List<Subject> subs,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final d = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: d ? const Color(0xFF12122A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(t.typeIcon, color: t.priorityColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AText(
                      t.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (t.isCompleted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ED573).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Color(0xFF2ED573),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2ED573),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _detailChipLocal(
                      Icons.menu_book_rounded,
                      subjectName(subs, t.subjectId),
                    ),
                    const SizedBox(width: 8),
                    _detailChipLocal(
                      Icons.priority_high_rounded,
                      "${t.priorityLabel} Priority",
                      color: t.priorityColor,
                    ),
                    const SizedBox(width: 8),
                    _detailChipLocal(
                      Icons.category_rounded,
                      t.type[0].toUpperCase() + t.type.substring(1),
                    ),
                  ],
                ),
              ),
              const Divider(height: 30),
              const Text(
                "Description",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              AText(
                t.description.isEmpty
                    ? "No description provided."
                    : t.description,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (t.dueDate != null) ...[
                const Text(
                  "Deadline",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      intl.DateFormat('EEEE, MMM d, yyyy').format(t.dueDate!),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      intl.DateFormat('h:mm a').format(t.dueDate!),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final now = DateTime.now();
                    final diff = t.dueDate!.difference(now);
                    String remaining;
                    Color remainColor;
                    if (diff.isNegative) {
                      remaining =
                          'Overdue by ${diff.abs().inDays}d ${diff.abs().inHours % 24}h';
                      remainColor = const Color(0xFFFF4757);
                    } else if (diff.inDays > 0) {
                      remaining =
                          '${diff.inDays}d ${diff.inHours % 24}h remaining';
                      remainColor = const Color(0xFF2ED573);
                    } else if (diff.inHours > 0) {
                      remaining =
                          '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
                      remainColor = const Color(0xFFFF9F43);
                    } else {
                      remaining = '${diff.inMinutes}m remaining';
                      remainColor = const Color(0xFFFF4757);
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: remainColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timelapse_rounded,
                            size: 16,
                            color: remainColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            remaining,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: remainColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 30),
              // ── State-change action buttons ──
              Row(
                children: [
                  if (!t.isFailed)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<AppBloc>().add(FailTask(t.id!, true));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.cancel_rounded, size: 16),
                        label: const Text('Mark as Failed'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF4757),
                          side: const BorderSide(color: Color(0xFFFF4757)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (t.isFailed) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<AppBloc>().add(FailTask(t.id!, false));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('Restore to Pending'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2ED573),
                          side: const BorderSide(color: Color(0xFF2ED573)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailChipLocal(
    IconData icon,
    String label, {
    Color color = Colors.grey,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOVA TAB — Stateful widget for editable instructor focus + PDF/PPTX upload
// ═══════════════════════════════════════════════════════════════════════════════
class _JarvisTab extends StatefulWidget {
  final Subject subject;
  final List<JarvisDocument> docs;
  final String instructorFocus;

  const _JarvisTab({
    required this.subject,
    required this.docs,
    required this.instructorFocus,
  });

  @override
  State<_JarvisTab> createState() => _JarvisTabState();
}

class _JarvisTabState extends State<_JarvisTab> {
  late TextEditingController _focusController;
  bool _editingFocus = false;
  bool _uploadingFile = false;
  String _uploadStatus = 'AI is reading your file...';
  // ── Intel Card ──
  String? _intelCard;
  bool _loadingCard = false;
  bool _generatingCard = false;

  @override
  void initState() {
    super.initState();
    _focusController = TextEditingController(text: widget.instructorFocus);
    _loadIntelCard();
  }

  @override
  void didUpdateWidget(_JarvisTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editingFocus && oldWidget.instructorFocus != widget.instructorFocus) {
      _focusController.text = widget.instructorFocus;
    }
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  Future<void> _loadIntelCard() async {
    if (widget.subject.id == null) return;
    setState(() => _loadingCard = true);
    final card = await NovaIntelligenceEngine.loadIntelCard(widget.subject.id!);
    if (mounted)
      setState(() {
        _intelCard = card;
        _loadingCard = false;
      });
  }

  Future<void> _generateIntelCard() async {
    setState(() => _generatingCard = true);
    final card = await NovaIntelligenceEngine.generateIntelCard(widget.subject);
    if (mounted)
      setState(() {
        _intelCard = card.isEmpty ? null : card;
        _generatingCard = false;
      });
  }

  // ── MIME type by file extension ─────────────────────────────────────────────
  Widget _intelCardSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF39FF14).withOpacity(0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF39FF14).withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF39FF14).withOpacity(0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFF39FF14),
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  'NOVA  INTEL  CARD',
                  style: TextStyle(
                    color: Color(0xFF39FF14),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    fontFamily: 'Courier',
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _generatingCard ? null : _generateIntelCard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF39FF14).withOpacity(0.5),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _generatingCard
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF39FF14),
                            ),
                          )
                        : Text(
                            _intelCard == null ? '⚡ Generate' : '🔄 Regen',
                            style: const TextStyle(
                              color: Color(0xFF39FF14),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: _loadingCard
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: Color(0xFF39FF14),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : _intelCard == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No intel card yet.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upload past exams and lecture notes first, then tap Generate. NOVA will analyze your instructor\'s exam pattern and predict likely questions.',
                        style: TextStyle(
                          color: Colors.white24,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  )
                : SelectableText(
                    _intelCard!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.65,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _mimeType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'text/plain';
    }
  }

  // ── Sanitize text (prevent crashes from bad unicode) ──────────────────────
  String _sanitizeText(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      if (rune == 0) continue;
      if (rune >= 0xD800 && rune <= 0xDFFF) continue;
      if (rune > 0x10FFFF) continue;
      buffer.writeCharCode(rune);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .trim();
  }

  void _showNoApiKeySnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Set your Gemini API key first: open NOVA overlay → Settings (key icon)',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  // ── MAIN UPLOAD FLOW ────────────────────────────────────────────────────────
  // Strategy:
  //   PDF/PPTX/Images → Gemini Files API (upload once, get URI, use forever)
  //   TXT/MD           → Read directly
  //
  // Why Files API?
  //   • Handles files up to 20MB natively
  //   • No base64 encoding (avoids payload limits)
  //   • No chunking PDF bytes (broken PDF = empty result)
  //   • Gemini reads the PDF as a document, not OCR
  //   • Same URI can be reused for deep analysis (Break Doctor Brain)
  Future<void> _pickAndAddDocument(String type) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'pptx',
          'ppt',
          'txt',
          'md',
          'jpg',
          'jpeg',
          'png',
        ],
        withData: false,
        allowMultiple: false,
      );
      if (picked == null || picked.files.single.path == null) return;

      final file = picked.files.single;
      final path = file.path!;
      final ext = path.split('.').last.toLowerCase();
      final name = file.name;

      // ── Plain text: read directly ──────────────────────────────────────────
      if (ext == 'txt' || ext == 'md') {
        setState(() {
          _uploadingFile = true;
          _uploadStatus = 'Reading file...';
        });
        String text = '';
        try {
          text = _sanitizeText(await File(path).readAsString());
        } catch (_) {}
        setState(() => _uploadingFile = false);
        if (text.isEmpty) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File appears to be empty.')),
            );
          return;
        }
        if (mounted)
          _showAddDocSheet(name, text, type, fileUri: null, fileMime: null);
        return;
      }

      // ── Binary files (PDF, PPTX, images): use Gemini Files API ──────────────
      final apiKey = await JarvisBrainService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _showNoApiKeySnack();
        return;
      }

      final bytes = await File(path).readAsBytes();
      final fileSize = bytes.length;
      final mime = _mimeType(ext);

      setState(() {
        _uploadingFile = true;
        _uploadStatus =
            'Uploading ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB to Gemini...';
      });

      // Step 1: Upload file to Gemini Files API → get URI
      final uploaded = await JarvisBrainService.uploadFileToGemini(
        bytes: bytes,
        mimeType: mime,
        displayName: name,
        onStatus: (s) {
          if (mounted) setState(() => _uploadStatus = s);
        },
      );

      if (uploaded == null) {
        setState(() => _uploadingFile = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Upload failed. Check your API key and internet connection.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final fileUri = uploaded['uri']!;
      final fileMime = uploaded['mimeType']!;

      // Step 2: Extract text using the URI (for NOVA chat context / search)
      // Note: even if text extraction returns 0 chars, the file URI is still valid
      // and "Break Doctor Brain" will work using the URI directly.
      setState(() => _uploadStatus = 'Extracting text for search...');
      final extracted = await JarvisBrainService.extractTextFromFileUri(
        fileUri: fileUri,
        mimeType: fileMime,
      );

      setState(() => _uploadingFile = false);
      if (!mounted) return;

      // Show confirmation sheet. File URI is always valid even if text = empty.
      // User can still run "Break Doctor Brain NOW" which uses the URI directly.
      _showAddDocSheet(
        name,
        extracted,
        type,
        fileUri: fileUri,
        fileMime: fileMime,
      );
    } catch (e) {
      setState(() => _uploadingFile = false);
      debugPrint('_pickAndAddDocument error: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAddDocSheet(
    String defaultName,
    String extractedContent,
    String type, {
    required String? fileUri, // Gemini Files API URI (null for text files)
    required String? fileMime, // MIME type for the uploaded file
  }) {
    final nameController = TextEditingController(text: defaultName);
    final contentController = TextEditingController(text: extractedContent);
    final subjectId = widget.subject.id ?? 0;
    final charCount = extractedContent.length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(c).size.height * 0.9,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(c).brightness == Brightness.dark
                ? const Color(0xFF12122A)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    type == 'past_exam'
                        ? Icons.quiz_rounded
                        : Icons.description_rounded,
                    color: type == 'past_exam'
                        ? Colors.orange
                        : const Color(0xFF6C63FF),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    type == 'past_exam' ? 'Add Past Exam' : 'Add Document',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    fileUri != null ? 'Uploaded ✓' : 'Ready',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      charCount > 0
                          ? '$charCount chars extracted'
                          : 'Use Brain analysis below',
                      style: TextStyle(
                        fontSize: 12,
                        color: charCount > 0 ? Colors.grey : Colors.orange,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: type == 'past_exam'
                      ? 'e.g. Midterm 2024'
                      : 'e.g. Chapter 3 notes',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: TextField(
                  controller: contentController,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: charCount > 0
                        ? 'Extracted text ($charCount chars, editable)'
                        : 'Could not extract text — Run "Break Doctor Brain" below for full AI analysis',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Save button
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save to NOVA Memory'),
                onPressed: () {
                  final docName = nameController.text.trim();
                  final docContent = contentController.text.trim();
                  if (docName.isEmpty) {
                    ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(content: Text('Enter a name')),
                    );
                    return;
                  }
                  context.read<AppBloc>().add(
                    AddJarvisDocument(
                      JarvisDocument(
                        subjectId: subjectId,
                        type: type,
                        name: docName,
                        content: docContent,
                        fileUri: fileUri,
                        fileMime: fileMime,
                      ),
                    ),
                  );
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('\'$docName\' added to NOVA memory'),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              // Break Doctor Brain button (only if file was uploaded via Files API)
              if (fileUri != null) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.psychology_alt_rounded),
                  label: const Text('🔬 Break Doctor Brain NOW'),
                  onPressed: () {
                    final docName = nameController.text.trim().isEmpty
                        ? defaultName
                        : nameController.text.trim();
                    final docContent = contentController.text.trim();
                    // Save first, then analyze
                    context.read<AppBloc>().add(
                      AddJarvisDocument(
                        JarvisDocument(
                          subjectId: subjectId,
                          type: type,
                          name: docName,
                          content: docContent,
                          fileUri: fileUri,
                          fileMime: fileMime,
                        ),
                      ),
                    );
                    Navigator.pop(c);
                    // Run deep analysis using file URI
                    _runDirectDeepAnalysis(
                      docName: docName,
                      docType: type,
                      fileUri: fileUri,
                      fileMime: fileMime!,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4757),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    'Analyze now — crack the exam pattern instantly',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Run deep analysis using file URI directly (no text extraction needed) ──
  Future<void> _runDirectDeepAnalysis({
    required String docName,
    required String docType,
    required String fileUri,
    required String fileMime,
  }) async {
    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF6C63FF)),
              const SizedBox(height: 20),
              const Text(
                '🔬 Breaking Doctor Brain...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'NOVA is reading $docName\nThis takes 30-60 seconds.',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Gemini is analyzing the document directly\n(not OCR — actual content understanding)',
                style: TextStyle(color: Colors.white38, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    final state = context.read<AppBloc>().state;
    final subject =
        state.subjects.where((s) => s.id == widget.subject.id).firstOrNull ??
        widget.subject;
    final subjectDocs = state.jarvisDocuments
        .where((d) => d.subjectId == widget.subject.id)
        .toList();
    final allContext = subjectDocs
        .map(
          (d) =>
              '[${d.name}]:\n${d.content.substring(0, d.content.length.clamp(0, 1500))}',
        )
        .join('\n\n');

    final analysis = await JarvisBrainService.analyzeFileDirectly(
      fileUri: fileUri,
      mimeType: fileMime,
      subjectName: subject.name,
      doctorName: subject.doctorName,
      docType: docType,
      docName: docName,
      allSubjectContext: allContext,
    );

    if (mounted) {
      Navigator.of(context).pop(); // Close loading
      _displayAnalysisReport(docName, analysis, fromCache: false);
    }
  }

  void _confirmDeleteDoc(JarvisDocument doc) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove from NOVA memory?'),
        content: Text(
          'Delete "${doc.name}"? NOVA will no longer have access to this content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (doc.id != null)
                context.read<AppBloc>().add(DeleteJarvisDocument(doc.id!));
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectId = widget.subject.id ?? 0;
    final subjectColor = Color(widget.subject.color);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Instructor Focus Card ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: subjectColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: subjectColor.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_rounded, color: subjectColor, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Instructor Focus',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const Spacer(),
                  if (widget.instructorFocus.isNotEmpty && !_editingFocus)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          color: Colors.grey,
                          onPressed: () => setState(() => _editingFocus = true),
                          tooltip: 'Edit',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          color: Colors.redAccent,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Clear instructor focus?'),
                                content: const Text(
                                  'This will remove the focus note for this subject.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      context.read<AppBloc>().add(
                                        SetInstructorFocus(subjectId, ''),
                                      );
                                      Navigator.pop(c);
                                      setState(() {
                                        _focusController.text = '';
                                        _editingFocus = false;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            );
                          },
                          tooltip: 'Delete',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'What does the instructor emphasize? NOVA uses this for exam advice.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              if (!_editingFocus && widget.instructorFocus.isNotEmpty)
                // Display mode
                GestureDetector(
                  onTap: () => setState(() => _editingFocus = true),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      widget.instructorFocus,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                )
              else
                // Edit mode
                Column(
                  children: [
                    TextField(
                      controller: _focusController,
                      maxLines: 3,
                      autofocus: _editingFocus,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Problem-solving, definitions from slides, past exam style',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_editingFocus && widget.instructorFocus.isNotEmpty)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() {
                                _focusController.text = widget.instructorFocus;
                                _editingFocus = false;
                              }),
                              child: const Text('Cancel'),
                            ),
                          ),
                        if (_editingFocus && widget.instructorFocus.isNotEmpty)
                          const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<AppBloc>().add(
                                SetInstructorFocus(
                                  subjectId,
                                  _focusController.text.trim(),
                                ),
                              );
                              setState(() => _editingFocus = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Saved. NOVA will use this.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: const Text('Save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: subjectColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── EXAM PREPARATION BUTTON ──────────────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7F00FF).withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _runExamPrep,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 20,
                ),
                child: Row(
                  children: [
                    const Text('🧠', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXAM PREPARATION',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Full enigma breakdown + predictions + exam generator',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ── POST-EXAM REVIEW BUTTON ───────────────────────────────────────────
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1A1A2E), subjectColor.withOpacity(0.25)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: subjectColor.withOpacity(0.45)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => PostExamAnalyzer.show(context, widget.subject),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                child: Row(
                  children: [
                    const Text('📝', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ANALYZE PAST EXAM',
                            style: TextStyle(
                              color: subjectColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Upload exam → NOVA reviews each question → saves mistakes to all future plans',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: subjectColor,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── NOVA Subject Intel Card ────────────────────────────────────────────
        _intelCardSection(),

        const SizedBox(height: 8),

        // ── Documents & Past Exams ─────────────────────────────────────────────────────────────────────────
        // ── Documents & Past Exams ───────────────────────────────────────────
        Row(
          children: [
            const Icon(
              Icons.folder_special_rounded,
              color: Color(0xFF6C63FF),
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'NOVA Memory',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const Spacer(),
            Text(
              '${widget.docs.length} files',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Feed NOVA with documents and past exams. Supports PDF, PowerPoint, and text files.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        // Upload buttons
        if (_uploadingFile)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _uploadStatus,
                    style: const TextStyle(color: Color(0xFF9D97FF)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickAndAddDocument('document'),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Add Document'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6C63FF),
                    side: const BorderSide(color: Color(0xFF6C63FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickAndAddDocument('past_exam'),
                  icon: const Icon(Icons.quiz_rounded, size: 18),
                  label: const Text('Past Exam'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

        const SizedBox(height: 8),
        // Supported formats hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Supported: PDF, .pptx, .ppt, .txt, .md',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _buildGapDetectorCard(context),
        const SizedBox(height: 16),

        // Documents list
        if (widget.docs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 48,
                    color: Colors.grey.withOpacity(0.4),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No files yet. Add a past exam or document.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...widget.docs.map((d) => _docCard(d, subjectColor)),
      ],
    );
  }

  Widget _docCard(JarvisDocument d, Color subjectColor) {
    final isPastExam = d.isPastExam;
    final color = isPastExam ? Colors.orange : const Color(0xFF6C63FF);
    final charCount = d.content.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPastExam ? Icons.quiz_rounded : Icons.description_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isPastExam ? 'Past Exam' : 'Document',
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$charCount chars',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Deep analyze button
              IconButton(
                icon: const Icon(
                  Icons.psychology_alt_rounded,
                  color: Color(0xFF6C63FF),
                  size: 20,
                ),
                onPressed: () => _showDeepAnalysis(d),
                tooltip: 'Deep Analysis — Break the Doctor Brain',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () => _confirmDeleteDoc(d),
                tooltip: 'Remove from NOVA memory',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showDeepAnalysis(JarvisDocument doc) async {
    // Check cached analysis
    try {
      final db = await DatabaseHelper.instance.database;
      final cached = await db.query(
        'jarvis_doc_analysis',
        where: 'docId = ?',
        whereArgs: [doc.id ?? -1],
        limit: 1,
      );
      if (cached.isNotEmpty) {
        _displayAnalysisReport(
          doc.name,
          cached.first['analysis'] as String,
          fromCache: true,
        );
        return;
      }
    } catch (_) {}

    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C63FF)),
            const SizedBox(height: 20),
            const Text(
              '🔬 Breaking Doctor Brain...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Analyzing ${doc.name}',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              '30-90 seconds — reading the full document',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    final state = context.read<AppBloc>().state;
    final subjectDocs = state.jarvisDocuments
        .where((d) => d.subjectId == doc.subjectId)
        .toList();
    final allContext = subjectDocs
        .where((d) => d.id != doc.id) // exclude self to avoid duplication
        .map(
          (d) =>
              '[${d.name}]:\n${d.content.substring(0, d.content.length.clamp(0, 1500))}',
        )
        .join('\n\n');
    final subject = state.subjects
        .where((s) => s.id == doc.subjectId)
        .firstOrNull;

    // Use deepAnalyzeDocument with stored text content
    final analysis = await JarvisBrainService.deepAnalyzeDocument(
      subjectName: subject?.name ?? 'Unknown Subject',
      doctorName: subject?.doctorName ?? 'Unknown',
      docType: doc.type,
      docName: doc.name,
      content: doc.content,
      allSubjectContext: allContext,
    );

    // Cache it
    try {
      if (doc.id != null) {
        final db = await DatabaseHelper.instance.database;
        await db.insert(
          'jarvis_doc_analysis',
          {
            'subjectId': doc.subjectId,
            'docId': doc.id!,
            'analysis': analysis,
            'createdAt': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop();
      _displayAnalysisReport(doc.name, analysis, fromCache: false);
    }
  }

  // ── Shared beautiful report viewer ──────────────────────────────────────
  void _displayAnalysisReport(
    String title,
    String content, {
    bool fromCache = false,
    String subtitle = '',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReportViewerPage(
          title: title,
          subtitle: subtitle,
          content: content,
          fromCache: fromCache,
        ),
      ),
    );
  }

  // ── Exam Prep launcher ────────────────────────────────────────────────────
  Future<void> _runExamPrep() async {
    final state = context.read<AppBloc>().state;
    final subjectId = widget.subject.id ?? 0;
    final meta = state.subjectMetadata
        .where((m) => m.subjectId == subjectId)
        .firstOrNull;
    final focus = meta?.instructorFocus ?? '';

    // Open the new Iron Man HUD Dashboard
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ExamPrepHud(subject: widget.subject, instructorFocus: focus),
      ),
    );
  }

  Widget _buildGapDetectorCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.yellowAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellowAccent.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final studyDocs = widget.docs
                .where((d) => d.type == 'document')
                .toList();
            final pastExams = widget.docs
                .where((d) => d.type == 'past_exam')
                .toList();
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _GapDetectorDialog(
                subjectName: widget.subject.name,
                studyMaterials: studyDocs,
                pastExams: pastExams,
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
                    color: Colors.yellowAccent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: Colors.yellowAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistical Gap Detector',
                        style: TextStyle(
                          color: Colors.yellowAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Find untested topics by cross-referencing materials vs exams.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.yellowAccent,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tasks Tab helper (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _TasksTabContent extends StatefulWidget {
  final List<TaskModel> pending;
  final List<TaskModel> done;
  final List<TaskModel> failed;
  final List<Subject> subs;
  final Widget Function(TaskModel) buildCard;
  final void Function(TaskModel) onShowDetails;
  const _TasksTabContent({
    required this.pending,
    required this.done,
    required this.failed,
    required this.subs,
    required this.buildCard,
    required this.onShowDetails,
  });
  @override
  State<_TasksTabContent> createState() => _TasksTabContentState();
}

class _TasksTabContentState extends State<_TasksTabContent> {
  bool _doneExpanded = false;
  bool _failedExpanded = false;
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      children: [
        if (widget.pending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.pending_actions_rounded,
                  size: 18,
                  color: Color(0xFFFF9F43),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pending (${widget.pending.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFFFF9F43),
                  ),
                ),
              ],
            ),
          ),
          ...widget.pending.map((t) => widget.buildCard(t)),
        ],
        if (widget.pending.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.celebration_rounded,
                    size: 40,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'All tasks completed! 🎉',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        if (widget.done.isNotEmpty) ...[
          const SizedBox(height: 8),
          Glass(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _doneExpanded = !_doneExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: Color(0xFF2ED573),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Completed (${widget.done.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF2ED573),
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _doneExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF2ED573),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.done.map((t) => widget.buildCard(t)).toList(),
            ),
            crossFadeState: _doneExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
        // ── Failed Tasks Section ──
        if (widget.failed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Glass(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _failedExpanded = !_failedExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cancel_rounded,
                      size: 20,
                      color: Color(0xFFFF4757),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Failed (${widget.failed.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFFFF4757),
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _failedExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFFF4757),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.failed.map((t) => widget.buildCard(t)).toList(),
            ),
            crossFadeState: _failedExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// REPORT VIEWER PAGE — Beautiful markdown rendering with export & Arabic toggle
// =============================================================================
class _ReportViewerPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String content;
  final bool fromCache;
  const _ReportViewerPage({
    required this.title,
    required this.subtitle,
    required this.content,
    this.fromCache = false,
  });
  @override
  State<_ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<_ReportViewerPage> {
  double _fontSize = 14;
  bool _copied = false;

  Future<void> _share() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/jarvis_report.txt');
      await file.writeAsString(widget.content, encoding: utf8Codec);
      await Share.shareXFiles([XFile(file.path)], text: widget.title);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 8,
              16,
              16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A0050), Color(0xFF4A0080)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.fromCache)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CACHED',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Dr. ${widget.subtitle}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Controls row ────────────────────────────────────────────────
                Row(
                  children: [
                    // Font size
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.text_decrease_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            onPressed: () => setState(
                              () => _fontSize = (_fontSize - 1).clamp(11, 22),
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                          ),
                          Text(
                            '${_fontSize.toInt()}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.text_increase_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            onPressed: () => setState(
                              () => _fontSize = (_fontSize + 1).clamp(11, 22),
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Copy
                    IconButton(
                      onPressed: _copy,
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        color: _copied ? Colors.greenAccent : Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Copy to clipboard',
                    ),
                    // Export / share
                    IconButton(
                      onPressed: _share,
                      icon: const Icon(
                        Icons.share_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Export / Share',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────────
          Expanded(
            child: Markdown(
              data: widget.content,
              selectable: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                  fontWeight: FontWeight.w700,
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
                blockquote: TextStyle(
                  color: const Color(0xFFB0BEC5),
                  fontSize: _fontSize,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: const BoxDecoration(
                  color: Color(0xFF1A1A3E),
                  border: Border(
                    left: BorderSide(color: Color(0xFF7F00FF), width: 4),
                  ),
                ),
                listBullet: TextStyle(
                  color: const Color(0xFFBB86FC),
                  fontSize: _fontSize,
                ),
                horizontalRuleDecoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF3A3A6A), width: 1),
                  ),
                ),
                tableHead: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: _fontSize,
                ),
                tableBody: TextStyle(
                  color: const Color(0xFFCCCCFF),
                  fontSize: _fontSize - 1,
                ),
                tableBorder: TableBorder.all(color: const Color(0xFF3A3A6A)),
                tableHeadAlign: TextAlign.center,
                blockSpacing: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const utf8Codec = Utf8Codec();

// =============================================================================
// EXAM PREP LAUNCHER — Language picker + mode selector
// =============================================================================
class _ExamPrepLauncher extends StatefulWidget {
  final String subjectName;
  final String doctorName;
  final int docCount;
  final int pastExamCount;
  const _ExamPrepLauncher({
    required this.subjectName,
    required this.doctorName,
    required this.docCount,
    required this.pastExamCount,
  });
  @override
  State<_ExamPrepLauncher> createState() => _ExamPrepLauncherState();
}

class _ExamPrepLauncherState extends State<_ExamPrepLauncher> {
  String _lang = 'english';

  void _launch(String mode) => Navigator.pop(context, '$_lang:$mode');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EXAM PREPARATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      '${widget.subjectName} — Dr. ${widget.doctorName}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Stats
          Row(
            children: [
              _StatChip(
                icon: Icons.folder_rounded,
                label: '${widget.docCount} docs',
                color: const Color(0xFF6C63FF),
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.quiz_rounded,
                label: '${widget.pastExamCount} past exams',
                color: Colors.orange,
              ),
            ],
          ),

          if (widget.docCount == 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add documents and past exams for better predictions.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Language selector
          const Text(
            'LANGUAGE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _LangButton(
                  label: 'English',
                  active: _lang == 'english',
                  onTap: () => setState(() => _lang = 'english'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LangButton(
                  label: 'Egyptian Arabic',
                  active: _lang == 'arabic',
                  onTap: () => setState(() => _lang = 'arabic'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Text(
            'WHAT DO YOU NEED?',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),

          // Full analysis
          _ModeButton(
            icon: '🔬',
            title: 'Full Enigma Breakdown',
            subtitle: 'Doctor pattern analysis, predictions, study roadmap',
            color: const Color(0xFF7F00FF),
            onTap: () => _launch('analysis'),
          ),
          const SizedBox(height: 8),

          const Text(
            'GENERATE PREDICTED EXAM',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _ExamTypeButton(
                  label: '5th Week\nQuiz',
                  icon: '📝',
                  onTap: () => _launch('week5'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExamTypeButton(
                  label: 'Mid-\nterm',
                  icon: '📋',
                  onTap: () => _launch('midterm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExamTypeButton(
                  label: '10th Week\nQuiz',
                  icon: '📝',
                  onTap: () => _launch('week10'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExamTypeButton(
                  label: 'Final\nExam',
                  icon: '🏁',
                  onTap: () => _launch('final'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _LangButton({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF7F00FF) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? const Color(0xFF7F00FF) : Colors.white24,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _ModeButton extends StatelessWidget {
  final String icon, title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
        ],
      ),
    ),
  );
}

class _ExamTypeButton extends StatelessWidget {
  final String label, icon;
  final VoidCallback onTap;
  const _ExamTypeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// =============================================================================
// EXAM PREP LOADING DIALOG
// =============================================================================
class _ExamPrepLoadingDialog extends StatelessWidget {
  final String mode;
  final String subjectName;
  const _ExamPrepLoadingDialog({required this.mode, required this.subjectName});

  @override
  Widget build(BuildContext context) {
    final messages = {
      'analysis': [
        'Gathering all subject data...',
        'Analyzing doctor\'s patterns...',
        'Breaking the exam code...',
        'Generating intelligence report...',
      ],
      'week5': [
        'Studying past exam patterns...',
        'Predicting 5th week topics...',
        'Generating quiz...',
      ],
      'midterm': [
        'Analyzing doctor\'s midterm style...',
        'Predicting exam structure...',
        'Generating predicted midterm...',
      ],
      'week10': [
        'Analyzing patterns...',
        'Predicting 10th week topics...',
        'Generating quiz...',
      ],
      'final': [
        'Analyzing ALL past exams...',
        'Decoding final exam patterns...',
        'Generating full predicted final...',
      ],
    };
    final msgs = messages[mode] ?? messages['analysis']!;

    return AlertDialog(
      backgroundColor: const Color(0xFF0D0D2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFF7F00FF),
                  strokeWidth: 3,
                ),
                const Text('🧠', style: TextStyle(fontSize: 28)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'NOVA is working...',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subjectName,
            style: const TextStyle(color: Color(0xFFBB86FC), fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...msgs.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF7F00FF),
                    size: 16,
                  ),
                  Text(
                    m,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '60-120 seconds',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Saved Reports History ──────────────────────────────────────────────────
void _showSavedReports(BuildContext context, String subjectName) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'saved_reports_$subjectName';
  final reports = prefs.getStringList(key) ?? [];

  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '📋 Saved Reports',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No saved reports yet.\nSave a report from any analysis dialog.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: reports.length,
                itemBuilder: (_, i) {
                  final parts = reports[i].split('|');
                  if (parts.length < 3) return const SizedBox.shrink();
                  final type = parts[0];
                  final dateStr = parts[1];
                  final content = parts.sublist(2).join('|');
                  final date = DateTime.tryParse(dateStr);
                  final dateLabel = date != null
                      ? '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                      : dateStr;
                  final color = type.contains('Collision')
                      ? Colors.redAccent
                      : type.contains('Gap')
                      ? Colors.yellowAccent
                      : type.contains('Cascade')
                      ? Colors.cyanAccent
                      : Colors.white54;

                  return Card(
                    color: const Color(0xFF252547),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        type.contains('Collision')
                            ? Icons.warning_amber_rounded
                            : type.contains('Gap')
                            ? Icons.radar_rounded
                            : Icons.account_tree_rounded,
                        color: color,
                        size: 28,
                      ),
                      title: Text(
                        type,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.share,
                              color: Colors.white38,
                              size: 18,
                            ),
                            onPressed: () => Share.share(content),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            onPressed: () async {
                              reports.removeAt(i);
                              await prefs.setStringList(key, reports);
                              Navigator.pop(ctx);
                              if (context.mounted)
                                _showSavedReports(context, subjectName);
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: const Color(0xFF1A1A2E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 500),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        type.contains('Collision')
                                            ? Icons.warning_amber_rounded
                                            : type.contains('Gap')
                                            ? Icons.radar_rounded
                                            : Icons.account_tree_rounded,
                                        color: color,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          type,
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    dateLabel,
                                    style: const TextStyle(
                                      color: Colors.white30,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        content,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class _AbsenceColliderDialog extends StatefulWidget {
  final String subjectName;
  final List<Map<String, dynamic>> absences;
  final List<MarkModel> marks;
  final List<JarvisDocument> docs;

  const _AbsenceColliderDialog({
    required this.subjectName,
    required this.absences,
    required this.marks,
    required this.docs,
  });

  @override
  State<_AbsenceColliderDialog> createState() => _AbsenceColliderDialogState();
}

class _AbsenceColliderDialogState extends State<_AbsenceColliderDialog> {
  bool _loading = true;
  String _analysis = '';

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final result = await JarvisBrainService.analyzeAbsenceMarkCollision(
      subjectName: widget.subjectName,
      absences: widget.absences,
      marks: widget.marks,
      documents: widget.docs,
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
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'COLLISION REPORT',
                    style: TextStyle(
                      color: Colors.redAccent,
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
                      color: Colors.redAccent,
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
                        'Collision Report|${DateTime.now().toIso8601String()}|$_analysis',
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
                      color: Colors.redAccent,
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
                    CircularProgressIndicator(color: Colors.redAccent),
                    SizedBox(height: 16),
                    Text(
                      'Cross-referencing timeline data...',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13),
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
                        color: Colors.redAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      em: const TextStyle(
                        color: Colors.orange,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(color: Colors.redAccent),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Colors.redAccent, width: 3),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.fromLTRB(
                        12,
                        8,
                        12,
                        8,
                      ),
                      tableHead: const TextStyle(
                        color: Colors.redAccent,
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

class _GapDetectorDialog extends StatefulWidget {
  final String subjectName;
  final List<JarvisDocument> studyMaterials;
  final List<JarvisDocument> pastExams;

  const _GapDetectorDialog({
    required this.subjectName,
    required this.studyMaterials,
    required this.pastExams,
  });

  @override
  State<_GapDetectorDialog> createState() => _GapDetectorDialogState();
}

class _GapDetectorDialogState extends State<_GapDetectorDialog> {
  bool _loading = true;
  String _analysis = '';

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final result = await JarvisBrainService.analyzeStatisticalGaps(
      subjectName: widget.subjectName,
      studyMaterials: widget.studyMaterials,
      pastExams: widget.pastExams,
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
                  Icons.radar_rounded,
                  color: Colors.yellowAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'GAP DETECTOR',
                    style: TextStyle(
                      color: Colors.yellowAccent,
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
                      color: Colors.yellowAccent,
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
                        'Gap Analysis|${DateTime.now().toIso8601String()}|$_analysis',
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
                      color: Colors.yellowAccent,
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
                    CircularProgressIndicator(color: Colors.yellowAccent),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing materials vs. exams...',
                      style: TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 13,
                      ),
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
                        color: Colors.yellowAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      em: const TextStyle(
                        color: Colors.amber,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(color: Colors.yellowAccent),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Colors.yellowAccent,
                            width: 3,
                          ),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.fromLTRB(
                        12,
                        8,
                        12,
                        8,
                      ),
                      tableHead: const TextStyle(
                        color: Colors.yellowAccent,
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
