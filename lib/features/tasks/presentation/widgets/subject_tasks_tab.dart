import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/utils/helpers.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';

class SubjectTasksTab extends StatelessWidget {
  final Subject subject;
  final List<TaskModel> tasks;
  final List<Subject> allSubjects;

  const SubjectTasksTab({
    super.key,
    required this.subject,
    required this.tasks,
    required this.allSubjects,
  });

  @override
  Widget build(BuildContext context) {
    return _tasksTab(context, tasks, allSubjects);
  }

    Widget _tasksTab(
    BuildContext ctx,
    List<TaskModel> tasks,
    List<Subject> subs,
  ) {
    final pending = tasks.where((t) => !t.isCompleted && !t.isFailed).toList();
    final done = tasks.where((t) => t.isCompleted).toList();
    final failed = tasks.where((t) => t.isFailed).toList();
    if (tasks.isEmpty)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_rounded,
              size: 44,
              color: Colors.grey.withOpacity(0.3),
            ),
            const SizedBox(height: 6),
            const Text('No tasks', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    return _TasksTabContent(
      pending: pending,
      done: done,
      failed: failed,
      subs: subs,
      buildCard: (t) => _subjectTaskCard(ctx, t, subs),
      onShowDetails: (t) => _showSubjectTaskDetails(ctx, t, subs),
    );
  }


    Widget _subjectTaskCard(BuildContext ctx, TaskModel t, List<Subject> subs) {
    return Dismissible(
      key: Key('st${t.id}_${t.isCompleted}'),
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
                  content: Text('Delete "${t.title}"?'),
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
        } else {
          final ok =
              await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    t.isCompleted ? 'Mark as Pending?' : 'Mark as Done?',
                  ),
                  content: Text(
                    '${t.isCompleted ? 'Mark as pending' : 'Mark as done'} "${t.title}"?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(
                        t.isCompleted ? 'Mark Pending' : 'Mark Done',
                        style: const TextStyle(color: Color(0xFF2ED573)),
                      ),
                    ),
                  ],
                ),
              ) ??
              false;
          if (ok) ctx.read<AppBloc>().add(ToggleTask(t.id!, !t.isCompleted));
          return false;
        }
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
              t.isCompleted ? Icons.undo_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              t.isCompleted ? 'Undo' : 'Done',
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
          onTap: () => _showSubjectTaskDetails(ctx, t, subs),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                GestureDetector(
                  onTap: () => ctx.read<AppBloc>().add(
                    ToggleTask(t.id!, !t.isCompleted),
                  ),
                  onLongPress: () =>
                      ctx.read<AppBloc>().add(FailTask(t.id!, !t.isFailed)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.isFailed
                          ? const Color(0xFFFF4757)
                          : t.isCompleted
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
                            Icons.close_rounded,
                            size: 13,
                            color: Colors.white,
                          )
                        : t.isCompleted
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
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: (t.isCompleted || t.isFailed)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (t.dueDate != null)
                        Text(
                          intl.DateFormat('MMM d, h:mm a').format(t.dueDate!),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: t.priorityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t.priorityLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: t.priorityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (t.isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ED573).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFF2ED573),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (t.isFailed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4757).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Failed',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFFF4757),
                            fontWeight: FontWeight.w600,
                          ),
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

  void _showSubjectTaskDetails(
    BuildContext context,
    TaskModel t,
    List<Subject> subs,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final d = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: d ? const Color(0xFF12122A) : Colors.white,
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
                  if (t.isCompleted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ED573).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Color(0xFF2ED573),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2ED573),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _detailChipLocal(
                      Icons.menu_book_rounded,
                      subjectName(subs, t.subjectId),
                    ),
                    const SizedBox(width: 8),
                    _detailChipLocal(
                      Icons.priority_high_rounded,
                      "${t.priorityLabel} Priority",
                      color: t.priorityColor,
                    ),
                    const SizedBox(width: 8),
                    _detailChipLocal(
                      Icons.category_rounded,
                      t.type[0].toUpperCase() + t.type.substring(1),
                    ),
                  ],
                ),
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
                t.description.isEmpty
                    ? "No description provided."
                    : t.description,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (t.dueDate != null) ...[
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
                      intl.DateFormat('EEEE, MMM d, yyyy').format(t.dueDate!),
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
                      intl.DateFormat('h:mm a').format(t.dueDate!),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final now = DateTime.now();
                    final diff = t.dueDate!.difference(now);
                    String remaining;
                    Color remainColor;
                    if (diff.isNegative) {
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
              const SizedBox(height: 30),
              // ── State-change action buttons ──
              Row(
                children: [
                  if (!t.isFailed)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<AppBloc>().add(FailTask(t.id!, true));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.cancel_rounded, size: 16),
                        label: const Text('Mark as Failed'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF4757),
                          side: const BorderSide(color: Color(0xFFFF4757)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (t.isFailed) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<AppBloc>().add(FailTask(t.id!, false));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('Restore to Pending'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2ED573),
                          side: const BorderSide(color: Color(0xFF2ED573)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailChipLocal(
    IconData icon,
    String label, {
    Color color = Colors.grey,
  }) {
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOVA TAB — Stateful widget for editable instructor focus + PDF/PPTX upload
// ═══════════════════════════════════════════════════════════════════════════════

  class _TasksTabContent extends StatefulWidget {
  final List<TaskModel> pending;
  final List<TaskModel> done;
  final List<TaskModel> failed;
  final List<Subject> subs;
  final Widget Function(TaskModel) buildCard;
  final void Function(TaskModel) onShowDetails;
  const _TasksTabContent({
    required this.pending,
    required this.done,
    required this.failed,
    required this.subs,
    required this.buildCard,
    required this.onShowDetails,
  });
  @override
  State<_TasksTabContent> createState() => _TasksTabContentState();
}

class _TasksTabContentState extends State<_TasksTabContent> {
  bool _doneExpanded = false;
  bool _failedExpanded = false;
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      children: [
        if (widget.pending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.pending_actions_rounded,
                  size: 18,
                  color: Color(0xFFFF9F43),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pending (${widget.pending.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFFFF9F43),
                  ),
                ),
              ],
            ),
          ),
          ...widget.pending.map((t) => widget.buildCard(t)),
        ],
        if (widget.pending.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.celebration_rounded,
                    size: 40,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'All tasks completed! 🎉',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        if (widget.done.isNotEmpty) ...[
          const SizedBox(height: 8),
          Glass(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _doneExpanded = !_doneExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: Color(0xFF2ED573),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Completed (${widget.done.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF2ED573),
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _doneExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF2ED573),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.done.map((t) => widget.buildCard(t)).toList(),
            ),
            crossFadeState: _doneExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
        // ── Failed Tasks Section ──
        if (widget.failed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Glass(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _failedExpanded = !_failedExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cancel_rounded,
                      size: 20,
                      color: Color(0xFFFF4757),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Failed (${widget.failed.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFFFF4757),
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _failedExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFFF4757),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.failed.map((t) => widget.buildCard(t)).toList(),
            ),
            crossFadeState: _failedExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ],
    );
  }
}
