import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:study_organizer/services/class_alarm_service.dart';
import 'package:study_organizer/services/midnight_scheduler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:sqflite/sqflite.dart';

import 'package:workmanager/workmanager.dart';
import 'services/database.dart';
import 'services/notifications.dart';
import 'services/nova_watchdog_service.dart';
import 'services/nova_intelligence_engine.dart';
import 'app.dart'; // Your EngineeringApp widget

// ─────────────────────────────────────────────────────────────────────────────
// UNIFIED WORKMANAGER DISPATCHER
//
// CRITICAL: WorkManager can only be initialized ONCE per app.
// All background tasks must funnel through a single top-level dispatcher.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // ── CRITICAL: In background, main() never runs. ──
    // We must initialize Flutter bindings + notification plugin here
    // before anything that touches platform channels.
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize timezones (needed for any scheduled notif work)
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    } catch (_) {}

    // Initialize notifications so NotifService.show() works in background
    await NotifService.init();

    switch (task) {
      case 'nova_watchdog_check':
        await NovaWatchdogService.runCheck();
        break;
      case 'nova_friday_regen':
        await NovaIntelligenceEngine.runFridayRegen();
        break;
    }
    return Future.value(true);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
//
// Initialization order matters:
//   1. WidgetsFlutterBinding — must be FIRST before any platform channels
//   2. Timezone — before NotifService.init() which uses tz.local
//   3. NotifService.init() — registers background handler and permissions
//   4. WorkManager — single initialization for ALL background tasks
//   5. DatabaseHelper — opens the SQLite connection
//   6. runApp()
// ─────────────────────────────────────────────────────────────────────────────
void main() async {

  
  runZonedGuarded(()async {
    // CRITICAL: Must be called before any async work or platform channel use
    WidgetsFlutterBinding.ensureInitialized();

    // Lock orientation to portrait (optional but prevents layout issues)
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Initialize timezone data AND set local location BEFORE NotifService.init()
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    } catch (e) {
      debugPrint('main() timezone init error (non-fatal): $e');
    }

    // Initialize notification service — registers the background handler
    await NotifService.init();
    await ClassAlarmService.init();
    await MidnightScheduler.init();
    await NotifDiag.init(); // ← add this
    // ── Single WorkManager initialization for ALL background tasks ──
    // Both watchdog and intelligence engine use this shared dispatcher.
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

    // Schedule background tasks (non-blocking — use shared WorkManager instance)
    await NovaIntelligenceEngine.scheduleFridayRegen();

    // Open database
    final db = await DatabaseHelper.instance.database;

    runApp(EngineeringApp(db: db));
  },
  (error,stack){
    debugPrint('🔴 [ZONE ERROR] $error');
    debugPrint('🔴 [ZONE STACK] $stack');
  });
}