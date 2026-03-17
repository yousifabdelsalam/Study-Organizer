// nova_smart_schedule_service.dart — AI-Powered Smart Weekly Study Planner
//
// WHAT THIS REPLACES:
// The old algorithm in nova_intelligence_engine.dart had a broken topic rotation
// and ignored deadlines, exam proximity, and subject difficulty entirely.
//
// HOW THIS WORKS:
// 1. Reads the user's weekly template (free slots per day) from SharedPreferences
// 2. Gathers all subjects, topics, tasks, marks, timetable
// 3. Sends ALL of this to Gemini with a structured prompt asking for a JSON study plan
// 4. Gemini produces a smart plan considering:
//    - Exam proximity (closer exam = more slots)
//    - Topic stage (lower stage = more review needed)
//    - Subject difficulty/credit hours
//    - Available free time per day
//    - Balance across subjects
//    - No studying same subject 2+ hours in a row
// 5. Saves to nova_study_plan table
//
// FALLBACK:
// If AI fails (no key, rate limit), uses improved deterministic algorithm.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart' as intl;

import '../models/subject.dart';
import '../models/task.dart';
import '../models/timetable.dart';
import '../models/mark.dart';
import '../models/topic.dart';
import 'jarvis_brain_service.dart';
import 'database.dart';
import '../models/subject_note.dart';

// ─────────────────────────────────────────────────────────────────────────────
class NovaSmartScheduleService {
  /// Main entry point. Call this after user saves their weekly template.
  static Future<void> generateSmartPlan({
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<TimetableEntry> timetable,
    required List<MarkModel> marks,
    required List<StudyTopic> topics,
    required List<SubjectNote> examMistakes,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Analyzing your schedule…');

    final prefs = await SharedPreferences.getInstance();
    final rawSchedule = prefs.getString('nova_weekly_schedule');
    if (rawSchedule == null) {
      debugPrint('[NovaSchedule] No weekly schedule set. Skipping.');
      return;
    }

    final schedule = jsonDecode(rawSchedule) as List;
    final now = DateTime.now();
    final planStart = DateTime(now.year, now.month, now.day);
    final fmt = intl.DateFormat('yyyy-MM-dd');

    // ── Build free slot summary (what's available each day) ──────────────────
    final Map<int, List<_FreeBlock>> freeBlocksByDay = {};
    for (int d = 0; d < 7; d++) {
      if (d >= schedule.length) continue;
      final daySlots = schedule[d] as List;
      freeBlocksByDay[d + 1] = _extractFreeBlocks(daySlots); // 1=Mon..7=Sun
    }

    final totalFreeHoursPerDay = <int, double>{};
    for (final entry in freeBlocksByDay.entries) {
      final total =
          entry.value.fold(0, (sum, b) => sum + b.durationSlots) * 0.5;
      totalFreeHoursPerDay[entry.key] = total;
    }

    onStatus?.call('NOVA is building your study plan…');

    // ── Try AI-powered plan first ─────────────────────────────────────────────
    try {
      final aiPlan = await _generateAIPlan(
        subjects: subjects,
        tasks: tasks,
        timetable: timetable,
        marks: marks,
        topics: topics,
        examMistakes: examMistakes,
        freeBlocksByDay: freeBlocksByDay,
        totalFreeHoursPerDay: totalFreeHoursPerDay,
        planStart: planStart,
      );

      if (aiPlan.isNotEmpty) {
        onStatus?.call('Saving plan…');
        await _savePlan(aiPlan, planStart, fmt);
        debugPrint('[NovaSchedule] AI plan saved: ${aiPlan.length} blocks');
        return;
      }
    } catch (e) {
      debugPrint('[NovaSchedule] AI plan failed, using fallback: $e');
    }

    // ── Fallback: deterministic algorithm ────────────────────────────────────
    onStatus?.call('Generating fallback plan…');
    await _generateDeterministicPlan(
      subjects: subjects,
      tasks: tasks,
      marks: marks,
      topics: topics,
      freeBlocksByDay: freeBlocksByDay,
      planStart: planStart,
      fmt: fmt,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AI PLAN GENERATOR
  // Sends a comprehensive prompt to Gemini asking for a structured JSON plan.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> _generateAIPlan({
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<TimetableEntry> timetable,
    required List<MarkModel> marks,
    required List<StudyTopic> topics,
    required List<SubjectNote> examMistakes,
    required Map<int, List<_FreeBlock>> freeBlocksByDay,
    required Map<int, double> totalFreeHoursPerDay,
    required DateTime planStart,
  }) async {
    final now = DateTime.now();
    final fmt = intl.DateFormat('yyyy-MM-dd');
    final dayNames = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    // Build subject data with urgency info
    final subjectData = StringBuffer();
    for (final s in subjects) {
      if (s.id == null) continue;

      // Nearest exam
      final exams =
          tasks
              .where(
                (t) =>
                    !t.isCompleted &&
                    t.isExam &&
                    t.subjectId == s.id &&
                    t.dueDate != null,
              )
              .where((t) => t.dueDate!.isAfter(now))
              .toList()
            ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      final nearestExam = exams.isEmpty ? null : exams.first;

      // Average mark
      final sm = marks
          .where((m) => m.subjectId == s.id && m.total > 0)
          .toList();
      final avgPct = sm.isEmpty
          ? null
          : sm.map((m) => m.obtained / m.total).reduce((a, b) => a + b) /
                sm.length;

      // Topic summary
      final subTopics = topics.where((t) => t.subjectId == s.id).toList();
      final unstudied = subTopics.where((t) => t.stage == 0).length;
      final overdue = subTopics
          .where(
            (t) =>
                t.stage > 0 &&
                t.nextReview != null &&
                t.nextReview!.isBefore(now),
          )
          .length;
          
      // Exam Mistakes
      final mistakes = examMistakes.where((m) => m.subjectId == s.id).toList();
      final mistakesSummary = mistakes.isNotEmpty 
          ? '${mistakes.length} mistakes recorded. MUST review them.' 
          : 'None recorded.';

      subjectData.writeln(
        '- ${s.name} | ${s.creditHours} CH | Dr.${s.doctorName} | '
        'Exam: ${nearestExam != null ? "${nearestExam.title} in ${nearestExam.dueDate!.difference(now).inDays} days" : "none"} | '
        'Avg: ${avgPct != null ? "${(avgPct * 100).toStringAsFixed(0)}%" : "no marks"} | '
        'Topics: ${subTopics.length} total, $unstudied new, $overdue overdue | '
        'Mistakes: $mistakesSummary',
      );
    }

    // Build free time per day
    final freeTimeSummary = StringBuffer();
    for (int dow = 1; dow <= 7; dow++) {
      final date = planStart.add(Duration(days: dow - 1));
      final blocks = freeBlocksByDay[dow] ?? [];
      if (blocks.isEmpty) {
        freeTimeSummary.writeln(
          '${dayNames[dow]} (${fmt.format(date)}): NO free time',
        );
        continue;
      }
      final blockStr = blocks
          .map(
            (b) =>
                '${b.startTime}–${b.endTime} (${(b.durationSlots * 0.5).toStringAsFixed(1)}h)',
          )
          .join(', ');
      freeTimeSummary.writeln(
        '${dayNames[dow]} (${fmt.format(date)}): $blockStr',
      );
    }

    // Build topic list for AI reference
    final topicList = StringBuffer();
    for (final s in subjects) {
      if (s.id == null) continue;
      final subTopics =
          topics.where((t) => t.subjectId == s.id && !t.isMastered).toList()
            ..sort((a, b) => a.stage.compareTo(b.stage));
      for (final t in subTopics.take(8)) {
        final reviewStatus = t.stage == 0
            ? 'NOT YET STUDIED'
            : t.nextReview != null && t.nextReview!.isBefore(now)
            ? 'OVERDUE (${now.difference(t.nextReview!).inDays}d late)'
            : 'due ${t.nextReview != null ? fmt.format(t.nextReview!) : "soon"}';
        topicList.writeln(
          '  [${s.name}] ${t.title} | Stage ${t.stage}/5 | $reviewStatus',
        );
      }
    }

    final prompt =
        '''You are NOVA — a smart academic planner AI. Generate a weekly study plan.

PLANNING PERIOD: ${fmt.format(planStart)} to ${fmt.format(planStart.add(const Duration(days: 6)))}
TODAY: ${dayNames[now.weekday]}, ${fmt.format(now)}

SUBJECTS (with urgency data):
${subjectData.toString().trim()}

FREE TIME SLOTS (ONLY schedule in these blocks — do NOT create sessions outside them):
${freeTimeSummary.toString().trim()}

TOPICS TO STUDY (prioritize low stage + overdue):
${topicList.toString().isEmpty ? 'No topics entered yet — use subject names for sessions.' : topicList.toString().trim()}

PLANNING RULES (follow strictly):
1. ONLY use the exact free time blocks listed above. Never schedule outside them.
2. Each study session: minimum 60 min (2 slots), maximum 90 min (3 slots).
3. NEVER study the same subject twice in a row on the same day.
4. Subjects with exams in ≤5 days: assign 40%+ of available time.
5. Subjects with avg < 60% OR with recorded Exam Mistakes: give extra sessions and explicitly mandate reviewing the mistakes in the `reason` field.
6. Prioritize stage-0 topics (not yet studied) over reviews.
7. Balance across days — don't stack everything on one day.
8. Leave at least 30 min gap between sessions (for breaks).
9. Sunday: lighter load or pure review only.
10. Do NOT create more sessions than free time allows.

Return ONLY a valid JSON array. No markdown. No explanation. No code block.

Each element:
{
  "date": "YYYY-MM-DD",
  "dayOfWeek": 1,
  "startTime": "2 PM",
  "endTime": "3:30 PM",
  "subjectId": 1,
  "subjectName": "Digital Systems",
  "topicTitle": "Topic Name (Subject Name)",
  "reason": "One specific reason for this session timing and priority",
  "durationMinutes": 90
}

dayOfWeek: 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday

Generate the complete 7-day plan now:''';

    final result = await JarvisBrainService.generateRaw(
      prompt: prompt,
      maxTokens: 3000,
      temperature: 0.1,
      isJson: true,
    );

    if (result == null || result.isEmpty) return [];

    // Parse the JSON
    String cleaned = result
        .trim()
        .replaceFirst(RegExp(r'^```\w*\n?'), '')
        .replaceAll(RegExp(r'\n?```$'), '')
        .trim();

    // Extract array
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    cleaned = cleaned.substring(start, end + 1);

    final list = jsonDecode(cleaned) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SAVE AI PLAN TO DB
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> _savePlan(
    List<Map<String, dynamic>> blocks,
    DateTime planStart,
    intl.DateFormat fmt,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final planStartStr = fmt.format(planStart);

    await db.delete(
      'nova_study_plan',
      where: 'date >= ? AND status = ?',
      whereArgs: [planStartStr, 'pending'],
    );

    final now = DateTime.now();
    int weekNum =
        ((now.difference(DateTime(now.year)).inDays + 10 - now.weekday) / 7)
            .floor();

    for (final block in blocks) {
      try {
        await db.insert('nova_study_plan', {
          'subjectId': block['subjectId'],
          'dayOfWeek': block['dayOfWeek'],
          'date': block['date'],
          'startTime': block['startTime'] ?? '9 AM',
          'endTime': block['endTime'] ?? '10:30 AM',
          'topicTitle':
              block['topicTitle'] ?? block['subjectName'] ?? 'Study Session',
          'reason': block['reason'] ?? 'NOVA scheduled',
          'status': 'pending',
          'weekNumber': weekNum,
        });
      } catch (e) {
        debugPrint('[NovaSchedule] Insert error: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FALLBACK DETERMINISTIC ALGORITHM — improved version
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> _generateDeterministicPlan({
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<MarkModel> marks,
    required List<StudyTopic> topics,
    required Map<int, List<_FreeBlock>> freeBlocksByDay,
    required DateTime planStart,
    required intl.DateFormat fmt,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final planStartStr = fmt.format(planStart);

    await db.delete(
      'nova_study_plan',
      where: 'date >= ? AND status = ?',
      whereArgs: [planStartStr, 'pending'],
    );

    int weekNum =
        ((now.difference(DateTime(now.year)).inDays + 10 - now.weekday) / 7)
            .floor();

    // Score each topic
    final scored = topics.where((t) => !t.isMastered).map((t) {
      final s = subjects.firstWhere(
        (s) => s.id == t.subjectId,
        orElse: () => Subject(name: ''),
      );
      if (s.id == null) return _ScoredTopicFallback(t, s, 0.0);

      // Urgency from nearest exam
      double urgency = 1.0;
      final exams =
          tasks
              .where(
                (task) =>
                    !task.isCompleted &&
                    task.isExam &&
                    task.subjectId == s.id &&
                    task.dueDate != null &&
                    task.dueDate!.isAfter(now),
              )
              .toList()
            ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      if (exams.isNotEmpty) {
        final days = exams.first.dueDate!.difference(now).inDays;
        urgency += days <= 2
            ? 5.0
            : days <= 5
            ? 3.0
            : days <= 10
            ? 2.0
            : 1.0;
      }

      // Low marks bonus
      final sm = marks
          .where((m) => m.subjectId == s.id && m.total > 0)
          .toList();
      if (sm.isNotEmpty) {
        final avg =
            sm.map((m) => m.obtained / m.total).reduce((a, b) => a + b) /
            sm.length;
        if (avg < 0.6) urgency += 2.0;
      }

      // Stage score
      final stageScore =
          1.0 / pow(t.stage == 0 ? 0.3 : t.stage.toDouble(), 1.2);

      // Overdue bonus
      double overdue = 1.0;
      if (t.nextReview != null && t.nextReview!.isBefore(now)) {
        overdue += (now.difference(t.nextReview!).inDays * 0.2).clamp(0.0, 3.0);
      }

      return _ScoredTopicFallback(t, s, urgency * stageScore * overdue);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) return;

    // Assign to free blocks with subject alternation
    int topicIdx = 0;
    String? lastSubjectName;

    for (int dow = 1; dow <= 7; dow++) {
      final date = planStart.add(Duration(days: dow - 1));
      final blocks = freeBlocksByDay[dow] ?? [];

      for (final block in blocks) {
        if (block.durationSlots < 2) continue; // skip tiny blocks

        int cursor = block.startSlot;
        int remaining = block.durationSlots;

        while (remaining >= 2) {
          final sliceSlots = (remaining >= 3 && remaining != 4) ? 3 : 2;

          // Find next topic that isn't same subject as last (for variety)
          _ScoredTopicFallback? chosen;
          for (int i = topicIdx; i < scored.length + topicIdx; i++) {
            final candidate = scored[i % scored.length];
            if (candidate.subject.name != lastSubjectName ||
                scored.length == 1) {
              chosen = candidate;
              topicIdx = (i + 1) % scored.length;
              break;
            }
          }
          if (chosen == null) break;

          lastSubjectName = chosen.subject.name;

          await db.insert('nova_study_plan', {
            'subjectId': chosen.subject.id,
            'dayOfWeek': dow,
            'date': fmt.format(date),
            'startTime': _slotTime(cursor),
            'endTime': _slotTime(cursor + sliceSlots),
            'topicTitle': '${chosen.topic.title} (${chosen.subject.name})',
            'reason': chosen.topic.stage == 0
                ? 'First study — new material'
                : chosen.topic.nextReview != null &&
                      chosen.topic.nextReview!.isBefore(now)
                ? 'Overdue review (Stage ${chosen.topic.stage})'
                : 'Spaced repetition (Stage ${chosen.topic.stage})',
            'status': 'pending',
            'weekNumber': weekNum,
          });

          cursor += sliceSlots;
          remaining -= sliceSlots;
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Extract contiguous free blocks from a day's slot array.
  static List<_FreeBlock> _extractFreeBlocks(List daySlots) {
    final blocks = <_FreeBlock>[];
    int start = -1;

    for (int s = 0; s <= 36; s++) {
      final isFree =
          s < daySlots.length &&
          (daySlots[s] == 'Free' || (daySlots[s] as String).isEmpty);

      if (isFree && start == -1) {
        start = s;
      } else if (!isFree && start != -1) {
        blocks.add(_FreeBlock(startSlot: start, durationSlots: s - start));
        start = -1;
      }
    }
    if (start != -1)
      blocks.add(_FreeBlock(startSlot: start, durationSlots: 36 - start));
    return blocks;
  }

  static String _slotTime(int slot) {
    final totalMins = 360 + slot * 30;
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return m == 0
        ? '$h12 ${h >= 12 ? "PM" : "AM"}'
        : '$h12:${m.toString().padLeft(2, '0')} ${h >= 12 ? "PM" : "AM"}';
  }
}

// ── Internal data classes ─────────────────────────────────────────────────────
class _FreeBlock {
  final int startSlot;
  final int durationSlots;

  _FreeBlock({required this.startSlot, required this.durationSlots});

  String get startTime => NovaSmartScheduleService._slotTime(startSlot);
  String get endTime =>
      NovaSmartScheduleService._slotTime(startSlot + durationSlots);
}

class _ScoredTopicFallback {
  final StudyTopic topic;
  final Subject subject;
  final double score;
  _ScoredTopicFallback(this.topic, this.subject, this.score);
}
