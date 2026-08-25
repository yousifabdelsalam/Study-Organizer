import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:table_calendar/table_calendar.dart';

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/utils/helpers.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _fmt = CalendarFormat.month;
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: BlocBuilder<AppBloc, AppState>(
        builder: (ctx, state) {
          final events = <DateTime, List<TaskModel>>{};
          for (final t in state.tasks) {
            if (t.dueDate != null) {
              final k = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
              events.putIfAbsent(k, () => []).add(t);
            }
          }
          final selKey = DateTime(_selected.year, _selected.month, _selected.day);
          final selTasks = events[selKey] ?? [];

          return Column(children: [
            Glass(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: TableCalendar<TaskModel>(
                firstDay: DateTime.utc(2020), lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focused,
                calendarFormat: _fmt,
                selectedDayPredicate: (d) => isSameDay(_selected, d),
                eventLoader: (d) => events[DateTime(d.year, d.month, d.day)] ?? [],
                startingDayOfWeek: StartingDayOfWeek.saturday,
                onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
                onFormatChanged: (f) => setState(() => _fmt = f),
                onPageChanged: (f) => _focused = f,
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.3), shape: BoxShape.circle),
                  selectedDecoration: const BoxDecoration(color: Color(0xFF6C63FF), shape: BoxShape.circle),
                  markerDecoration: const BoxDecoration(color: Color(0xFFFF9F43), shape: BoxShape.circle),
                  markerSize: 5, markersMaxCount: 3, outsideDaysVisible: false,
                ),
                headerStyle: HeaderStyle(
                  formatButtonDecoration: BoxDecoration(border: Border.all(color: const Color(0xFF6C63FF)), borderRadius: BorderRadius.circular(10)),
                  formatButtonTextStyle: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12),
                  titleCentered: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(children: [
                Text(intl.DateFormat('EEEE, MMM d').format(_selected),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                Text('${selTasks.length} task(s)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
            Expanded(
              child: selTasks.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.event_available_rounded, size: 44, color: Colors.grey.withOpacity(0.3)),
                const SizedBox(height: 6),
                const Text('No tasks this day', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ]))
                  : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: selTasks.length,
                itemBuilder: (_, i) {
                  final t = selTasks[i];
                  return Glass(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(width: 4, height: 40, decoration: BoxDecoration(color: t.priorityColor, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(width: 10),
                      Icon(t.typeIcon, color: t.priorityColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AText(t.title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                            decoration: t.isCompleted ? TextDecoration.lineThrough : null)),
                        Text('${subjectName(state.subjects, t.subjectId)} • ${t.type}',
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ])),
                      if (t.dueDate != null)
                        Text(intl.DateFormat('h:mm a').format(t.dueDate!), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}