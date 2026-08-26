import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:study_organizer/features/subjects/presentation/pages/subject_detail_page.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/core/services/notifications_service.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/core/utils/helpers.dart';

class SubjectsPage extends StatelessWidget {
  const SubjectsPage({super.key});

  static const _colors = [
    0xFF6C63FF,
    0xFFFF6B81,
    0xFF2ED573,
    0xFFFF9F43,
    0xFF1E90FF,
    0xFFFF4757,
    0xFF7B68EE,
    0xFF00CEC9,
    0xFFE17055,
    0xFFFD79A8,
    0xFF00B894,
    0xFF6C5CE7,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subjects')),
      body: BlocBuilder<AppBloc, AppState>(
        builder: (ctx, state) {
          if (state.subjects.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 56,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No subjects yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(top: 6, bottom: 80),
            itemCount: state.subjects.length,
            itemBuilder: (_, i) => _subjectCard(ctx, state.subjects[i], state),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_subjects',
        onPressed: () => _showAdd(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Subject'),
      ),
    );
  }

  Widget _subjectCard(BuildContext ctx, Subject s, AppState state) {
    return Glass(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: () => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: ctx.read<AppBloc>(),
              child: SubjectDetailPage(subject: s),
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Color(s.color).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text(
                      s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Color(s.color),
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AText(
                        s.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${s.creditHours} Credit Hours',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_rounded,
                            size: 18,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (v) async {
                    if (v == 'edit') {
                      _showAdd(ctx, edit: s);
                    } else {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: Text('Delete ${s.name}?'),
                          content: const Text(
                            'All related data will be deleted.',
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
                      );
                      if (ok == true)
                        ctx.read<AppBloc>().add(DeleteSubject(s.id!));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (s.doctorName.isNotEmpty)
                  _chip(
                    Icons.person_rounded,
                    'Dr. ${s.doctorName}',
                    Color(s.color),
                  ),
                if (s.hasSection && s.sectionEngineer.isNotEmpty)
                  _chip(
                    Icons.engineering_rounded,
                    'Sec: ${s.sectionEngineer}',
                    Colors.teal,
                  ),
                if (s.hasLab && s.labEngineer.isNotEmpty)
                  _chip(
                    Icons.science_rounded,
                    'Lab: ${s.labEngineer}',
                    Colors.orange,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData ic, String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: 13, color: c),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              t,
              style: TextStyle(
                fontSize: 10,
                color: c,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showAdd(BuildContext context, {Subject? edit}) {
    final nameC = TextEditingController(text: edit?.name ?? '');
    final docC = TextEditingController(text: edit?.doctorName ?? '');
    final secC = TextEditingController(text: edit?.sectionEngineer ?? '');
    final labC = TextEditingController(text: edit?.labEngineer ?? '');
    int ch = edit?.creditHours ?? 3;
    int col = edit?.color ?? _colors[0];
    int mL = edit?.maxLectureAbs ?? 4;
    int mS = edit?.maxSectionAbs ?? 4;
    int mLab = edit?.maxLabAbs ?? 4;
    bool hasSec = edit?.hasSection ?? true;
    bool hasLab = edit?.hasLab ?? false;
    int step = 0;

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
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
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
                      edit != null ? 'Edit Subject' : 'New Subject',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Step indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Container(
                        width: step == i ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: step == i
                              ? const Color(0xFF6C63FF)
                              : Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (step == 0) ...[
                    const Text(
                      '📖 Basic Info',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameC,
                      decoration: const InputDecoration(
                        labelText: 'Subject Name',
                        prefixIcon: Icon(Icons.menu_book_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: docC,
                      decoration: const InputDecoration(
                        labelText: 'Doctor Name',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'Credit Hours: ',
                          style: TextStyle(fontSize: 13),
                        ),
                        IconButton(
                          onPressed: () {
                            if (ch > 1) setS(() => ch--);
                          },
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 22,
                          ),
                        ),
                        Text(
                          '$ch',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setS(() => ch++),
                          icon: const Icon(Icons.add_circle_outline, size: 22),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Color', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _colors.map((c) {
                        final s = col == c;
                        return GestureDetector(
                          onTap: () => setS(() => col = c),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: s
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                              boxShadow: s
                                  ? [
                                      BoxShadow(
                                        color: Color(c).withOpacity(0.5),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: s
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (step == 1) ...[
                    const Text(
                      '👥 Staff & Sections',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: const Text(
                              'Section',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: hasSec,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) => setS(() => hasSec = v),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text(
                              'Lab',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: hasLab,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) => setS(() => hasLab = v),
                          ),
                        ),
                      ],
                    ),
                    if (hasSec) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: secC,
                        decoration: const InputDecoration(
                          labelText: 'Section Engineer',
                          prefixIcon: Icon(Icons.engineering_rounded),
                        ),
                      ),
                    ],
                    if (hasLab) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: labC,
                        decoration: const InputDecoration(
                          labelText: 'Lab Engineer',
                          prefixIcon: Icon(Icons.science_rounded),
                        ),
                      ),
                    ],
                  ],
                  if (step == 2) ...[
                    const Text(
                      '📊 Absence Limits',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _absRow(
                      'Max Lecture Absences',
                      mL,
                      (v) => setS(() => mL = v),
                    ),
                    if (hasSec)
                      _absRow(
                        'Max Section Absences',
                        mS,
                        (v) => setS(() => mS = v),
                      ),
                    if (hasLab)
                      _absRow(
                        'Max Lab Absences',
                        mLab,
                        (v) => setS(() => mLab = v),
                      ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (step > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setS(() => step--),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Back'),
                          ),
                        ),
                      if (step > 0) const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (step < 2) {
                              setS(() => step++);
                              return;
                            }
                            if (nameC.text.trim().isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Enter name')),
                              );
                              return;
                            }
                            final sub = Subject(
                              name: nameC.text.trim(),
                              doctorName: docC.text.trim(),
                              sectionEngineer: secC.text.trim(),
                              labEngineer: labC.text.trim(),
                              color: col,
                              creditHours: ch,
                              maxLectureAbs: mL,
                              maxSectionAbs: mS,
                              maxLabAbs: mLab,
                              hasSection: hasSec,
                              hasLab: hasLab,
                            );
                            if (edit != null) {
                              context.read<AppBloc>().add(
                                UpdateSubject(edit.id!, sub),
                              );
                            } else {
                              context.read<AppBloc>().add(AddSubject(sub));
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
                            step < 2
                                ? 'Next'
                                : (edit != null ? 'Update' : 'Create'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
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

  Widget _absRow(String label, int val, Function(int) onChange) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          IconButton(
            onPressed: () {
              if (val > 1) onChange(val - 1);
            },
            icon: const Icon(Icons.remove_circle_outline, size: 22),
          ),
          Text(
            '$val',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          IconButton(
            onPressed: () => onChange(val + 1),
            icon: const Icon(Icons.add_circle_outline, size: 22),
          ),
        ],
      ),
    );
  }
}
