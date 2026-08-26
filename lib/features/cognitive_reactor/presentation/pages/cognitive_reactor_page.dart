import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:screen_state/screen_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/pomodoro/data/models/pomodoro_session.dart';
import 'package:study_organizer/core/database/database_helper.dart';
import 'package:study_organizer/features/jarvis_assistant/data/services/jarvis_navigator.dart';
import 'package:study_organizer/features/speech_engine/data/services/audio_service.dart';
import 'package:study_organizer/features/cognitive_reactor/presentation/widgets/cyberpunk_painters.dart';
import 'package:study_organizer/features/cognitive_reactor/presentation/widgets/glitch_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODE CONFIG
// ─────────────────────────────────────────────────────────────────────────────
enum _Mode { focus, shortBreak, longBreak }

class _ModeConfig {
  final int duration;
  final String label;
  final String systemName;
  final Color color;
  final Color secondary;
  const _ModeConfig({
    required this.duration,
    required this.label,
    required this.systemName,
    required this.color,
    required this.secondary,
  });
}

// Default durations — runtime overridden from SharedPreferences
Map<_Mode, int> kModeDuration = {
  _Mode.focus: 25 * 60,
  _Mode.shortBreak: 5 * 60,
  _Mode.longBreak: 15 * 60,
};

const Map<_Mode, _ModeConfig> kModeConfig = {
  _Mode.focus: _ModeConfig(
    duration: 25 * 60, // placeholder; use kModeDuration at runtime
    label: 'NEURAL FOCUS',
    systemName: 'NEURAL_FOCUS_PROTOCOL',
    color: Color(0xFF00FF41),
    secondary: Color(0xFF00CC33),
  ),
  _Mode.shortBreak: _ModeConfig(
    duration: 5 * 60,
    label: 'SHORT RECHARGE',
    systemName: 'RECOVERY_SEQUENCE_ALPHA',
    color: Color(0xFF00FF88),
    secondary: Color(0xFF00D9FF),
  ),
  _Mode.longBreak: _ModeConfig(
    duration: 15 * 60,
    label: 'DEEP RESET',
    systemName: 'SYSTEM_RESTORE_OMEGA',
    color: Color(0xFFFF8C00),
    secondary: Color(0xFFFF0080),
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────
class CognitiveReactorPage extends StatefulWidget {
  const CognitiveReactorPage({super.key});
  @override
  State<CognitiveReactorPage> createState() => _CyberpunkState();
}

class _CyberpunkState extends State<CognitiveReactorPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── Mode & Timer ───────────────────────────────────────────────────────────
  _Mode _mode = _Mode.focus;
  int _remaining = 25 * 60;
  Timer? _timer;
  bool _running = false;
  int _sessions = 0;

  // ── Settings ───────────────────────────────────────────────────────────────
  int _graceSec = 15; // seconds; range 2–1800 (30 min)
  int _tf = 0;
  bool _gold = false;

  // ── Breach / screen state ──────────────────────────────────────────────────
  final Screen _screen = Screen();
  StreamSubscription<ScreenStateEvent>? _screenSub;
  bool _screenOn = true;
  DateTime? _awayStart;
  bool _breach = false;
  bool _glitch = false;
  String _statusMsg = 'AWAITING ACTIVATION';

  // ── Clock ──────────────────────────────────────────────────────────────────
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _loopCtrl; // ring rotation
  late AnimationController _breathCtrl; // glow pulse
  late AnimationController _burstCtrl; // completion burst
  late AnimationController _progCtrl; // smooth progress
  late Animation<double> _progAnim;

  // ── Random particles / rain ────────────────────────────────────────────────
  final Random _rng = Random();
  late List<ParticleData> _particles;
  late List<RainDropData> _rain;

  // ── Session context (study context tied to each Pomodoro) ──────────────────
  int? _sessionSubjectId; // selected subject for this session
  String? _sessionTopicLabel; // free-text topic label
  int? _activeDbSessionId; // DB row id once session is saved

  int get _modeDuration => kModeDuration[_mode]!;
  _ModeConfig get _cfg => kModeConfig[_mode]!;
  Color get _currentColor => _breach ? const Color(0xFFF44336) : _tierColor;
  double get _progress => (_modeDuration - _remaining) / _modeDuration;

  // TF cosmetic tier
  Color get _tierColor {
    if (_tf >= 1000) {
      // LEGENDARY: rainbow pulse based on time
      final hue = (_now.millisecondsSinceEpoch / 30) % 360;
      return HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    }
    if (_tf >= 500) return const Color(0xFFFFD54F); // GOLD
    if (_tf >= 200) return const Color(0xFFB0BEC5); // PRO / silver
    return _cfg.color; // BASE
  }

  String get _tierLabel {
    if (_tf >= 1000) return 'LEGENDARY';
    if (_tf >= 500) return 'GOLD';
    if (_tf >= 200) return 'PRO';
    return 'BASE';
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _particles = List.generate(
      50,
      (i) => ParticleData(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        char: [
          '0',
          '1',
          'A',
          'F',
          '>',
          '<',
          '/',
          '\\',
          '|',
          '-',
        ][_rng.nextInt(10)],
        speed: 0.5 + _rng.nextDouble() * 0.5,
        delay: i * 0.15,
      ),
    );
    _rain = List.generate(
      40,
      (i) => RainDropData(
        x: _rng.nextDouble(),
        speed: 0.8 + _rng.nextDouble(),
        delay: i * 0.1,
      ),
    );

    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _progAnim = const AlwaysStoppedAnimation(0.0);

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadData();
    _initScreen();

    // Register JARVIS Pomodoro voice controls
    PomodoroCommands.register(
      onStart: (modeStr) {
        if (modeStr != null) _switchMode(_modeFromString(modeStr));
        if (!_running) _start();
      },
      onStop: () {
        if (_running) _pause();
      },
      onReset: _reset,
      onSwitchMode: (modeStr) {
        if (modeStr != null) _switchMode(_modeFromString(modeStr));
      },
    );
  }

  static _Mode _modeFromString(String s) {
    if (s.contains('short')) return _Mode.shortBreak;
    if (s.contains('long') || s.contains('deep')) return _Mode.longBreak;
    return _Mode.focus;
  }

  void _initScreen() {
    try {
      _screenSub = _screen.screenStateStream.listen((event) {
        switch (event) {
          case ScreenStateEvent.SCREEN_OFF:
            _screenOn = false;
            break;
          case ScreenStateEvent.SCREEN_ON:
          case ScreenStateEvent.SCREEN_UNLOCKED:
            _screenOn = true;
            break;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PomodoroCommands.unregister();
    _screenSub?.cancel();
    _timer?.cancel();
    _clockTimer?.cancel();
    _loopCtrl.dispose();
    _breathCtrl.dispose();
    _burstCtrl.dispose();
    _progCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final p = await SharedPreferences.getInstance();
    // ── Daily TF reset ─────────────────────────────────────────────────────
    final today = '${_now.year}-${_now.month}-${_now.day}';
    final savedDate = p.getString('cr_tf_date') ?? '';
    int savedTf = p.getInt('cr_tf') ?? 0;
    if (savedDate != today) {
      // New day → reset TF to 0
      savedTf = 0;
      await p.setInt('cr_tf', 0);
      await p.setString('cr_tf_date', today);
    }
    // ── Load durations ──────────────────────────────────────────────────────
    kModeDuration[_Mode.focus] = p.getInt('cr_focusSec') ?? 25 * 60;
    kModeDuration[_Mode.shortBreak] = p.getInt('cr_shortSec') ?? 5 * 60;
    kModeDuration[_Mode.longBreak] = p.getInt('cr_longSec') ?? 15 * 60;

    setState(() {
      _graceSec = p.getInt('cr_graceSec') ?? 15;
      _tf = savedTf;
      _sessions = p.getInt('cr_sessions') ?? 0;
      _gold = _tf >= 500;
      if (!_running) _remaining = _modeDuration;
    });
  }

  Future<void> _save() async {
    final today = '${_now.year}-${_now.month}-${_now.day}';
    final p = await SharedPreferences.getInstance();
    await p.setInt('cr_tf', _tf);
    await p.setString('cr_tf_date', today);
    await p.setInt('cr_sessions', _sessions);
  }

  void _animProg(double t) {
    final b = _progAnim.value;
    _progAnim = Tween<double>(
      begin: b,
      end: t,
    ).animate(CurvedAnimation(parent: _progCtrl, curve: Curves.easeOut));
    _progCtrl.forward(from: 0);
  }

  // ── Mode switch ────────────────────────────────────────────────────────────
  void _switchMode(_Mode m) {
    _timer?.cancel();
    setState(() {
      _mode = m;
      _remaining = kModeDuration[m]!;
      _running = false;
      _breach = false;
      _statusMsg = 'AWAITING ACTIVATION';
    });
    _animProg(0.0);
  }

  // ── Timer control ──────────────────────────────────────────────────────────

  void _start() {
    if (_running) return;
    HapticFeedback.mediumImpact();

    if (_mode == _Mode.focus) {
      NovaAudioService.playAsset(
        'sounds/focus_mode_engaged_block_out_all_distractions.mp3',
      );
    } else {
      NovaAudioService.playAsset('sounds/focus_session_complete.mp3');
    }

    setState(() {
      _running = true;
      _breach = false;
      _statusMsg = '◉ ACTIVE';
    });
    // Save session start to DB
    _saveSessionStart();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining > 0) {
        setState(() {
          _remaining--;
          _animProg(_progress);
        });
      } else {
        _complete();
      }
    });
  }

  Future<void> _saveSessionStart() async {
    try {
      final session = PomodoroSession(
        subjectId: _sessionSubjectId,
        topicLabel: _sessionTopicLabel,
        mode: _mode.name,
        startedAt: DateTime.now(),
        plannedSeconds: _modeDuration,
        actualSeconds: 0,
        completed: false,
      );
      _activeDbSessionId = await DatabaseHelper.instance.insertPomodoroSession(
        session.toMap(),
      );
    } catch (e) {
      debugPrint('PomodoroSession save error: $e');
    }
  }

  // Pause: hold time (do NOT reset _remaining)
  void _pause() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _statusMsg = '○ PAUSED';
    });
    // Update session with elapsed time (not completed)
    _updateSessionEnd(completed: false);
  }

  void _updateSessionEnd({required bool completed}) {
    if (_activeDbSessionId == null) return;
    final elapsed = _modeDuration - _remaining;
    DatabaseHelper.instance.updatePomodoroSession(_activeDbSessionId!, {
      'endedAt': DateTime.now().toIso8601String(),
      'actualSeconds': elapsed,
      'completed': completed ? 1 : 0,
    });
  }

  void _reset() {
    _timer?.cancel();
    _animProg(0.0);
    setState(() {
      _running = false;
      _remaining = _modeDuration;
      _breach = false;
      _statusMsg = 'AWAITING ACTIVATION';
    });
  }

  // ── Timer control ────────────────────────────────────────────────────────────
  void _toggleTimer() {
    if (_running)
      _pause();
    else
      _start();
  }

  void _skip() {
    if (_mode == _Mode.focus) {
      _switchMode(_Mode.shortBreak);
    } else {
      _switchMode(_Mode.focus);
    }
  }

  void _complete() {
    _timer?.cancel();
    _sessions++;
    _tf += 100;
    _gold = _tf >= 500;
    _burstCtrl.forward(from: 0);
    _animProg(0.0);
    NovaAudioService.playAsset('sounds/focus_session_complete.mp3');

    // Mark DB session as completed
    _updateSessionEnd(completed: true);
    _activeDbSessionId = null;

    _Mode next;
    if (_mode == _Mode.focus) {
      next = (_sessions % 4 == 0) ? _Mode.longBreak : _Mode.shortBreak;
    } else {
      next = _Mode.focus;
    }

    setState(() {
      _running = false;
      _mode = next;
      _remaining = kModeDuration[next]!;
      _statusMsg = 'SESSION COMPLETE — +100 TF';
    });
    _save();
    _burstHaptic();
  }

  Future<void> _burstHaptic() async {
    for (int i = 0; i < 5; i++) {
      await Future.delayed(Duration(milliseconds: i * 100));
      if (mounted) HapticFeedback.heavyImpact();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_screenOn) _awayStart ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_awayStart != null) {
        final elapsed = DateTime.now().difference(_awayStart!);
        _awayStart = null;
        if (elapsed.inSeconds > _graceSec) {
          _triggerBreach(elapsed.inSeconds);
        } else {
          setState(() {
            _remaining = (_remaining - elapsed.inSeconds).clamp(
              0,
              _cfg.duration,
            );
          });
        }
      }
    }
  }

  void _triggerBreach(int secondsAway) {
    _timer?.cancel();
    _tf = (_tf - 50).clamp(0, 999999);
    _gold = _tf >= 500;
    _animProg(0.0);
    _burstHaptic();
    setState(() {
      _running = false;
      _remaining = _modeDuration;
      _breach = true;
      _glitch = true;
      _statusMsg = '⚠ BREACH — ${secondsAway}s ABSENT — -50 TF';
    });
    _save();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _glitch = false);
    });
    Future.delayed(const Duration(seconds: 7), () {
      if (mounted)
        setState(() {
          _breach = false;
          _statusMsg = 'AWAITING ACTIVATION';
        });
    });
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  String _graceLabel(int sec) {
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  void _openSettings() {
    int tmpG = _graceSec;
    int tmpFocus = kModeDuration[_Mode.focus]!;
    int tmpShort = kModeDuration[_Mode.shortBreak]!;
    int tmpLong = kModeDuration[_Mode.longBreak]!;
    final graceCtrl = TextEditingController(text: '$tmpG');
    final focusCtrl = TextEditingController(text: '${tmpFocus ~/ 60}');
    final shortCtrl = TextEditingController(text: '${tmpShort ~/ 60}');
    final longCtrl = TextEditingController(text: '${tmpLong ~/ 60}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF060810),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
        side: BorderSide(color: Color(0xFF00FF41), width: 1),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            28,
            24,
            28,
            MediaQuery.of(ctx).viewInsets.bottom + 44,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SYSTEM CONFIGURATION',
                  style: TextStyle(
                    color: Color(0xFF00FF41),
                    fontFamily: 'Courier',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Session durations ──────────────────────────────────────
                const Text(
                  'SESSION DURATIONS (minutes)',
                  style: TextStyle(
                    color: Color(0xFF4A607A),
                    fontFamily: 'Courier',
                    fontSize: 9,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _durationField(
                        'FOCUS',
                        focusCtrl,
                        const Color(0xFF00FF41),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _durationField(
                        'SHORT\nBREAK',
                        shortCtrl,
                        const Color(0xFF00FF88),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _durationField(
                        'LONG\nBREAK',
                        longCtrl,
                        const Color(0xFFFF8C00),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                // ── Absence threshold ──────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      'ABSENCE THRESHOLD',
                      style: TextStyle(
                        color: Color(0xFF4A607A),
                        fontFamily: 'Courier',
                        fontSize: 9,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _graceLabel(tmpG),
                      style: const TextStyle(
                        color: Color(0xFF00FF41),
                        fontFamily: 'Courier',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Slider: 2s → 1800s (30 min), log-ish ticks
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    activeTrackColor: const Color(0xFF00FF41),
                    inactiveTrackColor: const Color(0xFF172040),
                    thumbColor: const Color(0xFF00FF41),
                    overlayColor: const Color(0xFF00FF4119),
                  ),
                  child: Slider(
                    value: tmpG.toDouble().clamp(2, 1800),
                    min: 2,
                    max: 1800,
                    divisions: 100,
                    onChanged: (v) {
                      set(() => tmpG = v.round());
                      graceCtrl.text = '${v.round()}';
                    },
                  ),
                ),
                // Manual text input for grace
                TextField(
                  controller: graceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Color(0xFF00FF41),
                    fontFamily: 'Courier',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Grace (seconds)',
                    labelStyle: const TextStyle(
                      color: Color(0xFF4A607A),
                      fontFamily: 'Courier',
                      fontSize: 10,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF172040)),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF00FF41)),
                    ),
                    suffixText: 'max 1800',
                    suffixStyle: const TextStyle(
                      color: Color(0xFF4A607A),
                      fontFamily: 'Courier',
                      fontSize: 9,
                    ),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null) {
                      set(() => tmpG = parsed.clamp(2, 1800));
                    }
                  },
                ),

                const SizedBox(height: 20),
                // ── TF Tier rewards ────────────────────────────────────────
                const Text(
                  'TF REWARD TIERS  (resets daily)',
                  style: TextStyle(
                    color: Color(0xFF4A607A),
                    fontFamily: 'Courier',
                    fontSize: 9,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                _tierRow('0 → 199 TF', 'BASE', const Color(0xFF00FF41)),
                _tierRow(
                  '200 → 499 TF',
                  'PRO  — silver ring',
                  const Color(0xFFB0BEC5),
                ),
                _tierRow(
                  '500 → 999 TF',
                  'GOLD — golden theme',
                  const Color(0xFFFFD54F),
                ),
                _tierRow(
                  '1000+ TF',
                  'LEGENDARY — rainbow pulse',
                  const Color(0xFFFF6B6B),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    'Today: $_tf TF  |  Tier: $_tierLabel',
                    style: TextStyle(
                      color: _tierColor,
                      fontFamily: 'Courier',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _cfgBtn(
                        'APPLY',
                        const Color(0xFF00FF41),
                        () async {
                          // Parse durations
                          final fMin = int.tryParse(focusCtrl.text) ?? 25;
                          final sMin = int.tryParse(shortCtrl.text) ?? 5;
                          final lMin = int.tryParse(longCtrl.text) ?? 15;
                          final focusSec = fMin.clamp(1, 180) * 60;
                          final shortSec = sMin.clamp(1, 60) * 60;
                          final longSec = lMin.clamp(1, 120) * 60;
                          final graceSec = tmpG.clamp(2, 1800);

                          final p = await SharedPreferences.getInstance();
                          await p.setInt('cr_focusSec', focusSec);
                          await p.setInt('cr_shortSec', shortSec);
                          await p.setInt('cr_longSec', longSec);
                          await p.setInt('cr_graceSec', graceSec);

                          setState(() {
                            kModeDuration[_Mode.focus] = focusSec;
                            kModeDuration[_Mode.shortBreak] = shortSec;
                            kModeDuration[_Mode.longBreak] = longSec;
                            _graceSec = graceSec;
                            if (!_running) _remaining = _modeDuration;
                          });
                          if (mounted) Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _cfgBtn(
                        'RESET TF',
                        const Color(0xFFF44336),
                        () async {
                          final p = await SharedPreferences.getInstance();
                          await p.setInt('cr_tf', 0);
                          setState(() {
                            _tf = 0;
                            _gold = false;
                          });
                          if (mounted) Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _durationField(
    String label,
    TextEditingController ctrl,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'Courier',
          fontSize: 8,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontFamily: 'Courier',
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 4,
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: color.withOpacity(0.4)),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: color),
          ),
        ),
      ),
    ],
  );

  Widget _tierRow(String range, String label, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color, blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          range,
          style: const TextStyle(
            color: Color(0xFF4A607A),
            fontFamily: 'Courier',
            fontSize: 9,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'Courier',
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _cfgBtn(String label, Color c, VoidCallback fn) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: c,
      side: BorderSide(color: c),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: const RoundedRectangleBorder(),
    ),
    onPressed: fn,
    child: Text(
      label,
      style: TextStyle(
        color: c,
        fontFamily: 'Courier',
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        fontSize: 12,
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    Widget page = Scaffold(
      backgroundColor: const Color(0xFF0A0E16), // neon circuit board bg
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _loopCtrl,
          _breathCtrl,
          _burstCtrl,
          _progAnim,
        ]),
        builder: (context, _) {
          final color = _currentColor;
          final secondary = _breach ? const Color(0xFFFF0080) : _cfg.secondary;
          final prog = _progAnim.value;

          return Stack(
            children: [
              // ── Rain drops ──────────────────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: RainPainter(
                    drops: _rain,
                    t: _loopCtrl.value,
                    color: color,
                  ),
                ),
              ),

              // ── Data particles ──────────────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: ParticlePainter(
                    particles: _particles,
                    t: _loopCtrl.value,
                    color: color,
                  ),
                ),
              ),

              // ── Animated grid ───────────────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(t: _loopCtrl.value, color: color),
                ),
              ),

              // ── Radial glow ─────────────────────────────────────────────────
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 600,
                    height: 600,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          color.withOpacity(0.08 + 0.06 * _breathCtrl.value),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Content ─────────────────────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    _buildTopHud(color),
                    Expanded(child: _buildBody(color, secondary, prog)),
                    _buildBottomScanline(color),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    if (_glitch) page = GlitchWidget(child: page);
    return page;
  }

  // ── TOP HUD BAR ────────────────────────────────────────────────────────────
  Widget _buildTopHud(Color color) {
    // 12-hour AM/PM format
    final h12 = _now.hour == 0
        ? 12
        : _now.hour > 12
        ? _now.hour - 12
        : _now.hour;
    final amPm = _now.hour < 12 ? 'AM' : 'PM';
    final timeStr =
        '${h12.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')} $amPm';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Icon(
              Icons.arrow_back_ios_rounded,
              color: color.withOpacity(0.6),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // System Online dot
          AnimatedBuilder(
            animation: _breathCtrl,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color,
                    blurRadius: 6 + 4 * _breathCtrl.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'SYSTEM ONLINE',
            style: TextStyle(
              color: color,
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
          Container(
            width: 1,
            height: 14,
            color: color.withOpacity(0.3),
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Text(
            'ID: PMD-${_sessions.toString().padLeft(4, '0')}',
            style: const TextStyle(
              color: Color(0xFF00FF41),
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          Text(
            timeStr,
            style: TextStyle(
              color: color,
              fontFamily: 'Courier',
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _openSettings,
            child: Icon(Icons.tune, color: color.withOpacity(0.6), size: 18),
          ),
        ],
      ),
    );
  }

  // ── BODY ───────────────────────────────────────────────────────────────────
  Widget _buildBody(Color color, Color secondary, double prog) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;
        if (isNarrow) return _buildMobileLayout(color, secondary, prog);
        return _buildWideLayout(color, secondary, prog);
      },
    );
  }

  // ── MOBILE LAYOUT (single column) ─────────────────────────────────────────
  Widget _buildMobileLayout(Color color, Color secondary, double prog) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Mode label
          Text(
            _cfg.label,
            style: TextStyle(
              color: color,
              fontFamily: 'Courier',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              shadows: [
                Shadow(color: color, blurRadius: 20),
                Shadow(color: color, blurRadius: 40),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── MISSION CONTEXT panel ──
          _buildSessionContextPanel(color),
          const SizedBox(height: 12),
          // Arc reactor timer
          _buildArcReactor(color, secondary, prog, size: 300),
          const SizedBox(height: 20),
          // Status + controls
          _buildStatusBadge(color),
          const SizedBox(height: 20),
          _buildControls(color, secondary),
          const SizedBox(height: 20),
          // Mode selector
          _buildModeSelector(color),
          const SizedBox(height: 16),
          // Stats row
          _buildStatsRow(color),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Session Context Panel ─────────────────────────────────────────────
  Widget _buildSessionContextPanel(Color color) {
    final appState = context.read<AppBloc>().state;
    final subjects = appState.subjects;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1020),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                'MISSION CONTEXT',
                style: TextStyle(
                  color: color,
                  fontFamily: 'Courier',
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (_sessionSubjectId != null ||
                  (_sessionTopicLabel?.isNotEmpty ?? false))
                GestureDetector(
                  onTap: () => setState(() {
                    _sessionSubjectId = null;
                    _sessionTopicLabel = null;
                  }),
                  child: Icon(
                    Icons.clear,
                    color: color.withValues(alpha: 0.6),
                    size: 14,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Subject dropdown
          if (subjects.isNotEmpty)
            DropdownButtonFormField<int?>(
              value: _sessionSubjectId,
              dropdownColor: const Color(0xFF0A1020),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                labelText: 'Subject',
                labelStyle: TextStyle(
                  color: color.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              style: TextStyle(
                color: color,
                fontFamily: 'Courier',
                fontSize: 13,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text(
                    '— None —',
                    style: TextStyle(
                      color: Colors.white38,
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                  ),
                ),
                ...subjects.map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: _running
                  ? null
                  : (v) => setState(() => _sessionSubjectId = v),
            ),
          const SizedBox(height: 8),
          // Topic label text field
          TextFormField(
            initialValue: _sessionTopicLabel,
            enabled: !_running,
            style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              labelText: 'Topic / Lecture (optional)',
              labelStyle: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 12,
              ),
              hintText: 'e.g. Lecture 3 – Flip Flops',
              hintStyle: TextStyle(
                color: color.withValues(alpha: 0.25),
                fontSize: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: color),
                borderRadius: BorderRadius.circular(6),
              ),
              disabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: color.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onChanged: (v) =>
                _sessionTopicLabel = v.trim().isEmpty ? null : v.trim(),
          ),
        ],
      ),
    );
  }

  // ── WIDE LAYOUT (3-column) ─────────────────────────────────────────────────
  Widget _buildWideLayout(Color color, Color secondary, double prog) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left panel
          SizedBox(width: 180, child: _buildLeftPanel(color, prog)),
          const SizedBox(width: 16),
          // Center
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _cfg.label,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'Courier',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    shadows: [
                      Shadow(color: color, blurRadius: 20),
                      Shadow(color: color, blurRadius: 40),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildArcReactor(color, secondary, prog, size: 280),
                const SizedBox(height: 16),
                _buildStatusBadge(color),
                const SizedBox(height: 20),
                _buildControls(color, secondary),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right panel
          SizedBox(width: 180, child: _buildRightPanel(color, prog)),
        ],
      ),
    );
  }

  // ── LEFT PANEL ─────────────────────────────────────────────────────────────
  Widget _buildLeftPanel(Color color, double prog) {
    final efficiency = (70 + _sessions * 2).clamp(0, 95);
    final focusVal = _running ? 100 : 50;
    final energyVal = (100 - prog * 100).clamp(30.0, 100.0);

    return Column(
      children: [
        _hudPanel(color, 'SYSTEM STATUS', [
          _hudRow('MODE', _cfg.label, color),
          _hudRow('STATE', _running ? 'ACTIVE' : 'STANDBY', color),
          _hudRow('SESSIONS', '$_sessions', color),
          _hudRow('TF UNITS', '$_tf', color),
        ]),
        const SizedBox(height: 12),
        _hudPanel(color, 'PROTOCOL', [
          Text(
            _cfg.systemName,
            style: const TextStyle(
              color: Color(0xFF4A607A),
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          // Mini segment bar
          Row(
            children: List.generate(8, (i) {
              final filled = i < (prog * 8).round();
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: filled ? color : const Color(0xFF1A1A1A),
                    boxShadow: filled
                        ? [BoxShadow(color: color, blurRadius: 4)]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ]),
        const SizedBox(height: 12),
        _hudPanel(color, 'METRICS', [
          _metricBar('EFFICIENCY', efficiency / 100, color),
          const SizedBox(height: 6),
          _metricBar('FOCUS', focusVal / 100, color),
          const SizedBox(height: 6),
          _metricBar('ENERGY', energyVal / 100, color),
        ]),
      ],
    );
  }

  // ── RIGHT PANEL ────────────────────────────────────────────────────────────
  Widget _buildRightPanel(Color color, double prog) {
    return Column(
      children: [
        _buildModeSelector(color),
        const SizedBox(height: 12),
        _hudPanel(color, 'COMPLETED SESSIONS', [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(
              _sessions.clamp(0, 16),
              (i) => Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF00FF41),
                    width: 1.5,
                  ),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00FF41).withOpacity(0.12),
                      Colors.transparent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Color(0xFF00FF41),
                    fontFamily: 'Courier',
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          if (_sessions > 16)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${_sessions - 16} more',
                style: const TextStyle(
                  color: Color(0xFF00FF41),
                  fontFamily: 'Courier',
                  fontSize: 9,
                ),
              ),
            ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _breathCtrl,
            builder: (_, __) => Text(
              '$_sessions',
              style: TextStyle(
                color: const Color(0xFF00FF41),
                fontFamily: 'Courier',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                    color: const Color(0xFF00FF41),
                    blurRadius: 10 + 10 * _breathCtrl.value,
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _hudPanel(color, 'DIAGNOSTICS', [
          _hudRow('UPTIME', 'OPTIMAL', const Color(0xFF69F0AE)),
          _hudRow('LATENCY', '0.3ms', const Color(0xFF69F0AE)),
          _hudRow('SYNC', '100%', const Color(0xFF69F0AE)),
          _hudRow('GRACE', '${_graceSec}s', const Color(0xFF00FF41)),
        ]),
      ],
    );
  }

  // ── MODE SELECTOR ──────────────────────────────────────────────────────────
  Widget _buildModeSelector(Color color) {
    final modes = [_Mode.focus, _Mode.shortBreak, _Mode.longBreak];
    final icons = [Icons.psychology, Icons.coffee, Icons.battery_charging_full];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'SELECT MODE',
            style: TextStyle(
              color: color,
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
        ),
        ...List.generate(modes.length, (index) {
          final m = modes[index];
          final mc = kModeConfig[m]!;
          final selected = _mode == m;
          return GestureDetector(
            onTap: () => _switchMode(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? mc.color : mc.color.withOpacity(0.25),
                  width: selected ? 1.5 : 1,
                ),
                color: selected
                    ? mc.color.withOpacity(0.1)
                    : mc.color.withOpacity(0.03),
              ),
              child: Row(
                children: [
                  Icon(icons[index], color: mc.color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mc.label,
                          style: TextStyle(
                            color: selected
                                ? mc.color
                                : const Color(0xFF4A607A),
                            fontFamily: 'Courier',
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '${mc.duration ~/ 60}:00',
                          style: const TextStyle(
                            color: Color(0xFF333355),
                            fontFamily: 'Courier',
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.radio_button_checked, color: mc.color, size: 12),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── ARC REACTOR TIMER ──────────────────────────────────────────────────────
  Widget _buildArcReactor(
    Color color,
    Color secondary,
    double prog, {
    required double size,
  }) {
    final mins = (_remaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_remaining % 60).toString().padLeft(2, '0');

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer rotating rings
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _loopCtrl,
              builder: (_, __) => CustomPaint(
                painter: RingsPainter(
                  loop: _loopCtrl.value,
                  color: color,
                  secondary: secondary,
                ),
              ),
            ),
          ),

          // Arc reactor core + progress ring
          Positioned(
            left: size * 0.1,
            top: size * 0.1,
            right: size * 0.1,
            bottom: size * 0.1,
            child: CustomPaint(
              painter: CorePainter(
                progress: prog,
                color: color,
                secondary: secondary,
                breath: _breathCtrl.value,
                burst: _burstCtrl.value,
              ),
            ),
          ),

          // Corner HUD brackets
          ...([
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomRight,
            Alignment.bottomLeft,
          ].mapIndexed(
            (align, i) => Align(
              alignment: align,
              child: SizedBox(
                width: 36,
                height: 36,
                child: CustomPaint(
                  painter: BracketPainter(corner: i, color: color),
                ),
              ),
            ),
          )),

          // Clean, readable timer display
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$mins:$secs',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.22,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: color, blurRadius: 18),
                    Shadow(color: color, blurRadius: 36),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(prog * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontFamily: 'Courier',
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── STATUS BADGE ───────────────────────────────────────────────────────────
  Widget _buildStatusBadge(Color color) {
    return AnimatedBuilder(
      animation: _breathCtrl,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.6)),
          color: color.withOpacity(0.08),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1 + 0.1 * _breathCtrl.value),
              blurRadius: 15,
            ),
          ],
        ),
        child: Text(
          _running ? '◉ ACTIVE' : _statusMsg,
          style: TextStyle(
            color: color,
            fontFamily: 'Courier',
            fontSize: 11,
            letterSpacing: 3,
            shadows: [Shadow(color: color, blurRadius: 8)],
          ),
        ),
      ),
    );
  }

  // ── CONTROLS ───────────────────────────────────────────────────────────────
  Widget _buildControls(Color color, Color secondary) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _controlBtn(Icons.replay_rounded, color, _reset, small: true),
        const SizedBox(width: 20),
        _controlBtn(
          _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color,
          _toggleTimer,
          small: false,
        ),
        const SizedBox(width: 20),
        _controlBtn(Icons.skip_next_rounded, color, _skip, small: true),
      ],
    );
  }

  Widget _controlBtn(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    required bool small,
  }) {
    final size = small ? 52.0 : 72.0;
    final iconSize = small ? 22.0 : 32.0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _breathCtrl,
        builder: (_, __) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withOpacity(small ? 0.5 : 0.9),
              width: small ? 1 : 2,
            ),
            color: color.withOpacity(small ? 0.05 : 0.12),
            boxShadow: small
                ? null
                : [
                    BoxShadow(
                      color: color.withOpacity(0.2 + 0.15 * _breathCtrl.value),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
          ),
          child: Icon(icon, color: color, size: iconSize),
        ),
      ),
    );
  }

  // ── STATS ROW ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow(Color color) {
    final tier = _gold ? 'GOLD' : (_tf >= 200 ? 'PRO' : 'BASE');
    return Row(
      children: [
        _kv('SESSIONS', '$_sessions', color),
        _sep(),
        _kv('TF UNITS', '$_tf', color),
        _sep(),
        _kv('TIER', tier, color),
        _sep(),
        _kv('GRACE', '${_graceSec}s', color),
      ],
    );
  }

  Widget _kv(String k, String v, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          k,
          style: const TextStyle(
            color: Color(0xFF4A607A),
            fontFamily: 'Courier',
            fontSize: 7,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          v,
          style: TextStyle(
            color: color,
            fontFamily: 'Courier',
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _sep() =>
      Container(width: 1, height: 22, color: const Color(0xFF172040));

  // ── BOTTOM SCANLINE ────────────────────────────────────────────────────────
  Widget _buildBottomScanline(Color color) {
    return AnimatedBuilder(
      animation: _breathCtrl,
      builder: (_, __) => Container(
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, color, Colors.transparent],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4 + 0.4 * _breathCtrl.value),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }

  // ── HUD PANEL ──────────────────────────────────────────────────────────────
  Widget _hudPanel(Color color, String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF00FF41).withOpacity(0.25)),
        color: const Color(0xFF00FF41).withOpacity(0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top glow line
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, color, Colors.transparent],
              ),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _hudRow(String k, String v, Color vColor) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Text(
          k,
          style: const TextStyle(
            color: Color(0xFF4A607A),
            fontFamily: 'Courier',
            fontSize: 9,
          ),
        ),
        const Spacer(),
        Text(
          v,
          style: TextStyle(
            color: vColor,
            fontFamily: 'Courier',
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _metricBar(String label, double value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4A607A),
              fontFamily: 'Courier',
              fontSize: 8,
            ),
          ),
          const Spacer(),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 8),
          ),
        ],
      ),
      const SizedBox(height: 3),
      ClipRRect(
        child: Container(
          height: 3,
          decoration: const BoxDecoration(color: Color(0xFF1A1A1A)),
          child: FractionallySizedBox(
            widthFactor: value,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                boxShadow: [BoxShadow(color: color, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EXTENSION HELPERS
// ─────────────────────────────────────────────────────────────────────────────

extension _IndexedMap<T> on List<T> {
  List<R> mapIndexed<R>(R Function(T, int) fn) {
    return List.generate(length, (i) => fn(this[i], i));
  }
}
