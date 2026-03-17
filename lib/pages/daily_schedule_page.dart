// daily_schedule_page.dart — Weekly Schedule Builder v2
//
// CHANGES FROM v1:
// 1. Multi-select: swipe/drag finger across slots to paint them all at once
// 2. Smart schedule generation: loads data from DB itself (no AppBloc dep needed)
// 3. Generation status messages shown while NOVA plans
// 4. Long-press to quick-clear a slot
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/nova_smart_schedule_service.dart';
import '../services/database.dart';
import '../models/subject.dart';
import '../models/task.dart';
import '../models/timetable.dart';
import '../models/mark.dart';
import '../models/topic.dart';
import '../models/subject_note.dart';

const kSlotLabels = [
  'Sleep',
  'Class',
  'Gym',
  'Commute',
  'Family',
  'Mosque',
  'Free',
  'Work',
  'Other',
];

const kSlotColors = {
  'Sleep': Color(0xFF1A1A3E),
  'Class': Color(0xFF6C63FF),
  'Gym': Color(0xFF2ED573),
  'Commute': Color(0xFFFF9F43),
  'Family': Color(0xFFFF6B81),
  'Mosque': Color(0xFF17C0EB),
  'Free': Color(0xFF2D2D4E),
  'Work': Color(0xFFFFDD59),
  'Other': Color(0xFF808080),
  '': Color(0xFF1A1A2E),
};

const _prefKey = 'nova_weekly_schedule';

class DailySchedulePage extends StatefulWidget {
  const DailySchedulePage({super.key});
  @override
  State<DailySchedulePage> createState() => _DailySchedulePageState();
}

class _DailySchedulePageState extends State<DailySchedulePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final List<List<String>> _schedule = List.generate(
    7,
    (_) => List.generate(36, (_) => ''),
  );
  bool _loading = true;
  bool _generating = false;
  String _genStatus = '';

  // Multi-select state
  String? _paintLabel; // the label being painted in this drag gesture
  int? _dragStartSlot; // slot index where drag started
  int? _dragCurrentSlot; // slot index currently under finger
  Set<int> _draggedSlots = {};

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _slotLabel(int i) {
    final totalMins = 360 + i * 30;
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final suf = h >= 12 ? 'PM' : 'AM';
    return m == 0 ? '$h12 $suf' : '$h12:${m.toString().padLeft(2, '0')} $suf';
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 7,
      vsync: this,
      initialIndex: DateTime.now().weekday - 1,
    );
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List;
        for (int d = 0; d < 7 && d < decoded.length; d++) {
          final day = decoded[d] as List;
          for (int s = 0; s < 36 && s < day.length; s++) {
            _schedule[d][s] = day[s] as String? ?? '';
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_schedule));

    if (!mounted) return;

    setState(() {
      _generating = true;
      _genStatus = 'Saving schedule…';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Schedule saved. NOVA is building your study plan…'),
        backgroundColor: Color(0xFF1A3A1A),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Load all data from DB directly (no AppBloc dependency)
      setState(() => _genStatus = 'Loading your data…');
      final db = await DatabaseHelper.instance.database;

      final subjectRows = await db.query('subjects');
      final subjects = subjectRows
          .map(
            (r) => Subject(
              id: r['id'] as int?,
              name: r['name'] as String? ?? '',
              doctorName: r['doctorName'] as String? ?? '',
              creditHours: r['creditHours'] as int? ?? 3,
              color: r['color'] as int? ?? 0xFF6C63FF,
              maxLectureAbs: r['maxLectureAbs'] as int? ?? 4,
              maxSectionAbs: r['maxSectionAbs'] as int? ?? 4,
              maxLabAbs: r['maxLabAbs'] as int? ?? 4,
            ),
          )
          .toList();

      final taskRows = await db.query('tasks');
      final tasks = taskRows.map((r) => TaskModel.fromMap(r)).toList();

      final timetableRows = await db.query('timetable');
      final timetable = timetableRows
          .map((r) => TimetableEntry.fromMap(r))
          .toList();

      final markRows = await db.query('marks');
      final marks = markRows.map((r) => MarkModel.fromMap(r)).toList();

      final topicRows = await db.query('topics');
      final topics = topicRows.map((r) => StudyTopic.fromMap(r)).toList();

      final mistRows = await db.query('subject_notes', where: 'category = ?', whereArgs: ['exam_mistake']);
      final examMistakes = mistRows.map((r) => SubjectNote.fromMap(r)).toList();

      await NovaSmartScheduleService.generateSmartPlan(
        subjects: subjects,
        tasks: tasks,
        timetable: timetable,
        marks: marks,
        topics: topics,
        examMistakes: examMistakes,
        onStatus: (s) {
          if (mounted) setState(() => _genStatus = s);
        },
      );
    } catch (e) {
      debugPrint('[DailySchedule] plan gen error: $e');
    }

    if (mounted) {
      setState(() {
        _generating = false;
        _genStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🧠 NOVA study plan is ready! Check Study Plan tab.'),
          backgroundColor: Color(0xFF1A3A1A),
          duration: Duration(seconds: 3),
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
        title: const Row(
          children: [
            Icon(
              Icons.calendar_view_week_rounded,
              color: Color(0xFF39FF14),
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Weekly Schedule',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [_saveButton()],
        bottom: TabBar(
          controller: _tabs,
          tabs: _days.map((d) => Tab(text: d)).toList(),
          labelColor: const Color(0xFF39FF14),
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFF39FF14),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF39FF14)),
            )
          : TabBarView(
              controller: _tabs,
              children: List.generate(7, (day) => _dayGrid(day)),
            ),
      floatingActionButton: _paintLabel != null
          ? FloatingActionButton.extended(
              backgroundColor: (kSlotColors[_paintLabel] ?? Colors.grey)
                  .withOpacity(0.9),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.brush_rounded),
              label: Text('Painting: $_paintLabel'),
              onPressed: () => setState(() => _paintLabel = null),
            )
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF39FF14).withOpacity(0.12),
              foregroundColor: const Color(0xFF39FF14),
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text(
                'Free = NOVA plans here',
                style: TextStyle(fontSize: 12),
              ),
              onPressed: _showHelpSheet,
              elevation: 0,
            ),
    );
  }

  Widget _saveButton() {
    if (_generating) {
      return Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF39FF14),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _genStatus.isEmpty ? 'Planning…' : _genStatus,
              style: const TextStyle(color: Color(0xFF39FF14), fontSize: 12),
            ),
          ],
        ),
      );
    }
    return TextButton(
      onPressed: _save,
      child: const Text(
        'SAVE',
        style: TextStyle(
          color: Color(0xFF39FF14),
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _dayGrid(int day) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: 37, // 36 slots + header
      itemBuilder: (_, i) {
        if (i == 0) return _paintBar(day);
        return _slotTile(day, i - 1);
      },
    );
  }

  /// Top bar showing quick-select label buttons for paint mode
  Widget _paintBar(int day) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'Tap a label to paint mode, then drag over slots:',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: kSlotLabels.map((lbl) {
              final color = kSlotColors[lbl] ?? const Color(0xFF1A1A2E);
              final selected = _paintLabel == lbl;
              return GestureDetector(
                onTap: () =>
                    setState(() => _paintLabel = selected ? null : lbl),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? color : color.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? Colors.white : color.withOpacity(0.3),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    lbl,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          if (_paintLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF39FF14).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF39FF14).withOpacity(0.3),
                ),
              ),
              child: Text(
                '🖌️ Paint mode ON — drag to fill slots with "$_paintLabel". Tap label again to exit.',
                style: const TextStyle(color: Color(0xFF39FF14), fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slotTile(int day, int slot) {
    final label = _schedule[day][slot];
    final color = kSlotColors[label] ?? const Color(0xFF1A1A2E);
    final isFree = label == 'Free' || label.isEmpty;
    final isPainted = _draggedSlots.contains(slot);

    return GestureDetector(
      // Tap: if paint mode active → paint this slot; else open picker
      onTap: () {
        if (_paintLabel != null) {
          setState(() {
            _schedule[day][slot] = _paintLabel!;
            _draggedSlots.clear();
          });
        } else {
          _pickLabel(day, slot);
        }
      },
      // Long press: clear the slot
      onLongPress: () => setState(() => _schedule[day][slot] = ''),

      // Drag start: begin paint drag
      onVerticalDragStart: (_paintLabel != null)
          ? (d) {
              setState(() {
                _dragStartSlot = slot;
                _dragCurrentSlot = slot;
                _draggedSlots = {slot};
                _schedule[day][slot] = _paintLabel!;
              });
            }
          : null,

      // Drag update: paint each slot the finger passes through
      onVerticalDragUpdate: (_paintLabel != null)
          ? (d) {
              // Calculate which slot the finger is currently over based on y delta
              if (_dragStartSlot == null) return;
              final slotHeight = 47.0; // approximate height per tile
              final delta = d.localPosition.dy;
              final slotDelta = (delta / slotHeight).round();
              final targetSlot = (_dragStartSlot! + slotDelta).clamp(0, 35);
              if (_dragCurrentSlot != targetSlot) {
                setState(() {
                  _dragCurrentSlot = targetSlot;
                  // Paint all slots between start and current
                  final from = _dragStartSlot! < targetSlot
                      ? _dragStartSlot!
                      : targetSlot;
                  final to = _dragStartSlot! < targetSlot
                      ? targetSlot
                      : _dragStartSlot!;
                  _draggedSlots = {};
                  for (int s = from; s <= to && s < 36; s++) {
                    _draggedSlots.add(s);
                    _schedule[day][s] = _paintLabel!;
                  }
                });
              }
            }
          : null,

      onVerticalDragEnd: (_paintLabel != null)
          ? (_) => setState(() {
              _dragStartSlot = null;
              _dragCurrentSlot = null;
              _draggedSlots.clear();
            })
          : null,

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          color: isPainted
              ? (kSlotColors[_paintLabel] ?? color).withOpacity(0.95)
              : color.withOpacity(label.isEmpty ? 0.3 : 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPainted
                ? Colors.white.withOpacity(0.6)
                : isFree
                ? const Color(0xFF39FF14).withOpacity(0.15)
                : color.withOpacity(0.5),
            width: isPainted ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Center(
                child: Text(
                  _slotLabel(slot),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
            Container(width: 1, color: Colors.white12),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label.isEmpty ? 'Tap to assign' : label,
                style: TextStyle(
                  color: label.isEmpty ? Colors.white24 : Colors.white,
                  fontSize: 13,
                  fontWeight: label.isEmpty
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
            if (label.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _schedule[day][slot] = ''),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.clear_rounded,
                    color: Colors.white24,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLabel(int day, int slot) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF12122A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_days[day]}  ${_slotLabel(slot)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tip: Tap a label in the paint bar at the top, then drag across slots to fill many at once.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [...kSlotLabels, ''].map((lbl) {
                  final c = kSlotColors[lbl] ?? const Color(0xFF1A1A2E);
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, lbl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        lbl.isEmpty ? '✕ Clear' : lbl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted)
      setState(() => _schedule[day][slot] = chosen);
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12122A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'How to use Weekly Schedule',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '🖌️ PAINT MODE (fast):\nTap any label in the top bar → it glows. Then drag your finger down any column to fill multiple slots at once. Tap the label again to exit paint mode.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '👆 TAP: Opens the label picker for a single slot.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '✕ LONG PRESS: Clears a slot instantly.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              '🟢 FREE slots: NOVA builds your study plan only in these slots. Mark everything else first, then set remaining time as Free.',
              style: TextStyle(
                color: Color(0xFF39FF14),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
