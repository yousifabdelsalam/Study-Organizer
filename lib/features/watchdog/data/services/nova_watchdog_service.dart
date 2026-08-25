// nova_watchdog_service.dart
// Distraction watchdog: monitors daily app usage via app_usage package.
// WorkManager fires a background task every 15 min → checks limits → fires
// a notification if any app exceeded its daily allowance.

import 'dart:async';
import 'dart:convert';
import 'package:app_usage/app_usage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:study_organizer/features/speech_engine/data/services/audio_service.dart';
import 'package:study_organizer/core/services/notifications_service.dart'; // ← FIX: use the initialized NotifService

// ── Pre-populated list shown in the "Add App" UI ──────────────────────────
const kCommonDistractors = [
  {'name': 'Instagram', 'package': 'com.instagram.android'},
  {'name': 'TikTok', 'package': 'com.zhiliaoapp.musically'},
  {'name': 'YouTube', 'package': 'com.google.android.youtube'},
  {'name': 'Snapchat', 'package': 'com.snapchat.android'},
  {'name': 'Twitter/X', 'package': 'com.twitter.android'},
  {'name': 'Facebook', 'package': 'com.facebook.katana'},
  {'name': 'WhatsApp', 'package': 'com.whatsapp'},
];

const _prefWatchdogApps = 'nova_watchdog_apps'; // JSON list
const _prefAlertedToday = 'nova_watchdog_alerted'; // JSON map pkg→dateStr
const _taskName = 'nova_watchdog_check';

// ─────────────────────────────────────────────────────────────────────────────
class NovaWatchdogService {
  // ── Init ──────────────────────────────────────────────────────────────────
  // NOTE: WorkManager is now initialized in main.dart via callbackDispatcher.
  // This method is kept for API compatibility but is now a no-op.
  static Future<void> init() async {
    // WorkManager already initialized in main.dart
  }

  static Timer? _activeTimer;

  /// Start the 15-minute periodic background task AND a 30-second active foreground loop.
  ///
  /// WHY TWO TIMERS:
  /// • Android WorkManager enforces a hard minimum of 15 minutes for periodic
  ///   background tasks. A 1-minute limit for YouTube would never trigger while
  ///   the app is in the background with only WorkManager running.
  /// • The foreground timer runs every 30 seconds WHILE THE APP IS OPEN and
  ///   catches short limits instantly.
  /// • Additionally, CampusPage calls [runCheck] on every AppLifecycleState.resumed
  ///   event — so even if the user opens YouTube for 1 min, returns to NOVA,
  ///   the alert fires within 1 second of them coming back.
  static Future<void> startWatchdog() async {
    // 1. Background worker (every 15m minimum due to Android OS)
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );

    // 2. Active foreground checker — every 30 seconds while app is alive.
    // This catches sub-1-minute overages that WorkManager would miss entirely.
    _activeTimer?.cancel();
    _activeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      runCheck();
    });
  }

  static Future<void> stopWatchdog() async {
    _activeTimer?.cancel();
    await Workmanager().cancelByUniqueName(_taskName);
  }

  // ── App list CRUD ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getWatchedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefWatchdogApps);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  static Future<void> saveWatchedApps(List<Map<String, dynamic>> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefWatchdogApps, jsonEncode(apps));
  }

  static Future<void> addApp(
    String packageName,
    String displayName,
    int limitMinutes,
  ) async {
    final apps = await getWatchedApps();
    apps.removeWhere((a) => a['package'] == packageName);
    apps.add({
      'package': packageName,
      'name': displayName,
      'limitMinutes': limitMinutes,
    });
    await saveWatchedApps(apps);
  }

  static Future<void> removeApp(String packageName) async {
    final apps = await getWatchedApps();
    apps.removeWhere((a) => a['package'] == packageName);
    await saveWatchedApps(apps);
  }

  // ── Core check — runs in background every 15 min ─────────────────────────
  static Future<void> runCheck() async {
    try {
      final apps = await getWatchedApps();
      if (apps.isEmpty) return;

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);

      // Get today's usage stats
      final usageMap = <String, int>{}; // package → minutes used today
      try {
        final stats = await AppUsage().getAppUsage(start, now);
        for (final s in stats) {
          usageMap[s.packageName] = s.usage.inMinutes;
        }
      } catch (e) {
        debugPrint('AppUsage error: $e');
        return; // Usage Access not granted yet
      }

      final prefs = await SharedPreferences.getInstance();
      final todayStr = '${now.year}-${now.month}-${now.day}';
      final alertedRaw = prefs.getString(_prefAlertedToday) ?? '{}';
      final alerted = Map<String, String>.from(jsonDecode(alertedRaw) as Map);

      for (final app in apps) {
        final pkg = app['package'] as String;
        final name = app['name'] as String;
        final limitM = app['limitMinutes'] as int;
        final usedM = usageMap[pkg] ?? 0;

        if (usedM >= limitM && alerted[pkg] != todayStr) {
          alerted[pkg] = todayStr;
          await _fireNotification(name, usedM, limitM);
        }
      }

      // Persist updated alerted map
      await prefs.setString(_prefAlertedToday, jsonEncode(alerted));
    } catch (e) {
      debugPrint('WatchdogService.runCheck error: $e');
    }
  }

  // ── Notification ─────────────────────────────────────────────────────────
  static Future<void> _fireNotification(
    String appName,
    int used,
    int limit,
  ) async {
    try {
      // ✅ Use NotifService (initialized in both foreground and callbackDispatcher)
      await NotifService.show(
        id: 890000 + appName.hashCode.abs() % 9999,
        title: '⏱️ NOVA — Distraction Limit Reached',
        body:
            'You\'ve used $appName for ${used}m (limit: ${limit}m). '
            'Time to return to your study plan, sir.',
        channelId: 'nova_watchdog',
        channelName: 'Distraction Guard',
        channelDesc: 'App usage limit alerts',
        payload: 'watchdog:$appName',
      );

      // 🔊 Audio only works in foreground — safe to call, will fail silently in BG
      try {
        NovaAudioService.playAsset(
          'sounds/sir_you_are_approaching_your_daily_distraction_limit.mp3',
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Watchdog notification error: $e');
    }
  }
}
