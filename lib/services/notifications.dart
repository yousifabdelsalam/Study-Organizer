// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE — CLEAN REWRITE
//
// Provides:
//   1. NotifDiag          – Diagnostic logger (persistent file on device)
//   2. NotifHealthMonitor – 6-layer smart error detection system
//   3. NotifService       – Core notification scheduling service
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
import '../models/timetable.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import 'nova_audio_service.dart';

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
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
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
      final plugin = FlutterLocalNotificationsPlugin();
      final pending = await plugin.pendingNotificationRequests();
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
    const testId = 999991;
    try {
      await FlutterLocalNotificationsPlugin().cancel(testId);
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
          await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
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
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
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
      final pending =
          await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
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
  // When we schedule a notification, we record {id: expectedFireTimeMs} in
  // SharedPreferences. On next health check, if the fire time has passed but
  // the notification is STILL in the pending queue, the OS killed the alarm.

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

      final pending =
          await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
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
      id: 999990,
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
  static void Function(String payload, String? actionId)? onActionReceived;
  static final Map<int, Timer> _urgentTimers = {};
  static bool _tzInitialized = false;
  static final Set<int> _timetableNotifIds = {};

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
    } catch (_) {}
  }

  /// Remove a notification from the fallback store (on cancel).
  static Future<void> _removeFromStore(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? [];
      list.removeWhere((entry) {
        final parts = entry.split('\x1F');
        return parts.isNotEmpty && parts[0] == id.toString();
      });
      await prefs.setStringList(_kStoreKey, list);
    } catch (_) {}
  }

  /// Called every 60 seconds by ClassAlarmService foreground task.
  /// Fires any notification whose time has passed but hasn't been delivered.
  static Future<void> checkAndFireMissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? [];
      if (list.isEmpty) return;

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
          // Past due — check if it's within 24 hours (don't fire ancient ones)
          final ageMs = now - fireMs;
          if (ageMs < 86400000) { // 24 hours in ms
            // First cancel the (likely dead) scheduled alarm
            try { await _p.cancel(id); } catch (_) {}
            
            // Fire it NOW via show()
            await show(
              id: id,
              title: parts[2],
              body: parts[3],
              channelId: parts[4],
              channelName: parts[5],
              channelDesc: parts[6],
              payload: parts[7],
            );
            firedCount++;
          }
          // Don't keep in store — it's in the past
        } else {
          surviving.add(entry);
        }
      }

      await prefs.setStringList(_kStoreKey, surviving);

      if (firedCount > 0) {
        debugPrint('[FALLBACK] Fired $firedCount missed notification(s)');
        NotifDiag.logSync('FALLBACK',
            'Fired $firedCount missed notification(s) via foreground service');
      }
    } catch (e) {
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
  // CORE: schedule() — with L3 post-schedule verification
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
  //   - Urgent timer if due within 3h
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
    final fmtD = intl.DateFormat('MMM d');

    if (diff.inDays <= 7) {
      // 3-hour mark
      final threeH = due.subtract(const Duration(hours: 3));
      if (threeH.isAfter(now)) {
        await schedule(
          id: id + 100000,
          title: '🔥 Due in 3 hours!',
          body: '$title — Today at ${fmt.format(due)}',
          when: threeH,
        );
      }

      // 24-hour mark
      final oneDay = due.subtract(const Duration(hours: 24));
      if (oneDay.isAfter(now)) {
        await schedule(
          id: id,
          title: '⏰ Due in 24 hours',
          body: '$title — ${fmtD.format(due)} at ${fmt.format(due)}',
          when: oneDay,
        );
      }

      // Night before (9 PM)
      final dayBefore = due.subtract(const Duration(days: 1));
      final nightBefore =
          DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 21, 0);
      if (nightBefore.isAfter(now)) {
        await schedule(
          id: id + 200000,
          title: '📋 Due tomorrow',
          body: '$title — Tomorrow at ${fmt.format(due)}',
          when: nightBefore,
        );
      }
    }

    // Start urgent timer if within 3 hours
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

    final fmt = intl.DateFormat('h:mm a');
    final fmtD = intl.DateFormat('MMM d');
    final lbl = examType[0].toUpperCase() + examType.substring(1);
    const ch = 'exam_notifs';
    const cn = 'Exam Reminders';
    const cd = 'Exam reminders';

    // 3 days before
    await schedule(
      id: id + 500000,
      title: '📚 $lbl in 3 days',
      body: '$title — ${fmtD.format(due)}',
      when: due.subtract(const Duration(days: 3)),
      channelId: ch, channelName: cn, channelDesc: cd,
    );

    // Night before (9 PM)
    final dayBefore = due.subtract(const Duration(days: 1));
    await schedule(
      id: id + 600000,
      title: '⚠️ $lbl TOMORROW!',
      body: '$title — Study hard!',
      when: DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 21, 0),
      channelId: ch, channelName: cn, channelDesc: cd,
    );

    // 24 hours
    await schedule(
      id: id,
      title: '📝 $lbl in 24 hours',
      body: '$title — ${fmtD.format(due)}',
      when: due.subtract(const Duration(hours: 24)),
      channelId: ch, channelName: cn, channelDesc: cd,
    );

    // 3 hours
    await schedule(
      id: id + 100000,
      title: '🔥 $lbl in 3 hours!',
      body: '$title — ${fmt.format(due)}',
      when: due.subtract(const Duration(hours: 3)),
      channelId: ch, channelName: cn, channelDesc: cd,
    );
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

    // Quota guard
    try {
      final pending = await _p.pendingNotificationRequests();
      final slotsAvailable = 50 - pending.length;
      if (slotsAvailable <= 8) {
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
      final body =
          '${e.type[0].toUpperCase()}${e.type.substring(1)}'
          '${loc.isNotEmpty ? ' — $loc' : ''}';
      final notifTitle = '$emoji $subName — Starting NOW!';

      // Stable ID based on day/time/weekType
      final minuteOfWeek = (e.dayOfWeek - 1) * 1440 + (h * 60) + m;
      final weekTypeOff =
          e.weekType == 'both' ? 0 : e.weekType == 'odd' ? 1 : 2;
      final baseId = 900000 + minuteOfWeek * 3 + weekTypeOff;

      // ── Exceptional (one-time) classes ──────────────────────────────────
      if (e.isExceptional && e.exceptionalDate.isNotEmpty) {
        try {
          final exDate = DateTime.parse(e.exceptionalDate);
          final classStart =
              DateTime(exDate.year, exDate.month, exDate.day, h, m);
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
          id: baseId + 1,
          title: notifTitle,
          body: body,
          when: firstOcc,
          channelId: 'timetable_notifs',
          channelName: 'Class Reminders',
          channelDesc: 'Timetable',
          payload: 'timetable:${e.subjectId}',
        );
        _timetableNotifIds.add(baseId + 1);
        scheduledCount++;
      }

      // ── CASE B: weekType == 'odd'/'even' → next 2 matching fortnights ──
      else {
        int found = 0;
        DateTime candidate = _nextWeekdayAt(now, e.dayOfWeek, h, m);

        while (found < 2) {
          final wNum = _weekNumber(candidate);
          final wType = wNum.isOdd ? 'odd' : 'even';

          if (wType == e.weekType) {
            if (!_hasExamOnDate(tasks, candidate)) {
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
            }
          }

          candidate = candidate.add(const Duration(days: 7));
          if (candidate.difference(now).inDays > 90) break;
        }
      }

      // ── Immediate notification if class is starting NOW (±2 min) ────────
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
        final isTtRange = n.id >= 900000 && n.id <= 990000;
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
      List<ReminderModel> reminders) async {
    for (final r in reminders) {
      if (!r.isDone) await scheduleReminder(r);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // URGENT TASK REMINDERS (30-min ping timer)
  // ════════════════════════════════════════════════════════════════════════════

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
          'ack_task', '✅ Working on it',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
    _urgentTimers[taskId] =
        Timer.periodic(const Duration(minutes: 30), (_) async {
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
            'ack_task', '✅ Working on it',
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

  // ════════════════════════════════════════════════════════════════════════════
  // READ MY DAY notification
  // ════════════════════════════════════════════════════════════════════════════

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
    try {
      await _p.show(
        800000 + subjectId * 10 +
            (type == 'lecture' ? 1 : type == 'section' ? 2 : 3),
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
        870000 + subjectName.hashCode.abs() % 9999,
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
      await _p.cancel(870000 + subjectName.hashCode.abs() % 9999);
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CANCEL HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> cancelSingle(int id) async {
    try { await _p.cancel(id); } catch (_) {}
    _removeFromStore(id);
  }

  static Future<void> cancel(int id) async {
    for (final o in [0, 100000, 200000, 300000]) {
      try { await _p.cancel(id + o); } catch (_) {}
      _removeFromStore(id + o);
    }
  }

  static Future<void> cancelExam(int id) async {
    for (final o in [0, 100000, 300000, 500000, 600000]) {
      try { await _p.cancel(id + o); } catch (_) {}
      _removeFromStore(id + o);
    }
  }

  static Future<void> cancelReminder(int rid) async {
    try { await _p.cancel(980000 + rid); } catch (_) {}
    _removeFromStore(980000 + rid);
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
    if (candidate.isBefore(from.subtract(const Duration(minutes: 2)))) {
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