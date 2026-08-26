import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_state.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/attendance/presentation/widgets/subject_attendance_tab.dart';
import 'package:study_organizer/features/marks/presentation/widgets/subject_marks_tab.dart';
import 'package:study_organizer/features/tasks/presentation/widgets/subject_tasks_tab.dart';
import 'package:study_organizer/features/topics/presentation/widgets/subject_topics_tab.dart';
import 'package:study_organizer/features/notes/presentation/widgets/subject_notes_tab.dart';
import 'package:study_organizer/features/documents/presentation/widgets/subject_documents_tab.dart';

class SubjectDetailPage extends StatelessWidget {
  final Subject subject;
  const SubjectDetailPage({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(subject.name),
          bottom: TabBar(
            indicatorColor: Color(subject.color),
            labelColor: Color(subject.color),
            isScrollable: true,
            tabs: const [
              Tab(
                text: 'Attendance',
                icon: Icon(Icons.event_busy_rounded, size: 20),
              ),
              Tab(text: 'Marks', icon: Icon(Icons.grade_rounded, size: 20)),
              Tab(text: 'Tasks', icon: Icon(Icons.task_rounded, size: 20)),
              Tab(
                text: 'Study Topics',
                icon: Icon(Icons.menu_book_rounded, size: 20),
              ),
              Tab(text: 'Notes', icon: Icon(Icons.note_rounded, size: 20)),
              Tab(text: 'NOVA', icon: Icon(Icons.psychology_rounded, size: 20)),
            ],
          ),
        ),
        body: BlocBuilder<AppBloc, AppState>(
          builder: (ctx, state) {
            final abs = state.absences
                .where((a) => a['subjectId'] == subject.id)
                .toList();
            final marks = state.marks
                .where((m) => m.subjectId == subject.id)
                .toList();
            final tasks = state.tasks
                .where((t) => t.subjectId == subject.id)
                .toList();
            final topics = state.topics
                .where((t) => t.subjectId == subject.id)
                .toList();
            final notes = state.subjectNotes
                .where((n) => n.subjectId == subject.id)
                .toList();
            final docs = state.jarvisDocuments
                .where((d) => d.subjectId == subject.id)
                .toList();
            final instructorFocus = state.instructorFocusFor(subject.id ?? 0);
            final lCount = abs.where((a) => a['type'] == 'lecture').length;
            final sCount = abs.where((a) => a['type'] == 'section').length;
            final labCount = abs.where((a) => a['type'] == 'lab').length;

            return TabBarView(
              children: [
                SubjectAttendanceTab(
                  subject: subject,
                  abs: abs,
                  lCount: lCount,
                  sCount: sCount,
                  labCount: labCount,
                ),
                SubjectMarksTab(
                  subject: subject,
                  marks: marks,
                  abs: abs,
                  docs: docs,
                ),
                SubjectTasksTab(
                  subject: subject,
                  tasks: tasks,
                  allSubjects: state.subjects,
                ),
                SubjectTopicsTab(
                  subject: subject,
                  topics: topics,
                  docs: docs,
                ),
                SubjectNotesTab(
                  subject: subject,
                  notes: notes,
                ),
                SubjectDocumentsTab(
                  subject: subject,
                  docs: docs,
                  instructorFocus: instructorFocus,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
