import 'dart:async';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:study_organizer/models/topic.dart';
import 'package:study_organizer/pages/notif_diagnostic_page.dart';
import 'package:study_organizer/pages/subject_detail.dart';
import 'package:study_organizer/services/ai_service.dart';
import 'package:flutter/services.dart';
import 'package:study_organizer/services/class_alarm_service.dart';
import 'package:study_organizer/widgets/nova_brief_card.dart';

import '../services/nova_watchdog_service.dart';
import '../services/nova_brief_service.dart';
import '../services/nova_location_service.dart';
import '../services/nova_audio_service.dart';
import '../services/NovaElevenLabsService.dart';
import 'nova_settings_page.dart';

import 'daily_schedule_page.dart';

import '../models/subject.dart';
import '../models/task.dart';
import '../models/timetable.dart';
import '../models/reminder.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_event.dart';
import '../bloc/app_state.dart';
import '../services/notifications.dart';
import '../widgets/glass.dart';
import '../widgets/atext.dart';
import '../widgets/helpers.dart';
import '../widgets/jarvis_overlay.dart';
import '../widgets/layering_system_overlay.dart';

class CampusPage extends StatefulWidget {
  const CampusPage({super.key});
  @override
  State<CampusPage> createState() => _CampusPageState();
}

class _CampusPageState extends State<CampusPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, String>> _chatHistory = [];
  final TextEditingController _chatController = TextEditingController();
  bool _isAiTyping = false;
  late ConfettiController _confettiC;
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // ── NOVA Brief system ──────────────────────────────────────────────────────
  // Platform channel for volume-key interception (set up in MainActivity.kt)
  static const _volumeChannel = MethodChannel(
    'com.example.study_organizer/volume_key',
  );
  bool _briefSpeaking = false; // true while TTS speaks a brief
  bool _atHome = false; // updated each resume via NovaBriefService

  // ── Wake Word — handled by NovaVadService (native AudioRecord, zero beeps) ──

  // ═══════════════════════════════════════════
  // CLASS-TIME REFRESH
  // ═══════════════════════════════════════════
  // Fires a setState exactly when a class starts or ends so the banner
  // updates without polling.  Only next upcoming start/end is scheduled.
  final List<Timer> _classRefreshTimers = [];

  void _scheduleClassRefresh(List<TimetableEntry> entries) {
    // Cancel any pending timers first
    for (final t in _classRefreshTimers) t.cancel();
    _classRefreshTimers.clear();

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    // Collect all class start and end times as minutes-of-day
    final List<int> triggerMins = [];
    for (final e in entries) {
      for (final timeStr in [e.startTime, e.endTime]) {
        final parts = timeStr.split(':');
        if (parts.length < 2) continue;
        final m = int.tryParse(parts[0]);
        final s = int.tryParse(parts[1]);
        if (m == null || s == null) continue;
        final totalMin = m * 60 + s;
        if (totalMin > nowMin) triggerMins.add(totalMin);
      }
    }
    if (triggerMins.isEmpty) return;

    // Schedule a one-shot timer for every upcoming class boundary
    for (final targetMin in triggerMins) {
      final delayMin = targetMin - nowMin;
      if (delayMin <= 0) continue;
      // Add 5s buffer so we fire just AFTER the boundary
      final delay = Duration(minutes: delayMin, seconds: 5);
      _classRefreshTimers.add(
        Timer(delay, () {
          if (mounted) setState(() {}); // Force banner recalculation
        }),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _confettiC = ConfettiController(duration: const Duration(seconds: 5));
    WidgetsBinding.instance.addObserver(this);
    _initTTS();
    // _initVad();
    _checkCelebration();
    _setupVolumeKeyListener();
    NovaBriefService.loadPersistedBrief(); // Restore card from last session
    novaSpeak.value = () {
      _speakBriefOnDemand();
    }; // Register TTS callback for card

    // ═══ Listen for notification actions (Read My Day + Urgent Task) ═══
    NotifService.onActionReceived = (payload, actionId) {
      debugPrint('🔔 Action received: payload=$payload, actionId=$actionId');

      // ── Read My Day from notification buttons ──
      if (actionId == 'read_en' || actionId == 'read_ar') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final state = context.read<AppBloc>().state;
            final lang = actionId == 'read_ar' ? 'ar' : 'en';
            _readMyDay(context, state, lang);
          }
        });
      }

      // ── Urgent task "Working on it" from notification button ──
      if (actionId == 'ack_task' && payload.startsWith('urgent:')) {
        final taskIdStr = payload.replaceFirst('urgent:', '');
        final taskId = int.tryParse(taskIdStr);
        if (taskId != null) {
          NotifService.stopUrgentTaskReminder(taskId);
          debugPrint('✅ Stopped urgent reminders for task $taskId');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.read<AppBloc>().add(SetTaskWorking(taskId, true));
            }
          });
        }
      }

      // ── Read My Day from payload tap (not action button) ──
      if (payload == 'read_my_day:choose' && actionId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showReadMyDayPicker();
          }
        });
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppBloc>().state;
      _scheduleEndOfDayNotification(state);
      _rescheduleNotificationsOnStart(state);
      ClassAlarmService.start();
      // Schedule precise class-time refresh timers for today
      final todayDow = DateTime.now().weekday;
      final todayEntries = state.timetable
          .where(
            (e) =>
                e.dayOfWeek == todayDow &&
                (e.weekType == 'both' || e.weekType == state.currentWeekType),
          )
          .toList();
      _scheduleClassRefresh(todayEntries);
    });
  }

  // ── Shows language picker when notification body is tapped (not a button) ──
  void _showReadMyDayPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.headphones_rounded, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text('Read My Day'),
          ],
        ),
        content: const Text('Choose language for your daily briefing:'),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              final state = context.read<AppBloc>().state;
              _readMyDay(context, state, 'en');
            },
            icon: const Icon(Icons.volume_up_rounded, size: 18),
            label: const Text('English'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              final state = context.read<AppBloc>().state;
              _readMyDay(context, state, 'ar');
            },
            icon: const Icon(Icons.volume_up_rounded, size: 18),
            label: const Text('عربي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2ED573),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Native VAD wake-word init ─────────────────────────────────────────────
  // Uses NovaVadService: native AudioRecord (silent) → Whisper burst → keyword check.
  // Zero system sounds. The mic stays open via AudioRecord, not SpeechRecognizer.
  // void _initVad() {
  //   //NovaVadService.startWithStartupWindow(
  //     onWakeWord: () {
  //       if (!mounted) return;
  //       Future.delayed(const Duration(milliseconds: 300), () {
  //         if (!mounted) return;
  //         JarvisOverlay.show(
  //           context,
  //           autoListen: true,
  //         );
  //       });
  //     },
  //     onDismissed: () {
  //       // VAD stopped by voice — silent, nothing to do
  //       debugPrint('[CampusPage] VAD dismissed by voice command');
  //     },
  //   );
  // }

  // /// Call from JarvisOverlay's onDismiss callback so VAD resumes silently.
  // void onJarvisOverlayClosed() {
  //   // NovaVadService.resumeAfterJarvis();
  // }

  // // Add this method in _CampusPageState
  void _rescheduleTimetableNotifs(AppState state) {
    final subjectNames = <int, String>{};
    for (final s in state.subjects) {
      if (s.id != null) subjectNames[s.id!] = s.name;
    }
    NotifService.scheduleTimetableNotifs(
      entries: state.timetable,
      subjectNames: subjectNames,
      currentWeekType: state.currentWeekType,
      tasks: state.tasks,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // ── Always refresh class banner on resume (fixes stale LIVE state) ──
    if (state == AppLifecycleState.resumed) {
      setState(() {}); // recalculate now vs class times instantly
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final appState = context.read<AppBloc>().state;
          final todayDow = DateTime.now().weekday;
          final todayEntries = appState.timetable
              .where(
                (e) =>
                    e.dayOfWeek == todayDow &&
                    (e.weekType == 'both' ||
                        e.weekType == appState.currentWeekType),
              )
              .toList();
          _scheduleClassRefresh(todayEntries);
          // ── NOVA brief trigger ──────────────────────────────────────────
          _triggerNovaBrief(appState);
          // ── Distraction Guard: instant check when user returns to app ───
          NovaWatchdogService.runCheck();
        }
      });
    }
  }

  void _rescheduleNotificationsOnStart(AppState state) {
    try {
      final subjectNames = <int, String>{};
      for (final s in state.subjects) {
        if (s.id != null) subjectNames[s.id!] = s.name;
      }
      NotifService.scheduleTimetableNotifs(
        entries: state.timetable,
        subjectNames: subjectNames,
        currentWeekType: state.currentWeekType,
        tasks: state.tasks,
      );
      NotifService.rescheduleAllReminders(state.reminders);
      NotifService.scheduleReadMyDayNotif(
        allEntries: state.timetable,
        currentWeekType: state.currentWeekType,
      );
    } catch (e) {
      debugPrint('Auto-reschedule on start error: $e');
    }
  }

  Future<void> _initTTS() async {
    await _tts.setLanguage('en-US'); // Brief always in English (per plan)
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    // Completion callback so we can clear speaking flag
    _tts.setCompletionHandler(() {
      NovaBriefService.onBriefFinishedSpeaking();
      if (mounted) setState(() => _briefSpeaking = false);
    });
  }

  // ── Volume key channel (set up in MainActivity.kt) ────────────────────────
  void _setupVolumeKeyListener() {
    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method == 'volumeUp') {
        // Stop ElevenLabs TTS on volume up
        await NovaElevenLabsService.stop();
        await NovaAudioService.stop();
        if (_briefSpeaking) {
          await _tts.stop();
          NovaBriefService.onVolumeUpDuringSpeech();
          if (mounted) setState(() => _briefSpeaking = false);
        }
      } else if (call.method == 'volumeDown' || call.method == 'onVolumeDown') {
        // Stop ElevenLabs TTS on volume down
        await NovaElevenLabsService.stop();
        await NovaAudioService.stop();
        if (_briefSpeaking) {
          await _tts.stop();
          if (mounted) setState(() => _briefSpeaking = false);
        }
      }
    });
  }

  // ── NOVA brief trigger ────────────────────────────────────────────────────
  bool? _lastKnownAtHome;

  Future<void> _triggerNovaBrief(dynamic appState) async {
    // Check home location (fast, 5s timeout — falls back to false on failure)
    _atHome = await NovaLocationService.isAtHome();

    if (_lastKnownAtHome != null && _lastKnownAtHome != _atHome) {
      if (_atHome) {
        NovaAudioService.playAsset(
          'sounds/welcome_home_sir_shall_I_prepare_the_evening_review.mp3',
        );
      } else {
        NovaAudioService.playAsset(
          'sounds/we_have_arrived_at_the_aiet_campus.mp3',
        );
      }
    }
    _lastKnownAtHome = _atHome;

    final briefToSpeak = await NovaBriefService.onAppResumed(
      subjects: appState.subjects,
      tasks: appState.tasks,
      timetable: appState.timetable,
      absences: appState.absences,
      topics: appState.topics,
      currentWeekType: appState.currentWeekType,
      isAtHome: _atHome,
    );

    if (!mounted) return;

    if (briefToSpeak != null) {
      // At home + cooldown elapsed → speak aloud
      setState(() => _briefSpeaking = true);
      NovaBriefService.onBriefStartedSpeaking();
      await _tts.setLanguage('en-US');
      await _tts.speak(briefToSpeak);
    } else if (novaBriefText.value != null && !_atHome) {
      // Not at home → brief card is visible, show "tap to hear" banner
      novaBriefPausedBanner.value = novaBriefText.value;
      // Auto-clear banner after 6 s (same as volume-dismiss)
      Future.delayed(const Duration(seconds: 6), () {
        novaBriefPausedBanner.value = null;
      });
    }
  }

  // ── Speak brief on demand (card "HEAR BRIEF" button) ─────────────────────
  Future<void> _speakBriefOnDemand() async {
    final text = novaBriefText.value;
    if (text == null || _briefSpeaking) return;
    setState(() => _briefSpeaking = true);
    NovaBriefService.onBriefStartedSpeaking();
    await _tts.setLanguage('en-US');
    await _tts.speak(text);
  }

  Future<void> _checkCelebration() async {
    final prefs = await SharedPreferences.getInstance();
    final show = prefs.getBool('show_celebration') ?? false;
    if (show) {
      await prefs.setBool('show_celebration', false);
      if (mounted) _showLegendaryOverlay();
    }
  }

  void _showLegendaryOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          LegendaryCelebrationOverlay(onDismiss: () => Navigator.pop(ctx)),
    );
  }

  String _formatTo12H(String time24) {
    try {
      final dt = intl.DateFormat("HH:mm").parse(time24);
      return intl.DateFormat("hh:mm a").format(dt);
    } catch (e) {
      return time24;
    }
  }

  @override
  void dispose() {
    // NovaVadService.stop();
    _confettiC.dispose();
    for (final t in _classRefreshTimers) t.cancel();
    _classRefreshTimers.clear();
    _tts.stop();
    novaSpeak.value = null; // Unregister brief callback
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DefaultTabController(
          length: 6,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Campus'),
              actions: [
                // ── NOVA quick-access buttons ──────────────────────────────
                IconButton(
                  icon: const Icon(Icons.tune_rounded, color: Colors.white54),
                  tooltip: 'NOVA Settings',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NovaSettingsPage()),
                  ),
                ),
                // Add this to your existing AppBar actions:
                IconButton(
                  icon: const Icon(Icons.bug_report_rounded, color: Colors.white54),
                  tooltip: 'Notification Diagnostics',
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NotifDiagnosticPage())),
                ),
              ],
              bottom: const TabBar(
                indicatorColor: Color(0xFF6C63FF),
                labelColor: Color(0xFF6C63FF),
                isScrollable: true,
                tabs: [
                  Tab(
                    text: 'Advisor',
                    icon: Icon(Icons.psychology_rounded, size: 18),
                  ),
                  Tab(
                    text: 'Study',
                    icon: Icon(Icons.school_rounded, size: 18),
                  ),
                  Tab(
                    text: 'Timetable',
                    icon: Icon(Icons.schedule_rounded, size: 18),
                  ),
                  Tab(
                    text: 'Reminders',
                    icon: Icon(Icons.alarm_rounded, size: 18),
                  ),
                  Tab(
                    text: 'RPG',
                    icon: Icon(Icons.emoji_events_rounded, size: 18),
                  ),
                  Tab(
                    text: 'Backup',
                    icon: Icon(Icons.backup_outlined, size: 18),
                  ),
                ],
              ),
            ),
            body: BlocListener<AppBloc, AppState>(
              listener: (context, state) => _checkCelebration(),
              child: BlocBuilder<AppBloc, AppState>(
                builder: (ctx, state) {
                  return TabBarView(
                    children: [
                      _advisorTab(ctx, state),
                      _studyTab(ctx, state),
                      _timetableTab(ctx, state),
                      _remindersTab(ctx, state),
                      _rpgTab(ctx, state),
                      _backupTab(ctx),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiC,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [
              Color(0xFF6C63FF),
              Color(0xFF2ED573),
              Color(0xFFFF9F43),
              Color(0xFFFF4757),
              Color(0xFFFF6B81),
            ],
            numberOfParticles: 30,
          ),
        ),
        // JarvisFab removed — use "Second Brain" button in Advisor tab
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 🧠 ADVISOR TAB (unchanged)
  // ═══════════════════════════════════════════
  Widget _advisorTab(BuildContext ctx, AppState state) {
    final subjectAnalysis = <String, Map<String, dynamic>>{};
    for (var s in state.subjects) {
      final sMarks = state.marks.where((m) => m.subjectId == s.id).toList();
      if (sMarks.isNotEmpty) {
        double obtained = sMarks.fold(0, (sum, m) => sum + m.obtained);
        double total = sMarks.fold(0, (sum, m) => sum + m.total);
        double avg = total > 0 ? (obtained / total) * 100 : 0;
        subjectAnalysis[s.name] = {
          "score": avg,
          "isRisk": avg < 75,
          "subject": s,
        };
      }
    }

    final now = DateTime.now();
    final urgentTasks = state.tasks
        .where(
          (t) =>
              !t.isCompleted &&
              t.dueDate != null &&
              t.dueDate!.difference(now).inHours < 48,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A2A72), Color(0xFF009FFD)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Text(
                    "AI SYSTEM ONLINE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                "Ready to analyze academic vectors.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => JarvisOverlay.show(ctx),
                icon: const Icon(
                  Icons.psychology_rounded,
                  color: Color(0xFF2A2A72),
                ),
                label: const Text("SECOND BRAIN"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2A2A72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (urgentTasks.isNotEmpty) ...[
          const Text(
            "⚡ Priority Tonight",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          ...urgentTasks.map(
            (t) => GestureDetector(
              onTap: () => _showTaskDetailsSheet(ctx, t, state.subjects),
              child: Glass(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFFF4757),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        t.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          "🤖 NOVA Services",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 10),
        // ── NOVA Intelligence Strip ────────────────────────────────────────────
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF39FF14).withOpacity(0.06),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.psychology_alt_rounded,
                    color: Color(0xFF39FF14),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'NOVA INTELLIGENCE',
                    style: TextStyle(
                      color: Color(0xFF39FF14),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _novaActionBtn(
                      icon: Icons.calendar_view_week_rounded,
                      label: 'Weekly Schedule',
                      color: const Color(0xFFFF9F43),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DailySchedulePage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _novaActionBtn(
                      icon: Icons.tune_rounded,
                      label: 'NOVA Settings',
                      color: Colors.white54,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NovaSettingsPage(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ValueListenableBuilder<VoidCallback?>(
                valueListenable: novaSpeak,
                builder: (_, cb, __) => NovaBriefCard(onHear: cb ?? () {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ...subjectAnalysis.entries.map((e) {
          final score = e.value['score'] as double;
          return GestureDetector(
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => SubjectDetailPage(subject: e.value['subject']),
              ),
            ),
            child: Glass(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    color: score >= 85
                        ? Colors.green
                        : (score < 75 ? Colors.red : Colors.orange),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    "${score.toStringAsFixed(1)}%",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _novaActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  void _showChatInterface(BuildContext ctx, AppState state) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  "Advisor Strategy Session",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatHistory.length,
                    itemBuilder: (ctx, i) {
                      final isUser = _chatHistory[i]['role'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF6C63FF)
                                : Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _chatHistory[i]['content']!,
                            style: TextStyle(
                              color: isUser ? Colors.white : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isAiTyping) const LinearProgressIndicator(),
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          decoration: const InputDecoration(
                            hintText: "Ask about your data...",
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () async {
                          final text = _chatController.text;
                          if (text.isEmpty) return;
                          setModalState(() {
                            _chatHistory.add({'role': 'user', 'content': text});
                            _isAiTyping = true;
                            _chatController.clear();
                          });
                          final response = await AIService.getChatResponse(
                            history: _chatHistory,
                            subjects: state.subjects,
                            tasks: state.tasks,
                            marks: state.marks,
                          );
                          setModalState(() {
                            _chatHistory.add({
                              'role': 'assistant',
                              'content': response,
                            });
                            _isAiTyping = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTaskDetailsSheet(
    BuildContext context,
    TaskModel t,
    List<Subject> subs,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF12122A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(t.typeIcon, color: t.priorityColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AText(
                      t.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AText(
                t.description.isEmpty
                    ? "No description provided."
                    : t.description,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              Text(
                "Deadline: ${intl.DateFormat('EEEE, MMM d, yyyy').format(t.dueDate!)}",
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _findStudyGaps(List<TimetableEntry> timetable) {
    final gaps = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final days = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    for (int i = 0; i < 3; i++) {
      final checkDate = now.add(Duration(days: i));
      final dow = checkDate.weekday;
      final dailyClasses = timetable.where((e) => e.dayOfWeek == dow).toList();
      dailyClasses.sort(
        (a, b) => _parseTime(a.startTime).compareTo(_parseTime(b.startTime)),
      );
      double lastEndTime = 8.0;
      for (var cls in dailyClasses) {
        double start = _parseTime(cls.startTime);
        double end = _parseTime(cls.endTime);
        if (start - lastEndTime >= 1.5) {
          gaps.add({
            'day': i == 0 ? 'Today' : (i == 1 ? 'Tomorrow' : days[dow]),
            'duration': '${(start - lastEndTime).toStringAsFixed(1)}h',
            'time': '${_floatToTime(lastEndTime)} - ${_floatToTime(start)}',
          });
        }
        lastEndTime = max(lastEndTime, end);
      }
      if (lastEndTime < 16.5) {
        gaps.add({
          'day': i == 0 ? 'Today' : (i == 1 ? 'Tomorrow' : days[dow]),
          'duration': 'Evening',
          'time': 'After ${_floatToTime(lastEndTime)}',
        });
      }
    }
    return gaps.take(5).toList();
  }

  double _parseTime(String time) {
    try {
      final parts = time.split(':');
      return int.parse(parts[0]) + (int.parse(parts[1]) / 60.0);
    } catch (e) {
      return 0.0;
    }
  }

  String _floatToTime(double time) {
    int h = time.floor();
    int m = ((time - h) * 60).round();
    final dt = DateTime(2022, 1, 1, h, m);
    return intl.DateFormat('h:mm a').format(dt);
  }

  // ═══════════════════════════════════════════
  // TIMETABLE TAB (unchanged)
  // ═══════════════════════════════════════════
  Widget _timetableTab(BuildContext ctx, AppState state) {
    return BlocBuilder<AppBloc, AppState>(
      buildWhen: (prev, curr) =>
          prev.timetable != curr.timetable ||
          prev.currentWeekType != curr.currentWeekType ||
          prev.subjects != curr.subjects ||
          prev.lastUpdated != curr.lastUpdated,
      builder: (context, currentState) {
        // ═══ Use lastUpdated to prove we're getting fresh data ═══
        debugPrint(
          '📋 Timetable tab rebuild — lastUpdated: ${currentState.lastUpdated}',
        );

        final now = DateTime.now();
        final todayDow = now.weekday;
        final currentWeek = currentState.currentWeekType;

        final filteredTimetable = currentState.timetable
            .where((e) => e.weekType == 'both' || e.weekType == currentWeek)
            .toList();

        final todayEntries =
            filteredTimetable.where((e) => e.dayOfWeek == todayDow).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));

        final dayLabels = {
          1: 'Monday',
          2: 'Tuesday',
          3: 'Wednesday',
          4: 'Thursday',
          5: 'Friday',
          6: 'Saturday',
          7: 'Sunday',
        };
        final customOrder = [6, 7, 1, 2, 3, 4, 5];

        return ListView(
          // ═══ Force fresh list on every rebuild ═══
          key: ValueKey(currentState.lastUpdated),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            // Week type selector
            Glass(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFF6C63FF),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Week Type:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'odd',
                        label: Text('Odd', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: 'even',
                        label: Text('Even', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {currentWeek},
                    onSelectionChanged: (v) =>
                        ctx.read<AppBloc>().add(SetWeekType(v.first)),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),

            if (todayEntries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    const Text(
                      "📍 Today's Schedule",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dayLabels[todayDow] ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              // ═══ Pass lastUpdated to force recalculation ═══
              _nextClassBanner(
                todayEntries,
                currentState.subjects,
                currentState.lastUpdated,
              ),
              ...todayEntries.map(
                (e) =>
                    _timetableCard(ctx, e, currentState.subjects, currentState),
              ),
            ],

            if (todayEntries.isEmpty)
              Glass(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.weekend_rounded,
                          size: 40,
                          color: Colors.grey.withOpacity(0.3),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No classes today! 🎉',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '📅 Full Week',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),

            ...customOrder.map((dayNum) {
              final entries = filteredTimetable
                  .where((e) => e.dayOfWeek == dayNum)
                  .toList();
              if (entries.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                    child: Text(
                      '${dayNum == todayDow ? "⭐ " : ""}${dayLabels[dayNum]}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: dayNum == todayDow
                            ? const Color(0xFF6C63FF)
                            : null,
                      ),
                    ),
                  ),
                  ...entries.map(
                    (e) => _timetableCard(
                      ctx,
                      e,
                      currentState.subjects,
                      currentState,
                    ),
                  ),
                ],
              );
            }),

            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => _showAddTimetable(ctx, currentState),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Class'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _nextClassBanner(
    List<TimetableEntry> entries,
    List<Subject> subs,
    DateTime lastUpdated,
  ) {
    // Fresh time calculation every rebuild
    final nowDt = DateTime.now();
    final nowMin = nowDt.hour * 60 + nowDt.minute;

    debugPrint('🕐 Banner: nowMin=$nowMin, lastUpdated=$lastUpdated');

    // ── Find CURRENT class ──
    TimetableEntry? current;
    for (final e in entries) {
      final sp = e.startTime.split(':');
      final ep = e.endTime.split(':');
      if (sp.length < 2 || ep.length < 2) continue;
      final startMin = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final endMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      if (nowMin >= startMin && nowMin < endMin) {
        current = e;
        break;
      }
    }

    // ── CURRENT CLASS ──
    if (current != null) {
      final sName = subjectName(subs, current.subjectId);
      final sub = subs.where((s) => s.id == current!.subjectId).firstOrNull;
      final color = sub != null ? Color(sub.color) : const Color(0xFF2ED573);

      // Calculate time remaining in class
      final ep = current.endTime.split(':');
      final endMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final minsLeft = endMin - nowMin;

      return Glass(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.school_rounded, color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF2ED573),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE — ${minsLeft}m remaining',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2ED573),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${current.type[0].toUpperCase()}${current.type.substring(1)}'
                    ' • ${_formatTo12H(current.startTime)} - ${_formatTo12H(current.endTime)}'
                    '${current.room.isNotEmpty ? ' • Room ${current.room}' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Find NEXT class ──
    TimetableEntry? next;
    for (final e in entries) {
      final parts = e.startTime.split(':');
      if (parts.length < 2) continue;
      final eMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (eMin > nowMin) {
        next = e;
        break;
      }
    }

    // ── ALL DONE ──
    if (next == null) {
      return Glass(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: const [
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF2ED573),
              size: 24,
            ),
            SizedBox(width: 10),
            Text(
              'All classes done for today!',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // ── NEXT CLASS with countdown ──
    final sName = subjectName(subs, next.subjectId);
    final nextParts = next.startTime.split(':');
    final nextMin = int.parse(nextParts[0]) * 60 + int.parse(nextParts[1]);
    final minsUntil = nextMin - nowMin;
    final countdownText = minsUntil >= 60
        ? '${minsUntil ~/ 60}h ${minsUntil % 60}m'
        : '${minsUntil}m';

    return Glass(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.navigate_next_rounded,
              color: Color(0xFF6C63FF),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Class — in $countdownText',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  sName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${next.type[0].toUpperCase()}${next.type.substring(1)}'
                  ' • ${_formatTo12H(next.startTime)} - ${_formatTo12H(next.endTime)}'
                  '${next.room.isNotEmpty ? ' • Room ${next.room}' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timetableCard(
    BuildContext ctx,
    TimetableEntry e,
    List<Subject> subs,
    AppState state,
  ) {
    final sub = subs.where((s) => s.id == e.subjectId).firstOrNull;
    final color = sub != null ? Color(sub.color) : const Color(0xFF6C63FF);
    return GestureDetector(
      onTap: sub != null
          ? () => Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: ctx.read<AppBloc>(),
                  child: SubjectDetailPage(subject: sub),
                ),
              ),
            )
          : null,
      child: Glass(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Icon(e.typeIcon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subjectName(subs, e.subjectId),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${e.type[0].toUpperCase()}${e.type.substring(1)} • ${_formatTo12H(e.startTime)} - ${_formatTo12H(e.endTime)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (e.isExceptional) ...[
                        const SizedBox(width: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9F43).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFFFF9F43),
                              width: 0.5,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFF9F43),
                                size: 10,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'One-Time',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF9F43),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (e.room.isNotEmpty || e.building.isNotEmpty)
                    Text(
                      '${e.building}${e.building.isNotEmpty && e.room.isNotEmpty ? ' — ' : ''}${e.room.isNotEmpty ? 'Room ${e.room}' : ''}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.edit_rounded,
                color: Colors.grey,
                size: 18,
              ),
              onPressed: () => _showEditTimetable(ctx, e, state),
              tooltip: 'Edit class',
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 18,
              ),
              onPressed: () => _confirmDeleteTimetable(ctx, e, subs),
              tooltip: 'Delete class',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTimetable(
    BuildContext ctx,
    TimetableEntry e,
    List<Subject> subs,
  ) async {
    final sName = subjectName(subs, e.subjectId);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Remove Class?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '${e.type[0].toUpperCase()}${e.type.substring(1)} • ${_formatTo12H(e.startTime)} – ${_formatTo12H(e.endTime)}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    // Simple: just fire the delete event, BLoC handles everything
    if (ok == true && e.id != null) {
      ctx.read<AppBloc>().add(DeleteTimetableEntry(e.id!));
    }
  }

  void _showEditTimetable(
    BuildContext ctx,
    TimetableEntry entry,
    AppState state,
  ) {
    // Pre-fill with existing values
    int? subId = entry.subjectId;
    int dow = entry.dayOfWeek;
    String type = entry.type;
    String selectedWeekType = entry.weekType;
    final roomC = TextEditingController(text: entry.room);
    final buildingC = TextEditingController(text: entry.building);
    final startParts = entry.startTime.split(':');
    final endParts = entry.endTime.split(':');
    TimeOfDay startT = TimeOfDay(
      hour: int.tryParse(startParts[0]) ?? 8,
      minute: int.tryParse(startParts.elementAtOrNull(1) ?? '0') ?? 0,
    );
    TimeOfDay endT = TimeOfDay(
      hour: int.tryParse(endParts[0]) ?? 9,
      minute: int.tryParse(endParts.elementAtOrNull(1) ?? '30') ?? 30,
    );
    const days = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: d ? const Color(0xFF12122A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Edit Class',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: subId,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                    ),
                    items: state.subjects
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => subId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: dow,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                    ),
                    items: days.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => dow = v ?? dow),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedWeekType,
                    decoration: const InputDecoration(
                      labelText: 'Occurrence',
                      prefixIcon: Icon(Icons.repeat_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'both',
                        child: Text("Weekly (Every Week)"),
                      ),
                      DropdownMenuItem(
                        value: 'odd',
                        child: Text("Odd Weeks Only"),
                      ),
                      DropdownMenuItem(
                        value: 'even',
                        child: Text("Even Weeks Only"),
                      ),
                    ],
                    onChanged: (v) =>
                        setS(() => selectedWeekType = v ?? selectedWeekType),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.school_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'lecture',
                        child: Text('Lecture'),
                      ),
                      DropdownMenuItem(
                        value: 'section',
                        child: Text('Section'),
                      ),
                      DropdownMenuItem(value: 'lab', child: Text('Lab')),
                    ],
                    onChanged: (v) => setS(() => type = v ?? type),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.access_time_rounded),
                          title: const Text(
                            'Start',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            _formatTo12H(
                              '${startT.hour.toString().padLeft(2, '0')}:${startT.minute.toString().padLeft(2, '0')}',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () async {
                            final t = await showTimePicker(
                              context: c,
                              initialTime: startT,
                            );
                            if (t != null) setS(() => startT = t);
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.access_time_filled_rounded),
                          title: const Text(
                            'End',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            _formatTo12H(
                              '${endT.hour.toString().padLeft(2, '0')}:${endT.minute.toString().padLeft(2, '0')}',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () async {
                            final t = await showTimePicker(
                              context: c,
                              initialTime: endT,
                            );
                            if (t != null) setS(() => endT = t);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: roomC,
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      prefixIcon: Icon(Icons.door_front_door_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: buildingC,
                    decoration: const InputDecoration(
                      labelText: 'Building',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (subId == null) {
                        ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('Select a subject')),
                        );
                        return;
                      }
                      final startStr =
                          '${startT.hour.toString().padLeft(2, '0')}:${startT.minute.toString().padLeft(2, '0')}';
                      final endStr =
                          '${endT.hour.toString().padLeft(2, '0')}:${endT.minute.toString().padLeft(2, '0')}';
                      ctx.read<AppBloc>().add(
                        UpdateTimetableEntry(
                          TimetableEntry(
                            id: entry.id,
                            subjectId: subId,
                            dayOfWeek: dow,
                            startTime: startStr,
                            endTime: endStr,
                            type: type,
                            room: roomC.text.trim(),
                            building: buildingC.text.trim(),
                            weekType: selectedWeekType,
                          ),
                        ),
                      );
                      Navigator.pop(c);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Class updated')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddTimetable(BuildContext ctx, AppState state) {
    int? subId;
    int dow = DateTime.now().weekday;
    String type = 'lecture';
    String selectedWeekType = 'both';
    final roomC = TextEditingController();
    final buildingC = TextEditingController();
    TimeOfDay startT = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endT = const TimeOfDay(hour: 9, minute: 30);
    bool isExceptional = false;
    DateTime? exceptionalDate;
    const days = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: d ? const Color(0xFF12122A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Add Class',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: subId,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                    ),
                    items: state.subjects
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => subId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: dow,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                    ),
                    items: days.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => dow = v ?? dow),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedWeekType,
                    decoration: const InputDecoration(
                      labelText: 'Occurrence',
                      prefixIcon: Icon(Icons.repeat_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'both',
                        child: Text("Weekly (Every Week)"),
                      ),
                      DropdownMenuItem(
                        value: 'odd',
                        child: Text("Odd Weeks Only"),
                      ),
                      DropdownMenuItem(
                        value: 'even',
                        child: Text("Even Weeks Only"),
                      ),
                    ],
                    onChanged: (v) =>
                        setS(() => selectedWeekType = v ?? 'both'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.category_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'lecture',
                        child: Text('Lecture'),
                      ),
                      DropdownMenuItem(
                        value: 'section',
                        child: Text('Section'),
                      ),
                      DropdownMenuItem(value: 'lab', child: Text('Lab')),
                    ],
                    onChanged: (v) => setS(() => type = v ?? type),
                  ),
                  const SizedBox(height: 10),
                  // ── Exceptional class toggle ─────────
                  SwitchListTile(
                    title: const Text(
                      'One-Time Class',
                      style: TextStyle(fontSize: 14),
                    ),
                    secondary: const Icon(
                      Icons.event_available_rounded,
                      color: Color(0xFFFF9F43),
                    ),
                    value: isExceptional,
                    activeColor: const Color(0xFFFF9F43),
                    onChanged: (v) => setS(() => isExceptional = v),
                  ),
                  if (isExceptional) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: c,
                          initialDate:
                              exceptionalDate ??
                              DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (d != null) setS(() => exceptionalDate = d);
                      },
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(
                        exceptionalDate != null
                            ? '${exceptionalDate!.day}/${exceptionalDate!.month}/${exceptionalDate!.year}'
                            : 'Pick Date',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: c,
                              initialTime: startT,
                            );
                            if (t != null) setS(() => startT = t);
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(
                            'Start: ${startT.format(c)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: c,
                              initialTime: endT,
                            );
                            if (t != null) setS(() => endT = t);
                          },
                          icon: const Icon(Icons.stop_rounded, size: 18),
                          label: Text(
                            'End: ${endT.format(c)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: roomC,
                          decoration: const InputDecoration(
                            labelText: 'Room',
                            prefixIcon: Icon(Icons.room_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: buildingC,
                          decoration: const InputDecoration(
                            labelText: 'Building',
                            prefixIcon: Icon(Icons.business_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      if (subId == null) {
                        ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('Select a subject')),
                        );
                        return;
                      }
                      final sTime =
                          '${startT.hour.toString().padLeft(2, '0')}:${startT.minute.toString().padLeft(2, '0')}';
                      final eTime =
                          '${endT.hour.toString().padLeft(2, '0')}:${endT.minute.toString().padLeft(2, '0')}';
                      ctx.read<AppBloc>().add(
                        AddTimetableEntry(
                          TimetableEntry(
                            subjectId: subId!,
                            dayOfWeek: isExceptional
                                ? (exceptionalDate?.weekday ?? dow)
                                : dow,
                            startTime: sTime,
                            endTime: eTime,
                            type: type,
                            room: roomC.text.trim(),
                            building: buildingC.text.trim(),
                            weekType: isExceptional ? 'both' : selectedWeekType,
                            isExceptional: isExceptional,
                            exceptionalDate: exceptionalDate != null
                                ? exceptionalDate!.toIso8601String().split(
                                    'T',
                                  )[0]
                                : '',
                          ),
                        ),
                      );
                      Navigator.pop(c);

                      // ═══ ADD THIS — reschedule after adding ═══
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          _rescheduleTimetableNotifs(
                            context.read<AppBloc>().state,
                          );
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Add Class'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════
  // REMINDERS TAB (unchanged)
  // ═══════════════════════════════════════════
  Widget _remindersTab(BuildContext ctx, AppState state) {
    final today = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    final upcoming = state.reminders
        .where((r) => !r.isDone && r.date.compareTo(today) >= 0)
        .toList();
    final past = state.reminders
        .where((r) => r.isDone || r.date.compareTo(today) < 0)
        .toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Read My Day — relocated from Focus tab
        Glass(
          child: Column(
            children: [
              const Icon(
                Icons.headphones_rounded,
                size: 36,
                color: Color(0xFF6C63FF),
              ),
              const SizedBox(height: 8),
              const Text(
                '🎧 Read My Day',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 4),
              const Text(
                'Listen to your daily briefing hands-free',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSpeaking
                        ? null
                        : () => _readMyDay(ctx, state, 'en'),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text(
                      'English',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSpeaking
                        ? null
                        : () => _readMyDay(ctx, state, 'ar'),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text('عربي', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ED573),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (_isSpeaking) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        await _tts.stop();
                        setState(() => _isSpeaking = false);
                      },
                      icon: const Icon(
                        Icons.stop_circle_rounded,
                        color: Color(0xFFFF4757),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            '🔔 Morning Reminders',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Things to remember before leaving home',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        if (upcoming.isEmpty)
          Glass(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_off_rounded,
                      size: 40,
                      color: Colors.grey.withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No reminders set',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ...upcoming.map((r) => _reminderCard(ctx, r)),
        if (past.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...past.map((r) => _reminderCard(ctx, r)),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _showAddReminder(ctx),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Reminder'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reminderCard(BuildContext ctx, ReminderModel r) {
    return Glass(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () =>
                ctx.read<AppBloc>().add(ToggleReminder(r.id!, !r.isDone)),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: r.isDone ? const Color(0xFF2ED573) : Colors.transparent,
                border: Border.all(
                  color: r.isDone
                      ? const Color(0xFF2ED573)
                      : const Color(0xFF6C63FF),
                  width: 2,
                ),
              ),
              child: r.isDone
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AText(
                  r.text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    decoration: r.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '${r.date} at ${r.time}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.red,
              size: 18,
            ),
            onPressed: () => ctx.read<AppBloc>().add(DeleteReminder(r.id!)),
          ),
        ],
      ),
    );
  }

  void _showAddReminder(BuildContext ctx) {
    final textC = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(days: 1));
    TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: d ? const Color(0xFF12122A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Add Reminder',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textC,
                    decoration: const InputDecoration(
                      labelText: 'What to remember? (e.g. Take report)',
                      prefixIcon: Icon(Icons.note_alt_rounded),
                    ),
                    textDirection: detectDir(textC.text),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: c,
                              initialDate: date,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (p != null) setS(() => date = p);
                          },
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                          ),
                          label: Text(
                            intl.DateFormat('MMM d').format(date),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: c,
                              initialTime: time,
                            );
                            if (t != null) setS(() => time = t);
                          },
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: Text(
                            time.format(c),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (textC.text.trim().isEmpty) {
                        ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('Enter reminder text')),
                        );
                        return;
                      }
                      ctx.read<AppBloc>().add(
                        AddReminder(
                          ReminderModel(
                            text: textC.text.trim(),
                            date: intl.DateFormat('yyyy-MM-dd').format(date),
                            time:
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                      );
                      Navigator.pop(c);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════
  // RPG TAB (unchanged)
  // ═══════════════════════════════════════════
  Widget _rpgTab(BuildContext ctx, AppState state) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (ctx, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final prefs = snap.data!;
        final xp = prefs.getInt('total_xp') ?? 0;
        final level = (xp / 1000).floor() + 1;
        final xpInLevel = xp % 1000;
        final progress = xpInLevel / 1000;

        final completedWithDates = state.tasks
            .where(
              (t) =>
                  t.isCompleted &&
                  t.dueDate != null &&
                  t.createdAt != null &&
                  t.completedAt != null,
            )
            .toList();
        double procrastinationScore = 0.5;
        String procStatus = "No data yet";
        Color procColor = Colors.grey;
        if (completedWithDates.isNotEmpty) {
          double totalRatio = 0;
          for (var t in completedWithDates) {
            final total = t.dueDate!.difference(t.createdAt!).inMinutes;
            final left = t.dueDate!.difference(t.completedAt!).inMinutes;
            if (total > 0) totalRatio += (left / total).clamp(0.0, 1.0);
          }
          procrastinationScore = totalRatio / completedWithDates.length;
          if (procrastinationScore > 0.5) {
            procStatus = "Great! You finish tasks early.";
            procColor = const Color(0xFF2ED573);
          } else if (procrastinationScore < 0.2) {
            procStatus = "Warning: High Risk! Last minute.";
            procColor = const Color(0xFFFF4757);
          } else {
            procStatus = "Good. Keep improving.";
            procColor = const Color(0xFFFF9F43);
          }
        }

        final completedTasks = state.tasks.where((t) => t.isCompleted).length;
        final highTasks = state.tasks
            .where((t) => t.isCompleted && t.priority == 3)
            .length;
        final medTasks = state.tasks
            .where((t) => t.isCompleted && t.priority == 2)
            .length;
        final lowTasks = state.tasks
            .where((t) => t.isCompleted && t.priority == 1)
            .length;

        String title;
        IconData titleIcon;
        if (level >= 10) {
          title = 'Engineering Legend';
          titleIcon = Icons.auto_awesome;
        } else if (level >= 7) {
          title = 'Senior Engineer';
          titleIcon = Icons.engineering;
        } else if (level >= 5) {
          title = 'Project Lead';
          titleIcon = Icons.architecture;
        } else if (level >= 3) {
          title = 'Lab Specialist';
          titleIcon = Icons.science;
        } else {
          title = 'Freshman';
          titleIcon = Icons.school;
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(8),
          children: [
            Glass(
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(titleIcon, color: const Color(0xFF6C63FF), size: 28),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Level $level',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F43).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '$xp XP',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFFFF9F43),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$xpInLevel / 1000 XP to Level ${level + 1}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Procrastination Index",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: procrastinationScore,
                      minHeight: 12,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation(procColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    procStatus,
                    style: TextStyle(
                      color: procColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚡ XP Breakdown',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  _xpRow('🔴 High Priority Tasks', highTasks, 100),
                  _xpRow('🟠 Medium Priority Tasks', medTasks, 75),
                  _xpRow('🟢 Low Priority Tasks', lowTasks, 50),
                  const Divider(height: 16),
                  const Text(
                    '🎖️ Spaced Repetition Bonus (50 XP)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      height: 2,
                    ),
                  ),
                  const Text(
                    '🎖️ Early Bird Bonus (+40 XP)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      height: 2,
                    ),
                  ),
                  const Text(
                    '⛔ Clutch Penalty (-15 XP)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      height: 2,
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Total Completed: ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$completedTasks tasks',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🏆 Milestones',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(5, (i) {
                    final milestone = (i + 1) * 1000;
                    final reached = xp >= milestone;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            reached
                                ? Icons.emoji_events_rounded
                                : Icons.emoji_events_outlined,
                            color: reached
                                ? const Color(0xFFFF9F43)
                                : Colors.grey.withOpacity(0.3),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$milestone XP',
                            style: TextStyle(
                              fontWeight: reached
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: reached ? null : Colors.grey,
                            ),
                          ),
                          if (reached) ...[
                            const SizedBox(width: 8),
                            const Text(
                              '✓',
                              style: TextStyle(
                                color: Color(0xFF2ED573),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => _confettiC.play(),
                icon: const Icon(Icons.celebration_rounded),
                label: const Text('🎉 Celebrate!'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _xpRow(String label, int count, int xpPer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            '$count × $xpPer = ',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            '${count * xpPer} XP',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF9F43),
            ),
          ),
        ],
      ),
    );
  }

  // ── Read My Day (improved TTS) ────────────────────────────────────────────
  Future<void> _readMyDay(BuildContext ctx, AppState state, String lang) async {
    setState(() => _isSpeaking = true);

    final now = DateTime.now();
    final todayDow = now.weekday;

    final pendingTasks = state.tasks
        .where(
          (t) =>
              !t.isCompleted &&
              t.dueDate != null &&
              t.dueDate!.isAfter(now.subtract(const Duration(days: 1))),
        )
        .take(5)
        .toList();

    final todayClasses =
        state.timetable
            .where(
              (e) =>
                  e.dayOfWeek == todayDow &&
                  (e.weekType == 'both' || e.weekType == state.currentWeekType),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final todayReminders = state.reminders.where((r) {
      if (r.isDone) return false;
      try {
        final dp = r.date.split('-');
        if (dp.length < 3) return false;
        final rDate = DateTime(
          int.parse(dp[0]),
          int.parse(dp[1]),
          int.parse(dp[2]),
        );
        return rDate.year == now.year &&
            rDate.month == now.month &&
            rDate.day == now.day;
      } catch (_) {
        return false;
      }
    }).toList();

    // ═══ Check if all classes are already done ═══
    bool allClassesDone = true;
    if (todayClasses.isNotEmpty) {
      final nowMin = now.hour * 60 + now.minute;
      for (final c in todayClasses) {
        final ep = c.endTime.split(':');
        if (ep.length < 2) continue;
        final endMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
        if (endMin > nowMin) {
          allClassesDone = false;
          break;
        }
      }
    }

    // ═══ Find upcoming classes (not yet ended) ═══
    final upcomingClasses = <TimetableEntry>[];
    if (!allClassesDone) {
      final nowMin = now.hour * 60 + now.minute;
      for (final c in todayClasses) {
        final ep = c.endTime.split(':');
        if (ep.length < 2) continue;
        final endMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
        if (endMin > nowMin) {
          upcomingClasses.add(c);
        }
      }
    }

    // ═══ Find upcoming reminders (not yet passed) ═══
    final upcomingReminders = todayReminders.where((r) {
      try {
        final tp = r.time.split(':');
        if (tp.length < 2) return true; // include if can't parse
        final rMin = int.parse(tp[0]) * 60 + int.parse(tp[1]);
        final nowMin = now.hour * 60 + now.minute;
        return rMin > nowMin;
      } catch (_) {
        return true;
      }
    }).toList();

    String script;

    if (lang == 'ar') {
      await _tts.setLanguage('ar');
      await _tts.setSpeechRate(0.6);
      await _tts.setPitch(1.0);

      // ── Greeting based on time ──
      if (now.hour < 12) {
        script = 'صباح الخير يوسف. ';
      } else if (now.hour < 18) {
        script = 'مساء الخير يوسف. ';
      } else {
        script = 'مساء الخير يوسف. ';
      }

      // ── Reminders ──
      if (upcomingReminders.isNotEmpty) {
        script += 'عندك ${upcomingReminders.length} تذكير لسه ما جاش وقته. ';
        for (final r in upcomingReminders) {
          script += '${r.text}';
          if (r.time.isNotEmpty) {
            script += ' الساعة ${_formatTo12H(r.time)}';
          }
          script += '. ';
        }
      } else if (todayReminders.isNotEmpty) {
        script += 'كل التذكيرات بتاعة النهارده خلصت. ';
      }

      // ── Classes ──
      if (allClassesDone) {
        // All classes finished — end of day summary
        script +=
            'كل الحصص بتاعة النهارده خلصت. كان عندك ${todayClasses.length} '
            '${todayClasses.length == 1 ? 'حصة' : 'حصص'}. ';
      } else if (upcomingClasses.isNotEmpty) {
        script +=
            'لسه عندك ${upcomingClasses.length} ${upcomingClasses.length == 1 ? 'حصة' : 'حصص'} باقية. ';
        for (final c in upcomingClasses) {
          final sName = subjectName(state.subjects, c.subjectId);
          script += '$sName ';
          script +=
              '${c.type == 'lecture'
                  ? 'محاضرة'
                  : c.type == 'section'
                  ? 'سكشن'
                  : 'معمل'} ';
          script += 'الساعة ${_formatTo12H(c.startTime)}';
          if (c.room.isNotEmpty) script += ' في قاعة ${c.room}';
          if (c.building.isNotEmpty) script += ' مبنى ${c.building}';
          script += '. ';
        }
      } else {
        script += 'مفيش حصص النهارده. ';
      }

      // ── Tasks ──
      if (pendingTasks.isNotEmpty) {
        script += 'عندك ${pendingTasks.length} مهمة قريبة. ';
        for (final t in pendingTasks) {
          script += '${t.title}. ';
          if (t.dueDate != null) {
            final diff = t.dueDate!.difference(now).inHours;
            if (diff < 3) {
              script += 'مطلوبة دلوقتي! ';
            } else if (diff < 24) {
              script += 'مطلوبة النهارده. ';
            } else {
              script +=
                  'مطلوبة بعد ${diff ~/ 24} ${(diff ~/ 24) > 1 ? 'أيام' : 'يوم'}. ';
            }
          }
        }
      } else {
        script += 'مفيش مهام قريبة. ممتاز! ';
      }

      // ── Closing ──
      if (allClassesDone) {
        script += 'يوم كويس. استريح شوية وبعدين ذاكر!';
      } else {
        script += 'يلا وبلاش تضييع وقت!';
      }
    } else {
      // ═══════════════════════════════════════
      // ENGLISH
      // ═══════════════════════════════════════
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);

      // ── Greeting based on time ──
      if (now.hour < 12) {
        script = 'Good morning Yousif. ... ';
      } else if (now.hour < 18) {
        script = 'Good afternoon Yousif. ... ';
      } else {
        script = 'Good evening Yousif. ... ';
      }

      // ── Reminders ──
      if (upcomingReminders.isNotEmpty) {
        script +=
            'You have ${upcomingReminders.length} upcoming reminder${upcomingReminders.length > 1 ? 's' : ''}. ';
        for (final r in upcomingReminders) {
          script += '${r.text}';
          if (r.time.isNotEmpty) script += ', at ${_formatTo12H(r.time)}';
          script += '. ';
        }
        script += '... ';
      } else if (todayReminders.isNotEmpty) {
        script += 'All reminders for today are done. ';
      }

      // ── Classes ──
      if (allClassesDone) {
        // End of day — don't list classes, just summarize
        script +=
            'All ${todayClasses.length} class${todayClasses.length > 1 ? 'es' : ''} '
            'for today are done. Great job! ... ';
      } else if (upcomingClasses.isNotEmpty) {
        script +=
            'You still have ${upcomingClasses.length} class${upcomingClasses.length > 1 ? 'es' : ''} remaining. ';
        for (final c in upcomingClasses) {
          final sName = subjectName(state.subjects, c.subjectId);
          script += '$sName ${c.type}, at ${_formatTo12H(c.startTime)}';
          if (c.room.isNotEmpty) script += ', in room ${c.room}';
          if (c.building.isNotEmpty) script += ', building ${c.building}';
          script += '. ';
        }
        script += '... ';
      } else {
        script += 'No classes today. ';
      }

      // ── Tasks ──
      if (pendingTasks.isNotEmpty) {
        script +=
            'You have ${pendingTasks.length} upcoming task${pendingTasks.length > 1 ? 's' : ''}. ';
        for (final t in pendingTasks) {
          script += '${t.title}. ';
          if (t.dueDate != null) {
            final diff = t.dueDate!.difference(now).inHours;
            if (diff < 3) {
              script += 'Due very soon! ';
            } else if (diff < 24) {
              script += 'Due today. ';
            } else {
              script +=
                  'Due in ${diff ~/ 24} day${(diff ~/ 24) > 1 ? 's' : ''}. ';
            }
          }
        }
      } else {
        script += 'No pending tasks. Great job engineer! ';
      }

      // ── Closing based on context ──
      if (allClassesDone) {
        script +=
            '... Your classes are done for today. Time to rest and review! Have a great evening!';
      } else {
        script += '... Have a productive day!';
      }
    }

    await _tts.speak(script);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  Future<void> _scheduleEndOfDayNotification(AppState state) async {
    try {
      await NotifService.scheduleReadMyDayNotif(
        allEntries: state.timetable,
        currentWeekType: state.currentWeekType,
      );
    } catch (e) {
      debugPrint('Error scheduling end-of-day notif: $e');
    }
  }

  // ═══════════════════════════════════════════
  // BACKUP TAB (unchanged)
  // ═══════════════════════════════════════════
  Widget _backupTab(BuildContext ctx) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Glass(
          child: Column(
            children: [
              const Icon(Icons.cloud_sync, size: 50, color: Color(0xFF6C63FF)),
              const Text(
                "Backup & Restore",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => ctx.read<AppBloc>().add(ExportData()),
                icon: const Icon(Icons.upload),
                label: const Text("Export"),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.any,
                  );
                  if (res == null || res.files.single.path == null) return;

                  ctx.read<AppBloc>().add(ImportData(res.files.single.path!));

                  await Future.delayed(const Duration(seconds: 2));
                  if (!mounted) return;

                  final newState = context.read<AppBloc>().state;
                  _rescheduleNotificationsOnStart(newState);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Data imported & notifications rescheduled'),
                        backgroundColor: Color(0xFF2ED573),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text("Import"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 🧠 STUDY TAB — WITH SET DATE, RESET, DELETE
  // ═══════════════════════════════════════════
  Widget _studyTab(BuildContext context, AppState state) {
    if (state.topics.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              "🧠 Spaced Repetition",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                "No topics yet. Add one to start studying!",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddTopic(context, state),
              icon: const Icon(Icons.add),
              label: const Text("Add Topic"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    }

    // Group topics by subject ID
    final Map<int, List<StudyTopic>> topicsBySubject = {};
    for (var topic in state.topics) {
      topicsBySubject.putIfAbsent(topic.subjectId, () => []).add(topic);
    }

    // Sort subjects safely (handle cases where subject might have been deleted)
    final sortedSubjectIds = topicsBySubject.keys.toList()..sort((a, b) {
        final subA = state.subjects.firstWhere((s) => s.id == a, orElse: () => const Subject(name: 'Unknown'));
        final subB = state.subjects.firstWhere((s) => s.id == b, orElse: () => const Subject(name: 'Unknown'));
        return subA.name.compareTo(subB.name);
      });

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            "🧠 Spaced Repetition",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        
        ...sortedSubjectIds.expand((subjectId) {
          final sub = state.subjects.firstWhere(
            (s) => s.id == subjectId,
            orElse: () => const Subject(name: 'Unknown'),
          );
          
          final subjectTopics = topicsBySubject[subjectId]!;
          // Sort topics within subject by next review date
          subjectTopics.sort((a, b) {
            if (a.nextReview == null && b.nextReview == null) return 0;
            if (a.nextReview == null) return -1;
            if (b.nextReview == null) return 1;
            return a.nextReview!.compareTo(b.nextReview!);
          });

          return [
            // Subject Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(sub.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    sub.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(sub.color),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            
            // Topic Cards for this subject
            ...subjectTopics.map((topic) {
              final isDue = topic.nextReview != null && topic.nextReview!.isBefore(DateTime.now());
              final isNew = topic.stage == 0;
              final isMastered = topic.stage >= 5;

              return InkWell(
                onTap: () {
                  LayeringSystemOverlay.show(context, topic);
                },
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              topic.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMastered
                                  ? Colors.green.withOpacity(0.2)
                                  : isDue
                                      ? Colors.red.withOpacity(0.2)
                                      : Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isMastered
                                  ? "Mastered"
                                  : isNew
                                      ? "New"
                                      : "Stage ${topic.stage}",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isMastered
                                    ? Colors.green
                                    : isDue
                                        ? Colors.red
                                        : Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (topic.currentLayer <= 3)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.withOpacity(0.5)),
                              ),
                              child: Text(
                                'Layer ${topic.currentLayer}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey),
                            onSelected: (action) {
                              switch (action) {
                                case 'set_date':
                                  _showSetReviewDate(context, topic);
                                  break;
                                case 'reset':
                                  _confirmResetTopic(context, topic);
                                  break;
                                case 'delete':
                                  _confirmDeleteTopic(context, topic);
                                  break;
                              }
                            },
                            itemBuilder: (c) => [
                              const PopupMenuItem(
                                value: 'set_date',
                                child: Row(children: [Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF6C63FF)), SizedBox(width: 8), Text('Set Review Date')]),
                              ),
                              const PopupMenuItem(
                                value: 'reset',
                                child: Row(children: [Icon(Icons.restart_alt_rounded, size: 18, color: Color(0xFFFF9F43)), SizedBox(width: 8), Text('Reset Progress')]),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete Topic')]),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            topic.nextReview == null
                                ? (isNew ? "Start now" : "Done!")
                                : isDue
                                    ? "Review Now!"
                                    : "Next: ${intl.DateFormat('MMM d').format(topic.nextReview!)}",
                            style: TextStyle(fontSize: 12, color: isDue ? Colors.red : Colors.grey),
                          ),
                          if (topic.lastStudied != null) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.history_rounded, size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Text(
                              'Last: ${intl.DateFormat('MMM d').format(topic.lastStudied!)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                          const Spacer(),
                          if (!isMastered)
                            ElevatedButton(
                              onPressed: () => context.read<AppBloc>().add(ReviewTopic(topic)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isNew ? const Color(0xFF6C63FF) : (isDue ? const Color(0xFFFF4757) : Colors.grey),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(isNew ? "Mark Studied" : "Reviewed"),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ];
        }),
        
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _showAddTopic(context, state),
            icon: const Icon(Icons.add),
            label: const Text("Add Topic"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ── Set custom review date ────────────────────────────────────────────────
  void _showSetReviewDate(BuildContext ctx, StudyTopic topic) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate:
          topic.nextReview ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Set review date for "${topic.title}"',
    );
    if (picked != null) {
      ctx.read<AppBloc>().add(SetTopicReviewDate(topic, picked));
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              'Review date set to ${intl.DateFormat('MMM d').format(picked)}',
            ),
            backgroundColor: const Color(0xFF6C63FF),
          ),
        );
      }
    }
  }

  // ── Confirm reset topic ───────────────────────────────────────────────────
  void _confirmResetTopic(BuildContext ctx, StudyTopic topic) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Color(0xFFFF9F43)),
            SizedBox(width: 8),
            Text('Reset Progress?'),
          ],
        ),
        content: Text(
          'Reset "${topic.title}" back to Stage 0 (New)?\n\n'
          'Current stage: ${topic.stageLabel}\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ctx.read<AppBloc>().add(ResetTopic(topic));
              Navigator.pop(c);
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('"${topic.title}" reset to New'),
                  backgroundColor: const Color(0xFFFF9F43),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9F43),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  // ── Confirm delete topic ──────────────────────────────────────────────────
  void _confirmDeleteTopic(BuildContext ctx, StudyTopic topic) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Topic?'),
          ],
        ),
        content: Text(
          'Delete "${topic.title}" permanently?\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (topic.id != null)
                ctx.read<AppBloc>().add(DeleteTopic(topic.id!));
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddTopic(BuildContext ctx, AppState state) {
    final titleC = TextEditingController();
    int? subId;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(c).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: Theme.of(c).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Add Study Topic",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleC,
              decoration: const InputDecoration(
                labelText: "Topic Name (e.g. Bernoulli)",
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: "Subject"),
              items: state.subjects
                  .map(
                    (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                  )
                  .toList(),
              onChanged: (v) => subId = v,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (titleC.text.isNotEmpty && subId != null) {
                  ctx.read<AppBloc>().add(
                    AddTopic(StudyTopic(subjectId: subId!, title: titleC.text)),
                  );
                  Navigator.pop(c);
                }
              },
              child: const Text("Start Tracking"),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// CELEBRATION OVERLAY (unchanged)
// ═══════════════════════════════════════════
class LegendaryCelebrationOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  const LegendaryCelebrationOverlay({super.key, required this.onDismiss});

  @override
  State<LegendaryCelebrationOverlay> createState() =>
      _LegendaryCelebrationOverlayState();
}

class _LegendaryCelebrationOverlayState
    extends State<LegendaryCelebrationOverlay>
    with TickerProviderStateMixin {
  late List<ConfettiController> _fireworks;
  late AnimationController _colorCtrl;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  Timer? _barrageTimer;

  @override
  void initState() {
    super.initState();
    _fireworks = List.generate(
      5,
      (_) => ConfettiController(duration: const Duration(milliseconds: 800)),
    );
    _startFireworksBarrage();
    _colorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);
  }

  void _startFireworksBarrage() {
    int index = 0;
    _barrageTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      _fireworks[index % 5].play();
      index++;
    });
  }

  @override
  void dispose() {
    for (var c in _fireworks) c.dispose();
    _colorCtrl.dispose();
    _scaleCtrl.dispose();
    _barrageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorCtrl,
      builder: (context, child) {
        final color = HSVColor.fromAHSV(
          0.85,
          _colorCtrl.value * 360,
          1.0,
          1.0,
        ).toColor();
        return Stack(
          children: [
            ModalBarrier(color: color, dismissible: false),
            Align(
              alignment: const Alignment(-0.8, -0.8),
              child: _buildFirework(0),
            ),
            Align(
              alignment: const Alignment(0.8, -0.8),
              child: _buildFirework(1),
            ),
            Align(
              alignment: const Alignment(0, -0.5),
              child: _buildFirework(2),
            ),
            Align(
              alignment: const Alignment(-0.8, 0.5),
              child: _buildFirework(3),
            ),
            Align(
              alignment: const Alignment(0.8, 0.5),
              child: _buildFirework(4),
            ),
            Center(
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Glass(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 100,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 24),
                      _buildShakingText("LEGENDARY!"),
                      const SizedBox(height: 12),
                      const Text(
                        "FULL MARK ACQUIRED",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: widget.onDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        child: const Text(
                          "I AM UNSTOPPABLE",
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFirework(int index) {
    return ConfettiWidget(
      confettiController: _fireworks[index],
      blastDirectionality: BlastDirectionality.explosive,
      shouldLoop: false,
      colors: const [Colors.white, Colors.yellow, Colors.cyan, Colors.lime],
      minBlastForce: 20,
      maxBlastForce: 50,
      numberOfParticles: 15,
    );
  }

  Widget _buildShakingText(String text) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 50), (i) => i),
      builder: (context, snapshot) {
        final offset = snapshot.hasData
            ? Offset(
                (Random().nextDouble() - 0.5) * 6,
                (Random().nextDouble() - 0.5) * 6,
              )
            : Offset.zero;
        return Transform.translate(
          offset: offset,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 10,
                  offset: Offset(2, 2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════
// JARVIS FAB (unchanged)
// ═══════════════════════════════════════════
class _JarvisFab extends StatefulWidget {
  const _JarvisFab();

  @override
  State<_JarvisFab> createState() => _JarvisFabState();
}

class _JarvisFabState extends State<_JarvisFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _pulse.value,
        child: GestureDetector(
          onTap: () => JarvisOverlay.show(context),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF009FFD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                SizedBox(height: 1),
                Text(
                  'NOVA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus Alert Banner — shows when screen unlocks during focus mode
// ─────────────────────────────────────────────────────────────────────────────
class _FocusAlertBanner extends StatefulWidget {
  final int minutesLeft;
  final VoidCallback onDismiss;
  const _FocusAlertBanner({required this.minutesLeft, required this.onDismiss});

  @override
  State<_FocusAlertBanner> createState() => _FocusAlertBannerState();
}

class _FocusAlertBannerState extends State<_FocusAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF4757), Color(0xFFFF6B81)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔴 FOCUS MODE ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${widget.minutesLeft} min remaining — put the phone down!',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: widget.onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
