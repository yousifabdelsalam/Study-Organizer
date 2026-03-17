import 'package:equatable/equatable.dart';
import 'package:study_organizer/models/topic.dart';
import 'package:study_organizer/models/subject_note.dart';
import 'package:study_organizer/models/jarvis_document.dart';
import '../models/task.dart';
import '../models/subject.dart';
import '../models/mark.dart';
import '../models/semester.dart';
import '../models/timetable.dart';
import '../models/reminder.dart';

abstract class AppEvent extends Equatable {
  const AppEvent();
  @override
  List<Object?> get props => [];
}

class LoadAll extends AppEvent {}

class AddSubject extends AppEvent {
  final Subject s;
  const AddSubject(this.s);
}

class UpdateSubject extends AppEvent {
  final int id;
  final Subject s;
  const UpdateSubject(this.id, this.s);
}

class DeleteSubject extends AppEvent {
  final int id;
  const DeleteSubject(this.id);
}

class AddTask extends AppEvent {
  final TaskModel t;
  const AddTask(this.t);
}

class UpdateTask extends AppEvent {
  final int id;
  final Map<String, dynamic> data;
  const UpdateTask(this.id, this.data);
}

class DeleteTask extends AppEvent {
  final int id;
  const DeleteTask(this.id);
}

class ToggleTask extends AppEvent {
  final int id;
  final bool done;
  const ToggleTask(this.id, this.done);
}

class FailTask extends AppEvent {
  final int id;
  final bool failed;
  const FailTask(this.id, this.failed);
}

class EditTask extends AppEvent {
  final int id;
  final TaskModel t;
  const EditTask(this.id, this.t);
}

class AddAbsence extends AppEvent {
  final int subjectId;
  final String date, type;
  const AddAbsence(this.subjectId, this.date, this.type);
}

class DeleteAbsence extends AppEvent {
  final int id;
  const DeleteAbsence(this.id);
}

class AddMark extends AppEvent {
  final MarkModel m;
  const AddMark(this.m);
}

class DeleteMark extends AppEvent {
  final int id;
  const DeleteMark(this.id);
}

class AddSemester extends AppEvent {
  final SemesterModel s;
  const AddSemester(this.s);
}

class DeleteSemester extends AppEvent {
  final int id;
  const DeleteSemester(this.id);
}

class AddTimetableEntry extends AppEvent {
  final TimetableEntry entry;
  const AddTimetableEntry(this.entry);
}

class DeleteTimetableEntry extends AppEvent {
  final int id;
  const DeleteTimetableEntry(this.id);
}

// NEW: edit an existing timetable entry in-place
class UpdateTimetableEntry extends AppEvent {
  final TimetableEntry entry; // must have a valid id
  const UpdateTimetableEntry(this.entry);
  @override
  List<Object?> get props => [entry];
}

class AddReminder extends AppEvent {
  final ReminderModel r;
  const AddReminder(this.r);
}

class DeleteReminder extends AppEvent {
  final int id;
  const DeleteReminder(this.id);
}

class ToggleReminder extends AppEvent {
  final int id;
  final bool done;
  const ToggleReminder(this.id, this.done);
}

class SetWeekType extends AppEvent {
  final String weekType;
  const SetWeekType(this.weekType);
}

class ExportData extends AppEvent {}

class ImportData extends AppEvent {
  final String filePath;
  const ImportData(this.filePath);
}

class AddTopic extends AppEvent {
  final StudyTopic topic;
  const AddTopic(this.topic);
}

class UpdateTopic extends AppEvent {
  final StudyTopic topic;
  const UpdateTopic(this.topic);
}

class ReviewTopic extends AppEvent {
  final StudyTopic topic;
  const ReviewTopic(this.topic);
}

class DeleteTopic extends AppEvent {
  final int id;
  const DeleteTopic(this.id);
}

class ResetTopic extends AppEvent {
  final StudyTopic topic;
  const ResetTopic(this.topic);
}

class SetTopicReviewDate extends AppEvent {
  final StudyTopic topic;
  final DateTime reviewDate;
  const SetTopicReviewDate(this.topic, this.reviewDate);
}

class SetTaskWorking extends AppEvent {
  final int taskId;
  final bool isWorking;
  const SetTaskWorking(this.taskId, this.isWorking);
}

class RescheduleTimetableNotifs extends AppEvent {}

class RescheduleReminderNotifs extends AppEvent {}

// Subject Notes
class AddSubjectNote extends AppEvent {
  final SubjectNote note;
  const AddSubjectNote(this.note);
}

class UpdateSubjectNote extends AppEvent {
  final SubjectNote note;
  const UpdateSubjectNote(this.note);
}

class DeleteSubjectNote extends AppEvent {
  final int id;
  const DeleteSubjectNote(this.id);
}

class TimetableTimeTick extends AppEvent {
  const TimetableTimeTick();
}

class EndWeek extends AppEvent {
  final bool end;
  const EndWeek(this.end);
}

// JARVIS brain: documents & instructor focus
class AddJarvisDocument extends AppEvent {
  final JarvisDocument document;
  const AddJarvisDocument(this.document);
}

class DeleteJarvisDocument extends AppEvent {
  final int id;
  const DeleteJarvisDocument(this.id);
}

class SetInstructorFocus extends AppEvent {
  final int subjectId;
  final String focus;
  const SetInstructorFocus(this.subjectId, this.focus);
}
