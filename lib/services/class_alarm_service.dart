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

// ════════════════════════════════════════════════════════════════════════════
// TASK HANDLER — flutter_foreground_task v9.x exact signatures
// ════════════════════════════════════════════════════════════════════════════
class ClassAlarmHandler extends TaskHandler {
  Timer? _classTimer;

  // v9.x: second param is TaskStarter (not SendPort)
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await NotifService.init();
    debugPrint('[ClassAlarm] Started — starter: ${starter.name}');
    await _reschedule();
  }

  // v9.x: void return, only DateTime param — no async, no SendPort
  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('[ClassAlarm] Heartbeat');
    _reschedule();
  }

  // v9.x: second param is bool isTimeout (not SendPort)
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _classTimer?.cancel();
    debugPrint('[ClassAlarm] Destroyed (isTimeout: $isTimeout)');
  }

  Future<void> _reschedule() async {
    _classTimer?.cancel();
    final now = DateTime.now();
    final classes = await _getTodayClasses(now);

    if (classes.isEmpty) {
      debugPrint('[ClassAlarm] No more classes today');
      return;
    }

    classes.sort((a, b) => a.startTime.compareTo(b.startTime));

    _ClassEntry? next;
    for (final c in classes) {
      if (c.startTime.isAfter(now.subtract(const Duration(seconds: 5)))) {
        next = c;
        break;
      }
    }

    if (next == null) {
      debugPrint('[ClassAlarm] All classes passed for today');
      return;
    }

    final delay = next.startTime.difference(now);
    if (delay.isNegative) return;

    debugPrint(
        '[ClassAlarm] Next: "${next.title}" in ${delay.inMinutes}m ${delay.inSeconds % 60}s');

    final firing = next;
    _classTimer = Timer(delay, () async {
      debugPrint('[ClassAlarm] FIRING show() for "${firing.title}"');
      await NotifService.show(
        id: firing.notifId,
        title: firing.title,
        body: firing.body,
        channelId: 'timetable_notifs',
        channelName: 'Class Reminders',
        channelDesc: 'Timetable',
        payload: firing.payload,
      );
      await _reschedule();
    });
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
        if (classDateTime
            .isBefore(now.subtract(const Duration(minutes: 1)))) {
          continue;
        }

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

      debugPrint(
          '[ClassAlarm] ${result.length} classes today (weekday=${now.weekday}, weekType=$weekType)');
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

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ════════════════════════════════════════════════════════════════════════════
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
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // v9.x: int milliseconds — 900000 = 15 minutes
        eventAction: ForegroundTaskEventAction.repeat(900000),
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