// nova_intelligence_engine.dart
// Phase 2: Subject Intel Cards + Weekly Intelligence Briefing generator.
// Runs on demand and every Friday 9 PM via WorkManager.

import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/timetable/data/models/timetable.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/features/topics/data/models/topic.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';
import 'package:study_organizer/core/database/database_helper.dart';

// ── WorkManager task name ─────────────────────────────────────────────────
const _kFridayTask = 'nova_friday_regen';

// ── Background dispatcher removed — now unified in main.dart callbackDispatcher ──

// ─────────────────────────────────────────────────────────────────────────────
class NovaIntelligenceEngine {
  // ── Schedule Friday 9PM regen (called once from main.dart after WM init) ──
  static Future<void> scheduleFridayRegen() async {
    await _scheduleFridayRegen();
  }

  static Future<void> _scheduleFridayRegen() async {
    final now = DateTime.now();
    // Find next Friday 21:00
    int daysUntilFri = (DateTime.friday - now.weekday + 7) % 7;
    if (daysUntilFri == 0 && now.hour >= 21) daysUntilFri = 7;
    final next = DateTime(now.year, now.month, now.day + daysUntilFri, 21, 0);
    final delay = next.difference(now);

    await Workmanager().registerOneOffTask(
      _kFridayTask,
      _kFridayTask,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  // ── Friday 9 PM batch run ─────────────────────────────────────────────────
  static Future<void> runFridayRegen() async {
    debugPrint('🧠 NOVA Friday regen starting...');
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('subjects');
      final subjects = rows
          .map(
            (r) => Subject(
              id: r['id'] as int?,
              name: r['name'] as String? ?? '',
              doctorName: r['doctorName'] as String? ?? '',
              color: r['color'] as int? ?? 0xFF6C63FF,
              creditHours: r['creditHours'] as int? ?? 3,
              maxLectureAbs: r['maxLectureAbs'] as int? ?? 4,
              maxSectionAbs: r['maxSectionAbs'] as int? ?? 4,
              maxLabAbs: r['maxLabAbs'] as int? ?? 4,
            ),
          )
          .toList();

      // 1. Refresh all intel cards in parallel
      await Future.wait(subjects.map((s) => generateIntelCard(s)));

      // 2. Generate weekly study plan based on DailySchedulePage "Free" slots
      final timetable = await _loadTimetable(db);
      final topics = await _loadTopics(db);
      await generateWeeklyStudyPlan(subjects, timetable, topics);

      // 3. Reschedule self for next Friday
      await _scheduleFridayRegen();

      debugPrint('✅ NOVA Friday regen complete');
    } catch (e) {
      debugPrint('❌ NOVA Friday regen error: $e');
    }
  }

  static Future<List<TimetableEntry>> _loadTimetable(Database db) async {
    final rows = await db.query('timetable');
    return rows.map((r) => TimetableEntry.fromMap(r)).toList();
  }

  static Future<List<StudyTopic>> _loadTopics(Database db) async {
    final rows = await db.query('topics');
    return rows.map((r) => StudyTopic.fromMap(r)).toList();
  }

  static Future<void> generateWeeklyStudyPlanFromDB() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('subjects');
    final subjects = rows
        .map(
          (r) => Subject(id: r['id'] as int?, name: r['name'] as String? ?? ''),
        )
        .toList();
    final topics = await _loadTopics(db);
    // Timetable isn't strictly needed for the blank areas, but passing empty for signature
    await generateWeeklyStudyPlan(subjects, [], topics);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Weekly Study Plan Generator
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> generateWeeklyStudyPlan(
    List<Subject> subjects,
    List<TimetableEntry> timetable,
    List<StudyTopic> topics,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();

      // Load user's weekly schedule template
      final rawSchedule = prefs.getString('nova_weekly_schedule');
      if (rawSchedule == null) return; // Schedule not set up yet

      final schedule = jsonDecode(rawSchedule) as List;
      final now = DateTime.now();

      // We'll generate for the next 7 days starting today
      final planStart = DateTime(now.year, now.month, now.day);

      // We prioritize topics mathematically: Score = Stage^-1.5
      // Lower stage (Level 0, 1) gets much higher priority than Level 4, 5
      final Map<int, double> topicScores = {};
      for (final t in topics) {
        topicScores[t.id!] =
            1.0 / (pow(t.stage == 0 ? 0.5 : t.stage.toDouble(), 1.5));
      }

      final sortedTopics = topics.toList()
        ..sort(
          (a, b) =>
              (topicScores[b.id!] ?? 0).compareTo(topicScores[a.id!] ?? 0),
        );

      if (sortedTopics.isEmpty) return; // Nothing to study

      int topicIdx = 0;

      // Clear old pending blocks starting from planStart
      final planStartStr = planStart.toIso8601String().split('T')[0];
      await db.delete(
        'nova_study_plan',
        where: 'date >= ? AND status = ?',
        whereArgs: [planStartStr, 'pending'],
      );

      // 36 slots = 6:00 AM to 23:30 (11:30 PM). Each slot is 30 mins.
      // E.g. slot 0 = 6:00-6:30, slot 1 = 6:30-7:00
      String _slotTime(int slot) {
        final totalMins = 360 + slot * 30;
        final h = totalMins ~/ 60;
        final m = totalMins % 60;
        final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        final suf = h >= 12 ? 'PM' : 'AM';
        return m == 0
            ? '$h12 $suf'
            : '$h12:${m.toString().padLeft(2, '0')} $suf';
      }

      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final date = planStart.add(Duration(days: dayOffset));
        final dow = date.weekday; // 1=Mon .. 7=Sun

        final schedDow = dow - 1; // 0=Mon .. 6=Sun in DailySchedulePage
        if (schedDow >= schedule.length) continue;
        final daySlots = schedule[schedDow] as List;

        // Find contiguous "Free" slots (or empty slots)
        int currentBlockStartSlot = -1;

        for (int s = 0; s <= 36; s++) {
          final isFree =
              s < daySlots.length &&
              (daySlots[s] == 'Free' || daySlots[s] == '');

          if (isFree && currentBlockStartSlot == -1) {
            currentBlockStartSlot = s;
          } else if (!isFree && currentBlockStartSlot != -1) {
            // End of a free block. Let's see how long it is.
            final blockLength = s - currentBlockStartSlot;

            // We only schedule study blocks of 2+ slots (1+ hours)
            if (blockLength >= 2) {
              int remainingSlots = blockLength;
              int currentStart = currentBlockStartSlot;

              while (remainingSlots >= 2) {
                // Determine slice size: prefer 3 slots (1.5h), fall back to 2 slots (1h)
                int sliceSlots = (remainingSlots >= 3) ? 3 : 2;
                if (remainingSlots == 4)
                  sliceSlots = 2; // Split 2h into two 1h blocks

                final topic = sortedTopics[topicIdx % sortedTopics.length];
                final sub = subjects.firstWhere(
                  (sb) => sb.id == topic.subjectId,
                  orElse: () => Subject(name: 'Unknown'),
                );

                await db.insert('nova_study_plan', {
                  'subjectId': sub.id,
                  'dayOfWeek': dow,
                  'date': date.toIso8601String().split('T')[0],
                  'startTime': _slotTime(currentStart),
                  'endTime': _slotTime(currentStart + sliceSlots),
                  'topicTitle': '${topic.title} (${sub.name})',
                  'reason': 'Spaced Repetition (Level ${topic.stage})',
                  'status': 'pending',
                  'weekNumber': _weekNum(date),
                });

                // Mix topic index slightly so 5-hour block isn't identical
                topicIdx += (topicIdx % 3 == 0) ? 2 : 1;

                currentStart += sliceSlots;
                remainingSlots -= sliceSlots;
              }
            }
            currentBlockStartSlot = -1;
          }
        }
      }
    } catch (e) {
      debugPrint('Study plan generation error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Subject Intel Card
  // ─────────────────────────────────────────────────────────────────────────
  /// Generates or refreshes the intel card for a subject.
  /// Saves to nova_subject_intel table. Returns the card text.
  static Future<String> generateIntelCard(Subject subject) async {
    if (subject.id == null) return '';
    try {
      final db = await DatabaseHelper.instance.database;

      // Fetch all documents for this subject
      final docRows = await db.query(
        'jarvis_documents',
        where: 'subjectId = ?',
        whereArgs: [subject.id],
      );
      // Create simple doc objects from rows
      final docs = docRows
          .map(
            (r) => _DocInfo(
              type: r['type'] as String? ?? '',
              name: r['name'] as String? ?? '',
              content: r['content'] as String? ?? '',
            ),
          )
          .toList();
      if (docs.isEmpty) return '';

      // Fetch marks for context
      final marks = await db.query(
        'marks',
        where: 'subjectId = ?',
        whereArgs: [subject.id],
      );

      // Fetch topics
      final topics = await db.query(
        'topics',
        where: 'subjectId = ?',
        whereArgs: [subject.id],
      );

      // Fetch subject metadata
      final meta = await db.query(
        'subject_metadata',
        where: 'subjectId = ?',
        whereArgs: [subject.id],
      );
      final instructorFocus = meta.isNotEmpty
          ? (meta.first['instructor_focus'] as String? ?? '')
          : '';

      // Separate past exams from lecture notes
      // pastExams and studyMats not needed directly — just for reference
      // final pastExams = docs.where((d) => d.type == 'past_exam').toList();

      final docSummary = docs
          .map((d) => '[${d.type.toUpperCase()}] ${d.name}')
          .join('\n');
      final docContent = docs
          .map(
            (d) =>
                '=== ${d.name} ===\n${d.content.length > 3000 ? d.content.substring(0, 3000) : d.content}',
          )
          .join('\n\n');

      final marksSummary = marks
          .map(
            (m) =>
                '${m['category']} - ${m['label']}: ${m['obtained']}/${m['total']}',
          )
          .join(', ');

      final topicsSummary = topics
          .map((t) => '${t['title']} (stage ${t['stage']})')
          .join(', ');

      final prompt =
          '''
You are NOVA — an elite academic intel system. Generate a compressed Subject Intel Card.
Output ONLY the card as plain text (no markdown headers, no JSON).
Target: ~800 tokens. Dense, actionable, no fluff.

SUBJECT: ${subject.name}
INSTRUCTOR: ${subject.doctorName.isEmpty ? 'Unknown' : subject.doctorName}
INSTRUCTOR FOCUS: ${instructorFocus.isEmpty ? 'Not specified' : instructorFocus}
DOCUMENTS (${docs.length} files): $docSummary
PAST EXAMS: ${docs.where((d) => d.type == 'past_exam').length}
STUDENT MARKS: ${marksSummary.isEmpty ? 'No marks recorded' : marksSummary}
TOPICS (spaced repetition): ${topicsSummary.isEmpty ? 'None recorded' : topicsSummary}

DOCUMENT CONTENT (truncated):
$docContent

Generate the Subject Intel Card with these exact sections:
EXAM DNA: exam structure, question types, time distribution, difficulty pattern
TOP 5 TOPICS: most frequently tested (with % estimate each)
INSTRUCTOR PATTERNS: what this doctor always tests, what they emphasize, known traps
STUDENT STATUS: current performance trend, weak areas, mastery gaps  
NEVER ASKED: topics in materials that haven't appeared in past exams (overdue to appear)
PREDICTED QUESTIONS: 3-4 specific questions most likely on next exam, with reasoning
''';

      final card = await JarvisBrainService.generateRaw(
        prompt: prompt,
        maxTokens: 900,
        temperature: 0.2,
      );

      if (card != null && card.isNotEmpty) {
        // Save to DB
        await db.insert('nova_subject_intel', {
          'subjectId': subject.id,
          'subjectName': subject.name,
          'cardText': card,
          'documentCount': docs.length,
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return card;
      }
    } catch (e) {
      debugPrint('Intel card error for ${subject.name}: $e');
    }
    return '';
  }

  /// Load saved intel card from DB.
  static Future<String?> loadIntelCard(int subjectId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'nova_subject_intel',
      where: 'subjectId = ?',
      whereArgs: [subjectId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['cardText'] as String?;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Weekly Intelligence Briefing
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String> generateWeeklyBriefing({
    required List<Subject> subjects,
    required List<TaskModel> tasks,
    required List<TimetableEntry> timetable,
    required List<Map<String, dynamic>> absences,
    required List<MarkModel> marks,
    required List<StudyTopic> topics,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Load all intel cards
      final cards = StringBuffer();
      for (final s in subjects) {
        if (s.id == null) continue;
        final card = await loadIntelCard(s.id!);
        if (card != null)
          cards.write('\n\n=== ${s.name} INTEL CARD ===\n$card');
      }

      // Absence status per subject
      final absStatus = subjects
          .map((s) {
            if (s.id == null) return '';
            final sa = absences.where((a) => a['subjectId'] == s.id).toList();
            final lc = sa.where((a) => a['type'] == 'lecture').length;
            final sc = sa.where((a) => a['type'] == 'section').length;
            final lbc = sa.where((a) => a['type'] == 'lab').length;
            return '${s.name}: L$lc/${s.maxLectureAbs} S$sc/${s.maxSectionAbs} Lab$lbc/${s.maxLabAbs}';
          })
          .where((s) => s.isNotEmpty)
          .join(' | ');

      // Upcoming exams
      final now = DateTime.now();
      final examStr = tasks
          .where(
            (t) =>
                !t.isCompleted &&
                t.isExam &&
                t.dueDate != null &&
                t.dueDate!.isAfter(now),
          )
          .map((t) {
            final days = t.dueDate!.difference(now).inDays;
            final sub =
                subjects
                    .where((s) => s.id == t.subjectId)
                    .map((s) => s.name)
                    .firstOrNull ??
                '?';
            return '${t.title} ($sub) in $days days';
          })
          .join(' | ');

      final prompt =
          '''
You are NOVA — elite academic intelligence AI. Generate a Weekly Intelligence Briefing.
Format: plain text with these exact section headers (use ALL CAPS header + colon):

THREAT ASSESSMENT: Rate each subject 🔴CRITICAL/🟠URGENT/🟡WATCH/🟢ON TRACK with exam countdown and absence status. Be blunt.

A+ PROBABILITY: Per subject, honest % chance of A+ this semester with 1-line reasoning.

THIS WEEK'S MANDATORY ACTIONS: Top 5 priority actions in order. Specific, actionable, no vague advice.

THE ONE THING: Single most important action this week. Make it count.

INTEL CARDS:${cards.isEmpty ? ' (No documents uploaded yet)' : cards.toString()}

ABSENCE STATUS: $absStatus
UPCOMING EXAMS: ${examStr.isEmpty ? 'None scheduled' : examStr}
TODAY: ${now.day}/${now.month}/${now.year} (${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1]})

Write like a tactical military briefing officer who also happens to care deeply about this student's success.
Be direct. Flag real dangers. End with one motivational line.
''';

      final briefing = await JarvisBrainService.generateRaw(
        prompt: prompt,
        maxTokens: 1200,
        temperature: 0.3,
      );

      if (briefing != null && briefing.isNotEmpty) {
        await db.insert('nova_weekly_briefing', {
          'briefingText': briefing,
          'createdAt': DateTime.now().toIso8601String(),
          'weekNumber': _weekNum(now),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return briefing;
      }
    } catch (e) {
      debugPrint('Weekly briefing error: $e');
    }
    return '';
  }

  static Future<String?> loadLatestBriefing() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'nova_weekly_briefing',
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['briefingText'] as String?;
  }

  static int _weekNum(DateTime d) {
    final doy = d.difference(DateTime(d.year)).inDays + 1;
    return ((doy - d.weekday + 10) / 7).floor();
  }
}

// ── Simple doc info holder for intel engine ──────────────────────────────
class _DocInfo {
  final String type, name, content;
  const _DocInfo({
    required this.type,
    required this.name,
    required this.content,
  });
}
