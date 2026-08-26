import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/theme/app_theme.dart';
import 'package:study_organizer/features/shell/presentation/pages/main_shell.dart';
import 'package:study_organizer/features/jarvis_assistant/data/services/jarvis_navigator.dart';

// Feature Cubits
import 'package:study_organizer/features/subjects/presentation/cubit/subjects_cubit.dart';
import 'package:study_organizer/features/tasks/presentation/cubit/tasks_cubit.dart';
import 'package:study_organizer/features/attendance/presentation/cubit/attendance_cubit.dart';
import 'package:study_organizer/features/marks/presentation/cubit/marks_cubit.dart';
import 'package:study_organizer/features/topics/presentation/cubit/topics_cubit.dart';
import 'package:study_organizer/features/notes/presentation/cubit/notes_cubit.dart';
import 'package:study_organizer/features/timetable/presentation/cubit/timetable_cubit.dart';
import 'package:study_organizer/features/reminders/presentation/cubit/reminders_cubit.dart';
import 'package:study_organizer/features/documents/presentation/cubit/documents_cubit.dart';
import 'package:study_organizer/features/gpa_calculator/presentation/cubit/gpa_cubit.dart';

class EngineeringApp extends StatefulWidget {
  final Database db;
  const EngineeringApp({super.key, required this.db});
  static final themeNotifier = ValueNotifier(ThemeMode.dark);

  @override
  State<EngineeringApp> createState() => _EngineeringAppState();
}

class _EngineeringAppState extends State<EngineeringApp> {
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      EngineeringApp.themeNotifier.value = (p.getBool('dark') ?? true)
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AppBloc(widget.db)..add(LoadAll())),
        BlocProvider(create: (_) => SubjectsCubit()..loadSubjects()),
        BlocProvider(create: (_) => TasksCubit()..loadTasks()),
        BlocProvider(create: (_) => AttendanceCubit()..loadAttendance()),
        BlocProvider(create: (_) => MarksCubit()..loadMarks()),
        BlocProvider(create: (_) => TopicsCubit()..loadTopics()),
        BlocProvider(create: (_) => NotesCubit()..loadNotes()),
        BlocProvider(create: (_) => TimetableCubit()..loadTimetable()),
        BlocProvider(create: (_) => RemindersCubit()..loadReminders()),
        BlocProvider(create: (_) => DocumentsCubit()..loadDocuments()),
        BlocProvider(create: (_) => GpaCubit()..loadSemesters()),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: EngineeringApp.themeNotifier,
        builder: (_, mode, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: JarvisNavigator.navigatorKey,
          themeMode: mode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: MainShell(key: JarvisNavigator.shellKey),
        ),
      ),
    );
  }
}
