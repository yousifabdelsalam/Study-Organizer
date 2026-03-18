import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:intl/intl.dart' as intl;
import '../models/timetable.dart';
import '../models/reminder.dart';
import '../models/topic.dart';
import '../models/subject.dart';
import '../models/task.dart';
import 'nova_audio_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATION DIAGNOSTIC LOGGER
//
// Writes every scheduling attempt, error, and system check to a persistent
// file on device. Survives app restarts. Read from NotifDiagnosticPage.
//
// Usage:
//   await NotifDiag.init();                    ← call once in main()
//   await NotifDiag.runFull(entries, names, weekType);  ← full check
//   await NotifDiag.readAll();                 ← get log string for display
// ═══════════════════════════════════════════════════════════════════════════════
class NotifDiag {
  static const int _maxLines = 600;
  static File? _file;

  // ── Init: open or create the log file ──────────────────────────────────────
  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/notif_diag.log');
      if (!await _file!.exists()) await _file!.writeAsString('');
    } catch (e) {
      debugPrint('[NotifDiag] init failed: $e');
    }
  }

  // ── Write a log line ───────────────────────────────────────────────────────
  static Future<void> log(
      String tag,
      String msg, {
        bool isError = false,
      }) async {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final prefix = isError ? '❌' : '✅';
    final line = '[$ts] $prefix [$tag] $msg';
    debugPrint(line);
    try {
      if (_file != null) {
        await _file!.writeAsString('$line\n', mode: FileMode.append);
        final lines = await _file!.readAsLines();
        if (lines.length > _maxLines) {
          await _file!.writeAsString(
            lines.skip(lines.length - _maxLines).join('\n') + '\n',
          );
        }
      }
    } catch (_) {}
  }

  // Same as log() but does NOT await — for fire-and-forget call sites
  static void logSync(String tag, String msg, {bool isError = false}) {
    log(tag, msg, isError: isError);
  }

  // ── Read all logs ──────────────────────────────────────────────────────────
  static Future<String> readAll() async {
    try {
      if (_file != null && await _file!.exists()) {
        final content = await _file!.readAsString();
        return content.isEmpty ? '(log is empty)' : content;
      }
    } catch (_) {}
    return '(log file not accessible)';
  }

  // ── Clear log ─────────────────────────────────────────────────────────────
  static Future<void> clear() async {
    try {
      if (_file != null) await _file!.writeAsString('');
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LAYER 1 — PERMISSIONS
  //
  // The #1 silent killer. On Android 12+ exact alarm permission is a
  // SEPARATE permission from notifications. If it's denied, zonedSchedule()
  // returns no error but the alarm is never registered.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> checkPermissions() async {
    await log('PERM', '─── Permission Check ───');
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android =
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
      >();

      if (android == null) {
        await log(
          'PERM',
          'Android plugin resolved to NULL — are you on iOS?',
          isError: true,
        );
        return;
      }

      // General notification permission (Android 13+ / API 33+)
      final notifEnabled = await android.areNotificationsEnabled();
      final notifGranted = notifEnabled == true;
      await log(
        'PERM',
        'Notifications enabled: $notifEnabled'
            '${notifGranted ? '' : '  ← USER ACTION REQUIRED: Settings → App → Notifications'}',
        isError: !notifGranted,
      );

      // Exact alarm permission (Android 12+ / API 31+)
      // This is the most common reason timetable notifications silently fail.
      try {
        final exactAlarm = await android.canScheduleExactNotifications();
        final exactGranted = exactAlarm == true;
        await log(
          'PERM',
          'Exact alarms allowed: $exactAlarm'
              '${exactGranted ? '' : '  ← CRITICAL: Settings → Special App Access → Alarms & Reminders → enable'}',
          isError: !exactGranted,
        );
      } catch (e) {
        await log(
          'PERM',
          'canScheduleExactNotifications() threw: $e  (API < 31 device?)',
          isError: true,
        );
      }
    } catch (e) {
      await log('PERM', 'Permission check crashed: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LAYER 2 — TIMEZONE
  //
  // If tz.local is UTC, all Cairo notifications fire 2 hours early or late.
  // If tz is not initialized at all, TZDateTime.from() throws and the
  // entire schedule() call silently returns.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> checkTimezone() async {
    await log('TZ', '─── Timezone Check ───');
    try {
      final localName = tz.local.name;
      final tzNow = tz.TZDateTime.now(tz.local);
      final sysNow = DateTime.now();

      await log('TZ', 'tz.local.name     = "$localName"');
      await log('TZ', 'tz.TZDateTime.now = $tzNow');
      await log('TZ', 'DateTime.now()    = $sysNow');

      final driftMin = tzNow.difference(sysNow).inMinutes.abs();

      if (localName == 'UTC' || localName.isEmpty) {
        await log(
          'TZ',
          'TIMEZONE IS UTC — all Cairo notifications will fire 2 hours wrong!',
          isError: true,
        );
      } else if (localName != 'Africa/Cairo') {
        await log(
          'TZ',
          'Timezone is "$localName" not "Africa/Cairo" — verify this is intentional',
          isError: true,
        );
      } else if (driftMin > 5) {
        await log(
          'TZ',
          'TZDateTime vs DateTime drift: ${driftMin}min — possible DST mismatch',
          isError: true,
        );
      } else {
        await log('TZ', 'Timezone correct, drift: ${driftMin}min');
      }
    } catch (e) {
      await log(
        'TZ',
        'Timezone check crashed — tzdata may not be initialized: $e',
        isError: true,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LAYER 3 — DATA INTEGRITY
  //
  // Checks what actually gets passed into scheduleTimetableNotifs.
  // Empty entries or all-mismatched weekType = zero notifications.
  // Missing subjectId in the names map = every class shows as "Class".
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> checkTimetableData({
    required List<TimetableEntry> entries,
    required Map<int, String> subjectNames,
    required String currentWeekType,
  }) async {
    await log('DATA', '─── Timetable Data Snapshot ───');
    await log('DATA', 'entries.length   = ${entries.length}');
    await log('DATA', 'currentWeekType  = "$currentWeekType"');
    await log('DATA', 'subjectNames map = $subjectNames');

    if (entries.isEmpty) {
      await log(
        'DATA',
        'NO TIMETABLE ENTRIES — nothing will be scheduled! '
            'Did the DB import succeed? Is the Bloc state loaded?',
        isError: true,
      );
      return;
    }

    final now = DateTime.now();
    int willScheduleCount = 0;
    int skippedWeekType = 0;
    int skippedPast = 0;
    int missingSubject = 0;

    for (final e in entries) {
      final subName =
          subjectNames[e.subjectId] ?? '??? (id=${e.subjectId})';
      final hasMissing = !subjectNames.containsKey(e.subjectId);
      if (hasMissing) missingSubject++;

      // For 'both' entries — does the next occurrence exist?
      final parts = e.startTime.split(':');
      bool isPastToday = false;
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        if (now.weekday == e.dayOfWeek) {
          final todayStart = DateTime(now.year, now.month, now.day, h, m);
          isPastToday =
              todayStart.isBefore(now.subtract(const Duration(minutes: 2)));
        }
      }

      final weekTypeMismatch =
          e.weekType != 'both' && e.weekType != currentWeekType;

      String verdict;
      if (weekTypeMismatch) {
        verdict =
        '⚠️ WEEK TYPE MISMATCH (entry="${e.weekType}" vs current="$currentWeekType") '
            '— old logic skipped this; new logic schedules next matching week';
        skippedWeekType++;
      } else if (isPastToday) {
        verdict =
        '⚠️ CLASS PASSED TODAY — will schedule for next occurrence (new logic handles this)';
        skippedPast++;
      } else {
        verdict = hasMissing
            ? '⚠️ WILL SCHEDULE but subject name missing (shows as "Class")'
            : '✓ WILL SCHEDULE';
        willScheduleCount++;
      }

      await log(
        'DATA',
        '  ${e.dayName.padRight(9)} ${e.startTime} | '
            '${subName.padRight(20)} | weekType=${e.weekType.padRight(4)} | $verdict',
      );
    }

    await log(
      'DATA',
      'Summary: ${entries.length} entries → '
          '$willScheduleCount active | '
          '$skippedWeekType odd/even (handled by new scheduler) | '
          '$skippedPast past-today (handled by _nextWeekdayAt) | '
          '$missingSubject missing subject names',
    );

    if (subjectNames.isEmpty) {
      await log(
        'DATA',
        'subjectNames map is EMPTY — all classes will show as "Class". '
            'Subjects may not be loaded yet when scheduleTimetableNotifs was called.',
        isError: true,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LAYER 4 — ANDROID QUOTA GUARD
  //
  // Android hard-limits exact alarms to 50 pending notifications total.
  // When you hit this limit, new zonedSchedule() calls return NO error
  // but the alarm is silently discarded. This is the sneakiest failure.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> checkAndroidQuota() async {
    await log('QUOTA', '─── Android 50-Alarm Quota Check ───');
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final pending = await plugin.pendingNotificationRequests();
      final count = pending.length;

      await log(
        'QUOTA',
        'Pending notifications: $count / 50',
        isError: count >= 45,
      );

      if (count >= 50) {
        await log(
          'QUOTA',
          'AT LIMIT: new notifications are being silently dropped!',
          isError: true,
        );
      } else if (count >= 45) {
        await log(
          'QUOTA',
          'NEAR LIMIT: only ${50 - count} slots left',
          isError: true,
        );
      }

      // Break down by ID range
      final timetable = pending
          .where((p) =>
      p.payload != null && p.payload!.startsWith('timetable:'))
          .toList();
      final tasks = pending.where((p) => p.id < 100000).toList();
      final exams =
      pending
          .where((p) => p.id >= 100000 && p.id < 300000)
          .toList();
      final reminders =
      pending
          .where((p) => p.id >= 700000 && p.id < 800000)
          .toList();
      final morning =
      pending
          .where((p) => p.id >= 1000000 && p.id <= 1000007)
          .toList();
      final nova =
      pending
          .where((p) => p.id >= 860000 && p.id <= 870000)
          .toList();
      final other =
      pending
          .where(
            (p) =>
        !timetable.contains(p) &&
            !tasks.contains(p) &&
            !exams.contains(p) &&
            !reminders.contains(p) &&
            !morning.contains(p) &&
            !nova.contains(p),
      )
          .toList();

      await log(
        'QUOTA',
        'Breakdown → Timetable:${timetable.length} | '
            'Tasks:${tasks.length} | Exams:${exams.length} | '
            'Reminders:${reminders.length} | Morning:${morning.length} | '
            'NOVA:${nova.length} | Other:${other.length}',
      );

      if (timetable.isEmpty) {
        await log(
          'QUOTA',
          'ZERO timetable notifications in pending queue! '
              'Either scheduling failed, or all were cancelled.',
          isError: true,
        );
      } else {
        await log('QUOTA', 'Timetable alarms registered:');
        for (final p in timetable) {
          await log(
            'QUOTA',
            '  id=${p.id} | "${p.title}" | payload="${p.payload}"',
          );
        }
      }
    }catch(e){

    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LAYER 5 — LIVE FIRE TEST
  //
  // Schedules a real test notification 1 minute from now, then immediately
  // checks it landed in the pending queue.
  //
  // PASS: alarm appears in pending list → scheduling pipeline works.
  //       Wait 1 min — if notification fires, OS delivery works too.
  //
  // FAIL (not in pending): exact alarm permission denied OR quota full.
  // FAIL (in pending but never fires): manufacturer battery kill
  //       (Xiaomi MIUI, Samsung One UI, Oppo ColorOS aggressive Doze).
  //       Fix: Settings → Battery → Special app access → add app to exemptions.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> scheduleTestNotification() async {
    await log('TEST', '─── 1-Minute Live Fire Test ───');
    const testId = 999991;
    try {
      // Cancel any leftover from a previous test run
      await FlutterLocalNotificationsPlugin().cancel(testId);

      final fireAt = DateTime.now().add(const Duration(minutes: 1));
      await NotifService.schedule(
        id: testId,
        title: '🧪 DIAG — Notification system works!',
        body:
        'Scheduled at ${DateTime.now().hour}:'
            '${DateTime.now().minute.toString().padLeft(2, '0')}, '
            'fired at ${fireAt.hour}:${fireAt.minute.toString().padLeft(2, '0')}',
        when: fireAt,
        channelId: 'study_notifs',
        channelName: 'Study Reminders',
        channelDesc: 'Diagnostic test notification',
        payload: 'diag_test',
      );

      // Give the plugin 300ms to register the alarm, then verify
      await Future.delayed(const Duration(milliseconds: 300));
      final pending =
      await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
      final found = pending.any((p) => p.id == testId);

      if (found) {
        await log(
          'TEST',
          'Test alarm confirmed in pending queue ✓  '
              'Expect a notification at ${fireAt.hour}:${fireAt.minute.toString().padLeft(2, '0')}. '
              'If it does NOT appear → manufacturer Doze is killing alarms.',
        );
      } else {
        await log(
          'TEST',
          'Test alarm NOT in pending queue after scheduling! '
              'zonedSchedule() returned no error but alarm was not registered. '
              'Most likely cause: exact alarm permission denied OR quota full (check QUOTA above).',
          isError: true,
        );
      }
    } catch (e) {
      await log('TEST', 'Test notification threw: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FULL DIAGNOSTIC RUN — call from NotifDiagnosticPage button
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> runFull({
    required List<TimetableEntry> entries,
    required Map<int, String> subjectNames,
    required String currentWeekType,
    bool scheduleTestNotif = false,
  }) async {
    await log('DIAG', '════════ DIAGNOSTIC START — ${DateTime.now()} ════════');
    await checkPermissions();
    await checkTimezone();
    await checkTimetableData(
      entries: entries,
      subjectNames: subjectNames,
      currentWeekType: currentWeekType,
    );
    await checkAndroidQuota();
    if (scheduleTestNotif) await scheduleTestNotification();
    await log('DIAG', '════════ DIAGNOSTIC END ════════');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND HANDLER — must be top-level, annotated vm:entry-point
// ═══════════════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse details) {
  debugPrint('[BG] Notif: ${details.payload} action:${details.actionId}');
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOTIF SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
class NotifService {
  static final FlutterLocalNotificationsPlugin _p =
  FlutterLocalNotificationsPlugin();
  static void Function(String payload, String? actionId)? onActionReceived;
  static Timer? _deepStudyTimer;
  static int _pingCount = 0;
  static final Map<int, Timer> _urgentTimers = {};
  static bool _tzInitialized = false;

  // Tracks every timetable notification ID scheduled in this session.
  // Used by cancelTimetableAll() to cancel them without iterating ID ranges.
  static final Set<int> _timetableNotifIds = {};

  // ── init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    _ensureTimezone();

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    _p.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
    >();

    if (androidPlugin != null) {
      for (final ch in _channels) {
        try {
          await androidPlugin.createNotificationChannel(ch);
        } catch (_) {}
      }
    }

    await _p.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (d) {
        debugPrint('[FG] Notif: ${d.payload} action:${d.actionId}');
        if (d.payload != null) onActionReceived?.call(d.payload!, d.actionId);
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    if (androidPlugin != null) {
      try {
        await androidPlugin.requestNotificationsPermission();
      } catch (_) {}
      try {
        await androidPlugin.requestExactAlarmsPermission();
      } catch (_) {}
    }

    NotifDiag.logSync('INIT', 'NotifService.init() complete');
  }

  // ── channels ──────────────────────────────────────────────────────────────
  static final List<AndroidNotificationChannel> _channels = [
    const AndroidNotificationChannel(
      'study_notifs',
      'Study Reminders',
      description: 'Task reminders',
      importance: Importance.max,
    ),
    const AndroidNotificationChannel(
      'exam_notifs',
      'Exam Reminders',
      description: 'Exam reminders',
      importance: Importance.max,
    ),
    const AndroidNotificationChannel(
      'timetable_notifs',
      'Class Reminders',
      description: 'Timetable class reminders',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      'reminder_notifs',
      'Reminders',
      description: 'Custom reminders',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      'deep_study',
      'Deep Study',
      description: 'Study session pings',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      'read_my_day',
      'Read My Day',
      description: 'End-of-day schedule reading',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      'urgent_tasks',
      'Urgent Tasks',
      description: 'Tasks due within 3 hours',
      importance: Importance.max,
    ),
    const AndroidNotificationChannel(
      'nova_checkin',
      'NOVA Daily Check-ins',
      description: 'Scheduled NOVA briefing notifications',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      'nova_watchdog',
      'Distraction Guard',
      description: 'App usage limit alerts',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      'nova_attendance',
      'Attendance Guardian',
      description: 'Mandatory attendance alerts',
      importance: Importance.max,
    ),
  ];

  // ── timezone ──────────────────────────────────────────────────────────────
  static void _ensureTimezone() {
    if (_tzInitialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
      _tzInitialized = true;
      NotifDiag.logSync('TZ', 'Timezone initialized to Africa/Cairo');
    } catch (e) {
      NotifDiag.logSync(
        'TZ',
        'FAILED to initialize timezone: $e',
        isError: true,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CORE: schedule() — instrumented with full diagnostic logging
  //
  // Every call is logged. Errors are NEVER swallowed silently anymore.
  // Previously: catch(e) { debugPrint('❌ schedule error: $e'); }
  // Now: logged to persistent file with full stack trace.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String channelId = 'study_notifs',
    String channelName = 'Study Reminders',
    String channelDesc = 'Reminders',
    String? payload,
    List<AndroidNotificationAction>? actions,
  }) async {
    _ensureTimezone();

    // ── Guard 1: Past time ────────────────────────────────────────────────────
    if (when.isBefore(DateTime.now())) {
      NotifDiag.log('SCHED', 'SKIPPED id=$id "$title" — target time $when is in the past');
      return;
    }

    // ── Guard 2: Convert to TZDateTime and log it ─────────────────────────────
    final tzWhen = tz.TZDateTime.from(when, tz.local);
    NotifDiag.log('SCHED',
        'Scheduling id=$id "$title" for $when → tz=$tzWhen (tz.local=${tz.local.name})');

    try {
      await _p.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            actions: actions,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload ?? '$id',
      );
      NotifDiag.log('SCHED', 'zonedSchedule OK id=$id');
    } catch (e, stack) {
      // ── This is the line that was previously swallowing all errors ──────────
      NotifDiag.log('SCHED',
          'zonedSchedule THREW for id=$id: $e\n$stack',
          isError: true);
    }
  }

  // ── show() — immediate (not scheduled) notification ───────────────────────
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String channelId = 'study_notifs',
    String channelName = 'Study Reminders',
    String channelDesc = 'Reminders',
    String? payload,
    List<AndroidNotificationAction>? actions,
  }) async {
    try {
      await _p.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            actions: actions,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        payload: payload ?? '$id',
      );
    } catch (e) {
      NotifDiag.logSync('SHOW', 'show() threw for id=$id: $e', isError: true);
    }
  }

  // ── Task Notifications ────────────────────────────────────────────────────
  static Future<void> scheduleTaskNotifs(
      int id,
      String title,
      DateTime due,
      ) async {
    await cancel(id);
    final now = DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) return;

    final fmt = intl.DateFormat('h:mm a');
    final fmtD = intl.DateFormat('MMM d');

    if (diff.inDays <= 7) {
      final threeHourMark = due.subtract(const Duration(hours: 3));
      if (threeHourMark.isAfter(now)) {
        await schedule(
          id: id + 100000,
          title: '🔥 Due in 3 hours!',
          body: '$title — Today at ${fmt.format(due)}',
          when: threeHourMark,
        );
      }
      final oneDayMark = due.subtract(const Duration(hours: 24));
      if (oneDayMark.isAfter(now)) {
        await schedule(
          id: id,
          title: '⏰ Due in 24 hours',
          body: '$title — ${fmtD.format(due)} at ${fmt.format(due)}',
          when: oneDayMark,
        );
      }
      final dayBefore = due.subtract(const Duration(days: 1));
      final nightBefore = DateTime(
          dayBefore.year, dayBefore.month, dayBefore.day, 21, 0);
      if (nightBefore.isAfter(now)) {
        await schedule(
          id: id + 200000,
          title: '📋 Due tomorrow',
          body: '$title — Tomorrow at ${fmt.format(due)}',
          when: nightBefore,
        );
      }
    }

    if (diff.inHours < 3) {
      startUrgentTaskReminder(id, title);
    }
  }

  // ── Exam Notifications ────────────────────────────────────────────────────
  static Future<void> scheduleExamNotifs(
      int id,
      String title,
      String examType,
      DateTime due,
      ) async {
    await cancelExam(id);
    final now = DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) return;
    final fmt = intl.DateFormat('h:mm a');
    final fmtD = intl.DateFormat('MMM d');
    final lbl = examType[0].toUpperCase() + examType.substring(1);
    const ch = 'exam_notifs';
    const cn = 'Exam Reminders';
    const cd = 'Exam reminders';
    final dayBefore = due.subtract(const Duration(days: 1));
    await schedule(
      id: id + 500000,
      title: '📚 $lbl in 3 days',
      body: '$title — ${fmtD.format(due)}',
      when: due.subtract(const Duration(days: 3)),
      channelId: ch,
      channelName: cn,
      channelDesc: cd,
    );
    await schedule(
      id: id + 600000,
      title: '⚠️ $lbl TOMORROW!',
      body: '$title — Study hard!',
      when: DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 21, 0),
      channelId: ch,
      channelName: cn,
      channelDesc: cd,
    );
    await schedule(
      id: id + 100000,
      title: '🔥 $lbl in 3 hours!',
      body: '$title — ${fmt.format(due)}',
      when: due.subtract(const Duration(hours: 3)),
      channelId: ch,
      channelName: cn,
      channelDesc: cd,
    );
    await schedule(
      id: id,
      title: '📝 $lbl in 24 hours',
      body: '$title — ${fmtD.format(due)}',
      when: due.subtract(const Duration(hours: 24)),
      channelId: ch,
      channelName: cn,
      channelDesc: cd,
    );
  }

  // // ── Daily Morning (Spaced Repetition) Notifications ──────────────────────
  // static Future<void> scheduleDailyMorningNotifs(
  //     List<StudyTopic> topics,
  //     List<Subject> subjects,
  //     ) async {
  //   for (int i = 0; i < 7; i++) {
  //     final date = DateTime.now().add(Duration(days: i));
  //     final targetDate = DateTime(date.year, date.month, date.day);
  //
  //     final dueTopics = topics.where((t) {
  //       final r = t.nextReview;
  //       if (r == null) return false;
  //       final rd = DateTime(r.year, r.month, r.day);
  //       return rd.isAtSameMomentAs(targetDate);
  //     }).toList();
  //
  //     if (dueTopics.isNotEmpty) {
  //       final when = DateTime(date.year, date.month, date.day, 8, 0);
  //       if (when.isBefore(DateTime.now())) continue;
  //       await schedule(
  //         id: 1000000 + i,
  //         title: '🧠 Study Time!',
  //         body: 'You have ${dueTopics.length} topics due for Spaced Repetition today.',
  //         when: when,
  //         channelId: 'study_notifs',
  //         channelName: 'Study Reminders',
  //       );
  //     } else {
  //       await cancelSingle(1000000 + i);
  //     }
  //   }
  // }

  // ════════════════════════════════════════════════════════════════════════════
  // TIMETABLE NOTIFICATIONS — FIXED
  //
  // Old approach (broken):
  //   - Looped over dayOffset 0..2 → only 3 days ahead, expires and never
  //     reschedules unless user opens the app
  //   - Skipped odd/even entries that didn't match THIS week → they were
  //     never scheduled at all if the window missed their day
  //   - No repeat → every notification is one-shot
  //
  // New approach:
  //   - weekType == 'both'  → weekly auto-repeat via matchDateTimeComponents
  //     = DateTimeComponents.dayOfWeekAndTime. ONE alarm per class, fires
  //     forever every week without rescheduling.
  //   - weekType == 'odd'/'even' → schedules the next 4 matching fortnightly
  //     occurrences (covers ~2 months). Rescheduled whenever the app opens.
  //   - _nextWeekdayAt() ensures we always find the correct future date even
  //     if the class day already passed this week.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> scheduleTimetableNotifs({
    required List<TimetableEntry> entries,
    required Map<int, String> subjectNames,
    required String currentWeekType,
    required List<TaskModel> tasks,
  }) async {
    await cancelTimetableAll();
    try {
      final pending = await _p.pendingNotificationRequests();
      final slotsAvailable = 50 - pending.length;
      if (slotsAvailable <= 8) {
        debugPrint('⚠️ [QUOTA] Only $slotsAvailable slots free — timetable scheduling skipped');
        return;
      }
    } catch (_) {}

    // ── Diagnostic snapshot of what we're about to schedule ──────────────────
    await NotifDiag.log('TTSCHED',
        'scheduleTimetableNotifs called: ${entries.length} entries, '
            'weekType=$currentWeekType, subjects=${subjectNames.keys.toList()}');

    _ensureTimezone();

    final now = DateTime.now();
    int scheduledCount = 0;

    await NotifDiag.log(
      'TTSCHED',
      'scheduleTimetableNotifs called: ${entries.length} entries, '
          'weekType=$currentWeekType',
    );

    for (final e in entries) {
      // ── Parse start time ──────────────────────────────────────────────────
      final parts = e.startTime.split(':');
      if (parts.length < 2) {
        await NotifDiag.log(
          'TTSCHED',
          'Bad startTime "${e.startTime}" for subjectId=${e.subjectId} — skipping',
          isError: true,
        );
        continue;
      }
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;

      final subName = subjectNames[e.subjectId] ?? 'Class';
      final emoji =
      e.type == 'lab' ? '🧪' : e.type == 'section' ? '🔧' : '📚';
      final loc = [
        if (e.room.isNotEmpty) 'Room ${e.room}',
        if (e.building.isNotEmpty) e.building,
      ].join(' · ');
      final body =
          '${e.type[0].toUpperCase()}${e.type.substring(1)}'
          '${loc.isNotEmpty ? ' — $loc' : ''}';
      final notifTitle = '$emoji $subName — Starting NOW!';

      // Stable ID: uniquely bound to this (dayOfWeek, startTime) slot.
      // Uses dayOfWeek from the MODEL (not a loop variable) so IDs are
      // identical across rescheduling calls.
      final minuteOfWeek = (e.dayOfWeek - 1) * 1440 + (h * 60) + m;
      final weekTypeOff = e.weekType == 'both' ? 0 : e.weekType == 'odd' ? 1 : 2;
      final baseId = 900000 + minuteOfWeek * 3 + weekTypeOff;

      // ── Handle exceptional (one-time) classes ─────────────────────────────
      if (e.isExceptional && e.exceptionalDate.isNotEmpty) {
        try {
          final exDate = DateTime.parse(e.exceptionalDate);
          final classStart = DateTime(exDate.year, exDate.month, exDate.day, h, m);
          if (classStart.isAfter(now.subtract(const Duration(minutes: 2)))) {
            if (!_hasExamOnDate(tasks, classStart)) {
              await schedule(
                id: baseId + 1,
                title: notifTitle,
                body: body,
                when: classStart,
                channelId: 'timetable_notifs',
                channelName: 'Class Reminders',
                channelDesc: 'Timetable',
                payload: 'timetable:${e.subjectId}',
              );
              _timetableNotifIds.add(baseId + 1);
              scheduledCount++;
              await NotifDiag.log(
                'TTSCHED',
                'Exceptional class: $subName on ${e.exceptionalDate} at $h:${m.toString().padLeft(2, '0')} (id:${baseId + 1})',
              );
            }
          }
        } catch (err) {
          await NotifDiag.log(
            'TTSCHED',
            'Bad exceptionalDate "${e.exceptionalDate}": $err',
            isError: true,
          );
        }
        continue; // exceptional entries don't get the repeating logic
      }

      // ── CASE A: weekType == 'both' → weekly auto-repeat ───────────────────
      // One alarm, fires every 7 days automatically.
      // Android handles the repeat — no rescheduling needed after boot
      // (boot receiver will re-register it on reboot).
      if (e.weekType == 'both') {
        final firstOcc = _nextWeekdayAt(now, e.dayOfWeek, h, m);

        if (_hasExamOnDate(tasks, firstOcc)) {
          await NotifDiag.log(
            'TTSCHED',
            'SKIP $subName ${_dowName(e.dayOfWeek)} ${e.startTime} — exam on first occurrence ${firstOcc.toIso8601String().split('T')[0]}',
          );
          continue;
        }

        await _scheduleWeeklyRepeating(
          id: baseId + 1,
          title: notifTitle,
          body: body,
          firstOccurrence: firstOcc,
          payload: 'timetable:${e.subjectId}',
        );
        _timetableNotifIds.add(baseId + 1);
        scheduledCount++;

        await NotifDiag.log(
          'TTSCHED',
          'WEEKLY [$subName] every ${_dowName(e.dayOfWeek)} at '
              '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} — '
              'first occ: ${firstOcc.toIso8601String().split('T')[0]} (id:${baseId + 1})',
        );
      }

      // ── CASE B: weekType == 'odd' or 'even' → next 4 matching fortnights ──
      // We can't use auto-repeat because the week parity changes every 7 days,
      // so we schedule 4 explicit one-shot alarms (~2 months of coverage).
      // They get refreshed whenever the app opens via _rescheduleNotificationsOnStart.
      else {
        int found = 0;
        DateTime candidate = _nextWeekdayAt(now, e.dayOfWeek, h, m);

        while (found < 2) {
          final wNum = _weekNumber(candidate);
          final wType = wNum.isOdd ? 'odd' : 'even';

          if (wType == e.weekType) {
            if (_hasExamOnDate(tasks, candidate)) {
              await NotifDiag.log(
                'TTSCHED',
                'SKIP $subName ${candidate.toIso8601String().split('T')[0]} — exam on that day',
              );
            } else {
              final notifId = baseId + 1 + (found * 100000);
              await schedule(
                id: notifId,
                title: notifTitle,
                body: body,
                when: candidate,
                channelId: 'timetable_notifs',
                channelName: 'Class Reminders',
                channelDesc: 'Timetable',
                payload: 'timetable:${e.subjectId}',
              );
              _timetableNotifIds.add(notifId);
              scheduledCount++;
              found++;
              await NotifDiag.log(
                'TTSCHED',
                'ODD/EVEN [$subName] ${e.weekType} week on '
                    '${candidate.toIso8601String().split('T')[0]} at '
                    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} '
                    '(id:$notifId, occurrence $found/4)',
              );
            }
          }

          candidate = candidate.add(const Duration(days: 7));

          // Safety cap: don't search more than 90 days out
          if (candidate.difference(now).inDays > 90) {
            await NotifDiag.log(
              'TTSCHED',
              'ODD/EVEN [$subName] — only found $found occurrences in 90 days (weekType=${e.weekType})',
              isError: found == 0,
            );
            break;
          }
        }
      }

      // ── Immediate notification if this class is starting RIGHT NOW (±2 min) ──
      if (e.dayOfWeek == now.weekday) {
        final todayStart = DateTime(now.year, now.month, now.day, h, m);
        final diff = todayStart.difference(now).inMinutes;
        if (diff <= 2 &&
            todayStart.isAfter(now.subtract(const Duration(minutes: 2)))) {
          await show(
            id: baseId + 2,
            title: notifTitle,
            body: body,
            channelId: 'timetable_notifs',
            channelName: 'Class Reminders',
            channelDesc: 'Timetable',
            payload: 'timetable:${e.subjectId}',
          );
          _timetableNotifIds.add(baseId + 2);
          scheduledCount++;
          await NotifDiag.log(
            'TTSCHED',
            'IMMEDIATE notif fired for $subName (class is starting NOW)',
          );
        }
      }
    }

    await NotifDiag.log(
      'TTSCHED',
      'scheduleTimetableNotifs DONE — $scheduledCount alarms registered',
      isError: scheduledCount == 0 && entries.isNotEmpty,
    );
  }

  // ── cancelTimetableAll — payload-aware sweep ──────────────────────────────
  //
  // Old approach: only cancelled IDs in memory Set + a fixed ID range.
  // Problem: fresh install has empty Set, orphaned IDs outside range survived.
  //
  // New approach:
  //   1. Cancel everything in memory Set (fast path)
  //   2. Full pending-queue sweep: cancel any remaining timetable payload
  //      regardless of ID, catching orphans from previous sessions.
  static Future<void> cancelTimetableAll() async {
    final idsCopy = List<int>.from(_timetableNotifIds);
    _timetableNotifIds.clear();
    for (final id in idsCopy) {
      try { await _p.cancel(id); } catch (_) {}
    }
    try {
      final pending = await _p.pendingNotificationRequests();
      for (final notif in pending) {
        final isTimetableRange = notif.id >= 900000 && notif.id <= 990000;
        final hasTimetablePayload =
            notif.payload != null && notif.payload!.startsWith('timetable:');
        if (isTimetableRange || hasTimetablePayload) {
          try { await _p.cancel(notif.id); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ── Reminder Notifications ────────────────────────────────────────────────
  static Future<void> scheduleReminder(ReminderModel r) async {
    if (r.id == null) return;
    await cancelReminder(r.id!);
    final when = r.dateTime;
    if (when == null || when.isBefore(DateTime.now())) return;

    await schedule(
      id: 980000 + r.id!,
      title: '🔔 Reminder',
      body: r.text,
      when: when,
      channelId: 'reminder_notifs',
      channelName: 'Reminders',
      channelDesc: 'Custom reminders',
      payload: 'reminder:${r.id}',
    );
  }

  static Future<void> rescheduleAllReminders(
      List<ReminderModel> reminders,
      ) async {
    for (final r in reminders) {
      if (!r.isDone) await scheduleReminder(r);
    }
  }

  // ── Urgent Task Reminders (every 30 min) ──────────────────────────────────
  static void startUrgentTaskReminder(int taskId, String title) {
    stopUrgentTaskReminder(taskId);
    show(
      id: 970000 + taskId,
      title: '⚡ Due soon: $title',
      body: 'Due in under 3 hours! Tap to mark as working on it.',
      channelId: 'urgent_tasks',
      channelName: 'Urgent Tasks',
      channelDesc: 'Tasks due within 3 hours',
      payload: 'urgent:$taskId',
      actions: [
        const AndroidNotificationAction(
          'ack_task',
          '✅ Working on it',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
    _urgentTimers[taskId] = Timer.periodic(const Duration(minutes: 30), (
        _,
        ) async {
      await show(
        id: 970000 + taskId,
        title: '⚡ Still pending: $title',
        body: 'Due very soon! Tap to acknowledge.',
        channelId: 'urgent_tasks',
        channelName: 'Urgent Tasks',
        channelDesc: 'Tasks due within 3 hours',
        payload: 'urgent:$taskId',
        actions: [
          const AndroidNotificationAction(
            'ack_task',
            '✅ Working on it',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
    });
  }

  static void stopUrgentTaskReminder(int taskId) {
    _urgentTimers[taskId]?.cancel();
    _urgentTimers.remove(taskId);
    _p.cancel(970000 + taskId).catchError((_) {});
  }

  static void stopAllUrgentReminders() {
    for (final id in _urgentTimers.keys.toList()) {
      stopUrgentTaskReminder(id);
    }
  }

  // ── Read My Day Notification ──────────────────────────────────────────────
  static Future<void> scheduleReadMyDayNotif({
    required List<TimetableEntry> allEntries,
    required String currentWeekType,
  }) async {
    await cancelSingle(995000);
    final now = DateTime.now();
    final todayDow = now.weekday;
    final weekNum = _weekNumber(now);
    final todayWeekType = weekNum.isOdd ? 'odd' : 'even';

    final todayEntries = allEntries.where((e) {
      if (e.dayOfWeek != todayDow) return false;
      return e.weekType == 'both' || e.weekType == todayWeekType;
    }).toList();
    if (todayEntries.isEmpty) return;

    DateTime? lastEnd;
    for (final e in todayEntries) {
      final p = e.endTime.split(':');
      if (p.length < 2) continue;
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(p[0]),
        int.parse(p[1]),
      );
      if (lastEnd == null || dt.isAfter(lastEnd)) lastEnd = dt;
    }
    if (lastEnd == null) return;
    final notifyAt = lastEnd.add(const Duration(minutes: 5));
    if (notifyAt.isBefore(now)) return;

    await schedule(
      id: 995000,
      title: '🎓 Day complete! Hear your summary?',
      body: 'Tap to listen to your daily briefing',
      when: notifyAt,
      channelId: 'read_my_day',
      channelName: 'Read My Day',
      channelDesc: 'End-of-day review',
      payload: 'read_my_day:choose',
      actions: [
        const AndroidNotificationAction(
          'read_en',
          '🔊 English',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'read_ar',
          '🔊 عربي',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
  }

  // ── Absence Warning ──────────────────────────────────────────────────────
  static Future<void> showAbsenceWarning({
    required int subjectId,
    required String subjectName,
    required int current,
    required int maxAbs,
    required String type,
  }) async {
    final remaining = maxAbs - current;
    if (remaining > 1) return;
    try {
      await _p.show(
        800000 +
            subjectId * 10 +
            (type == 'lecture' ? 1 : type == 'section' ? 2 : 3),
        remaining == 0 ? '🚫 Maximum Absences Reached!' : '⚠️ Absence Warning!',
        remaining == 0
            ? '$subjectName — Reached max $type absences!'
            : '$subjectName — Only 1 $type absence left!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'study_notifs',
            'Study Reminders',
            channelDescription: 'Task reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  // // ── NOVA: Schedule daily check-in notifications ───────────────────────────
  // static Future<void> scheduleNovaCheckIns(List<TimeOfDay> times) async {
  //   _ensureTimezone();
  //   for (int i = 1; i <= 3; i++) {
  //     try {
  //       await _p.cancel(860000 + i);
  //     } catch (_) {}
  //   }
  //   for (int i = 0; i < times.length && i < 3; i++) {
  //     final t = times[i];
  //     final now = DateTime.now();
  //     var next = DateTime(now.year, now.month, now.day, t.hour, t.minute);
  //     if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  //     try {
  //       await _p.zonedSchedule(
  //         860001 + i,
  //         '🧠 NOVA Briefing',
  //         'Your scheduled intelligence brief is ready. Tap to open.',
  //         tz.TZDateTime.from(next, tz.local),
  //         NotificationDetails(
  //           android: AndroidNotificationDetails(
  //             'nova_checkin',
  //             'NOVA Daily Check-ins',
  //             channelDescription: 'Scheduled NOVA briefing notifications',
  //             importance: Importance.high,
  //             priority: Priority.high,
  //           ),
  //           iOS: const DarwinNotificationDetails(
  //             presentAlert: true,
  //             presentSound: true,
  //           ),
  //         ),
  //         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  //         uiLocalNotificationDateInterpretation:
  //         UILocalNotificationDateInterpretation.absoluteTime,
  //         matchDateTimeComponents: DateTimeComponents.time,
  //         payload: 'nova_brief_checkin',
  //       );
  //     } catch (e) {
  //       NotifDiag.logSync(
  //         'NOVA',
  //         'scheduleNovaCheckIn[$i] error: $e',
  //         isError: true,
  //       );
  //     }
  //   }
  // }

  // ── NOVA: Mandatory attendance alert ─────────────────────────────────────
  static Future<void> showMandatoryAttendanceAlert({
    required String subjectName,
    required String time,
    required String room,
  }) async {
    try {
      NovaAudioService.playAsset(
        'sounds/alert_mandatory_attendance_is_required_tomorrow.mp3',
      );
      await _p.show(
        870000 + subjectName.hashCode.abs() % 9999,
        '⛔ NOVA — MANDATORY CLASS TOMORROW',
        '$subjectName at $time${room.isNotEmpty ? ', $room' : ''}. '
            'You have 1 absence left. Missing this bars you from the final.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'nova_attendance',
            'Attendance Guardian',
            channelDescription: 'Mandatory attendance alerts',
            importance: Importance.max,
            priority: Priority.high,
            ongoing: true,
            autoCancel: false,
            actions: [
              const AndroidNotificationAction(
                'ack_attend',
                "I'll be there",
                showsUserInterface: false,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        payload: 'mandatory_attend:$subjectName',
      );
    } catch (e) {
      NotifDiag.logSync(
        'NOVA',
        'showMandatoryAttendanceAlert error: $e',
        isError: true,
      );
    }
  }

  static Future<void> cancelMandatoryAlert(String subjectName) async {
    try {
      await _p.cancel(870000 + subjectName.hashCode.abs() % 9999);
    } catch (_) {}
  }

  // ── Cancel Helpers ────────────────────────────────────────────────────────
  static Future<void> cancelSingle(int id) async {
    try {
      await _p.cancel(id);
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    for (final o in [0, 100000, 200000, 300000]) {
      try {
        await _p.cancel(id + o);
      } catch (_) {}
    }
  }

  static Future<void> cancelExam(int id) async {
    for (final o in [0, 100000, 300000, 500000, 600000]) {
      try {
        await _p.cancel(id + o);
      } catch (_) {}
    }
  }

  static Future<void> cancelReminder(int rid) async {
    try { await _p.cancel(980000 + rid); } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  /// Returns the next DateTime where weekday == [targetWeekday] at [h]:[m],
  /// guaranteed to be in the future (never in the past).
  static DateTime _nextWeekdayAt(
      DateTime from,
      int targetWeekday,
      int h,
      int m,
      ) {
    // Build today's occurrence of that weekday+time
    int daysUntil = (targetWeekday - from.weekday) % 7;
    var candidate = DateTime(
      from.year,
      from.month,
      from.day + daysUntil,
      h,
      m,
    );

    // If the candidate is in the past (or within the 2-min grace), push forward
    if (candidate.isBefore(from.subtract(const Duration(minutes: 2)))) {
      candidate = candidate.add(const Duration(days: 7));
    }

    return candidate;
  }

  /// Returns true if there is a midterm or final exam on the same calendar
  /// day as [date].
  static bool _hasExamOnDate(List<TaskModel> tasks, DateTime date) {
    return tasks.any((t) {
      if (!t.isExam || (t.type != 'midterm' && t.type != 'final')) {
        return false;
      }
      if (t.dueDate == null) return false;
      return t.dueDate!.year == date.year &&
          t.dueDate!.month == date.month &&
          t.dueDate!.day == date.day;
    });
  }

  /// Schedules a weekly-repeating alarm using matchDateTimeComponents.
  /// One zonedSchedule call, fires every 7 days on the same day+time.
  static Future<void> _scheduleWeeklyRepeating({
    required int id,
    required String title,
    required String body,
    required DateTime firstOccurrence,
    String? payload,
  }) async {
    // No longer uses matchDateTimeComponents — alarmClock mode doesn't support it.
    // Schedules a single one-shot alarm. The midnight WorkManager job and
    // _rescheduleNotificationsOnStart() handle rescheduling after each fires.
    await schedule(
      id: id,
      title: title,
      body: body,
      when: firstOccurrence,
      channelId: 'timetable_notifs',
      channelName: 'Class Reminders',
      channelDesc: 'Timetable',
      payload: payload ?? '$id',
    );
    NotifDiag.logSync(
      'WEEKLY',
      'Registered one-shot (alarmClock) id=$id | "$title" | '
          'fires=${firstOccurrence.toIso8601String().split('T')[0]}',
    );
  }


  /// ISO weekday name abbreviation (1=Mon ... 7=Sun)
  static String _dowName(int dow) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dow - 1];

  /// ISO week number calculation (matches the app_bloc.dart implementation)
  static int _weekNumber(DateTime date) {
    final doy = int.parse(intl.DateFormat('D').format(date));
    return ((doy - date.weekday + 10) / 7).floor();
  }
}