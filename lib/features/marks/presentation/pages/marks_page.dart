import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/gpa_calculator/data/models/semester.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';

class MarksPage extends StatelessWidget {
  const MarksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marks & GPA')),
      body: BlocBuilder<AppBloc, AppState>(
        builder: (ctx, state) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              _gpaCalculator(ctx, state),
              _overallPie(state),
              _subjectBreakdown(state),
              _semesterHistory(ctx, state),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_marks',
        onPressed: () => _showAddSem(context),
        icon: const Icon(Icons.history_rounded),
        label: const Text('Add Semester'),
      ),
    );
  }

  Widget _gpaCalculator(BuildContext ctx, AppState state) {
    if (state.subjects.isEmpty) return const SizedBox.shrink();

    // Calculate current GPA from marks
    double totalPoints = 0;
    int totalCredits = 0;

    final subjectData = <Map<String, dynamic>>[];

    for (final s in state.subjects) {
      final sm = state.marks.where((m) => m.subjectId == s.id).toList();
      double o = 0, t = 0;
      for (final m in sm) {
        o += m.obtained;
        t += m.total;
      }
      final pct = t > 0 ? o / t * 100 : -1.0;
      final gpaPoints = _pctToGpa(pct);

      subjectData.add({
        'subject': s,
        'pct': pct,
        'gpa': gpaPoints,
        'grade': _pctToGrade(pct),
        'obtained': o,
        'total': t,
      });

      if (pct >= 0) {
        totalPoints += gpaPoints * s.creditHours;
        totalCredits += s.creditHours;
      }
    }

    final currentGpa = totalCredits > 0 ? totalPoints / totalCredits : 0.0;

    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calculate_rounded,
                color: Color(0xFF6C63FF),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'GPA Calculator',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'GPA: ${currentGpa.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Subject rows
          ...subjectData.map((d) {
            final s = d['subject'] as Subject;
            final pct = d['pct'] as double;
            final grade = d['grade'] as String;
            final gpa = d['gpa'] as double;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color(s.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${s.creditHours} CH',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 45,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _gradeColor(pct).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      pct >= 0 ? grade : '—',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _gradeColor(pct),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 35,
                    child: Text(
                      pct >= 0 ? gpa.toStringAsFixed(1) : '—',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 20),
          // GPA Predictor button
          Center(
            child: TextButton.icon(
              onPressed: () => _showGpaPredictor(ctx, state),
              icon: const Icon(Icons.trending_up_rounded, size: 18),
              label: const Text(
                'GPA Predictor',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGpaPredictor(BuildContext ctx, AppState state) {
    final targets = <int, String>{};
    for (final s in state.subjects) {
      // Get current grade as default
      final sm = state.marks.where((m) => m.subjectId == s.id).toList();
      double o = 0, t = 0;
      for (final m in sm) {
        o += m.obtained;
        t += m.total;
      }
      final pct = t > 0 ? o / t * 100 : -1.0;
      targets[s.id!] = pct >= 0 ? _pctToGrade(pct) : 'B';
    }

    const grades = [
      'A+',
      'A',
      'A-',
      'B+',
      'B',
      'B-',
      'C+',
      'C',
      'C-',
      'D+',
      'D',
      'F',
    ];

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          // Calculate predicted GPA
          double totalPoints = 0;
          int totalCredits = 0;
          for (final s in state.subjects) {
            final grade = targets[s.id!] ?? 'B';
            totalPoints += _gradeToGpa(grade) * s.creditHours;
            totalCredits += s.creditHours;
          }
          final predictedGpa = totalCredits > 0
              ? totalPoints / totalCredits
              : 0.0;

          final d = Theme.of(c).brightness == Brightness.dark;
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(c).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: d ? const Color(0xFF12122A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '🎯 GPA Predictor',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set target grades to predict your GPA',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.school_rounded,
                              color: Color(0xFF6C63FF),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Predicted GPA: ${predictedGpa.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6C63FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: state.subjects.length,
                    itemBuilder: (_, i) {
                      final s = state.subjects[i];
                      final current = targets[s.id!] ?? 'B';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Color(s.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${s.creditHours} CH',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Color(s.color).withOpacity(0.3),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: current,
                                  isDense: true,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(s.color),
                                  ),
                                  items: grades
                                      .map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(g),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setS(() => targets[s.id!] = v);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 35,
                              child: Text(
                                _gradeToGpa(current).toStringAsFixed(1),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(s.color),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  double _pctToGpa(double pct) {
    if (pct < 0) return 0;
    if (pct >= 97) return 4.0;
    if (pct >= 93) return 4.0;
    if (pct >= 89) return 3.7;
    if (pct >= 84) return 3.3;
    if (pct >= 80) return 3.0;
    if (pct >= 76) return 2.7;
    if (pct >= 73) return 2.3;
    if (pct >= 70) return 2.0;
    if (pct >= 67) return 1.7;
    if (pct >= 64) return 1.3;
    if (pct >= 60) return 1.0;
    return 0.0;
  }

  String _pctToGrade(double pct) {
    if (pct >= 97) return 'A+';
    if (pct >= 93) return 'A';
    if (pct >= 89) return 'A-';
    if (pct >= 84) return 'B+';
    if (pct >= 80) return 'B';
    if (pct >= 76) return 'B-';
    if (pct >= 73) return 'C+';
    if (pct >= 70) return 'C';
    if (pct >= 67) return 'C-';
    if (pct >= 64) return 'D+';
    if (pct >= 60) return 'D';
    return 'F';
  }

  double _gradeToGpa(String grade) {
    switch (grade) {
      case 'A+':
        return 4.0;
      case 'A':
        return 4.0;
      case 'A-':
        return 3.7;
      case 'B+':
        return 3.3;
      case 'B':
        return 3.0;
      case 'B-':
        return 2.7;
      case 'C+':
        return 2.3;
      case 'C':
        return 2.0;
      case 'C-':
        return 1.7;
      case 'D+':
        return 1.3;
      case 'D':
        return 1.0;
      default:
        return 0.0;
    }
  }

  Color _gradeColor(double pct) {
    if (pct < 0) return Colors.grey;
    if (pct >= 84) return const Color(0xFF2ED573);
    if (pct >= 70) return const Color(0xFFFF9F43);
    if (pct >= 60) return const Color(0xFFFF6B81);
    return const Color(0xFFFF4757);
  }

  Widget _overallPie(AppState state) {
    if (state.subjects.isEmpty || state.marks.isEmpty) {
      return Glass(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  Icons.analytics_rounded,
                  size: 48,
                  color: Colors.grey.withOpacity(0.3),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add subjects & marks to see analytics',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sections = <PieChartSectionData>[];
    final legends = <Widget>[];
    double totalObt = 0, totalMax = 0;

    for (final s in state.subjects) {
      final sm = state.marks.where((m) => m.subjectId == s.id).toList();
      if (sm.isEmpty) continue;
      double o = 0, t = 0;
      for (final m in sm) {
        o += m.obtained;
        t += m.total;
      }
      totalObt += o;
      totalMax += t;
      final pct = t > 0 ? o / t * 100 : 0.0;
      final subjectColor = Color(s.color);

      sections.add(
        PieChartSectionData(
          value: pct,
          title: '${pct.toStringAsFixed(0)}%',
          color: subjectColor,
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
        ),
      );

      legends.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: subjectColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${s.name} (${pct.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }

    final overallPct = totalMax > 0 ? totalObt / totalMax * 100 : 0.0;

    return Glass(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Performance',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${overallPct.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sections.isNotEmpty)
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 3,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: legends,
          ),
        ],
      ),
    );
  }

  Widget _subjectBreakdown(AppState state) {
    final subjectsWithMarks = state.subjects
        .where((s) => state.marks.any((m) => m.subjectId == s.id))
        .toList();
    if (subjectsWithMarks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            'Subject Breakdown',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        ...subjectsWithMarks.map((s) {
          final sm = state.marks.where((m) => m.subjectId == s.id).toList();
          double o = 0, t = 0;
          for (final m in sm) {
            o += m.obtained;
            t += m.total;
          }
          final pct = t > 0 ? o / t * 100 : 0.0;
          return Glass(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(s.color).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Color(s.color),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AText(
                        s.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0, 1),
                          minHeight: 5,
                          backgroundColor: Colors.grey.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation(Color(s.color)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${o.toStringAsFixed(1)}/${t.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      _pctToGrade(pct),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _gradeColor(pct),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _semesterHistory(BuildContext ctx, AppState state) {
    if (state.semesters.isEmpty) return const SizedBox.shrink();

    // Calculate cumulative GPA
    double cumulativePoints = 0;
    int cumulativeCredits = 0;
    for (final sem in state.semesters) {
      cumulativePoints += sem.gpa * sem.credits;
      cumulativeCredits += sem.credits;
    }
    final cGpa = cumulativeCredits > 0
        ? cumulativePoints / cumulativeCredits
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              const Text(
                'Semester History',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2ED573).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'CGPA: ${cGpa.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFF2ED573),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.semesters.length >= 2)
          Glass(
            child: SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 4.0,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                        r.toY.toStringAsFixed(2),
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
                          v.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          final rev = state.semesters.reversed.toList();
                          if (i < rev.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                rev[i].name.length > 8
                                    ? '${rev[i].name.substring(0, 8)}..'
                                    : rev[i].name,
                                style: const TextStyle(fontSize: 8),
                              ),
                            );
                          }
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
                    horizontalInterval: 1,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(state.semesters.length, (i) {
                    final rev = state.semesters.reversed.toList();
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: rev[i].gpa.clamp(0, 4),
                          color: const Color(0xFF6C63FF),
                          width: 20,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ...state.semesters.map(
          (sem) => Glass(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      sem.gpa.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sem.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'GPA: ${sem.gpa.toStringAsFixed(2)} | ${sem.credits} Credits',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                  onPressed: () =>
                      ctx.read<AppBloc>().add(DeleteSemester(sem.id!)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddSem(BuildContext ctx) {
    final nC = TextEditingController();
    final gC = TextEditingController();
    final cC = TextEditingController();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) {
        final d = Theme.of(c).brightness == Brightness.dark;
        return Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          decoration: BoxDecoration(
            color: d ? const Color(0xFF12122A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    'Add Semester',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nC,
                  decoration: const InputDecoration(
                    labelText: 'Name (e.g. Fall 2024)',
                    prefixIcon: Icon(Icons.school_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: gC,
                        decoration: const InputDecoration(
                          labelText: 'GPA (0-4)',
                          prefixIcon: Icon(Icons.grade_rounded),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: cC,
                        decoration: const InputDecoration(
                          labelText: 'Credits',
                          prefixIcon: Icon(Icons.credit_score_rounded),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    if (nC.text.isEmpty) {
                      ScaffoldMessenger.of(c).showSnackBar(
                        const SnackBar(content: Text('Enter name')),
                      );
                      return;
                    }
                    ctx.read<AppBloc>().add(
                      AddSemester(
                        SemesterModel(
                          name: nC.text.trim(),
                          gpa: double.tryParse(gC.text) ?? 0,
                          credits: int.tryParse(cC.text) ?? 0,
                        ),
                      ),
                    );
                    Navigator.pop(c);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
