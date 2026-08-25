// study_plan_page.dart — Shows NOVA-generated study blocks for today.
// Each block: Done / Skip / Reschedule.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/core/database/database_helper.dart';
import 'package:study_organizer/features/ai_assistant/data/services/nova_audio_service.dart';
import 'package:study_organizer/core/widgets/glass.dart';

class StudyPlanPage extends StatefulWidget {
  const StudyPlanPage({super.key});
  @override
  State<StudyPlanPage> createState() => _StudyPlanPageState();
}

class _StudyPlanPageState extends State<StudyPlanPage> {
  List<Map<String, dynamic>> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBlocks();
  }

  Future<void> _loadBlocks() async {
    final db = await DatabaseHelper.instance.database;
    final today = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now();
    final dow = now.weekday; // 1=Mon
    final rows = await db.query(
      'nova_study_plan',
      where: 'date = ? OR (date IS NULL AND dayOfWeek = ?)',
      whereArgs: [today, dow],
      orderBy: 'startTime ASC',
    );
    if (mounted)
      setState(() {
        _blocks = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        _loading = false;
      });
  }

  Future<void> _setStatus(int id, String status) async {
    if (status == 'done') {
      NovaAudioService.playAsset('sounds/that_is_one_step_closer.mp3');
    }
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'nova_study_plan',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadBlocks();
  }

  Future<void> _reschedule(Map<String, dynamic> block) async {
    // Find next free slot today or tomorrow — simplified: move +1 block in list
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final tmrw = intl.DateFormat(
      'yyyy-MM-dd',
    ).format(now.add(const Duration(days: 1)));
    // Just mark as rescheduled and clone for tomorrow same time
    await db.update(
      'nova_study_plan',
      {'status': 'rescheduled'},
      where: 'id = ?',
      whereArgs: [block['id']],
    );
    await db.insert('nova_study_plan', {
      'subjectId': block['subjectId'],
      'dayOfWeek': now.add(const Duration(days: 1)).weekday,
      'date': tmrw,
      'startTime': block['startTime'],
      'endTime': block['endTime'],
      'topicTitle': block['topicTitle'],
      'reason': 'Rescheduled from ${block['date']}',
      'status': 'pending',
      'weekNumber': block['weekNumber'] ?? 0,
    });
    await _loadBlocks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '📅 Block rescheduled to tomorrow at the same time.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Color(0xFF1A2A3A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12122A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Today's Study Plan",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            Text(
              intl.DateFormat('EEEE, d MMM').format(DateTime.now()),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF39FF14)),
            )
          : _blocks.isEmpty
          ? _emptyState()
          : _planList(),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.event_note_rounded, color: Colors.white24, size: 64),
        const SizedBox(height: 16),
        const Text(
          "No study blocks today",
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          "NOVA generates your plan every Friday night.\nMake sure your weekly schedule is set up.",
          style: TextStyle(color: Colors.white24, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _planList() {
    final pending = _blocks.where((b) => b['status'] == 'pending').toList();
    final completed = _blocks.where((b) => b['status'] != 'pending').toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pending.isNotEmpty) ...[
          _header('⚡ Upcoming (${pending.length})'),
          ...pending.map(_blockTile),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 8),
          _header('✓ Completed / Skipped'),
          ...completed.map(_blockTile),
        ],
      ],
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _blockTile(Map<String, dynamic> b) {
    final status = b['status'] as String? ?? 'pending';
    final done = status == 'done';
    final skipped = status == 'skipped' || status == 'rescheduled';
    final color = done
        ? const Color(0xFF2ED573)
        : skipped
        ? Colors.white24
        : const Color(0xFF6C63FF);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(done ? 0.4 : 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b['topicTitle'] as String? ?? 'Study Block',
                      style: TextStyle(
                        color: done ? Colors.white38 : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      '${b['startTime']} – ${b['endTime']}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(status),
            ],
          ),
          if ((b['reason'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              b['reason'] as String,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _actionBtn(
                  '✅ Done',
                  const Color(0xFF2ED573),
                  () => _setStatus(b['id'] as int, 'done'),
                ),
                const SizedBox(width: 8),
                _actionBtn(
                  '⏩ Skip',
                  Colors.orange,
                  () => _setStatus(b['id'] as int, 'skipped'),
                ),
                const SizedBox(width: 8),
                _actionBtn(
                  '🔄 Reschedule',
                  const Color(0xFF6C63FF),
                  () => _reschedule(b),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final map = {
      'done': ('Done', const Color(0xFF2ED573)),
      'skipped': ('Skipped', Colors.orange),
      'rescheduled': ('Rescheduled', const Color(0xFF6C63FF)),
      'pending': ('Pending', Colors.white24),
    };
    final (lbl, clr) = map[status] ?? ('?', Colors.white24);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: clr.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: clr.withOpacity(0.3)),
      ),
      child: Text(
        lbl,
        style: TextStyle(color: clr, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
