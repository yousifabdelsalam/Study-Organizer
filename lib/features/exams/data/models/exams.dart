import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/utils/helpers.dart';

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key});

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exams & Quizzes'),
          bottom: TabBar(
            indicatorColor: const Color(0xFF6C63FF),
            labelColor: const Color(0xFF6C63FF),
            tabs: const [
              Tab(
                  text: 'Upcoming',
                  icon: Icon(Icons.event_note_rounded, size: 20)),
              Tab(
                  text: 'Completed',
                  icon: Icon(Icons.done_all_rounded, size: 20)),
            ],
          ),
        ),
        body: BlocBuilder<AppBloc, AppState>(
          builder: (ctx, state) {
            // Filter only exam types
            final allExams =
            state.tasks.where((t) => t.isExam).toList();
            final pending =
            allExams.where((t) => !t.isCompleted).toList();
            final done =
            allExams.where((t) => t.isCompleted).toList();

            return TabBarView(children: [
              _examList(ctx, pending, state.subjects, false),
              _examList(ctx, done, state.subjects, true),
            ]);
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddExam(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Exam'),
        ),
      ),
    );
  }

  Widget _examList(BuildContext ctx, List<TaskModel> exams,
      List<Subject> subs, bool isDone) {
    if (exams.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              isDone
                  ? Icons.celebration_rounded
                  : Icons.quiz_rounded,
              size: 56,
              color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(
              isDone
                  ? 'No completed exams'
                  : 'No upcoming exams!',
              style: const TextStyle(color: Colors.grey)),
        ]),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 80),
      itemCount: exams.length,
      itemBuilder: (_, i) => _examCard(ctx, exams[i], subs),
    );
  }

  Widget _examCard(
      BuildContext ctx, TaskModel t, List<Subject> subs) {
    return Dismissible(
      key: Key('exam_${t.id}_${t.isCompleted}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Delete Exam?'),
              content: Text(
                  'Are you sure you want to delete "${t.title}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Delete',
                        style:
                        TextStyle(color: Color(0xFFFF4757)))),
              ],
            ),
          ) ??
              false;
          if (ok) ctx.read<AppBloc>().add(DeleteTask(t.id!));
          return ok;
        } else if (direction == DismissDirection.startToEnd) {
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(t.isCompleted
                  ? 'Mark as Pending?'
                  : 'Mark as Done?'),
              content: Text(
                  'Do you want to ${t.isCompleted ? "mark as pending" : "mark as done"} "${t.title}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(
                        t.isCompleted
                            ? 'Mark Pending'
                            : 'Mark Done',
                        style: const TextStyle(
                            color: Color(0xFF2ED573)))),
              ],
            ),
          ) ??
              false;
          if (ok) {
            ctx
                .read<AppBloc>()
                .add(ToggleTask(t.id!, !t.isCompleted));
          }
          return false;
        }
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFF2ED573),
            borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              t.isCompleted
                  ? Icons.undo_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 28),
          const SizedBox(width: 8),
          Text(t.isCompleted ? 'Undo' : 'Done',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ]),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFFFF4757),
            borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Delete',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          SizedBox(width: 8),
          Icon(Icons.delete_rounded, color: Colors.white, size: 28),
        ]),
      ),
      child: Glass(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _examColor(t.type).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(t.typeIcon, size: 14, color: _examColor(t.type)),
                  const SizedBox(width: 4),
                  Text(
                      t.type[0].toUpperCase() + t.type.substring(1),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _examColor(t.type))),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.priorityColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(t.priorityLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: t.priorityColor)),
              ),
              const Spacer(),
              if (t.isCompleted)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF2ED573), size: 20),
            ]),
            const SizedBox(height: 8),
            AText(t.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  decoration:
                  t.isCompleted ? TextDecoration.lineThrough : null,
                )),
            const SizedBox(height: 4),
            Text(subjectName(subs, t.subjectId),
                style:
                const TextStyle(fontSize: 12, color: Colors.grey)),
            if (t.dueDate != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                    intl.DateFormat('EEEE, MMM d, h:mm a')
                        .format(t.dueDate!),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
                const Spacer(),
                _dueBadge(t.dueDate!),
              ]),
            ],
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              AText(t.description,
                  style:
                  const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dueBadge(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    final diff = dueDate.difference(today).inDays;

    String label;
    Color color;
    if (diff < 0) {
      label = 'Overdue';
      color = const Color(0xFFFF4757);
    } else if (diff == 0) {
      label = 'Today!';
      color = const Color(0xFFFF4757);
    } else if (diff == 1) {
      label = 'Tomorrow';
      color = const Color(0xFFFF9F43);
    } else {
      label = '$diff days';
      color = const Color(0xFF2ED573);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Color _examColor(String type) {
    switch (type) {
      case 'quiz':
        return const Color(0xFF6C63FF);
      case 'midterm':
        return const Color(0xFFFF9F43);
      case 'final':
        return const Color(0xFFFF4757);
      default:
        return Colors.grey;
    }
  }

  void _showAddExam(BuildContext context) {
    final state = context.read<AppBloc>().state;
    final titleC = TextEditingController();
    final descC = TextEditingController();
    int? subId;
    int priority = 3; // exams default high
    String type = 'quiz';
    DateTime? dueDate;
    TimeOfDay? dueTime;

    const types = ['quiz', 'midterm', 'final'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final d = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: BoxDecoration(
            color: d ? const Color(0xFF12122A) : Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28)),
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
                            borderRadius:
                            BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Center(
                    child: Text('New Exam',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700))),
                const SizedBox(height: 16),
                TextField(
                    controller: titleC,
                    decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title_rounded)),
                    textDirection: detectDir(titleC.text),
                    onChanged: (_) => setS(() {})),
                const SizedBox(height: 10),
                TextField(
                    controller: descC,
                    decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon:
                        Icon(Icons.description_rounded)),
                    maxLines: 3,
                    minLines: 1,
                    textDirection: detectDir(descC.text),
                    onChanged: (_) => setS(() {})),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                    value: subId,
                    decoration: const InputDecoration(
                        labelText: 'Subject',
                        prefixIcon:
                        Icon(Icons.menu_book_rounded)),
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('General')),
                      ...state.subjects.map((s) =>
                          DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name))),
                    ],
                    onChanged: (v) => setS(() => subId = v)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                        labelText: 'Exam Type',
                        prefixIcon:
                        Icon(Icons.category_rounded)),
                    items: types
                        .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t[0].toUpperCase() +
                            t.substring(1))))
                        .toList(),
                    onChanged: (v) =>
                        setS(() => type = v!)),
                const SizedBox(height: 12),
                const Text('Priority',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  _pChip('Low', 1, const Color(0xFF2ED573),
                      priority, (v) => setS(() => priority = v)),
                  const SizedBox(width: 8),
                  _pChip(
                      'Medium',
                      2,
                      const Color(0xFFFF9F43),
                      priority,
                          (v) => setS(() => priority = v)),
                  const SizedBox(width: 8),
                  _pChip('High', 3, const Color(0xFFFF4757),
                      priority, (v) => setS(() => priority = v)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate:
                          dueDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(
                              const Duration(days: 30)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 730)),
                        );
                        if (p != null) {
                          setS(() => dueDate = p);
                        }
                      },
                      icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18),
                      label: Text(
                          dueDate != null
                              ? intl.DateFormat('MMM d')
                              .format(dueDate!)
                              : 'Date',
                          style:
                          const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final p = await showTimePicker(
                            context: ctx,
                            initialTime: dueTime ??
                                const TimeOfDay(
                                    hour: 9, minute: 0));
                        if (p != null) {
                          setS(() => dueTime = p);
                        }
                      },
                      icon: const Icon(
                          Icons.access_time_rounded,
                          size: 18),
                      label: Text(
                          dueTime != null
                              ? dueTime!.format(ctx)
                              : 'Time',
                          style:
                          const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12))),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    if (titleC.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Enter title')));
                      return;
                    }
                    DateTime? fd;
                    if (dueDate != null) {
                      fd = DateTime(
                          dueDate!.year,
                          dueDate!.month,
                          dueDate!.day,
                          dueTime?.hour ?? 9,
                          dueTime?.minute ?? 0);
                    }
                    final task = TaskModel(
                      subjectId: subId,
                      title: titleC.text.trim(),
                      description: descC.text.trim(),
                      dueDate: fd,
                      priority: priority,
                      type: type,
                    );
                    context.read<AppBloc>().add(AddTask(task));
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                      const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(14))),
                  child: const Text('Add Exam',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _pChip(
      String l, int v, Color c, int sel, Function(int) onTap) {
    final s = sel == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(v),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: s ? c.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: s ? c : Colors.grey.withOpacity(0.3),
                width: s ? 2 : 1),
          ),
          child: Center(
              child: Text(l,
                  style: TextStyle(
                      color: s ? c : Colors.grey,
                      fontWeight:
                      s ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 12))),
        ),
      ),
    );
  }
}