import 'package:flutter/material.dart';
import 'package:study_organizer/models/exams.dart';
import 'dashboard.dart';
import 'tasks.dart';
import 'calendar.dart';
import 'subjects.dart';
import 'marks.dart';
import 'campus.dart';
import 'nova_settings_page.dart';
import 'weekly_briefing_page.dart';
import 'study_plan_page.dart';
import 'daily_schedule_page.dart';
import '../widgets/nova_brief_card.dart';
import '../services/nova_brief_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _idx = 0;

  final _pages = [
    const DashboardPage(),
    const TasksPage(),
    const ExamsPage(),
    const CalendarPage(),
    const SubjectsPage(),
    const MarksPage(),
    const CampusPage(),
  ];

  void switchTo(int index) {
    setState(() => _idx = index);
  }

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _idx, children: _pages),

          // ── NOVA paused-brief banner (shown after volume-UP dismisses TTS) ──
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: d ? const Color(0xFF12122A) : Colors.white,
          border: Border(
            top: BorderSide(
              color: d ? Colors.white12 : Colors.black12,
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navBtn(0, Icons.dashboard_rounded, 'Home'),
                _navBtn(1, Icons.task_alt_rounded, 'Tasks'),
                _navBtn(2, Icons.quiz_rounded, 'Exams'),
                _navBtn(3, Icons.calendar_month_rounded, 'Cal'),
                _navBtn(4, Icons.menu_book_rounded, 'Subjects'),
                _navBtn(5, Icons.analytics_rounded, 'Marks'),
                _navBtn(6, Icons.location_on_rounded, 'Campus'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navBtn(int i, IconData icon, String label) {
    final sel = _idx == i;
    final color = sel ? const Color(0xFF6C63FF) : Colors.grey;
    return InkWell(
      onTap: () => setState(() => _idx = i),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                color: color,
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
