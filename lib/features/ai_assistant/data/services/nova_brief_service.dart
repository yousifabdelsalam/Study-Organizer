// nova_brief_service.dart — NOVA App-Open Briefing engine
// Assembles brief text from live state, enforces 90-min cooldown,
// exposes ValueNotifiers consumed by NovaBriefCard and campus.dart.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/calendar/data/models/timetable.dart';
import 'package:study_organizer/features/subjects/data/models/topic.dart';

// ── Global ValueNotifiers ─────────────────────────────────────────────────────
final ValueNotifier<String?>       novaBriefText         = ValueNotifier(null);
final ValueNotifier<bool>          novaBriefSpeaking     = ValueNotifier(false);
final ValueNotifier<String?>       novaBriefPausedBanner = ValueNotifier(null);
/// campus.dart registers _speakBriefOnDemand here; NovaBriefCard calls it.
final ValueNotifier<VoidCallback?> novaSpeak = ValueNotifier(null);

// ─────────────────────────────────────────────────────────────────────────────
class NovaBriefService {
  static const _prefLastBriefTs = 'nova_last_brief_ts';
  static const _prefBriefText   = 'nova_last_brief_text';
  static const _cooldownMinutes = 90;

  static Future<String?> onAppResumed({
    required List<Subject>              subjects,
    required List<TaskModel>            tasks,
    required List<TimetableEntry>       timetable,
    required List<Map<String,dynamic>>  absences,
    required List<StudyTopic>           topics,
    required String                     currentWeekType,
    required bool                       isAtHome,
  }) async {
    final now = DateTime.now();
    if (now.hour < 5) return null;              // silent hours

    final brief = _build(subjects, tasks, timetable, absences, topics, currentWeekType);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBriefText, brief);
    novaBriefText.value = brief;

    // ── AUTO-SPEAK DISABLED ──────────────────────────────────────────────────
    // Brief is now silent on app open — it only shows as a card.
    // User can tap "HEAR BRIEF" on the card to listen.
    // Return null so the caller (campus.dart) never speaks it automatically.
    return null;

    // ── ORIGINAL AUTO-SPEAK LOGIC (re-enable by removing the return null above)
    // final elapsed = now.millisecondsSinceEpoch - (prefs.getInt(_prefLastBriefTs) ?? 0);
    // if (elapsed < _cooldownMinutes * 60000) return null;
    // if (!isAtHome) return null;
    // await prefs.setInt(_prefLastBriefTs, now.millisecondsSinceEpoch);
    // return brief;
  }

  static Future<void> loadPersistedBrief() async {
    final s = (await SharedPreferences.getInstance()).getString(_prefBriefText);
    if (s != null && s.isNotEmpty) novaBriefText.value = s;
  }

  static Future<void> dismissBrief() async {
    novaBriefText.value = null;
    await (await SharedPreferences.getInstance()).remove(_prefBriefText);
  }

  static void onVolumeUpDuringSpeech() {
    if (!novaBriefSpeaking.value) return;
    novaBriefSpeaking.value = false;
    novaBriefPausedBanner.value = novaBriefText.value;
    Timer(const Duration(seconds: 6), () => novaBriefPausedBanner.value = null);
  }

  static void onBriefStartedSpeaking()  => novaBriefSpeaking.value = true;
  static void onBriefFinishedSpeaking() => novaBriefSpeaking.value = false;

  // ── Brief text assembly ───────────────────────────────────────────────────
  static String _build(
    List<Subject> subjects, List<TaskModel> tasks,
    List<TimetableEntry> timetable, List<Map<String,dynamic>> absences,
    List<StudyTopic> topics, String weekType,
  ) {
    final now = DateTime.now();
    final h   = now.hour;
    final sb  = StringBuffer(h < 12 ? 'Good morning, sir. ' : h < 18 ? 'Afternoon, sir. ' : 'Good evening, sir. ');

    // Today's classes
    final today = timetable
        .where((e) => e.dayOfWeek == now.weekday && (e.weekType == 'both' || e.weekType == weekType))
        .toList()..sort((a,b) => a.startTime.compareTo(b.startTime));
    if (today.isEmpty) {
      sb.write('No classes today. ');
    } else {
      sb.write('${today.length} ${today.length == 1 ? "class" : "classes"} today: ');
      sb.write(today.map((e) {
        final n = subjects.where((s) => s.id == e.subjectId).map((s) => s.name).firstOrNull ?? 'Unknown';
        return '$n at ${_h12(e.startTime)}';
      }).join(', '));
      sb.write('. ');
    }

    // Absence critical warnings
    for (final s in subjects) {
      if (s.id == null) continue;
      final sa   = absences.where((a) => a['subjectId'] == s.id).toList();
      final lc   = sa.where((a) => a['type'] == 'lecture').length;
      final sc   = sa.where((a) => a['type'] == 'section').length;
      final lbc  = sa.where((a) => a['type'] == 'lab').length;
      if (s.maxLectureAbs > 0 && s.maxLectureAbs - lc == 1) sb.write('One lecture absence left in ${s.name}. ');
      if (s.maxLectureAbs > 0 && s.maxLectureAbs - lc <= 0) sb.write('Barred from ${s.name} lectures. ');
      if (s.maxSectionAbs > 0 && s.maxSectionAbs - sc == 1) sb.write('One section absence left in ${s.name}. ');
      if (s.maxLabAbs     > 0 && s.maxLabAbs     - lbc == 1) sb.write('One lab absence left in ${s.name}. ');
    }

    // Upcoming exams ≤ 10 days
    final exams = tasks
        .where((t) => !t.isCompleted && t.isExam && t.dueDate != null &&
               t.dueDate!.isAfter(now) && t.dueDate!.difference(now).inDays <= 10)
        .toList()..sort((a,b) => a.dueDate!.compareTo(b.dueDate!));
    if (exams.isNotEmpty) {
      final e   = exams.first;
      final d   = e.dueDate!.difference(now).inDays;
      final sub = subjects.where((s) => s.id == e.subjectId).map((s) => s.name).firstOrNull ?? 'Unknown';
      sb.write('${e.title} for $sub is ${d == 0 ? "today" : d == 1 ? "tomorrow" : "in $d days"}. ');
    }

    // Overdue topics (morning only)
    if (h < 14) {
      final od = topics.where((t) => !t.isMastered &&
          (t.stage == 0 || (t.nextReview != null && t.nextReview!.isBefore(now)))).length;
      if (od >= 3) sb.write('$od topics overdue for review. ');
    }

    sb.write(h < 12 ? 'Study plan is ready.' : h < 18 ? 'Focus on what matters most.' : 'Plan your evening well, sir.');
    return sb.toString().trim();
  }

  static String _h12(String t) {
    final p = t.split(':');
    if (p.length < 2) return t;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final h12 = h > 12 ? h-12 : (h == 0 ? 12 : h);
    return m == 0 ? '$h12 ${h >= 12 ? "PM" : "AM"}' : '$h12:${m.toString().padLeft(2,"0")} ${h >= 12 ? "PM" : "AM"}';
  }
}
