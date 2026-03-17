import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:intl/intl.dart' as intl;
import '../models/timetable.dart';
import '../models/reminder.dart';
import '../models/topic.dart';
import '../models/subject.dart';
import '../models/task.dart';
import 'nova_audio_service.dart';

@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse details) {
  debugPrint('[BG] Notif: ${details.payload} action:${details.actionId}');
}

class NotifService {
  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();
  static void Function(String payload, String? actionId)? onActionReceived;
  static Timer? _deepStudyTimer;
  static int _pingCount = 0;
  static final Map<int, Timer> _urgentTimers = {};
  static bool _tzInitialized = false;

  static Future<void> init() async {
    _ensureTimezone();
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _p
        .resolvePlatformSpecificImplementation<
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
    debugPrint('✅ NotifService ready');
  }

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

  static void _ensureTimezone() {
    if (_tzInitialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
      _tzInitialized = true;
    } catch (_) {}
  }

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
    if (when.isBefore(DateTime.now())) return;
    try {
      await _p.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload ?? '$id',
      );
    } catch (e) {
      debugPrint('❌ schedule error: $e');
    }
  }

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
      debugPrint('❌ show error: $e');
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

    final dayBefore = due.subtract(const Duration(days: 1));
    await schedule(
      id: id + 200000,
      title: '📋 Due tomorrow',
      body: '$title — Tomorrow at ${fmt.format(due)}',
      when: DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 21, 0),
    );
    await schedule(
      id: id,
      title: '⏰ Due in 24 hours',
      body: '$title — ${fmtD.format(due)} at ${fmt.format(due)}',
      when: due.subtract(const Duration(hours: 24)),
    );
    await schedule(
      id: id + 100000,
      title: '🔥 Due in 3 hours!',
      body: '$title — Today at ${fmt.format(due)}',
      when: due.subtract(const Duration(hours: 3)),
    );

    if (diff.inHours < 3 && !diff.isNegative) {
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

  // Add this field at the top of the class (with the other static fields)
  static final Set<int> _timetableNotifIds = {};

  static Future<void> scheduleDailyMorningNotifs(
    List<StudyTopic> topics,
    List<Subject> subjects,
  ) async {
    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final targetDate = DateTime(date.year, date.month, date.day);

      final dueTopics = topics.where((t) {
        final r = t.nextReview;
        if (r == null) return false;
        final targetDateWithoutTime = DateTime(r.year, r.month, r.day);
        return targetDateWithoutTime.isAtSameMomentAs(targetDate);
      }).toList();

      if (dueTopics.isNotEmpty) {
        final when = DateTime(date.year, date.month, date.day, 8, 0); // 8:00 AM
        if (when.isBefore(DateTime.now())) continue;

        final body =
            'You have ${dueTopics.length} topics due for Spaced Repetition today.';
        await schedule(
          id: 1000000 + i,
          title: '🧠 Study Time!',
          body: body,
          when: when,
          channelId: 'study_notifs',
          channelName: 'Study Reminders',
        );
      } else {
        await cancelSingle(1000000 + i);
      }
    }
  }

  // ── FIXED: Timetable Notifications ──────────────────────────────────────
  // Uses stable IDs based on subjectId + startTime hash (not loop index)
  // so notifications are never silently overwritten when entries reorder.
  static Future<void> scheduleTimetableNotifs({
    required List<TimetableEntry> entries,
    required Map<int, String> subjectNames,
    required String currentWeekType,
    required List<TaskModel> tasks,
  }) async {
    await cancelTimetableAll();
    final now = DateTime.now();
    int scheduledCount = 0;
    const int maxDaysAhead = 2; // Limit to 2 days to stay under Android 50-notif limit

    for (int dayOffset = 0; dayOffset <= maxDaysAhead; dayOffset++) {
      final targetDate = now.add(Duration(days: dayOffset));
      final targetDow = targetDate.weekday;
      final weekNum = _weekNumber(targetDate);
      final targetWeekType = weekNum.isOdd ? 'odd' : 'even';

      // Check if there is a midterm or final exam on this day
      final hasExamToday = tasks.any((t) {
        if (!t.isExam || (t.type != 'midterm' && t.type != 'final'))
          return false;
        if (t.dueDate == null) return false;
        return t.dueDate!.year == targetDate.year &&
            t.dueDate!.month == targetDate.month &&
            t.dueDate!.day == targetDate.day;
      });

      if (hasExamToday) {
        debugPrint(
          '🚫 Skipping class notifs on ${targetDate.toIso8601String().split('T')[0]} due to Midterm/Final Exam',
        );
        continue;
      }

      for (final e in entries) {
        if (e.dayOfWeek != targetDow) continue;
        if (e.weekType != 'both' && e.weekType != targetWeekType) continue;

        final parts = e.startTime.split(':');
        if (parts.length < 2) continue;
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;

        final classStart = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          h,
          m,
        );

        // Skip if class started more than 2 minutes ago (grace window)
        if (classStart.isBefore(now.subtract(const Duration(minutes: 2))))
          continue;

        final subName = subjectNames[e.subjectId] ?? 'Class';
        final emoji = e.type == 'lab'
            ? '🧪'
            : e.type == 'section'
            ? '🔧'
            : '📚';
        final loc = [
          if (e.room.isNotEmpty) 'Room ${e.room}',
          if (e.building.isNotEmpty) e.building,
        ].join(' · ');

        // Stable ID: uniquely bound to the specific minute of the week (0 to 10079)
        final minuteOfWeek = (targetDow - 1) * 1440 + (h * 60) + m;
        final baseId = 900000 + (minuteOfWeek * 3);

        // AT class start time
        await schedule(
          id: baseId + 1,
          title: '$emoji $subName — Starting NOW!',
          body:
              '${e.type[0].toUpperCase()}${e.type.substring(1)}${loc.isNotEmpty ? ' — $loc' : ''}',
          when: classStart,
          channelId: 'timetable_notifs',
          channelName: 'Class Reminders',
          channelDesc: 'Timetable',
          payload: 'timetable:${e.subjectId}',
        );
        _timetableNotifIds.add(baseId + 1);
        scheduledCount++;
        debugPrint(
          '✅ Scheduled START notif for $subName at $classStart (id:${baseId + 1})',
        );

        // If class starts within 2 minutes, fire an IMMEDIATE notification
        final untilStart = classStart.difference(now).inMinutes;
        if (untilStart <= 2 &&
            classStart.isAfter(now.subtract(const Duration(minutes: 2)))) {
          await show(
            id: baseId + 2,
            title: '$emoji $subName — Starting NOW!',
            body:
                '${e.type[0].toUpperCase()}${e.type.substring(1)}${loc.isNotEmpty ? ' — $loc' : ''}',
            channelId: 'timetable_notifs',
            channelName: 'Class Reminders',
            channelDesc: 'Timetable',
          );
          _timetableNotifIds.add(baseId + 2);
          scheduledCount++;
          debugPrint(
            '🔔 IMMEDIATE notif for $subName (class is NOW, id:${baseId + 2})',
          );
        }
      }
    }

    debugPrint('✅ Timetable notifs: Scheduled $scheduledCount notifications');
  }

  // ═══ FIXED: Efficient cancel and comprehensive leak cleanup ═══
  static Future<void> cancelTimetableAll() async {
    // 1) Cancel IDs we tracked in memory
    final idsCopy = List<int>.from(_timetableNotifIds);
    _timetableNotifIds.clear();

    for (final id in idsCopy) {
      try {
        await _p.cancel(id);
      } catch (_) {}
    }

    // 2) Cancel any orphaned timetable notifs from previous app sessions
    // including cleanly sweeping up any older leaked IDs from the previous hash bug
    // that reached as high as 989999 and jammed Android's 50-limit queue.
    try {
      final pending = await _p.pendingNotificationRequests();
      for (final p in pending) {
        // Safe range just for new Timetables (and old ones up to 960000)
        if (p.id >= 900000 && p.id <= 960000) {
          try {
            await _p.cancel(p.id);
          } catch (_) {}
        }
        // Careful cleanup of older leaked Timetable IDs without killing active Tasks/Urgent/Reminders
        else if (p.id > 960000 && p.id <= 990000) {
          if (p.payload != null && p.payload!.startsWith('timetable:')) {
            try {
              await _p.cancel(p.id);
            } catch (_) {}
          }
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

    final base = 980000 + r.id!;
    await schedule(
      id: base,
      title: '🔔 Reminder',
      body: r.text,
      when: when,
      channelId: 'reminder_notifs',
      channelName: 'Reminders',
      channelDesc: 'Custom reminders',
      payload: 'reminder:${r.id}',
    );
    final early = when.subtract(const Duration(minutes: 15));
    if (early.isAfter(DateTime.now())) {
      await schedule(
        id: base + 1,
        title: '⏰ Reminder in 15 min',
        body: r.text,
        when: early,
        channelId: 'reminder_notifs',
        channelName: 'Reminders',
        channelDesc: 'Custom reminders',
        payload: 'reminder:${r.id}',
      );
    }
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
          "✅ Working on it",
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
            "✅ Working on it",
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
    for (final id in _urgentTimers.keys.toList()) stopUrgentTaskReminder(id);
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

  // ── Deep Study Pings ──────────────────────────────────────────────────────
  // static void startDeepStudyPings() {
  //   stopDeepStudyPings();
  //   _pingCount = 0;
  //   _deepStudyTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
  //     _pingCount++;
  //     final messages = [
  //       '📵 Put the phone down! Focus on your books.',
  //       '🛡️ Your deep study session is running — stay focused!',
  //       '📚 Engineers don\'t quit. Get back to studying!',
  //       '⚡ Your GPA depends on this moment. Focus!',
  //       '🔥 Keep grinding! You\'re doing great.',
  //     ];
  //     await show(
  //       id: 990000 + (_pingCount % 100),
  //       title: '🛡️ Deep Study Mode',
  //       body: messages[_pingCount % messages.length],
  //       channelId: 'deep_study',
  //       channelName: 'Deep Study',
  //       channelDesc: 'Study pings',
  //     );
  //   });
  // }

  // static void stopDeepStudyPings() {
  //   _deepStudyTimer?.cancel();
  //   _deepStudyTimer = null;
  //   _pingCount = 0;
  //   for (int i = 0; i < 100; i++) {
  //     _p.cancel(990000 + i).catchError((_) {});
  //   }
  // }

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
            (type == 'lecture'
                ? 1
                : type == 'section'
                ? 2
                : 3),
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
    try {
      await _p.cancel(980000 + rid);
    } catch (_) {}
    try {
      await _p.cancel(980000 + rid + 1);
    } catch (_) {}
  }

  // ── NOVA: Schedule daily check-in notifications ─────────────────────────
  // [times] is a list of TimeOfDay (up to 3). Each becomes a daily notif.
  static Future<void> scheduleNovaCheckIns(List<TimeOfDay> times) async {
    _ensureTimezone();
    // Cancel previous check-ins (IDs 860001–860003)
    for (int i = 1; i <= 3; i++) {
      try {
        await _p.cancel(860000 + i);
      } catch (_) {}
    }
    for (int i = 0; i < times.length && i < 3; i++) {
      final t = times[i];
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      try {
        await _p.zonedSchedule(
          860001 + i,
          '🧠 NOVA Briefing',
          'Your scheduled intelligence brief is ready. Tap to open.',
          tz.TZDateTime.from(next, tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              'nova_checkin',
              'NOVA Daily Check-ins',
              channelDescription: 'Scheduled NOVA briefing notifications',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // daily repeat
          payload: 'nova_brief_checkin',
        );
      } catch (e) {
        debugPrint('scheduleNovaCheckIn error: $e');
      }
    }
  }

  // ── NOVA: Mandatory attendance alert (night-before, ongoing = can't swipe) ─
  static Future<void> showMandatoryAttendanceAlert({
    required String subjectName,
    required String time,
    required String room,
  }) async {
    try {
      // 🔊 Play audio alert
      NovaAudioService.playAsset(
        'sounds/alert_mandatory_attendance_is_required_tomorrow.mp3',
      );
      await _p.show(
        870000 + subjectName.hashCode.abs() % 9999,
        '⛔ NOVA — MANDATORY CLASS TOMORROW',
        '$subjectName at $time${room.isNotEmpty ? ', $room' : ''}. You have 1 absence left. Missing this bars you from the final.',
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
      debugPrint('showMandatoryAttendanceAlert error: $e');
    }
  }

  /// Cancel mandatory attendance alert for a subject.
  static Future<void> cancelMandatoryAlert(String subjectName) async {
    try {
      await _p.cancel(870000 + subjectName.hashCode.abs() % 9999);
    } catch (_) {}
  }

  static int _weekNumber(DateTime date) {
    final doy = int.parse(intl.DateFormat('D').format(date));
    return ((doy - date.weekday + 10) / 7).floor();
  }
}
