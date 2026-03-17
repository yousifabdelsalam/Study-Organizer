import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:study_organizer/models/topic.dart';
import 'package:study_organizer/models/subject_note.dart';
import 'package:study_organizer/models/jarvis_document.dart';
import 'package:study_organizer/models/subject_metadata.dart';
import 'package:study_organizer/services/nova_audio_service.dart';

import '../services/database.dart';
import '../models/subject.dart';
import '../models/task.dart';
import '../models/mark.dart';
import '../models/semester.dart';
import '../models/timetable.dart';
import '../models/reminder.dart';
import '../services/notifications.dart';
import 'app_event.dart';
import 'app_state.dart';

class AppBloc extends Bloc<AppEvent, AppState> {
  Timer? _timetableUpdateTimer;
  DateTime? _nextScheduledUpdate;
  final Database db;
  bool fullmark = false;
  bool isEndDay = false;

  static AppBloc get(BuildContext context) => BlocProvider.of(context);

  AppBloc(this.db) : super(AppState()) {
    on<LoadAll>(_onLoad);
    on<AddSubject>(_onAddSubject);
    on<UpdateSubject>(_onUpdateSubject);
    on<DeleteSubject>(_onDeleteSubject);
    on<AddTask>(_onAddTask);
    on<EditTask>(_onEditTask);
    on<UpdateTask>(_onUpdateTask);
    on<DeleteTask>(_onDeleteTask);
    on<ToggleTask>(_onToggleTask);
    on<FailTask>(_onFailTask);
    on<AddAbsence>(_onAddAbsence);
    on<DeleteAbsence>(_onDeleteAbsence);
    on<AddMark>(_onAddMark);
    on<DeleteMark>(_onDeleteMark);
    on<AddSemester>(_onAddSemester);
    on<DeleteSemester>(_onDeleteSemester);
    on<AddTimetableEntry>(_onAddTimetable);
    on<DeleteTimetableEntry>(_onDeleteTimetable);
    on<UpdateTimetableEntry>(_onUpdateTimetable);
    on<AddReminder>(_onAddReminder);
    on<DeleteReminder>(_onDeleteReminder);
    on<ToggleReminder>(_onToggleReminder);
    on<SetWeekType>(_onSetWeekType);
    on<ExportData>(_onExportData);
    on<ImportData>(_onImportData);
    on<AddTopic>(_onAddTopic);
    on<ReviewTopic>(_onReviewTopic);
    on<DeleteTopic>(_onDeleteTopic);
    on<UpdateTopic>(_onUpdateTopic);
    on<ResetTopic>(_onResetTopic);
    on<SetTopicReviewDate>(_onSetTopicReviewDate);
    on<RescheduleTimetableNotifs>(_onRescheduleTimetableNotifs);
    on<RescheduleReminderNotifs>(_onRescheduleReminderNotifs);
    on<AddSubjectNote>(_onAddSubjectNote);
    on<UpdateSubjectNote>(_onUpdateSubjectNote);
    on<DeleteSubjectNote>(_onDeleteSubjectNote);
    on<SetTaskWorking>(_onSetTaskWorking);
    on<TimetableTimeTick>(_onTimetableTimeTick);
    on<AddJarvisDocument>(_onAddJarvisDocument);
    on<DeleteJarvisDocument>(_onDeleteJarvisDocument);
    on<SetInstructorFocus>(_onSetInstructorFocus);
  }

  void Is_End_Day() {
    isEndDay = true;
    emit(changed());
  }

  Future<void> _reload(Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;

    final tp = (await db.query(
      'topics',
      orderBy: 'nextReview ASC',
    )).map((e) => StudyTopic.fromMap(e)).toList();
    final s = (await db.query(
      'subjects',
    )).map((e) => Subject.fromMap(e)).toList();
    final t = (await db.query(
      'tasks',
      orderBy: 'priority DESC, dueDate ASC',
    )).map((e) => TaskModel.fromMap(e)).toList();
    final a = await db.query('absences', orderBy: 'date DESC');
    final m = (await db.query(
      'marks',
    )).map((e) => MarkModel.fromMap(e)).toList();
    final sm = (await db.query(
      'semesters',
      orderBy: 'createdAt DESC',
    )).map((e) => SemesterModel.fromMap(e)).toList();
    final tt = (await db.query(
      'timetable',
      orderBy: 'dayOfWeek ASC, startTime ASC',
    )).map((e) => TimetableEntry.fromMap(e)).toList();
    final rm = (await db.query(
      'reminders',
      orderBy: 'date ASC',
    )).map((e) => ReminderModel.fromMap(e)).toList();

    List<SubjectNote> sn = [];
    try {
      sn = (await db.query(
        'subject_notes',
        orderBy: 'updatedAt DESC',
      )).map((e) => SubjectNote.fromMap(e)).toList();
    } catch (_) {}

    List<JarvisDocument> jd = [];
    List<SubjectMetadata> meta = [];
    try {
      jd = (await db.query(
        'jarvis_documents',
        orderBy: 'createdAt DESC',
      )).map((e) => JarvisDocument.fromMap(e)).toList();
      final metaRows = await db.query('subject_metadata');
      meta = metaRows.map((e) => SubjectMetadata.fromMap(e)).toList();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final savedWeekType = prefs.getString('current_week_type') ?? 'odd';

    emit(
      AppState(
        subjects: s,
        tasks: t,
        absences: a,
        marks: m,
        semesters: sm,
        timetable: tt,
        reminders: rm,
        topics: tp,
        subjectNotes: sn,
        jarvisDocuments: jd,
        subjectMetadata: meta,
        loading: false,
        currentWeekType: savedWeekType,
      ),
    );

    await _updateXP(t);

    // ═══ KEY: Schedule timer AFTER state has data ═══
    _scheduleNextTimetableUpdate();



    // ═══ CRITICAL: Reschedule everything after import/reload ═══
    final subjectNames = <int, String>{};
    for (final sub in s) {
      if (sub.id != null) subjectNames[sub.id!] = sub.name;
    }
    await NotifService.scheduleTimetableNotifs(
      entries: tt,
      subjectNames: subjectNames,
      currentWeekType: savedWeekType,
      tasks: t,
    );
    await NotifService.scheduleReadMyDayNotif(
      allEntries: tt,
      currentWeekType: savedWeekType,
    );
    // Re-schedule all task and exam notifs
    for (final task in t) {
      if (!task.isCompleted && task.dueDate != null) {
        if (task.isExam) {
          await NotifService.scheduleExamNotifs(
            task.id!,
            task.title,
            task.type,
            task.dueDate!,
          );
        } else {
          await NotifService.scheduleTaskNotifs(task.id!, task.title, task.dueDate!);
        }
      }
    }
    // Re-schedule reminders
    await NotifService.rescheduleAllReminders(rm);
  }

  // ── Topics ────────────────────────────────────────────────────────────────

  Future<void> _onAddTopic(AddTopic e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('topics', e.topic.toMap());
    await _reload(emit);
  }

  Future<void> _onUpdateTopic(UpdateTopic e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'topics',
      e.topic.toMap(),
      where: 'id=?',
      whereArgs: [e.topic.id],
    );
    await _reload(emit);
  }

  Future<void> _onReviewTopic(ReviewTopic e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    final newTopic = e.topic.advanceStage();
    await db.update(
      'topics',
      newTopic.toMap(),
      where: 'id=?',
      whereArgs: [e.topic.id],
    );
    if (newTopic.nextReview != null) {
      try {
        await NotifService.schedule(
          id: 900000 + newTopic.id!,
          title: '🧠 Review: ${newTopic.title}',
          body: 'Spaced repetition time!',
          when: newTopic.nextReview!,
        );
      } catch (err) {
        debugPrint('Review notif error: $err');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bonus_xp', (prefs.getInt('bonus_xp') ?? 0) + 50);
    await _reload(emit);
  }

  Future<void> _onDeleteTopic(DeleteTopic e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('topics', where: 'id=?', whereArgs: [e.id]);
    try {
      await NotifService.cancelSingle(900000 + e.id);
    } catch (_) {}
    await _reload(emit);
  }

  Future<void> _onResetTopic(ResetTopic e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    final resetTopic = e.topic.resetToNew();
    await db.update(
      'topics',
      resetTopic.toMap(),
      where: 'id=?',
      whereArgs: [e.topic.id],
    );
    try {
      await NotifService.cancelSingle(900000 + e.topic.id!);
    } catch (_) {}
    await _reload(emit);
  }

  Future<void> _onSetTopicReviewDate(
    SetTopicReviewDate e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final updated = e.topic.withCustomReview(e.reviewDate);
    await db.update(
      'topics',
      updated.toMap(),
      where: 'id=?',
      whereArgs: [e.topic.id],
    );
    try {
      await NotifService.schedule(
        id: 900000 + e.topic.id!,
        title: '🧠 Review: ${e.topic.title}',
        body: 'Custom review date — time to study!',
        when: e.reviewDate,
      );
    } catch (_) {}
    await _reload(emit);
  }

  // ── Subject Notes ─────────────────────────────────────────────────────────

  Future<void> _onAddSubjectNote(
    AddSubjectNote e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('subject_notes', e.note.toMap());
    await _reload(emit);
  }

  Future<void> _onUpdateSubjectNote(
    UpdateSubjectNote e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final data = e.note.toMap();
    data['updatedAt'] = DateTime.now().toIso8601String();
    await db.update(
      'subject_notes',
      data,
      where: 'id=?',
      whereArgs: [e.note.id],
    );
    await _reload(emit);
  }

  Future<void> _onDeleteSubjectNote(
    DeleteSubjectNote e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('subject_notes', where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  // ── XP & Celebration ──────────────────────────────────────────────────────

  Future<void> _triggerCelebration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_celebration', true);
    await prefs.setString('celebration_time', DateTime.now().toIso8601String());
  }

  Future<void> _updateXP(List<TaskModel> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    int taskXP = 0;
    for (final t in tasks) {
      if (t.isCompleted) {
        int baseXP = t.priority == 3 ? 100 : (t.priority == 2 ? 75 : 50);
        if (t.dueDate != null && t.completedAt != null && t.createdAt != null) {
          final totalWindow = t.dueDate!.difference(t.createdAt!).inMinutes;
          final timeLeft = t.dueDate!.difference(t.completedAt!).inMinutes;
          if (timeLeft > (totalWindow * 0.5))
            baseXP += 40;
          else if (timeLeft < (totalWindow * 0.05))
            baseXP -= 15;
        }
        taskXP += baseXP;
      }
    }
    if (fullmark) {
      taskXP = prefs.getInt('total_xp')! + 500;
      fullmark = false;
    }
    final bonusXP = prefs.getInt('bonus_xp') ?? 0;
    await prefs.setInt('total_xp', taskXP + bonusXP);
  }

  // ── Export/Import ─────────────────────────────────────────────────────────

  Future<void> _onExportData(ExportData e, Emitter<AppState> emit) async {
    try {
      final path = await DatabaseHelper.instance.dbPath;
      if (await File(path).exists()) {
        // Copy to temp with clear name so ZArchiver and other file managers recognise it
        final tempDir = await getTemporaryDirectory();
        final exportPath = '${tempDir.path}/study_organizer_backup.db';
        await File(path).copy(exportPath);
        await Share.shareXFiles([
          XFile(exportPath, mimeType: 'application/x-sqlite3'),
        ], text: 'My Engineering Organizer Backup');
      }
    } catch (err) {
      debugPrint('Export Failed: $err');
    }
  }

  Future<void> _onImportData(ImportData e, Emitter<AppState> emit) async {
    try {
      await DatabaseHelper.instance.close();
      final dbPath = await DatabaseHelper.instance.dbPath;
      await File(e.filePath).copy(dbPath);
      await _reload(emit);
    } catch (err) {
      debugPrint('Import Failed: $err');
      await _reload(emit);
    }
  }

  Future<void> _onLoad(LoadAll e, Emitter<AppState> emit) async {
    await _reload(emit);
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────
  // In your event handler registration (constructor or on<> block):

  // Add handler method:
  Future<void> _onSetTaskWorking(
    SetTaskWorking event,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'tasks',
      {'isWorking': event.isWorking ? 1 : 0},
      where: 'id = ?',
      whereArgs: [event.taskId],
    );

    // Stop urgent notifications when marking as working
    if (event.isWorking) {
      NotifService.stopUrgentTaskReminder(event.taskId);
    }

    // Reload tasks
    final tasks = (await db.query(
      'tasks',
    )).map((m) => TaskModel.fromMap(m)).toList();
    emit(state.copyWith(tasks: tasks));
  }

  Future<void> _onAddTask(AddTask e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('tasks', e.t.toMap());
    if (e.t.dueDate != null) {
      try {
        if (e.t.isExam) {
          await NotifService.scheduleExamNotifs(
            id,
            e.t.title,
            e.t.type,
            e.t.dueDate!,
          );
        } else {
          await NotifService.scheduleTaskNotifs(id, e.t.title, e.t.dueDate!);
        }
        // Start urgent reminders if due within 3 hours
        final diff = e.t.dueDate!.difference(DateTime.now());
        if (diff.inHours < 3 && !diff.isNegative) {
          NotifService.startUrgentTaskReminder(id, e.t.title);
        }
      } catch (err) {
        debugPrint('Add task notif error: $err');
      }
    }
    await _reload(emit);
  }

  Future<void> _onEditTask(EditTask e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('tasks', e.t.toMap(), where: 'id=?', whereArgs: [e.id]);
    try {
      if (e.t.dueDate != null) {
        if (e.t.isExam) {
          await NotifService.scheduleExamNotifs(
            e.id,
            e.t.title,
            e.t.type,
            e.t.dueDate!,
          );
        } else {
          await NotifService.scheduleTaskNotifs(e.id, e.t.title, e.t.dueDate!);
        }
      } else {
        await NotifService.cancel(e.id);
        await NotifService.cancelExam(e.id);
      }
    } catch (err) {
      debugPrint('Edit task notif error: $err');
    }
    await _reload(emit);
  }

  Future<void> _onUpdateTask(UpdateTask e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('tasks', e.data, where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  Future<void> _onDeleteTask(DeleteTask e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('tasks', where: 'id=?', whereArgs: [e.id]);
    try {
      await NotifService.cancel(e.id);
      await NotifService.cancelExam(e.id);
      NotifService.stopUrgentTaskReminder(e.id);
    } catch (err) {
      debugPrint('Delete task notif cancel error: $err');
    }
    await _reload(emit);
  }

  Future<void> _onToggleTask(ToggleTask e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'tasks',
      {
        'isCompleted': e.done ? 1 : 0,
        'completedAt': e.done ? now : null,
        if (e.done)
          'isFailed': 0, // Ensure checking a task clears 'failed' state
      },
      where: 'id=?',
      whereArgs: [e.id],
    );
    if (e.done) {
      // Play task completion sound
      try {
        // Use task_done.mp3 if it exists, else fallback to existing sound
        NovaAudioService.playAsset('sounds/task_done.mp3');
      } catch (_) {
        NovaAudioService.playAsset('sounds/that_is_one_step_closer.mp3');
      }
      // Cancel notifications
      try {
        await NotifService.cancel(e.id);
        await NotifService.cancelExam(e.id);
        NotifService.stopUrgentTaskReminder(e.id);
      } catch (err) {
        debugPrint('Toggle task notif cancel error: $err');
      }
    }
    await _reload(emit);
  }

  Future<void> _onFailTask(FailTask e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'tasks',
      {'isFailed': e.failed ? 1 : 0},
      where: 'id=?',
      whereArgs: [e.id],
    );
    await _reload(emit);
  }
  // ── Subjects ──────────────────────────────────────────────────────────────────────────

  Future<void> _onAddSubject(AddSubject e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('subjects', e.s.toMap());
    await _reload(emit);
  }

  Future<void> _onUpdateSubject(UpdateSubject e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('subjects', e.s.toMap(), where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  Future<void> _onDeleteSubject(DeleteSubject e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('subjects', where: 'id=?', whereArgs: [e.id]);
    await db.delete('tasks', where: 'subjectId=?', whereArgs: [e.id]);
    await db.delete('absences', where: 'subjectId=?', whereArgs: [e.id]);
    await db.delete('marks', where: 'subjectId=?', whereArgs: [e.id]);
    await db.delete('timetable', where: 'subjectId=?', whereArgs: [e.id]);
    try {
      await db.delete('subject_notes', where: 'subjectId=?', whereArgs: [e.id]);
    } catch (_) {}
    await _reload(emit);
  }

  // ── Marks ─────────────────────────────────────────────────────────────────

  Future<void> _onAddMark(AddMark e, Emitter<AppState> emit) async {
    fullmark = false;
    final db = await DatabaseHelper.instance.database;
    await db.insert('marks', e.m.toMap());
    if (e.m.obtained >= e.m.total && e.m.total > 0) {
      fullmark = true;
      // 🔊 Perfect score — "that's one step closer" A+ sound
      NovaAudioService.playAsset('sounds/that _is_one_step_closer.mp3');
      await _triggerCelebration();
    }
    await _reload(emit);
  }

  Future<void> _onDeleteMark(DeleteMark e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('marks', where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  // ── Absences ──────────────────────────────────────────────────────────────

  Future<void> _onAddAbsence(AddAbsence e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('absences', {
      'subjectId': e.subjectId,
      'date': e.date,
      'type': e.type,
    });
    try {
      final rows = await db.query(
        'subjects',
        where: 'id=?',
        whereArgs: [e.subjectId],
      );
      if (rows.isNotEmpty) {
        final sub = rows.first;
        final allAbs = await db.query(
          'absences',
          where: 'subjectId=? AND type=?',
          whereArgs: [e.subjectId, e.type],
        );
        final count = allAbs.length;
        final maxAbs = e.type == 'lecture'
            ? (sub['maxLectureAbs'] as int? ?? 4)
            : e.type == 'section'
            ? (sub['maxSectionAbs'] as int? ?? 4)
            : (sub['maxLabAbs'] as int? ?? 4);
        await NotifService.showAbsenceWarning(
          subjectId: e.subjectId,
          subjectName: sub['name'] as String? ?? 'Subject',
          current: count,
          maxAbs: maxAbs,
          type: e.type,
        );
      }
    } catch (err) {
      debugPrint('Absence check error: $err');
    }
    await _reload(emit);
  }

  Future<void> _onDeleteAbsence(DeleteAbsence e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('absences', where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  // ── Semesters ─────────────────────────────────────────────────────────────

  Future<void> _onAddSemester(AddSemester e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('semesters', e.s.toMap());
    await _reload(emit);
  }

  Future<void> _onDeleteSemester(
    DeleteSemester e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('semesters', where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  // ── Timetable ─────────────────────────────────────────────────────────────

  Future<void> _onAddTimetable(
    AddTimetableEntry e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('timetable', e.entry.toMap());
    await _reload(emit); // _reload now calls _scheduleNextTimetableUpdate
    _rescheduleAllTimetableNotifs();
  }

  Future<void> _onDeleteTimetable(
    DeleteTimetableEntry e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('timetable', where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
    _rescheduleAllTimetableNotifs();
  }

  Future<void> _onUpdateTimetable(
    UpdateTimetableEntry e,
    Emitter<AppState> emit,
  ) async {
    if (e.entry.id == null) return;
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'timetable',
      e.entry.toMap(),
      where: 'id=?',
      whereArgs: [e.entry.id],
    );
    await _reload(emit);
    _rescheduleAllTimetableNotifs();
  }

  void _rescheduleAllTimetableNotifs() {
    try {
      final subjectNames = <int, String>{};
      for (final s in state.subjects) {
        if (s.id != null) subjectNames[s.id!] = s.name;
      }
      NotifService.scheduleTimetableNotifs(
        entries: state.timetable,
        subjectNames: subjectNames,
        currentWeekType: state.currentWeekType,
        tasks: state.tasks,
      );
      NotifService.scheduleReadMyDayNotif(
        allEntries: state.timetable,
        currentWeekType: state.currentWeekType,
      );
    } catch (err) {
      debugPrint('Auto-reschedule error: $err');
    }
  }

  Future<void> _onRescheduleTimetableNotifs(
    RescheduleTimetableNotifs e,
    Emitter<AppState> emit,
  ) async {
    _rescheduleAllTimetableNotifs();
  }

  Future<void> _onRescheduleReminderNotifs(
    RescheduleReminderNotifs e,
    Emitter<AppState> emit,
  ) async {
    try {
      await NotifService.rescheduleAllReminders(state.reminders);
    } catch (_) {}
  }

  // ACTIVE TIMETABLE STATE UPDATES   -----------------------

  void _scheduleNextTimetableUpdate() {
    _timetableUpdateTimer?.cancel();

    final now = DateTime.now();
    final todayDow = now.weekday;
    final weekNum = _calcWeekNumber(now);
    final todayWeekType = weekNum.isOdd ? 'odd' : 'even';

    final todayClasses = state.timetable.where((e) {
      if (e.dayOfWeek != todayDow) return false;
      return e.weekType == 'both' || e.weekType == todayWeekType;
    }).toList();

    if (todayClasses.isEmpty) {
      debugPrint('⏰ No classes today — no timer needed');
      return;
    }

    // Collect ALL future transition times
    final List<DateTime> transitions = [];
    for (final cls in todayClasses) {
      final sp = cls.startTime.split(':');
      final ep = cls.endTime.split(':');
      if (sp.length < 2 || ep.length < 2) continue;

      final start = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(sp[0]),
        int.parse(sp[1]),
      );
      final end = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(ep[0]),
        int.parse(ep[1]),
      );

      if (start.isAfter(now)) transitions.add(start);
      if (end.isAfter(now)) transitions.add(end);
    }

    if (transitions.isEmpty) {
      debugPrint('⏰ All classes done — no timer needed');
      return;
    }

    transitions.sort();
    final nextEvent = transitions.first;

    // Calculate exact delay — NO buffer, fire exactly at class time
    final delay = nextEvent.difference(now);

    debugPrint(
      '⏰ Timer set: $nextEvent '
      '(${delay.inMinutes}m ${delay.inSeconds % 60}s from now) '
      '— ${transitions.length} transitions remaining',
    );

    _timetableUpdateTimer = Timer(delay, () {
      debugPrint('🔄 Timer FIRED at ${DateTime.now()} for event $nextEvent');
      if (!isClosed) {
        add(const TimetableTimeTick());
      }
    });
  }

  Future<void> _onTimetableTimeTick(
    TimetableTimeTick event,
    Emitter<AppState> emit,
  ) async {
    debugPrint('🔄 TimetableTimeTick handler — emitting new state');

    // Force UI rebuild with new timestamp
    emit(state.copyWith(lastUpdated: DateTime.now()));

    // Reschedule notifications
    _rescheduleAllTimetableNotifs();

    // Arm timer for NEXT transition
    _scheduleNextTimetableUpdate();
  }

  int _calcWeekNumber(DateTime date) {
    final doy = int.parse(intl.DateFormat('D').format(date));
    return ((doy - date.weekday + 10) / 7).floor();
  }

  @override
  Future<void> close() {
    _timetableUpdateTimer?.cancel();
    return super.close();
  }

  // ── Reminders ─────────────────────────────────────────────────────────────

  Future<void> _onAddReminder(AddReminder e, Emitter<AppState> emit) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('reminders', e.r.toMap());
    try {
      final when = e.r.dateTime;
      if (when != null && when.isAfter(DateTime.now())) {
        await NotifService.schedule(
          id: 700000 + id,
          title: '🔔 Reminder',
          body: e.r.text,
          when: when,
          channelId: 'reminder_notifs',
          channelName: 'Reminders',
          channelDesc: 'Custom reminders',
        );
        final early = when.subtract(const Duration(minutes: 15));
        if (early.isAfter(DateTime.now())) {
          await NotifService.schedule(
            id: 700000 + id + 50000,
            title: '⏰ Reminder in 15 min',
            body: e.r.text,
            when: early,
            channelId: 'reminder_notifs',
            channelName: 'Reminders',
            channelDesc: 'Custom reminders',
          );
        }
      }
    } catch (err) {
      debugPrint('Reminder schedule error: $err');
    }
    await _reload(emit);
  }

  Future<void> _onDeleteReminder(
    DeleteReminder e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('reminders', where: 'id=?', whereArgs: [e.id]);
    try {
      await NotifService.cancelSingle(700000 + e.id);
      await NotifService.cancelSingle(700000 + e.id + 50000);
    } catch (_) {}
    await _reload(emit);
  }

  Future<void> _onToggleReminder(
    ToggleReminder e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'reminders',
      {'isDone': e.done ? 1 : 0},
      where: 'id=?',
      whereArgs: [e.id],
    );
    if (e.done) {
      try {
        await NotifService.cancelSingle(700000 + e.id);
        await NotifService.cancelSingle(700000 + e.id + 50000);
      } catch (_) {}
    }
    await _reload(emit);
  }

  // ── Week Type ─────────────────────────────────────────────────────────────

  Future<void> _onSetWeekType(SetWeekType e, Emitter<AppState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_week_type', e.weekType);
    emit(state.copyWith(currentWeekType: e.weekType));
    _rescheduleAllTimetableNotifs();
    _scheduleNextTimetableUpdate();
  }

  // ── JARVIS brain: documents & instructor focus ───────────────────────────

  Future<void> _onAddJarvisDocument(
    AddJarvisDocument e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('jarvis_documents', e.document.toMap());
    await _reload(emit);
  }

  Future<void> _onDeleteJarvisDocument(
    DeleteJarvisDocument e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('jarvis_documents', where: 'id=?', whereArgs: [e.id]);
    await _reload(emit);
  }

  Future<void> _onSetInstructorFocus(
    SetInstructorFocus e,
    Emitter<AppState> emit,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('subject_metadata', {
      'subjectId': e.subjectId,
      'instructor_focus': e.focus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _reload(emit);
  }
}
