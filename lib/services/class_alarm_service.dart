import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart' as intl;
import 'notifications.dart';
import 'database.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ClassAlarmHandler());
}

class ClassAlarmHandler extends TaskHandler {

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    NotifService.initForService();
    debugPrint('[ClassAlarm] Started — starter: ${starter.name}');
    await _checkAndFire();
    // Fallback: fire any notifications that the OS killed
    await NotifService.checkAndFireMissed();
  }

  // Fires every 1 minute — this IS the clock, no Timers needed
  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkAndFire();
    // Fallback: fire any notifications that the OS killed
    NotifService.checkAndFireMissed();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ClassAlarm] Destroyed (isTimeout: $isTimeout)');
  }

  // ── Core logic: runs every 60 seconds ─────────────────────────────────────
  // If a class starts within the next 60 seconds → fire show() right now.
  // No state, no memory, no Timers. Each call is fully independent.
  Future<void> _checkAndFire() async {
    final now = DateTime.now();
    final classes = await _getTodayClasses(now);

    if (classes.isEmpty) return;

    for (final c in classes) {
      final secondsUntil = c.startTime.difference(now).inSeconds;

      // Fire if class starts within next 60 seconds (heartbeat window)
      // or started within the last 30 seconds (late wakeup tolerance)
      if (secondsUntil >= -30 && secondsUntil <= 60) {
        debugPrint(
          '[ClassAlarm] FIRING show() for "${c.title}" '
              '(${secondsUntil}s from now)',
        );
        await NotifService.show(
          id: c.notifId,
          title: c.title,
          body: c.body,
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

        result.add(_ClassEntry(
          startTime: classDateTime,
          title: '$emoji $subName — Starting NOW!',
          body: '${type[0].toUpperCase()}${type.substring(1)}'
              '${loc.isNotEmpty ? ' — $loc' : ''}',
          payload: 'timetable:$subjectId',
          notifId: 950000 + dayOfWeek * 10000 + h * 100 + m + subjectId,
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
  final int notifId;
  const _ClassEntry({
    required this.startTime,
    required this.title,
    required this.body,
    required this.payload,
    required this.notifId,
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
        // 60000ms = 1 minute — this is the clock tick
        eventAction: ForegroundTaskEventAction.repeat(60000),
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