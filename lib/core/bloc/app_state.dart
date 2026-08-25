import 'package:equatable/equatable.dart';
import 'package:study_organizer/features/subjects/data/models/topic.dart';
import 'package:study_organizer/features/subjects/data/models/subject_note.dart';
import 'package:study_organizer/features/ai_assistant/data/models/jarvis_document.dart';
import 'package:study_organizer/features/subjects/data/models/subject_metadata.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/tasks/data/models/task.dart';
import 'package:study_organizer/features/marks/data/models/mark.dart';
import 'package:study_organizer/features/marks/data/models/semester.dart';
import 'package:study_organizer/features/calendar/data/models/timetable.dart';
import 'package:study_organizer/features/calendar/data/models/reminder.dart';

class AppState extends Equatable {
  final List<Subject> subjects;
  final List<TaskModel> tasks;
  final List<Map<String, dynamic>> absences;
  final List<MarkModel> marks;
  final List<SemesterModel> semesters;
  final List<TimetableEntry> timetable;
  final List<ReminderModel> reminders;
  final List<StudyTopic> topics;
  final List<SubjectNote> subjectNotes;
  final List<JarvisDocument> jarvisDocuments;
  final List<SubjectMetadata> subjectMetadata;
  final bool loading;
  final String currentWeekType;
  final DateTime lastUpdated;

  AppState({
    this.subjects = const [],
    this.tasks = const [],
    this.absences = const [],
    this.marks = const [],
    this.semesters = const [],
    this.timetable = const [],
    this.reminders = const [],
    this.topics = const [],
    this.subjectNotes = const [],
    this.jarvisDocuments = const [],
    this.subjectMetadata = const [],
    this.loading = true,
    this.currentWeekType = 'odd',
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime(2000);

  String instructorFocusFor(int subjectId) {
    try {
      return subjectMetadata.firstWhere((e) => e.subjectId == subjectId).instructorFocus;
    } catch (_) {
      return '';
    }
  }

  AppState copyWith({
    List<Subject>? subjects,
    List<TaskModel>? tasks,
    List<Map<String, dynamic>>? absences,
    List<MarkModel>? marks,
    List<SemesterModel>? semesters,
    List<TimetableEntry>? timetable,
    List<ReminderModel>? reminders,
    List<StudyTopic>? topics,
    List<SubjectNote>? subjectNotes,
    List<JarvisDocument>? jarvisDocuments,
    List<SubjectMetadata>? subjectMetadata,
    bool? loading,
    String? currentWeekType,
    DateTime? lastUpdated,
  }) =>
      AppState(
        subjects: subjects ?? this.subjects,
        tasks: tasks ?? this.tasks,
        absences: absences ?? this.absences,
        marks: marks ?? this.marks,
        semesters: semesters ?? this.semesters,
        timetable: timetable ?? this.timetable,
        reminders: reminders ?? this.reminders,
        topics: topics ?? this.topics,
        subjectNotes: subjectNotes ?? this.subjectNotes,
        jarvisDocuments: jarvisDocuments ?? this.jarvisDocuments,
        subjectMetadata: subjectMetadata ?? this.subjectMetadata,
        loading: loading ?? this.loading,
        currentWeekType: currentWeekType ?? this.currentWeekType,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  @override
  List<Object?> get props => [
        subjects, tasks, absences, marks, semesters,
        timetable, reminders, topics, subjectNotes,
        jarvisDocuments, subjectMetadata,
        loading, currentWeekType, lastUpdated,
      ];
}

class changed extends AppState {}