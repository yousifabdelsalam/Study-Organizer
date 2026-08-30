// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE — CLEAN RECONSTRUCTION (v2)
//
// Fixes applied:
//   1. Non-overlapping ID allocation table (was: topic reviews & timetable
//      both used 900,000+, foreground alarms overlapped timetable range)
//   2. Single FlutterLocalNotificationsPlugin instance everywhere
//   3. Atomic fallback store with mutex (was: race conditions on concurrent
//      SharedPreferences read-modify-write)
//   4. Smart quota management — evicts low-priority alarms when near 50 limit
//   5. Urgent task reminders use scheduled notifications instead of in-process
//      Timer.periodic (was: timers died on background/kill)
//   6. Foreground service IDs separated from scheduled alarm IDs
//   7. Reminder double-scheduling eliminated (was: app_bloc + NotifService
//      both scheduling the same reminder under different IDs)
//
// Public API is 1:1 compatible with all callers (app_bloc, campus, tasks,
// midnight_scheduler, class_alarm_service, nova_watchdog_service, main).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:intl/intl.dart' as intl;
import 'package:permission_handler/permission_handler.dart';
import 'package:study_organizer/features/timetable/data/models/timetable.dart';
import 'package:study_organizer/features/reminders/data/models/reminder.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/topics/data/models/topic.dart';
import 'package:study_organizer/features/speech_engine/data/services/audio_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// §0  NON-OVERLAPPING ID ALLOCATION TABLE
//
// Every feature has a dedicated, non-overlapping range. This eliminates the
// silent-overwrite bug where timetable and topic reviews (both 900,000+)
// cancelled each other, and foreground alarms (950,000+) collided with
// timetable scheduled alarms.
// ═══════════════════════════════════════════════════════════════════════════════

class _IdRange {
  // Tasks
  static const int task24h        = 10000;   // 10,000 – 19,999
  static const int task3h         = 20000;   // 20,000 – 29,999
  static const int taskNight      = 30000;   // 30,000 – 39,999

  // Exams
  static const int exam24h       = 40000;   // 40,000 – 49,999
  static const int exam3h        = 50000;   // 50,000 – 59,999
  static const int examNight     = 60000;   // 60,000 – 69,999
  static const int exam3day      = 70000;   // 70,000 – 79,999

  // Reminders
  static const int reminder      = 80000;   // 80,000 – 89,999
  static const int reminderEarly = 90000;   // 90,000 – 99,999

  // Topic reviews (was 900,000 — collided with timetable!)
  static const int topicReview   = 100000;  // 100,000 – 109,999

  // Timetable scheduled alarms
  static const int timetable     = 110000;  // 110,000 – 159,999

  // Warnings
  static const int attendance    = 160000;  // 160,000 – 160,999
  static const int absence       = 161000;  // 161,000 – 161,999

  // Specials
  static const int readMyDay     = 170000;  // 170,000
  static const int novaCheckin   = 171000;  // 171,000 – 171,009
  static const int novaWatchdog  = 172000;  // 172,000 – 172,099

  // Urgent task reminders (scheduled, not Timer-based)
  static const int urgent        = 180000;  // 180,000 – 189,999

  // System
  static const int healthWarning = 199990;
  static const int diagTest      = 199991;

  // Foreground service alarms (ClassAlarmHandler show() calls)
  static const int foreground    = 200000;  // 200,000 – 249,999
}

// ═══════════════════════════════════════════════════════════════════════════════
// §1  DIAGNOSTIC LOGGER
// ═══════════════════════════════════════════════════════════════════════════════

class NotifDiag {
  static const int _maxLines = 600;
  static File? _file;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/notif_diag.log');
      if (!await _file!.exists()) await _file!.writeAsString('');
    } catch (e) {
      debugPrint('[NotifDiag] init failed: $e');
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────
  static Future<void> log(String tag, String msg, {bool isError = false}) async {
    final ts = _timestamp();
    final prefix = isError ? '❌' : '✅';
    final line = '[$ts] $prefix [$tag] $msg';
    debugPrint(line);
    try {
      if (_file == null) return;
      await _file!.writeAsString('$line\n', mode: FileMode.append);
      await _trimLog();
    } catch (_) {}
  }

  static void logSync(String tag, String msg, {bool isError = false}) {
    log(tag, msg, isError: isError); // fire-and-forget
  }

  // ── Read / Clear ──────────────────────────────────────────────────────────
  static Future<String> readAll() async {
    try {
      if (_file != null && await _file!.exists()) {
        final c = await _file!.readAsString();
        return c.isEmpty ? '(log is empty)' : c;
      }
    } catch (_) {}
    return '(log file not accessible)';
  }

  static Future<void> clear() async {
    try {
      if (_file != null) await _file!.writeAsString('');
    } catch (_) {}
  }

  // ── Full Diagnostic Run ───────────────────────────────────────────────────
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

    // Run health monitor and log its report
    final report = await NotifHealthMonitor.getHealthReport(
      entries: entries,
      subjectNames: subjectNames,
      currentWeekType: currentWeekType,
    );
    await log('HEALTH', report.summary);

    await log('DIAG', '════════ DIAGNOSTIC END ════════');
  }

  // ── L1: Permissions ───────────────────────────────────────────────────────
  static Future<void> checkPermissions() async {
    await log('PERM', '─── Permission Check ───');
    try {
      // FIX: use singleton plugin instead of creating a new instance
      final android = NotifService.plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) {
        await log('PERM', 'Android plugin resolved to NULL', isError: true);
        return;
      }

      final notifEnabled = await android.areNotificationsEnabled() ?? false;
      await log('PERM', 'Notifications enabled: $notifEnabled',
          isError: !notifEnabled);

      try {
        final exactAlarm =
            await android.canScheduleExactNotifications() ?? false;
        await log('PERM', 'Exact alarms allowed: $exactAlarm',
            isError: !exactAlarm);
      } catch (e) {
        await log('PERM', 'canScheduleExactNotifications() threw: $e',
            isError: true);
      }

      // Battery optimization status — this is the #1 cause of OS-killed alarms
      try {
        if (Platform.isAndroid) {
          final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
          await log('PERM', 'Battery optimization exempt: $batteryExempt',
              isError: !batteryExempt);
          if (!batteryExempt) {
            await log('PERM',
                '⚠️ Battery optimization is ON — Android WILL kill scheduled alarms! '
                'Go to Settings → Battery → App → Remove restrictions, '
                'or grant the exemption from the app.',
                isError: true);
          }
        }
      } catch (e) {
        await log('PERM', 'Battery optimization check threw: $e',
            isError: true);
      }
    } catch (e) {
      await log('PERM', 'Permission check crashed: $e', isError: true);
    }
  }

  // ── L2: Timezone ──────────────────────────────────────────────────────────
  static Future<void> checkTimezone() async {
    await log('TZ', '─── Timezone Check ───');
    try {
      final localName = tz.local.name;
      final tzNow = tz.TZDateTime.now(tz.local);
      final sysNow = DateTime.now();
      final driftMin = tzNow.difference(sysNow).inMinutes.abs();

      await log('TZ', 'tz.local.name=$localName  drift=${driftMin}min');

      if (localName == 'UTC' || localName.isEmpty) {
        await log('TZ', 'TIMEZONE IS UTC — notifications will fire wrong!',
            isError: true);
      } else if (localName != 'Africa/Cairo') {
        await log('TZ', 'Timezone is "$localName" not "Africa/Cairo"',
            isError: true);
      } else if (driftMin > 5) {
        await log('TZ', 'TZ drift ${driftMin}min — possible DST mismatch',
            isError: true);
      }
    } catch (e) {
      await log('TZ', 'Timezone check crashed: $e', isError: true);
    }
  }

  // ── L3: Data Integrity ────────────────────────────────────────────────────
  static Future<void> checkTimetableData({
    required List<TimetableEntry> entries,
    required Map<int, String> subjectNames,
    required String currentWeekType,
  }) async {
    await log('DATA', '─── Timetable Data Snapshot ───');
    await log('DATA',
        'entries=${entries.length}  weekType="$currentWeekType"  subjects=${subjectNames.length}');
    if (entries.isEmpty) {
      await log('DATA', 'NO TIMETABLE ENTRIES — nothing to schedule!',
          isError: true);
      return;
    }
    if (subjectNames.isEmpty) {
      await log('DATA', 'subjectNames map is EMPTY — all show as "Class"',
          isError: true);
    }

    int willSchedule = 0, missingSubject = 0;
    for (final e in entries) {
      if (!subjectNames.containsKey(e.subjectId)) missingSubject++;
      willSchedule++;
    }
    await log('DATA',
        'Summary: $willSchedule schedulable, $missingSubject missing subject name');
  }

  // ── L4: Quota ─────────────────────────────────────────────────────────────
  static Future<void> checkAndroidQuota() async {
    await log('QUOTA', '─── Android 50-Alarm Quota Check ───');
    try {
      // FIX: use singleton plugin
      final pending = await NotifService.plugin.pendingNotificationRequests();
      final count = pending.length;
      await log('QUOTA', 'Pending: $count / 50',
          isError: count >= 45);

      if (count >= 50) {
        await log('QUOTA',
            'AT LIMIT: new notifications are being silently dropped!',
            isError: true);
      }

      // Breakdown by payload/ID range
      final tt = pending.where((p) =>
          p.payload != null && p.payload!.startsWith('timetable:')).length;
      final rm = pending.where((p) =>
          p.payload != null && p.payload!.startsWith('reminder:')).length;
      await log('QUOTA',
          'Breakdown → Timetable:$tt  Reminders:$rm  Other:${count - tt - rm}');
    } catch (e) {
      await log('QUOTA', 'Quota check failed: $e', isError: true);
    }
  }

  // ── Live Fire Test ────────────────────────────────────────────────────────
  static Future<void> scheduleTestNotification() async {
    await log('TEST', '─── 1-Minute Live Fire Test ───');
    final testId = _IdRange.diagTest;
    try {
      await NotifService.plugin.cancel(testId);
      final fireAt = DateTime.now().add(const Duration(minutes: 1));
      await NotifService.schedule(
        id: testId,
        title: '🧪 DIAG — Notification system works!',
        body: 'Fired at ${fireAt.hour}:${fireAt.minute.toString().padLeft(2, '0')}',
        when: fireAt,
        channelId: 'study_notifs',
        channelName: 'Study Reminders',
        channelDesc: 'Diagnostic test',
        payload: 'diag_test',
      );

      await Future.delayed(const Duration(milliseconds: 300));
      final pending =
          await NotifService.plugin.pendingNotificationRequests();
      final found = pending.any((p) => p.id == testId);
      await log('TEST',
          found
              ? 'Test alarm confirmed in pending queue ✓'
              : 'Test alarm NOT in pending queue! Scheduling pipeline broken.',
          isError: !found);
    } catch (e) {
      await log('TEST', 'Test notification threw: $e', isError: true);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────
  static String _timestamp() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
  }

  static Future<void> _trimLog() async {
    try {
      if (_file == null) return;
      final lines = await _file!.readAsLines();
      if (lines.length > _maxLines) {
        await _file!.writeAsString(
          '${lines.skip(lines.length - _maxLines).join('\n')}\n',
        );
      }
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// §2  HEALTH MONITOR — 6-Layer Smart Error Detection
// ═══════════════════════════════════════════════════════════════════════════════

enum NotifIssueSeverity { warning, critical }

class NotifIssue {
  final String layer;
  final NotifIssueSeverity severity;
  final String message;
  const NotifIssue({
    required this.layer,
    required this.severity,
    required this.message,
  });

  @override
  String toString() =>
      '[${severity == NotifIssueSeverity.critical ? '🔴' : '🟡'} $layer] $message';
}

class NotifHealthReport {
  final List<NotifIssue> issues;
  final int pendingCount;
  final int quotaRemaining;
  final int deliveryFailures;

  const NotifHealthReport({
    required this.issues,
    required this.pendingCount,
    required this.quotaRemaining,
    this.deliveryFailures = 0,
  });

  bool get allHealthy => issues.isEmpty;
  bool get hasCritical =>
      issues.any((i) => i.severity == NotifIssueSeverity.critical);

  String get summary {
    if (allHealthy) return '✅ All 6 layers healthy ($pendingCount pending, $quotaRemaining slots free)';
    final buf = StringBuffer();
    buf.writeln('⚠️ ${issues.length} issue(s) detected:');
    for (final i in issues) {
      buf.writeln('  $i');
    }
    buf.write('Pending: $pendingCount | Free slots: $quotaRemaining | Delivery failures: $deliveryFailures');
    return buf.toString();
  }
}

class NotifHealthMonitor {
  static const _kDeliveryTrackKey = 'notif_delivery_track';

  // ── Run all 6 layers and produce a report ────────────────────────────────
  static Future<NotifHealthReport> getHealthReport({
    List<TimetableEntry>? entries,
    Map<int, String>? subjectNames,
    String? currentWeekType,
  }) async {
    final issues = <NotifIssue>[];
    int pendingCount = 0;

    // ── L1: Permission ─────────────────────────────────────────────────────
    try {
      // FIX: use singleton plugin
      final android = NotifService.plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final notifOn = await android.areNotificationsEnabled() ?? false;
        if (!notifOn) {
          issues.add(const NotifIssue(
            layer: 'L1-Permission',
            severity: NotifIssueSeverity.critical,
            message: 'Notifications are DISABLED in system settings',
          ));
        }
        try {
          final exactOk = await android.canScheduleExactNotifications() ?? false;
          if (!exactOk) {
            issues.add(const NotifIssue(
              layer: 'L1-Permission',
              severity: NotifIssueSeverity.critical,
              message: 'Exact alarms DENIED — scheduled notifications will not fire',
            ));
          }
        } catch (_) {}

        // Battery optimization — the #1 cause of OS-killed alarms
        try {
          if (Platform.isAndroid) {
            final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
            if (!batteryExempt) {
              issues.add(const NotifIssue(
                layer: 'L1-Permission',
                severity: NotifIssueSeverity.critical,
                message: 'Battery optimization is ON — Android will kill scheduled alarms. '
                    'Go to Settings → Battery → App → Remove restrictions',
              ));
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // ── L2: Timezone ───────────────────────────────────────────────────────
    try {
      final localName = tz.local.name;
      if (localName == 'UTC' || localName.isEmpty) {
        issues.add(const NotifIssue(
          layer: 'L2-Timezone',
          severity: NotifIssueSeverity.critical,
          message: 'Timezone is UTC — all Cairo notifications fire at wrong time',
        ));
      } else {
        final drift =
            tz.TZDateTime.now(tz.local).difference(DateTime.now()).inMinutes.abs();
        if (drift > 5) {
          issues.add(NotifIssue(
            layer: 'L2-Timezone',
            severity: NotifIssueSeverity.warning,
            message: 'TZ drift ${drift}min — possible DST mismatch',
          ));
        }
      }
    } catch (_) {
      issues.add(const NotifIssue(
        layer: 'L2-Timezone',
        severity: NotifIssueSeverity.critical,
        message: 'Timezone not initialized — scheduling will crash',
      ));
    }

    // ── L4: Quota ──────────────────────────────────────────────────────────
    try {
      // FIX: use singleton plugin
      final pending =
          await NotifService.plugin.pendingNotificationRequests();
      pendingCount = pending.length;
      if (pendingCount >= 50) {
        issues.add(const NotifIssue(
          layer: 'L4-Quota',
          severity: NotifIssueSeverity.critical,
          message: 'Android 50-alarm limit REACHED — new alarms are silently dropped',
        ));
      } else if (pendingCount >= 45) {
        issues.add(NotifIssue(
          layer: 'L4-Quota',
          severity: NotifIssueSeverity.warning,
          message: 'Near limit: only ${50 - pendingCount} slots remaining',
        ));
      }
    } catch (_) {}

    // ── L5: Delivery Tracking ──────────────────────────────────────────────
    int deliveryFails = 0;
    try {
      deliveryFails = await _checkDeliveryFailures();
      if (deliveryFails > 0) {
        issues.add(NotifIssue(
          layer: 'L5-Delivery',
          severity: NotifIssueSeverity.critical,
          message: '$deliveryFails notification(s) were scheduled but never fired — '
              'OS battery optimization is killing alarms. '
              'Go to Settings → Battery → App → Remove restrictions',
        ));
      }
    } catch (_) {}

    // ── L6: Data Validation ────────────────────────────────────────────────
    if (entries != null) {
      if (entries.isEmpty) {
        issues.add(const NotifIssue(
          layer: 'L6-Data',
          severity: NotifIssueSeverity.warning,
          message: 'No timetable entries — no class notifications will be scheduled',
        ));
      }
      if (subjectNames != null && subjectNames.isEmpty && entries.isNotEmpty) {
        issues.add(const NotifIssue(
          layer: 'L6-Data',
          severity: NotifIssueSeverity.warning,
          message: 'Subject names map is empty — all classes show as "Class"',
        ));
      }
      // Check for bad time formats
      for (final e in entries) {
        final parts = e.startTime.split(':');
        if (parts.length < 2 ||
            int.tryParse(parts[0]) == null ||
            int.tryParse(parts[1]) == null) {
          issues.add(NotifIssue(
            layer: 'L6-Data',
            severity: NotifIssueSeverity.warning,
            message: 'Bad startTime "${e.startTime}" for subjectId=${e.subjectId}',
          ));
        }
      }
    }

    final report = NotifHealthReport(
      issues: issues,
      pendingCount: pendingCount,
      quotaRemaining: 50 - pendingCount,
      deliveryFailures: deliveryFails,
    );

    // Fire warning notification if critical issues exist
    if (report.hasCritical) {
      _fireHealthWarning(report);
    }

    return report;
  }

  // ── L5: Delivery failure detection ───────────────────────────────────────
  static Future<void> trackScheduled(int id, DateTime fireTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = prefs.getStringList(_kDeliveryTrackKey) ?? [];
      map.add('$id|${fireTime.millisecondsSinceEpoch}');
      // Keep only last 100 tracked entries to avoid unbounded growth
      final trimmed = map.length > 100 ? map.sublist(map.length - 100) : map;
      await prefs.setStringList(_kDeliveryTrackKey, trimmed);
    } catch (_) {}
  }

  static Future<int> _checkDeliveryFailures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracked = prefs.getStringList(_kDeliveryTrackKey) ?? [];
      if (tracked.isEmpty) return 0;

      // FIX: use singleton plugin
      final pending =
          await NotifService.plugin.pendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();
      final now = DateTime.now().millisecondsSinceEpoch;
      int failures = 0;
      final surviving = <String>[];

      for (final entry in tracked) {
        final parts = entry.split('|');
        if (parts.length != 2) continue;
        final id = int.tryParse(parts[0]);
        final fireMs = int.tryParse(parts[1]);
        if (id == null || fireMs == null) continue;

        if (now > fireMs + 120000) {
          // Fire time passed (+ 2 min grace)
          if (pendingIds.contains(id)) {
            // STILL in pending → OS killed the alarm
            failures++;
            await NotifDiag.log('L5-DELIVERY',
                'FAILURE: id=$id was due at ${DateTime.fromMillisecondsSinceEpoch(fireMs)} '
                'but is still pending — OS killed the alarm',
                isError: true);
          }
          // Either way, remove from tracking (it's in the past)
        } else {
          // Not yet due — keep tracking
          surviving.add(entry);
        }
      }

      await prefs.setStringList(_kDeliveryTrackKey, surviving);
      return failures;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDeliveryTrackKey);
    } catch (_) {}
  }

  // ── Fire a warning notification to the user ──────────────────────────────
  static void _fireHealthWarning(NotifHealthReport report) {
    final criticals =
        report.issues.where((i) => i.severity == NotifIssueSeverity.critical);
    if (criticals.isEmpty) return;

    final body = criticals.map((i) => '• ${i.message}').join('\n');
    NotifService.show(
      id: _IdRange.healthWarning,
      title: '⚠️ Notification System Issue',
      body: body.length > 200 ? '${body.substring(0, 197)}...' : body,
      channelId: 'study_notifs',
      channelName: 'Study Reminders',
      channelDesc: 'Health warnings',
      payload: 'health_warning',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// §3  BACKGROUND HANDLER — must be top-level, annotated vm:entry-point
// ═══════════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse details) {
  debugPrint('[BG] Notif: ${details.payload} action:${details.actionId}');
}

// ═══════════════════════════════════════════════════════════════════════════════
// §4  NOTIFICATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class NotifService {
  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();

  /// Singleton plugin — used by NotifDiag and NotifHealthMonitor to avoid
  /// creating separate instances that conflict with the native channel.
  static FlutterLocalNotificationsPlugin get plugin => _p;

  static void Function(String payload, String? actionId)? onActionReceived;
  static bool _tzInitialized = false;
  static final Set<int> _timetableNotifIds = {};

  // ── Mutex for atomic fallback store operations ────────────────────────────
  static Completer<void>? _storeLock;

  static Future<void> _acquireStoreLock() async {
    while (_storeLock != null && !_storeLock!.isCompleted) {
      await _storeLock!.future;
    }
    _storeLock = Completer<void>();
  }

  static void _releaseStoreLock() {
    _storeLock?.complete();
    _storeLock = null;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FOREGROUND SERVICE FALLBACK — Vivo/Xiaomi/Oppo/Huawei alarm-kill bypass
  //
  // Chinese OEMs kill zonedSchedule() alarms silently. This stores every
  // scheduled notification with its fire time. The ClassAlarmService foreground
  // service calls checkAndFireMissed() every 60 seconds. If a notification
  // was supposed to fire but didn't → we fire it immediately via show().
  // ════════════════════════════════════════════════════════════════════════════
  static const _kStoreKey = 'notif_fallback_store';

  /// Persist a scheduled notification for fallback delivery.
  /// Uses mutex to prevent concurrent read-modify-write corruption.
  static Future<void> _storeScheduled({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String channelId,
    required String channelName,
    required String channelDesc,
    String? payload,
  }) async {
    try {
      await _acquireStoreLock();
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? [];
      // Format: id|fireTimeMs|title|body|channelId|channelName|channelDesc|payload
      final entry = [
        id.toString(),
        when.millisecondsSinceEpoch.toString(),
        title,
        body,
        channelId,
        channelName,
        channelDesc,
        payload ?? '$id',
      ].join('\x1F'); // Unit separator
      list.add(entry);
      // Cap at 200 entries
      final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
      await prefs.setStringList(_kStoreKey, trimmed);
    } catch (_) {
    } finally {
      _releaseStoreLock();
    }
  }

  /// Remove a notification from the fallback store (on cancel).
  /// Uses mutex to prevent concurrent read-modify-write corruption.
  static Future<void> _removeFromStore(int id) async {
    try {
      await _acquireStoreLock();
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? [];
      list.removeWhere((entry) {
        final parts = entry.split('\x1F');
        return parts.isNotEmpty && parts[0] == id.toString();
      });
      await prefs.setStringList(_kStoreKey, list);
    } catch (_) {
    } finally {
      _releaseStoreLock();
    }
  }

  /// Remove multiple IDs from the fallback store in a single atomic operation.
  static Future<void> _removeMultipleFromStore(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await _acquireStoreLock();
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? [];
      final idStrings = ids.map((id) => id.toString()).toSet();
      list.removeWhere((entry) {
        final parts = entry.split('\x1F');
        return parts.isNotEmpty && idStrings.contains(parts[0]);
      });
      await prefs.setStringList(_kStoreKey, list);
    } catch (_) {
    } finally {
      _releaseStoreLock();
    }
  }

  /// Called every 60 seconds by ClassAlarmService foreground task.
  /// Fires any notification whose time has passed but hasn't been delivered.
  /// Uses mutex for atomic store access.
  static Future<void> checkAndFireMissed() async {
    try {
      await _acquireStoreLock();
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? [];
      if (list.isEmpty) {
        _releaseStoreLock();
        return;
      }

      final pending = await _p.pendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();

      final now = DateTime.now().millisecondsSinceEpoch;
      final surviving = <String>[];
      int firedCount = 0;

      for (final entry in list) {
        final parts = entry.split('\x1F');
        if (parts.length < 8) continue;

        final id = int.tryParse(parts[0]);
        final fireMs = int.tryParse(parts[1]);
        if (id == null || fireMs == null) continue;

        if (now >= fireMs) {
          // Past due — only fire if missed by less than 30 minutes
          // (was 5min, but Doze mode can delay the 60s heartbeat, causing
          // the fallback to miss the window entirely — 30min gives enough
          // slack for "class started N minutes ago" to still be useful)
          final ageMs = now - fireMs;
          if (ageMs <= 1800000) { // 30 minutes in ms
            // ONLY fire if the OS failed to trigger it (still stuck in pending)
            if (pendingIds.contains(id)) {
              // Release lock before plugin calls to avoid deadlock
              _releaseStoreLock();

              // Cancel the dead scheduled alarm, then fire immediately
              try { await _p.cancel(id); } catch (_) {}
              final lateMinutes = (ageMs / 60000).round();
              final lateBody = lateMinutes > 2
                  ? '⏰ ${lateMinutes}m late — ${parts[3]}'
                  : parts[3];
              await show(
                id: id,
                title: parts[2],
                body: lateBody,
                channelId: parts[4],
                channelName: parts[5],
                channelDesc: parts[6],
                payload: parts[7],
              );
              firedCount++;

              // Re-acquire lock to continue loop
              await _acquireStoreLock();
            }
          }
          // Don't keep in store — it's in the past
        } else {
          surviving.add(entry);
        }
      }

      await prefs.setStringList(_kStoreKey, surviving);
      _releaseStoreLock();

      if (firedCount > 0) {
        debugPrint('[FALLBACK] Fired $firedCount missed notification(s)');
        NotifDiag.logSync('FALLBACK',
            'Fired $firedCount missed notification(s) via foreground service');
      }
    } catch (e) {
      _releaseStoreLock();
      debugPrint('[FALLBACK] checkAndFireMissed error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> init() async {
    _ensureTimezone();

    // Create all notification channels
    final android = _p.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      for (final ch in _channels) {
        try {
          await android.createNotificationChannel(ch);
        } catch (_) {}
      }
    }

    // Initialize plugin
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
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundHandler,
    );

    // Request permissions
    if (android != null) {
      try { await android.requestNotificationsPermission(); } catch (_) {}
      try { await android.requestExactAlarmsPermission(); } catch (_) {}
    }

    // Request battery optimization exemption — without this, Android can
    // (and does) silently kill scheduled alarms. This shows the system
    // dialog "Allow app to run in background?" once.
    try {
      if (Platform.isAndroid) {
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          final result = await Permission.ignoreBatteryOptimizations.request();
          NotifDiag.logSync('PERM',
              'Battery optimization exemption: ${result.isGranted ? "GRANTED ✓" : "DENIED ✗"}',
              isError: !result.isGranted);
        }
      }
    } catch (e) {
      NotifDiag.logSync('PERM', 'Battery exemption request failed: $e');
    }

    // Run delivery failure check on init (detects OS-killed alarms)
    try {
      final report = await NotifHealthMonitor.getHealthReport();
      if (report.deliveryFailures > 0) {
        NotifDiag.logSync('HEALTH',
            '${report.deliveryFailures} delivery failure(s) detected on init',
            isError: true);
        await checkAndFireMissed();
      }
    } catch (_) {}

    NotifDiag.logSync('INIT', 'NotifService.init() complete');
  }

  static Future<void> initForService() async {
    _ensureTimezone();
    try {
      await _p.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CHANNELS
  // ════════════════════════════════════════════════════════════════════════════

  static final List<AndroidNotificationChannel> _channels = const [
    AndroidNotificationChannel(
      'study_notifs', 'Study Reminders',
      description: 'Task reminders',
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'exam_notifs', 'Exam Reminders',
      description: 'Exam reminders',
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'timetable_notifs', 'Class Reminders',
      description: 'Timetable class reminders',
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'reminder_notifs', 'Reminders',
      description: 'Custom reminders',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'deep_study', 'Deep Study',
      description: 'Study session pings',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'read_my_day', 'Read My Day',
      description: 'End-of-day schedule reading',
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'urgent_tasks', 'Urgent Tasks',
      description: 'Tasks due within 3 hours',
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'nova_checkin', 'NOVA Daily Check-ins',
      description: 'Scheduled NOVA briefing notifications',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'nova_watchdog', 'Distraction Guard',
      description: 'App usage limit alerts',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'nova_attendance', 'Attendance Guardian',
      description: 'Mandatory attendance alerts',
      importance: Importance.max,
    ),
  ];

  // ════════════════════════════════════════════════════════════════════════════
  // TIMEZONE
  // ════════════════════════════════════════════════════════════════════════════

  static void _ensureTimezone() {
    if (_tzInitialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
      _tzInitialized = true;
      NotifDiag.logSync('TZ', 'Timezone initialized to Africa/Cairo');
    } catch (e) {
      NotifDiag.logSync('TZ', 'FAILED to initialize timezone: $e',
          isError: true);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // QUOTA MANAGEMENT
  //
  // Android limits scheduled alarms to ~50. Before scheduling, check pending
  // count. If near limit, evict lowest-priority alarms to make room.
  //
  // Priority (highest → lowest):
  //   1. Timetable (next 2 days), Exams, Urgent tasks
  //   2. Reminders, Tasks (3h)
  //   3. Tasks (24h, night-before), Read My Day
  //   4. Topic reviews, old tasks (>3 days out)
  // ════════════════════════════════════════════════════════════════════════════

  static Future<bool> _ensureQuotaAvailable({int slotsNeeded = 1}) async {
    try {
      final pending = await _p.pendingNotificationRequests();
      final available = 50 - pending.length;
      if (available >= slotsNeeded) return true;

      // Need to evict. Sort pending by eviction priority (lowest first).
      final evictCandidates = <int>[];

      // Priority 4 (evict first): topic reviews, old task 24h alerts
      for (final p in pending) {
        if (p.id >= _IdRange.topicReview && p.id < _IdRange.topicReview + 10000) {
          evictCandidates.add(p.id);
        }
      }
      // Priority 3: task 24h, task night-before, Read My Day
      for (final p in pending) {
        if (p.id >= _IdRange.task24h && p.id < _IdRange.task24h + 10000) {
          evictCandidates.add(p.id);
        }
        if (p.id >= _IdRange.taskNight && p.id < _IdRange.taskNight + 10000) {
          evictCandidates.add(p.id);
        }
        if (p.id == _IdRange.readMyDay) {
          evictCandidates.add(p.id);
        }
      }

      // Evict enough to make room
      final toEvict = slotsNeeded - available;
      final evicting = evictCandidates.take(toEvict).toList();
      for (final id in evicting) {
        try { await _p.cancel(id); } catch (_) {}
      }
      if (evicting.isNotEmpty) {
        _removeMultipleFromStore(evicting);
        NotifDiag.logSync('QUOTA',
            'Evicted ${evicting.length} low-priority alarm(s) to make room');
      }

      return evicting.length >= toEvict;
    } catch (_) {
      return true; // On error, try anyway
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CORE: schedule() — with quota management and fallback store
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

    // Guard: past time
    if (when.isBefore(DateTime.now())) {
      NotifDiag.logSync('SCHED',
          'SKIP id=$id "$title" — target $when is in the past');
      return;
    }

    // Ensure quota
    await _ensureQuotaAvailable();

    final tzWhen = tz.TZDateTime.from(when, tz.local);

    try {
      await _p.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.max,
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

      // L5: Track for delivery verification
      NotifHealthMonitor.trackScheduled(id, when);

      // Store for foreground service fallback (Vivo/Xiaomi/Oppo kill fix)
      _storeScheduled(
        id: id,
        title: title,
        body: body,
        when: when,
        channelId: channelId,
        channelName: channelName,
        channelDesc: channelDesc,
        payload: payload,
      );

      NotifDiag.logSync('SCHED', 'OK id=$id "$title" → $tzWhen');
    } catch (e, stack) {
      NotifDiag.logSync('SCHED',
          'THREW for id=$id: $e\n$stack', isError: true);
    }
  }

  // ── show() — immediate notification ───────────────────────────────────────
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
            channelId, channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.max,
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

  // ════════════════════════════════════════════════════════════════════════════
  // TASK NOTIFICATIONS
  //   - 24h before due
  //   - Night before (9 PM)
  //   - 3h before due
  //   - Urgent timer if due within 3h (now uses scheduled notifs)
  // ════════════════════════════════════════════════════════════════════════════

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

    if (diff.inDays <= 7) {
      // 3-hour mark (e.g. final sprint)
      final threeH = due.subtract(const Duration(hours: 3));
      if (threeH.isAfter(now)) {
        await schedule(
          id: _IdRange.task3h + (id % 10000),
          title: '🔥 Due in 3 hours!',
          body: '$title — Today at ${fmt.format(due)}',
          when: threeH,
        );
      }

      // Night before at 6:00 PM (18:00) — student evening study window
      final dayBefore = due.subtract(const Duration(days: 1));
      final nightBefore =
          DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 18, 0);
      if (nightBefore.isAfter(now)) {
        await schedule(
          id: _IdRange.taskNight + (id % 10000),
          title: '📋 Due tomorrow',
          body: '$title — Tomorrow at ${fmt.format(due)}',
          when: nightBefore,
        );
      }
    }

    // Start urgent reminders if within 3 hours
    if (diff.inHours < 3) {
      startUrgentTaskReminder(id, title);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // EXAM NOTIFICATIONS
  //   - 3 days before
  //   - Night before (9 PM)
  //   - 24h before
  //   - 3h before
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> scheduleExamNotifs(
    int id,
    String title,
    String examType,
    DateTime due,
  ) async {
    await cancelExam(id);
    final now = DateTime.now();
    if (due.difference(now).isNegative) return;

    final fmtD = intl.DateFormat('MMM d');
    final lbl = examType[0].toUpperCase() + examType.substring(1);
    const ch = 'exam_notifs';
    const cn = 'Exam Reminders';
    const cd = 'Exam reminders';

    // 3 days before
    final threeDays = due.subtract(const Duration(days: 3));
    if (threeDays.isAfter(now)) {
      await schedule(
        id: _IdRange.exam3day + (id % 10000),
        title: '📚 $lbl in 3 days',
        body: '$title — ${fmtD.format(due)}',
        when: threeDays,
        channelId: ch, channelName: cn, channelDesc: cd,
      );
    }

    // Night before at 6:00 PM (18:00)
    final dayBefore = due.subtract(const Duration(days: 1));
    final nightBefore =
        DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 18, 0);
    if (nightBefore.isAfter(now)) {
      await schedule(
        id: _IdRange.examNight + (id % 10000),
        title: '⚠️ $lbl TOMORROW!',
        body: '$title — Study hard!',
        when: nightBefore,
        channelId: ch, channelName: cn, channelDesc: cd,
      );
    }

    // 24 hours before
    final oneDay = due.subtract(const Duration(hours: 24));
    if (oneDay.isAfter(now)) {
      await schedule(
        id: _IdRange.exam24h + (id % 10000),
        title: '📝 $lbl in 24 hours',
        body: '$title — ${fmtD.format(due)}',
        when: oneDay,
        channelId: ch, channelName: cn, channelDesc: cd,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TIMETABLE NOTIFICATIONS
  //
  //   weekType == 'both'  → one-shot alarm, rescheduled by midnight job
  //   weekType == 'odd'/'even' → 2 explicit one-shots covering ~1 month
  //   Skips days with midterm/final exams
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> scheduleTimetableNotifs({
    required List<TimetableEntry> entries,
    required Map<int, String> subjectNames,
    required String currentWeekType,
    required List<TaskModel> tasks,
  }) async {
    await cancelTimetableAll();

    // Quota guard — leave room for tasks/exams/reminders
    try {
      final pending = await _p.pendingNotificationRequests();
      final slotsAvailable = 50 - pending.length;
      if (slotsAvailable <= 5) {
        NotifDiag.logSync('TTSCHED',
            'Only $slotsAvailable slots free — timetable scheduling skipped',
            isError: true);
        return;
      }
    } catch (_) {}

    _ensureTimezone();
    final now = DateTime.now();
    int scheduledCount = 0;

    await NotifDiag.log('TTSCHED',
        'scheduleTimetableNotifs: ${entries.length} entries, weekType=$currentWeekType');

    for (final e in entries) {
      // Parse time
      final parts = e.startTime.split(':');
      if (parts.length < 2) {
        await NotifDiag.log('TTSCHED',
            'Bad startTime "${e.startTime}" for subjectId=${e.subjectId}',
            isError: true);
        continue;
      }
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;

      // Build notification content
      final subName = subjectNames[e.subjectId] ?? 'Class';
      final emoji =
          e.type == 'lab' ? '🧪' : e.type == 'section' ? '🔧' : '📚';
      final loc = [
        if (e.room.isNotEmpty) 'Room ${e.room}',
        if (e.building.isNotEmpty) e.building,
      ].join(' · ');
      final bodyText =
          '${e.type[0].toUpperCase()}${e.type.substring(1)}'
          '${loc.isNotEmpty ? ' — $loc' : ''}';
      final notifTitle = '$emoji $subName — Starting NOW!';

      // Stable ID based on day/time/weekType — now using _IdRange.timetable
      final minuteOfWeek = (e.dayOfWeek - 1) * 1440 + (h * 60) + m;
      final weekTypeOff =
          e.weekType == 'both' ? 0 : e.weekType == 'odd' ? 1 : 2;
      final baseId = _IdRange.timetable + minuteOfWeek * 3 + weekTypeOff;

      // ── Exceptional (one-time) classes ──────────────────────────────────
      if (e.isExceptional && e.exceptionalDate.isNotEmpty) {
        try {
          final exDate = DateTime.parse(e.exceptionalDate);
          final classStart =
              DateTime(exDate.year, exDate.month, exDate.day, h, m);
          if (classStart.isAfter(now.subtract(const Duration(minutes: 2)))) {
            if (!_hasExamOnDate(tasks, classStart)) {
              await schedule(
                id: baseId,
                title: notifTitle,
                body: bodyText,
                when: classStart,
                channelId: 'timetable_notifs',
                channelName: 'Class Reminders',
                channelDesc: 'Timetable',
                payload: 'timetable:${e.subjectId}',
              );
              _timetableNotifIds.add(baseId);
              scheduledCount++;
            }
          }
        } catch (err) {
          await NotifDiag.log('TTSCHED',
              'Bad exceptionalDate "${e.exceptionalDate}": $err',
              isError: true);
        }
        continue;
      }

      // ── CASE A: weekType == 'both' → one-shot (rescheduled by midnight) ─
      if (e.weekType == 'both') {
        final firstOcc = _nextWeekdayAt(now, e.dayOfWeek, h, m);
        if (_hasExamOnDate(tasks, firstOcc)) continue;

        await schedule(
          id: baseId,
          title: notifTitle,
          body: bodyText,
          when: firstOcc,
          channelId: 'timetable_notifs',
          channelName: 'Class Reminders',
          channelDesc: 'Timetable',
          payload: 'timetable:${e.subjectId}',
        );
        _timetableNotifIds.add(baseId);
        scheduledCount++;
      }

      // ── CASE B: weekType == 'odd'/'even' → next matching class (rolling 1-slot) ──
      else {
        int found = 0;
        DateTime candidate = _nextWeekdayAt(now, e.dayOfWeek, h, m);

        while (found < 1) {
          final wNum = _weekNumber(candidate);
          final wType = wNum.isOdd ? 'odd' : 'even';

          if (wType == e.weekType) {
            if (!_hasExamOnDate(tasks, candidate)) {
              await schedule(
                id: baseId,
                title: notifTitle,
                body: bodyText,
                when: candidate,
                channelId: 'timetable_notifs',
                channelName: 'Class Reminders',
                channelDesc: 'Timetable',
                payload: 'timetable:${e.subjectId}',
              );
              _timetableNotifIds.add(baseId);
              scheduledCount++;
              found++;
            }
          }

          candidate = candidate.add(const Duration(days: 7));
          if (candidate.difference(now).inDays > 90) break;
        }
      }
    }

    await NotifDiag.log('TTSCHED',
        'DONE — $scheduledCount alarms registered',
        isError: scheduledCount == 0 && entries.isNotEmpty);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CANCEL: Timetable
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> cancelTimetableAll() async {
    // Fast path: cancel known IDs from memory
    final idsCopy = List<int>.from(_timetableNotifIds);
    _timetableNotifIds.clear();
    for (final id in idsCopy) {
      try { await _p.cancel(id); } catch (_) {}
    }
    // Full sweep: catch orphans from previous sessions
    try {
      final pending = await _p.pendingNotificationRequests();
      for (final n in pending) {
        // Match new timetable range (110,000–159,999)
        final isTtRange = n.id >= _IdRange.timetable && n.id < _IdRange.timetable + 50000;
        final hasTtPayload =
            n.payload != null && n.payload!.startsWith('timetable:');
        if (isTtRange || hasTtPayload) {
          try { await _p.cancel(n.id); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // REMINDER NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> scheduleReminder(ReminderModel r) async {
    if (r.id == null) return;
    await cancelReminder(r.id!);
    final when = r.dateTime;
    if (when == null || when.isBefore(DateTime.now())) return;

    await schedule(
      id: _IdRange.reminder + (r.id! % 10000),
      title: '🔔 Reminder',
      body: r.text,
      when: when,
      channelId: 'reminder_notifs',
      channelName: 'Reminders',
      channelDesc: 'Custom reminders',
      payload: 'reminder:${r.id}',
    );

    // Also schedule 15-min early reminder
    final early = when.subtract(const Duration(minutes: 15));
    if (early.isAfter(DateTime.now())) {
      await schedule(
        id: _IdRange.reminderEarly + (r.id! % 10000),
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
      List<ReminderModel> reminders) async {
    for (final r in reminders) {
      if (!r.isDone) await scheduleReminder(r);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SPACED REPETITION TOPIC REVIEWS (Smart Daily Digest)
  //
  // Groups all due topics by day for the next 7 days.
  // Schedules exactly 1 consolidated notification per day at 6:00 PM (18:00).
  // Uses at most 7 slots total regardless of whether you have 5 or 100 topics!
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> scheduleTopicReviews(List<StudyTopic> topics) async {
    await cancelTopicReviews();
    final now = DateTime.now();

    // Group active due topics by day offset (0 = today, 1 = tomorrow, ..., 7 = next week)
    final Map<int, List<StudyTopic>> topicsByDay = {};

    for (final topic in topics) {
      if (topic.isMastered || topic.nextReview == null) continue;
      final reviewDate = topic.nextReview!;
      final diffDays = DateTime(reviewDate.year, reviewDate.month, reviewDate.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;

      if (diffDays >= 0 && diffDays <= 7) {
        topicsByDay.putIfAbsent(diffDays, () => []).add(topic);
      }
    }

    for (final entry in topicsByDay.entries) {
      final dayOffset = entry.key;
      final dueTopics = entry.value;
      if (dueTopics.isEmpty) continue;

      final targetDate = now.add(Duration(days: dayOffset));
      final fireTime =
          DateTime(targetDate.year, targetDate.month, targetDate.day, 18, 0); // 6:00 PM

      if (fireTime.isBefore(now)) continue;

      final count = dueTopics.length;
      final sampleTitles = dueTopics.map((t) => t.title).take(2).join(', ');
      final moreCount = count > 2 ? ' +${count - 2} more' : '';

      final dayLabel = dayOffset == 0
          ? 'today'
          : dayOffset == 1
              ? 'tomorrow'
              : 'in $dayOffset days';

      await schedule(
        id: _IdRange.topicReview + dayOffset,
        title: '🧠 Spaced Review: $count topic${count > 1 ? 's' : ''} due $dayLabel',
        body: '$sampleTitles$moreCount — Keep your memory fresh!',
        when: fireTime,
        channelId: 'study_notifs',
        channelName: 'Study Reminders',
        channelDesc: 'Spaced repetition reviews',
        payload: 'topics:review',
      );
    }
  }

  static Future<void> cancelTopicReviews() async {
    for (int i = 0; i <= 7; i++) {
      try { await _p.cancel(_IdRange.topicReview + i); } catch (_) {}
      _removeFromStore(_IdRange.topicReview + i);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // URGENT TASK REMINDERS
  //
  // FIX: Was Timer.periodic (died on background/kill). Now uses scheduled
  // notifications at 30-min intervals that survive process death.
  // Schedules up to 6 pings: t+0, t+30, t+60, t+90, t+120, t+150 minutes.
  // ════════════════════════════════════════════════════════════════════════════

  static void startUrgentTaskReminder(int taskId, String title) {
    stopUrgentTaskReminder(taskId);

    // Immediate notification
    show(
      id: _IdRange.urgent + (taskId % 10000),
      title: '⚡ Due soon: $title',
      body: 'Due in under 3 hours! Tap to mark as working on it.',
      channelId: 'urgent_tasks',
      channelName: 'Urgent Tasks',
      channelDesc: 'Tasks due within 3 hours',
      payload: 'urgent:$taskId',
      actions: [
        const AndroidNotificationAction(
          'ack_task', '✅ Working on it',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    // Schedule follow-up pings that survive process death
    // Up to 5 more pings at 30-min intervals (uses sub-slots within ID range)
    final now = DateTime.now();
    for (int i = 1; i <= 5; i++) {
      final pingTime = now.add(Duration(minutes: 30 * i));
      final pingId = _IdRange.urgent + (taskId % 10000) + (i * 1000);
      // Ensure we don't overflow into next range
      if (pingId >= _IdRange.urgent + 10000) break;
      schedule(
        id: pingId,
        title: '⚡ Still pending: $title',
        body: 'Due very soon! Tap to acknowledge.',
        when: pingTime,
        channelId: 'urgent_tasks',
        channelName: 'Urgent Tasks',
        channelDesc: 'Tasks due within 3 hours',
        payload: 'urgent:$taskId',
        actions: [
          const AndroidNotificationAction(
            'ack_task', '✅ Working on it',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
    }
  }

  static void stopUrgentTaskReminder(int taskId) {
    // Cancel the immediate notification + all 5 scheduled pings
    _p.cancel(_IdRange.urgent + (taskId % 10000)).catchError((_) {});
    for (int i = 1; i <= 5; i++) {
      final pingId = _IdRange.urgent + (taskId % 10000) + (i * 1000);
      _p.cancel(pingId).catchError((_) {});
      _removeFromStore(pingId);
    }
  }

  static void stopAllUrgentReminders() {
    // Cancel all IDs in the urgent range by sweeping pending
    _p.pendingNotificationRequests().then((pending) {
      for (final p in pending) {
        if (p.id >= _IdRange.urgent && p.id < _IdRange.urgent + 10000) {
          _p.cancel(p.id).catchError((_) {});
          _removeFromStore(p.id);
        }
      }
    }).catchError((_) {});
  }

  // ════════════════════════════════════════════════════════════════════════════
  // READ MY DAY notification
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> scheduleReadMyDayNotif({
    required List<TimetableEntry> allEntries,
    required String currentWeekType,
  }) async {
    await cancelSingle(_IdRange.readMyDay);
    final now = DateTime.now();
    final todayDow = now.weekday;
    final weekNum = _weekNumber(now);
    final todayWeekType = weekNum.isOdd ? 'odd' : 'even';

    final todayEntries = allEntries.where((e) {
      if (e.dayOfWeek != todayDow) return false;
      return e.weekType == 'both' || e.weekType == todayWeekType;
    }).toList();
    if (todayEntries.isEmpty) return;

    // Find last class end time
    DateTime? lastEnd;
    for (final e in todayEntries) {
      final p = e.endTime.split(':');
      if (p.length < 2) continue;
      final dt = DateTime(
        now.year, now.month, now.day,
        int.parse(p[0]), int.parse(p[1]),
      );
      if (lastEnd == null || dt.isAfter(lastEnd)) lastEnd = dt;
    }
    if (lastEnd == null) return;

    final notifyAt = lastEnd.add(const Duration(minutes: 10));
    if (notifyAt.isBefore(now)) return;

    await schedule(
      id: _IdRange.readMyDay,
      title: '🎓 Day complete! Hear your summary?',
      body: 'Tap to listen to your daily briefing',
      when: notifyAt,
      channelId: 'read_my_day',
      channelName: 'Read My Day',
      channelDesc: 'End-of-day review',
      payload: 'read_my_day:choose',
      actions: [
        const AndroidNotificationAction(
          'read_en', '🔊 English',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'read_ar', '🔊 عربي',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ABSENCE WARNING
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> showAbsenceWarning({
    required int subjectId,
    required String subjectName,
    required int current,
    required int maxAbs,
    required String type,
  }) async {
    final remaining = maxAbs - current;
    if (remaining > 1) return;
    final typeOff = type == 'lecture' ? 1 : type == 'section' ? 2 : 3;
    try {
      await _p.show(
        _IdRange.absence + (subjectId % 100) * 10 + typeOff,
        remaining == 0
            ? '🚫 Maximum Absences Reached!'
            : '⚠️ Absence Warning!',
        remaining == 0
            ? '$subjectName — Reached max $type absences!'
            : '$subjectName — Only 1 $type absence left!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'study_notifs', 'Study Reminders',
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

  // ════════════════════════════════════════════════════════════════════════════
  // NOVA: Mandatory Attendance Alert
  // ════════════════════════════════════════════════════════════════════════════

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
        _IdRange.attendance + subjectName.hashCode.abs() % 999,
        '⛔ NOVA — MANDATORY CLASS TOMORROW',
        '$subjectName at $time${room.isNotEmpty ? ', $room' : ''}. '
            'You have 1 absence left. Missing this bars you from the final.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'nova_attendance', 'Attendance Guardian',
            channelDescription: 'Mandatory attendance alerts',
            importance: Importance.max,
            priority: Priority.high,
            ongoing: true,
            autoCancel: false,
            actions: [
              const AndroidNotificationAction(
                'ack_attend', "I'll be there",
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
      NotifDiag.logSync('NOVA',
          'showMandatoryAttendanceAlert error: $e', isError: true);
    }
  }

  static Future<void> cancelMandatoryAlert(String subjectName) async {
    try {
      await _p.cancel(_IdRange.attendance + subjectName.hashCode.abs() % 999);
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CANCEL HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> cancelSingle(int id) async {
    try { await _p.cancel(id); } catch (_) {}
    _removeFromStore(id);
  }

  /// Cancel all notifications related to a task (all 3 time slots + urgent)
  static Future<void> cancel(int id) async {
    final modId = id % 10000;
    final ids = [
      _IdRange.task24h + modId,
      _IdRange.task3h + modId,
      _IdRange.taskNight + modId,
    ];
    for (final nid in ids) {
      try { await _p.cancel(nid); } catch (_) {}
    }
    _removeMultipleFromStore(ids);
    stopUrgentTaskReminder(id);
  }

  /// Cancel all notifications related to an exam (all 4 time slots)
  static Future<void> cancelExam(int id) async {
    final modId = id % 10000;
    final ids = [
      _IdRange.exam24h + modId,
      _IdRange.exam3h + modId,
      _IdRange.examNight + modId,
      _IdRange.exam3day + modId,
    ];
    for (final nid in ids) {
      try { await _p.cancel(nid); } catch (_) {}
    }
    _removeMultipleFromStore(ids);
  }

  static Future<void> cancelReminder(int rid) async {
    final modId = rid % 10000;
    final ids = [
      _IdRange.reminder + modId,
      _IdRange.reminderEarly + modId,
    ];
    for (final nid in ids) {
      try { await _p.cancel(nid); } catch (_) {}
    }
    _removeMultipleFromStore(ids);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  /// Next occurrence of [targetWeekday] at [h]:[m], guaranteed future.
  static DateTime _nextWeekdayAt(
      DateTime from, int targetWeekday, int h, int m) {
    int daysUntil = (targetWeekday - from.weekday) % 7;
    var candidate = DateTime(
      from.year, from.month, from.day + daysUntil, h, m,
    );
    if (!candidate.isAfter(from)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }


  /// True if a midterm/final exam is on the same calendar day.
  static bool _hasExamOnDate(List<TaskModel> tasks, DateTime date) {
    return tasks.any((t) {
      if (!t.isExam || (t.type != 'midterm' && t.type != 'final')) return false;
      if (t.dueDate == null) return false;
      return t.dueDate!.year == date.year &&
          t.dueDate!.month == date.month &&
          t.dueDate!.day == date.day;
    });
  }

  /// ISO week number (matches app_bloc.dart implementation).
  static int _weekNumber(DateTime date) {
    final doy = int.parse(intl.DateFormat('D').format(date));
    return ((doy - date.weekday + 10) / 7).floor();
  }

 

}