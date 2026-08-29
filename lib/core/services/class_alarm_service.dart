import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart' as intl;
import 'package:study_organizer/core/services/notifications_service.dart';
import 'package:study_organizer/core/database/database_helper.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ClassAlarmHandler());
}

class ClassAlarmHandler extends TaskHandler {
  static final Set<String> _firedToday = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await NotifService.initForService();
    debugPrint('[ClassAlarm] Started — starter: ${starter.name}');
    await _checkAndFire();
    await NotifService.checkAndFireMissed();
  }

  // Fires every 15 seconds — this IS the clock, no Timers needed
  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkAndFire();
    // Run the heavier fallback check every ~60s (every 4th tick)
    _tickCount++;
    if (_tickCount % 4 == 0) {
      NotifService.checkAndFireMissed();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ClassAlarm] Destroyed (isTimeout: $isTimeout)');
  }

  // ── Core logic: runs every 15 seconds ─────────────────────────────────────
  static int _tickCount = 0;

  Future<void> _checkAndFire() async {
    final now = DateTime.now();
    final classes = await _getTodayClasses(now);

    if (classes.isEmpty) return;

    for (final c in classes) {
      final secondsUntil = c.startTime.difference(now).inSeconds;

      // Fire if class starts within next 20 seconds (just over 1 heartbeat)
      // or started within the last 5 minutes (Doze-proof safety net).
      // The duplicate guard (_firedToday) prevents double notifications,
      // so the wide late window costs nothing — it only catches misses.
      if (secondsUntil >= -300 && secondsUntil <= 20) {
        final key = '${now.year}-${now.month}-${now.day}-${c.notifId}';
        if (_firedToday.contains(key)) continue; // STRICT DUPLICATE GUARD
        _firedToday.add(key);

        final lateSeconds = -secondsUntil; // positive = how late we are

        debugPrint(
          '[ClassAlarm] FIRING show() for "${c.title}" '
              '(${secondsUntil}s from now)',
        );
        
        // ── PREEMPT NATIVE OS ALARM ──
        // Cancel the scheduled alarm so we don't get a double notification.
        // Uses the timetable scheduled ID range (110,000+).
        NotifService.cancelSingle(c.nativeScheduledId);
        
        // Build body — add late indicator if more than 60s late
        final body = lateSeconds > 60
            ? '⏰ ${(lateSeconds / 60).ceil()}m late — ${c.body}'
            : c.body;
        
        // FIX: Use foreground ID range (200,000+) — guaranteed no collision
        // with the scheduled alarm IDs (110,000+).
        await NotifService.show(
          id: c.notifId,
          title: c.title,
          body: body,
          channelId: 'timetable_notifs',
          channelName: 'Class Reminders',
          channelDesc: 'Timetable',
          payload: c.payload,
        );
      }
    }
  }

  Future<List<_ClassEntry>> _getTodayClasses(DateTime now) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('timetable');
      final subjectRows = await db.query('subjects');

      final subjectNames = <int, String>{};
      for (final row in subjectRows) {
        final id = row['id'] as int?;
        final name = row['name'] as String?;
        if (id != null && name != null) subjectNames[id] = name;
      }

      final doy = int.parse(intl.DateFormat('D').format(now));
      final weekNum = ((doy - now.weekday + 10) / 7).floor();
      final weekType = weekNum.isOdd ? 'odd' : 'even';

      final result = <_ClassEntry>[];

      for (final row in rows) {
        final dayOfWeek = (row['dayOfWeek'] as int?) ?? 0;
        final startTime = (row['startTime'] as String?) ?? '';
        final wType = (row['weekType'] as String?) ?? 'both';
        final subjectId = (row['subjectId'] as int?) ?? 0;
        final type = (row['type'] as String?) ?? 'lecture';
        final room = (row['room'] as String?) ?? '';
        final building = (row['building'] as String?) ?? '';

        if (dayOfWeek != now.weekday) continue;
        if (wType != 'both' && wType != weekType) continue;

        final parts = startTime.split(':');
        if (parts.length < 2) continue;
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;

        final classDateTime = DateTime(now.year, now.month, now.day, h, m);

        final subName = subjectNames[subjectId] ?? 'Class';
        final emoji =
        type == 'lab' ? '🧪' : type == 'section' ? '🔧' : '📚';
        final loc = [
          if (room.isNotEmpty) 'Room $room',
          if (building.isNotEmpty) building,
        ].join(' · ');

        // Timetable scheduled ID: same formula as scheduleTimetableNotifs()
        // so cancelSingle() targets the correct alarm.
        final minuteOfWeek = (dayOfWeek - 1) * 1440 + (h * 60) + m;
        final wOff = wType == 'both' ? 0 : wType == 'odd' ? 1 : 2;
        final scheduledId = 110000 + minuteOfWeek * 3 + wOff; // _IdRange.timetable base

        // FIX: Foreground alarm uses _IdRange.foreground (200,000+)
        // — no collision with scheduled timetable alarms (110,000+).
        final foregroundId = 200000 + dayOfWeek * 10000 + h * 100 + m + (subjectId % 50);

        result.add(_ClassEntry(
          startTime: classDateTime,
          title: '$emoji $subName — Starting NOW!',
          body: '${type[0].toUpperCase()}${type.substring(1)}'
              '${loc.isNotEmpty ? ' — $loc' : ''}',
          payload: 'timetable:$subjectId',
          notifId: foregroundId,
          nativeScheduledId: scheduledId,
        ));
      }

      return result;
    } catch (e) {
      debugPrint('[ClassAlarm] DB read failed: $e');
      return [];
    }
  }
}

class _ClassEntry {
  final DateTime startTime;
  final String title, body, payload;
  final int notifId;           // Foreground service notification ID (200,000+)
  final int nativeScheduledId; // Scheduled alarm ID to cancel (110,000+)
  const _ClassEntry({
    required this.startTime,
    required this.title,
    required this.body,
    required this.payload,
    required this.notifId,
    required this.nativeScheduledId,
  });
}

class ClassAlarmService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'class_alarm_service',
        channelName: 'Schedule Guardian',
        channelDescription: 'Keeps class notifications running',
        channelImportance: NotificationChannelImportance.NONE,
        priority: NotificationPriority.MIN,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 15000ms = 15 seconds — tight heartbeat for accurate class alerts.
        // The foreground service is the PRIMARY delivery mechanism; Android's
        // zonedSchedule is the backup. 15s ticks guarantee ≤15s delivery jitter.
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> start() async {
    await init();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Schedule Guardian',
        notificationText: 'Watching for your next class',
        callback: startCallback,
      );
    }
    debugPrint('[ClassAlarmService] Started');
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
