import 'package:flutter/material.dart';
import '../pages/main_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JARVIS NAVIGATOR  ─  global access to navigation + page switching
// ─────────────────────────────────────────────────────────────────────────────

class JarvisNavigator {
  // Set this as MaterialApp.navigatorKey for push/pop access from anywhere
  static final navigatorKey = GlobalKey<NavigatorState>();

  // Set this on MainShell so JARVIS can switch bottom-nav pages
  static final shellKey = GlobalKey<MainShellState>();

  // Bottom-nav page indices (matches MainShell._pages order)
  static const Map<String, int> _pageIndex = {
    'home': 0,
    'dashboard': 0,
    'tasks': 1,
    'task': 1,
    'exams': 2,
    'exam': 2,
    'calendar': 3,
    'schedule': 3,
    'timetable': 3,
    'subjects': 4,
    'subject': 4,
    'marks': 5,
    'grades': 5,
    'campus': 6,
    'focus': 6,
    'pomodoro': 6,
  };

  /// Navigate to a named page in the bottom nav
  static bool goToPage(String pageName) {
    final idx = _pageIndex[pageName.toLowerCase().trim()];
    if (idx == null) return false;
    shellKey.currentState?.switchTo(idx);
    return true;
  }

  /// Navigate + switch to a specific campus tab (timetable=0, pomodoro=1, ...)
  /// Returns true if navigated.
  static Future<bool> goToCampusTab(int tabIndex) async {
    goToPage('campus');
    // CampusPage exposes a static callback to switch its tab controller
    CampusTabSwitcher.switchTab?.call(tabIndex);
    return true;
  }

  /// Best-effort fuzzy page resolve from voice (e.g. "digital schedule" → campus)
  static String? resolvePageName(String raw) {
    final lower = raw.toLowerCase();
    for (final key in _pageIndex.keys) {
      if (lower.contains(key)) return key;
    }
    return null;
  }
}

/// Lightweight singleton callback so JARVIS can switch the campus tab controller
/// from outside the widget tree without maintaining a direct reference.
class CampusTabSwitcher {
  static void Function(int)? switchTab;
}

/// Static callbacks registered by CognitiveReactorPage so JARVIS can
/// start/stop/reset/switch mode from any page without a widget reference.
class PomodoroCommands {
  static void Function(String?)? _start;
  static void Function()? _stop;
  static void Function()? _reset;
  static void Function(String?)? _switchMode;

  static void register({
    void Function(String?)? onStart,
    void Function()? onStop,
    void Function()? onReset,
    void Function(String?)? onSwitchMode,
  }) {
    _start = onStart;
    _stop = onStop;
    _reset = onReset;
    _switchMode = onSwitchMode;
  }

  static void unregister() {
    _start = _stop = _reset = null;
    _switchMode = null;
  }

  static void start(String? mode) => _start?.call(mode);
  static void stop() => _stop?.call();
  static void reset() => _reset?.call();
  static void switchMode(String? mode) => _switchMode?.call(mode);
}
