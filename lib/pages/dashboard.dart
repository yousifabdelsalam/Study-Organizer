import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../bloc/app_bloc.dart';
import '../bloc/app_state.dart';
import '../models/task.dart';
import '../models/subject.dart';
import '../widgets/glass.dart';
import '../widgets/atext.dart';
import '../widgets/helpers.dart';
import '../widgets/night_before_overlay.dart';
import 'subject_detail.dart';
import 'cognitive_reactor_page.dart';
import '../widgets/nova_brief_card.dart';
import '../services/nova_brief_service.dart';
import '../services/nova_audio_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _refreshTimer;
  bool _criticalExamAlerted = false; // prevent sound re-playing on rebuild

  // ── Time-of-day helpers ───────────────────────────────────────────────────
  // Computed fresh on every build — never stale regardless of how long the
  // dashboard has been open.
  bool get _isNight {
    final h = DateTime.now().hour;
    return h >= 23 || h < 5;
  }

  bool get _isLate {
    final h = DateTime.now().hour;
    return h >= 1 && h < 5;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scheduleNextRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Arms a one-shot timer that fires exactly at the next time boundary
  /// (1 AM, 5 AM, 12 PM, 6 PM, 11 PM), calls setState, then re-arms.
  /// Zero polling — sleeps until the precise moment things need to change.
  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();

    final now = DateTime.now();
    const boundaries = [1, 5, 12, 18, 23]; // hours where UI changes

    // First boundary strictly after current time
    int? nextHour;
    for (final h in boundaries) {
      if (h > now.hour) {
        nextHour = h;
        break;
      }
      if (h == now.hour && now.minute > 0) {
        nextHour = h;
        break;
      }
    }
    nextHour ??= boundaries.first; // wrap to tomorrow's first boundary

    DateTime next = DateTime(now.year, now.month, now.day, nextHour);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    _refreshTimer = Timer(next.difference(now), () {
      if (mounted) {
        setState(() {}); // rebuild with fresh DateTime.now()
        _scheduleNextRefresh();
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isNight = _isNight;
    final isLate = _isLate;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.engineering_rounded, color: Color(0xFF6C63FF), size: 24),
            SizedBox(width: 8),
            Text('Engineering Organizer'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              final nv = EngineeringApp.themeNotifier.value == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              EngineeringApp.themeNotifier.value = nv;
              p.setBool('dark', nv == ThemeMode.dark);
            },
          ),
        ],
      ),
      body: BlocBuilder<AppBloc, AppState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = state.tasks.where((t) => !t.isCompleted).toList();
          final today = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
          final todayCount = state.tasks
              .where(
                (t) =>
                    t.dueDate != null &&
                    intl.DateFormat('yyyy-MM-dd').format(t.dueDate!) == today,
              )
              .length;

          List<TaskModel> upcoming;
          if (isNight) {
            final deadline = DateTime.now().add(const Duration(hours: 24));
            upcoming = pending
                .where(
                  (t) => t.dueDate != null && t.dueDate!.isBefore(deadline),
                )
                .toList();
          } else {
            upcoming = pending
                .where(
                  (t) =>
                      t.dueDate != null &&
                      t.dueDate!.isAfter(
                        DateTime.now().subtract(const Duration(days: 1)),
                      ),
                )
                .toList();
          }

          final progress = state.tasks.isNotEmpty
              ? state.tasks.where((t) => t.isCompleted).length /
                    state.tasks.length
              : 0.0;

          final tomorrow = DateTime.now().add(const Duration(days: 1));
          final tomorrowStr = intl.DateFormat('yyyy-MM-dd').format(tomorrow);
          final tomorrowExams = state.tasks
              .where(
                (t) =>
                    !t.isCompleted &&
                    t.isExam &&
                    t.dueDate != null &&
                    intl.DateFormat('yyyy-MM-dd').format(t.dueDate!) ==
                        tomorrowStr,
              )
              .toList();

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (tomorrowExams.isNotEmpty)
                _nightBeforeBanner(context, tomorrowExams),
              // ── NOVA Brief card (shows when brief is available) ──
              _greeting(),
              const SizedBox(height: 8),

              // ── Night banner ──────────────────────────────────────────────
              if (isNight)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.indigoAccent.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.nights_stay_rounded,
                        color: Colors.indigoAccent,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLate
                            ? "يا يوسف انت محتاج تنام 😴"
                            : "It's late. Focus on what's urgent.",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLate
                            ? "Get some sleep to focus tomorrow."
                            : "Showing only tasks due within 24 hours.",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),

              _stats(
                context,
                state.tasks.length,
                state.tasks.where((t) => t.isCompleted).length,
                todayCount,
                state.subjects.length,
              ),
              _progressCard(progress),

              if (upcoming.isNotEmpty)
                _upcoming(upcoming, state.subjects, context, isNight),

              if (upcoming.isEmpty && isNight)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      "No urgent tasks. Go sleep! 💤",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),

              if (state.subjects.isNotEmpty)
                _subjectsPreview(state.subjects, context),
            ],
          );
        },
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _greeting() {
    final h = DateTime.now().hour;
    final g = h < 12
        ? 'Good Morning ☀️'
        : h < 17
        ? 'Good Afternoon 🌤️'
        : 'Good Evening 🌙';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AText(
            g,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            intl.DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _stats(
    BuildContext context,
    int total,
    int done,
    int today,
    int subjects,
  ) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _sc(
            'Tasks',
            '$total',
            Icons.list_alt_rounded,
            const Color(0xFF6C63FF),
          ),
          _sc(
            'Done',
            '$done',
            Icons.check_circle_rounded,
            const Color(0xFF2ED573),
          ),
          _sc('Today', '$today', Icons.today_rounded, const Color(0xFFFF9F43)),
          _sc(
            'Subjects',
            '$subjects',
            Icons.menu_book_rounded,
            const Color(0xFFFF6B81),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CognitiveReactorPage()),
            ),
            child: Glass(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.cyanAccent, size: 24),
                  SizedBox(height: 4),
                  Text(
                    'FOCUS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.cyanAccent,
                      fontFamily: 'Courier',
                    ),
                  ),
                  Text(
                    'Reactor',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sc(String l, String v, IconData ic, Color c) {
    return Glass(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ic, color: c, size: 24),
          const SizedBox(height: 4),
          Text(
            v,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
          Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _progressCard(double p) {
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                color: Color(0xFF6C63FF),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Progress',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const Spacer(),
              Text(
                '${(p * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF6C63FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 8,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcoming(
    List<TaskModel> tasks,
    List<Subject> subs,
    BuildContext ctx,
    bool isNight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            isNight ? '⚠️ Critical Tasks (24h)' : '🔥 Upcoming',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        ...tasks.map((t) => _upcomingCard(t, subs, ctx, isNight)),
      ],
    );
  }

  Widget _upcomingCard(
    TaskModel t,
    List<Subject> subs,
    BuildContext context,
    bool isNight,
  ) {
    if (t.dueDate == null) return const SizedBox.shrink();
    final diff = t.dueDate!.difference(DateTime.now()).inDays;
    final tl = diff < 0
        ? 'Overdue'
        : diff == 0
        ? 'Today'
        : diff == 1
        ? 'Tomorrow'
        : '$diff days';

    return GestureDetector(
      onTap: () => _showTaskDetails(context, t, subs),
      child: Opacity(
        opacity: isNight ? 0.8 : 1.0,
        child: Glass(
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isNight ? Colors.black.withOpacity(0.3) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.priorityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(t.typeIcon, color: t.priorityColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AText(
                        t.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${subjectName(subs, t.subjectId)} • ${intl.DateFormat('MMM d, h:mm a').format(t.dueDate!)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (diff <= 1
                                ? const Color(0xFFFF4757)
                                : const Color(0xFFFF9F43))
                            .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tl,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: diff <= 1
                          ? const Color(0xFFFF4757)
                          : const Color(0xFFFF9F43),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTaskDetails(BuildContext context, TaskModel t, List<Subject> subs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? const Color(0xFF12122A)
              : Colors.white,
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
      ),
    );
  }

  Widget _subjectsPreview(List<Subject> subs, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            '📚 Subjects',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        ...subs.map(
          (s) => GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: context.read<AppBloc>(),
                  child: SubjectDetailPage(subject: s),
                ),
              ),
            ),
            child: Glass(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(s.color).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Color(s.color),
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AText(
                          s.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (s.doctorName.isNotEmpty)
                          Text(
                            'Dr. ${s.doctorName}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${s.creditHours} CH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(s.color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _nightBeforeBanner(BuildContext context, List<TaskModel> exams) {
    // 🔊 Play critical exam sound once per session when banner first appears
    if (!_criticalExamAlerted) {
      _criticalExamAlerted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NovaAudioService.playAsset(
          'sounds/attention_critical_exam_detected_for_tomorrow.mp3',
        );
      });
    }
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => NightBeforeOverlay(exams: exams),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.15),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.6),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_moon_rounded,
                color: Colors.redAccent,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NIGHT BEFORE PROTOCOL',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Critical Exam detected. Tap to initialize.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
