import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/theme/app_theme.dart';
import 'package:study_organizer/features/shell/presentation/pages/main_shell.dart';
import 'package:study_organizer/features/ai_assistant/data/services/jarvis_navigator.dart';

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
    return BlocProvider(
      create: (_) => AppBloc(widget.db)..add(LoadAll()),
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

