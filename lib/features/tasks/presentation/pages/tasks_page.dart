import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/core/services/notifications_service.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/utils/helpers.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String _search = '';
  final _searchC = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: _showSearch
              ? TextField(
                  controller: _searchC,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search tasks...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  style: const TextStyle(fontSize: 16),
                  onChanged: (v) => setState(() => _search = v),
                )
              : const Text('Tasks'),
          actions: [
            IconButton(
              icon: Icon(
                _showSearch ? Icons.close_rounded : Icons.search_rounded,
              ),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchC.clear();
                    _search = '';
                  }
                });
              },
            ),
          ],
          bottom: TabBar(
            indicatorColor: const Color(0xFF6C63FF),
            labelColor: const Color(0xFF6C63FF),
            tabs: const [
              Tab(
                text: 'Pending',
                icon: Icon(Icons.pending_actions_rounded, size: 20),
              ),
              Tab(
                text: 'Completed',
                icon: Icon(Icons.done_all_rounded, size: 20),
              ),
              Tab(text: 'Failed', icon: Icon(Icons.cancel_rounded, size: 20)),
            ],
          ),
        ),
        body: BlocBuilder<AppBloc, AppState>(
          builder: (ctx, state) {
            var tasks = state.tasks
                .where((t) => t.isTask)
                .toList(); // ADD THIS LINE - filter out exams
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              tasks = tasks
                  .where(
                    (t) =>
                        t.title.toLowerCase().contains(q) ||
                        t.description.toLowerCase().contains(q) ||
                        t.type.toLowerCase().contains(q) ||
                        subjectName(
                          state.subjects,
                          t.subjectId,
                        ).toLowerCase().contains(q),
                  )
                  .toList();
            }
            final pending = tasks
                .where((t) => !t.isCompleted && !t.isFailed)
                .toList();
            final done = tasks.where((t) => t.isCompleted).toList();
            final failed = tasks.where((t) => t.isFailed).toList();
            return TabBarView(
              children: [
                _taskList(ctx, pending, state.subjects, false, false),
                _taskList(ctx, done, state.subjects, true, false),
                _taskList(ctx, failed, state.subjects, false, true),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'fab_tasks',
          onPressed: () => _showAddOrEdit(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Task'),
        ),
      ),
    );
  }

  Widget _taskList(
    BuildContext ctx,
    List<TaskModel> tasks,
    List<Subject> subs,
    bool isDone,
    bool isFailed,
  ) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFailed
                  ? Icons.cancel_presentation_rounded
                  : isDone
                  ? Icons.celebration_rounded
                  : _search.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.inbox_rounded,
              size: 56,
              color: Colors.grey.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _search.isNotEmpty
                  ? 'No tasks match "$_search"'
                  : isFailed
                  ? 'No failed tasks'
                  : isDone
                  ? 'No completed tasks'
                  : 'No pending tasks!',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 80),
      itemCount: tasks.length,
      itemBuilder: (_, i) => _taskCard(ctx, tasks[i], subs),
    );
  }

  Widget _taskCard(BuildContext ctx, TaskModel t, List<Subject> subs) {
    return Dismissible(
      key: Key('t${t.id}_${t.isCompleted}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          final ok =
              await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text('Delete Task?'),
                  content: Text(
                    'Are you sure you want to delete "${t.title}"?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Color(0xFFFF4757)),
                      ),
                    ),
                  ],
                ),
              ) ??
              false;
          if (ok) ctx.read<AppBloc>().add(DeleteTask(t.id!));
          return ok;
        } else if (direction == DismissDirection.startToEnd) {
          final action = t.isFailed
              ? 'mark as done'
              : t.isCompleted
              ? 'mark as pending'
              : 'mark as done';
          final ok =
              await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    t.isFailed
                        ? 'Mark as Done?'
                        : t.isCompleted
                        ? 'Mark as Pending?'
                        : 'Mark as Done?',
                  ),
                  content: Text('Do you want to $action "${t.title}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(
                        t.isFailed
                            ? 'Mark Done'
                            : t.isCompleted
                            ? 'Mark Pending'
                            : 'Mark Done',
                        style: const TextStyle(color: Color(0xFF2ED573)),
                      ),
                    ),
                  ],
                ),
              ) ??
              false;
          if (ok) {
            if (t.isFailed) {
              ctx.read<AppBloc>().add(
                ToggleTask(t.id!, true),
              ); // app_bloc will reset isFailed
            } else {
              ctx.read<AppBloc>().add(ToggleTask(t.id!, !t.isCompleted));
            }
          }
          return false;
        }
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2ED573),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              t.isFailed
                  ? Icons.check_circle_rounded
                  : t.isCompleted
                  ? Icons.undo_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              t.isFailed
                  ? 'Done'
                  : t.isCompleted
                  ? 'Undo'
                  : 'Done',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4757),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
      child: Glass(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showTaskDetails(ctx, t, subs),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => ctx.read<AppBloc>().add(
                        ToggleTask(t.id!, !t.isCompleted),
                      ),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.isCompleted
                              ? const Color(0xFF2ED573)
                              : Colors.transparent,
                          border: Border.all(
                            color: t.isFailed
                                ? const Color(0xFFFF4757)
                                : t.isCompleted
                                ? const Color(0xFF2ED573)
                                : t.priorityColor,
                            width: 2,
                          ),
                        ),
                        child: t.isFailed
                            ? const Icon(
                                Icons.cancel_rounded,
                                size: 14,
                                color: Color(0xFFFF4757),
                              )
                            : t.isCompleted
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AText(
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration: t.isCompleted || t.isFailed
                              ? TextDecoration.lineThrough
                              : null,
                          color: t.isFailed ? Colors.grey : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: t.priorityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        t.priorityLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: t.priorityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (t.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 34),
                    child: AText(
                      t.description,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (t.dueDate != null || t.subjectId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 34),
                    child: Row(
                      children: [
                        Icon(t.typeIcon, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          t.type[0].toUpperCase() + t.type.substring(1),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                        if (t.dueDate != null) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            intl.DateFormat('MMM d, h:mm a').format(t.dueDate!),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
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
      builder: (ctx) {
        final d = Theme.of(ctx).brightness == Brightness.dark;
        return BlocBuilder<AppBloc, AppState>(
          builder: (ctx, state) {
            // Get fresh task data
            final freshTask = state.tasks.firstWhere(
              (task) => task.id == t.id,
              orElse: () => t,
            );

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
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
                      Icon(
                        freshTask.typeIcon,
                        color: freshTask.priorityColor,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AText(
                          freshTask.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddOrEdit(context, edit: freshTask);
                        },
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: Color(0xFF6C63FF),
                        ),
                        tooltip: 'Edit',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _detailChip(
                        Icons.menu_book_rounded,
                        subjectName(subs, freshTask.subjectId),
                      ),
                      _detailChip(
                        Icons.priority_high_rounded,
                        "${freshTask.priorityLabel} Priority",
                        color: freshTask.priorityColor,
                      ),
                      _detailChip(
                        Icons.category_rounded,
                        freshTask.type[0].toUpperCase() +
                            freshTask.type.substring(1),
                      ),
                      if (freshTask.isCompleted)
                        _detailChip(
                          Icons.check_circle_rounded,
                          'Completed',
                          color: const Color(0xFF2ED573),
                        ),
                      // ═══ Show "Working" badge ═══
                      if (freshTask.isWorking && !freshTask.isCompleted)
                        _detailChip(
                          Icons.engineering_rounded,
                          'Working On It',
                          color: const Color(0xFF009FFD),
                        ),
                    ],
                  ),
                  const Divider(height: 30),
                  const Text(
                    "Description",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AText(
                    freshTask.description.isEmpty
                        ? "No description provided."
                        : freshTask.description,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  if (freshTask.dueDate != null) ...[
                    const Text(
                      "Deadline",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: Color(0xFF6C63FF),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          intl.DateFormat(
                            'EEEE, MMM d, yyyy',
                          ).format(freshTask.dueDate!),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 18,
                          color: Color(0xFF6C63FF),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          intl.DateFormat('h:mm a').format(freshTask.dueDate!),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (_) {
                        final now = DateTime.now();
                        final diff = freshTask.dueDate!.difference(now);
                        String remaining;
                        Color remainColor;
                        if (freshTask.isCompleted) {
                          remaining = 'Completed ✓';
                          remainColor = const Color(0xFF2ED573);
                        } else if (diff.isNegative) {
                          remaining =
                              'Overdue by ${diff.abs().inDays}d ${diff.abs().inHours % 24}h';
                          remainColor = const Color(0xFFFF4757);
                        } else if (diff.inDays > 0) {
                          remaining =
                              '${diff.inDays}d ${diff.inHours % 24}h remaining';
                          remainColor = const Color(0xFF2ED573);
                        } else if (diff.inHours > 0) {
                          remaining =
                              '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
                          remainColor = const Color(0xFFFF9F43);
                        } else {
                          remaining = '${diff.inMinutes}m remaining';
                          remainColor = const Color(0xFFFF4757);
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: remainColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timelapse_rounded,
                                size: 16,
                                color: remainColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                remaining,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: remainColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════
                  // "WORKING ON IT" BUTTON
                  // ═══════════════════════════════════════
                  if (!freshTask.isCompleted &&
                      freshTask.dueDate != null &&
                      freshTask.id != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final newStatus = !freshTask.isWorking;
                          context.read<AppBloc>().add(
                            SetTaskWorking(freshTask.id!, newStatus),
                          );

                          if (newStatus) {
                            // Stop urgent notifications
                            NotifService.stopUrgentTaskReminder(freshTask.id!);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: const [
                                    Icon(
                                      Icons.engineering_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Marked as working! Urgent reminders stopped.',
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF009FFD),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          } else {
                            // Resume urgent notifications if due < 3h
                            final diff = freshTask.dueDate!.difference(
                              DateTime.now(),
                            );
                            if (diff.inHours < 3 && !diff.isNegative) {
                              NotifService.startUrgentTaskReminder(
                                freshTask.id!,
                                freshTask.title,
                              );
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: const [
                                    Icon(
                                      Icons.notifications_active,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Urgent reminders resumed.'),
                                  ],
                                ),
                                backgroundColor: const Color(0xFFFF9F43),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          freshTask.isWorking
                              ? Icons.notifications_active_rounded
                              : Icons.engineering_rounded,
                          size: 20,
                        ),
                        label: Text(
                          freshTask.isWorking
                              ? 'Resume Reminders'
                              : '✅ Working On It',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: freshTask.isWorking
                              ? const Color(0xFFFF9F43)
                              : const Color(0xFF009FFD),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailChip(IconData icon, String label, {Color color = Colors.grey}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddOrEdit(BuildContext context, {TaskModel? edit}) {
    final state = context.read<AppBloc>().state;
    final titleC = TextEditingController(text: edit?.title ?? '');
    final descC = TextEditingController(text: edit?.description ?? '');
    int? subId = edit?.subjectId;
    int priority = edit?.priority ?? 2;
    String type = edit?.type ?? 'assignment';
    DateTime? dueDate = edit?.dueDate;
    TimeOfDay? dueTime = edit?.dueDate != null
        ? TimeOfDay(hour: edit!.dueDate!.hour, minute: edit.dueDate!.minute)
        : null;
    const types = ['assignment', 'project', 'report', 'presentation'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final d = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
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
                  Center(
                    child: Text(
                      edit != null ? 'Edit Task' : 'New Task',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleC,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                    textDirection: detectDir(titleC.text),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descC,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description_rounded),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textDirection: detectDir(descC.text),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: subId,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('General'),
                      ),
                      ...state.subjects.map(
                        (s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)),
                      ),
                    ],
                    onChanged: (v) => setS(() => subId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.category_rounded),
                    ),
                    items: types
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t[0].toUpperCase() + t.substring(1)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Priority',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _pChip(
                        'Low',
                        1,
                        const Color(0xFF2ED573),
                        priority,
                        (v) => setS(() => priority = v),
                      ),
                      const SizedBox(width: 8),
                      _pChip(
                        'Medium',
                        2,
                        const Color(0xFFFF9F43),
                        priority,
                        (v) => setS(() => priority = v),
                      ),
                      const SizedBox(width: 8),
                      _pChip(
                        'High',
                        3,
                        const Color(0xFFFF4757),
                        priority,
                        (v) => setS(() => priority = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: dueDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                            );
                            if (p != null) setS(() => dueDate = p);
                          },
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                          ),
                          label: Text(
                            dueDate != null
                                ? intl.DateFormat('MMM d').format(dueDate!)
                                : 'Date',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final p = await showTimePicker(
                              context: ctx,
                              initialTime:
                                  dueTime ??
                                  const TimeOfDay(hour: 23, minute: 59),
                            );
                            if (p != null) setS(() => dueTime = p);
                          },
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: Text(
                            dueTime != null ? dueTime!.format(ctx) : 'Time',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: () => setS(() {
                          dueDate = null;
                          dueTime = null;
                        }),
                        icon: const Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Clear date',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (titleC.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Enter title')),
                        );
                        return;
                      }
                      DateTime? fd;
                      if (dueDate != null) {
                        fd = DateTime(
                          dueDate!.year,
                          dueDate!.month,
                          dueDate!.day,
                          dueTime?.hour ?? 23,
                          dueTime?.minute ?? 59,
                        );
                      }
                      final task = TaskModel(
                        subjectId: subId,
                        title: titleC.text.trim(),
                        description: descC.text.trim(),
                        dueDate: fd,
                        priority: priority,
                        isCompleted: edit?.isCompleted ?? false,
                        type: type,
                        createdAt: edit?.createdAt,
                      );
                      if (edit != null) {
                        context.read<AppBloc>().add(EditTask(edit.id!, task));
                      } else {
                        context.read<AppBloc>().add(AddTask(task));
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      edit != null ? 'Update Task' : 'Add Task',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pChip(String l, int v, Color c, int sel, Function(int) onTap) {
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
              width: s ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              l,
              style: TextStyle(
                color: s ? c : Colors.grey,
                fontWeight: s ? FontWeight.w700 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
