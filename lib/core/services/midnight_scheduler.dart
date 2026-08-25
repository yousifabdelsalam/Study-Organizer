import 'package:flutter/material.dart';
import 'package:study_organizer/features/timetable/data/models/timetable.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:study_organizer/core/database/database_helper.dart';
import 'package:study_organizer/core/services/notifications_service.dart';

const _kMidnightTask = 'midnight_reschedule';

class _MinimalEntry {
  final int dayOfWeek, subjectId;
  final String startTime, endTime, type, room, building, weekType;
  _MinimalEntry({
    required this.dayOfWeek, required this.subjectId,
    required this.startTime, required this.endTime,
    required this.type, required this.room,
    required this.building, required this.weekType,
  });

  TimetableEntry toTimetableEntry() => TimetableEntry(
    dayOfWeek: dayOfWeek, subjectId: subjectId,
    startTime: startTime, endTime: endTime,
    type: type, room: room, building: building, weekType: weekType,
  );
}

class MidnightScheduler {
  static Future<bool> runMidnightTask() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));

      final db = DatabaseHelper.instance;

      // Load timetable entries
      final timetableRows = await db.database
          .then((d) => d.query('timetable'));
      // Load subjects for name map
      final subjectRows = await db.database
          .then((d) => d.query('subjects'));
      // Load tasks
      final taskRows = await db.database
          .then((d) => d.query('tasks'));

      // Build subject name map
      final subjectNames = <int, String>{};
      for (final row in subjectRows) {
        final id = row['id'] as int?;
        final name = row['name'] as String?;
        if (id != null && name != null) subjectNames[id] = name;
      }

      // Parse timetable entries (minimal fields needed for scheduling)
      final entries = timetableRows.map((row) {
        return _MinimalEntry(
          dayOfWeek: (row['dayOfWeek'] as int?) ?? 0,
          startTime: (row['startTime'] as String?) ?? '',
          endTime: (row['endTime'] as String?) ?? '',
          subjectId: (row['subjectId'] as int?) ?? 0,
          type: (row['type'] as String?) ?? 'lecture',
          room: (row['room'] as String?) ?? '',
          building: (row['building'] as String?) ?? '',
          weekType: (row['weekType'] as String?) ?? 'both',
        );
      }).toList();

      // Determine current week type
      final now = DateTime.now();
      final doy = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
      final weekNum = ((doy - now.weekday + 10) / 7).floor();
      final weekType = weekNum.isOdd ? 'odd' : 'even';

      await NotifService.init();
      await NotifService.scheduleTimetableNotifs(
        entries: entries.map((e) => e.toTimetableEntry()).toList(),
        subjectNames: subjectNames,
        currentWeekType: weekType,
        tasks: [], // tasks handled separately — not critical for midnight run
      );

      debugPrint('✅ [WorkManager] Midnight reschedule complete');
    } catch (e) {
      debugPrint('❌ [WorkManager] Midnight reschedule failed: $e');
    }

    // Schedule the next midnight run
    scheduleNextMidnight();

    return true;
  }

  /// Call once on app start (in main.dart, after NotifService.init())
  static Future<void> init() async {
    scheduleNextMidnight();
  }

  /// Schedules a one-off WorkManager task to fire at the next 00:00:30
  /// (30 seconds past midnight so the day has cleanly rolled over).
  static void scheduleNextMidnight() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 30);
    final delay = nextMidnight.difference(now);

    Workmanager().registerOneOffTask(
      _kMidnightTask,          // unique name — overwrites any existing one
      _kMidnightTask,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
      ),
    );

    debugPrint(
      '⏰ [WorkManager] Next midnight reschedule in ${delay.inMinutes} min',
    );
  }
}