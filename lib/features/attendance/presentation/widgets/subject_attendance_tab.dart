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
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/features/documents/data/models/study_document.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';

class SubjectAttendanceTab extends StatelessWidget {
  final Subject subject;
  final List<Map<String, dynamic>> abs;
  final int lCount;
  final int sCount;
  final int labCount;

  const SubjectAttendanceTab({
    super.key,
    required this.subject,
    required this.abs,
    required this.lCount,
    required this.sCount,
    required this.labCount,
  });

  @override
  Widget build(BuildContext context) {
    return _attendanceTab(context, abs, lCount, sCount, labCount);
  }

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

class AbsenceColliderDialog extends StatefulWidget {
  final String subjectName;
  final List<Map<String, dynamic>> absences;
  final List<MarkModel> marks;
  final List<JarvisDocument> docs;

  const AbsenceColliderDialog({
    super.key,
    required this.subjectName,
    required this.absences,
    required this.marks,
    required this.docs,
  });

  @override
  State<AbsenceColliderDialog> createState() => _AbsenceColliderDialogState();
}

class _AbsenceColliderDialogState extends State<AbsenceColliderDialog> {
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
