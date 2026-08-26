import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/features/documents/data/models/study_document.dart';
import 'package:study_organizer/features/attendance/presentation/widgets/subject_attendance_tab.dart';
import 'package:study_organizer/features/timeline_replay/domain/services/timeline_replay_engine.dart';
import 'package:study_organizer/features/timeline_replay/presentation/widgets/timeline_replay_dialog.dart';


class SubjectMarksTab extends StatelessWidget {
  final Subject subject;
  final List<MarkModel> marks;
  final List<Map<String, dynamic>> abs;
  final List<JarvisDocument> docs;

  const SubjectMarksTab({
    super.key,
    required this.subject,
    required this.marks,
    required this.abs,
    required this.docs,
  });

  @override
  Widget build(BuildContext context) {
    return _marksTab(context, marks, abs, docs);
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
                            Icons.history_rounded,
                            size: 17,
                            color: Color(0xFF00F0FF),
                          ),
                          tooltip: 'Timeline Forensic Replay',
                          onPressed: () {
                            final state = ctx.read<AppBloc>().state;
                            final report = TimelineReplayEngine.reconstructTimeline(
                              subjectName: subject.name,
                              subjectId: subject.id ?? 0,
                              mark: m,
                              allTopics: state.topics,
                              allTasks: state.tasks,
                              allAbsences: state.absences,
                              allSessions: const [],
                            );
                            TimelineReplayDialog.show(ctx, report);
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                builder: (_) => AbsenceColliderDialog(
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
}

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
