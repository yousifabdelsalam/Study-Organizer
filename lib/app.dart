import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'bloc/app_bloc.dart';
import 'bloc/app_event.dart';
import 'pages/main_shell.dart';
import 'services/jarvis_navigator.dart';

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
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: MainShell(key: JarvisNavigator.shellKey),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorSchemeSeed: const Color(0xFF6C63FF),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0A0A1A)
          : const Color(0xFF68B7B3),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xFF12122A).withOpacity(0.9)
            : const Color(0xFF0E6463).withOpacity(0.9),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 19,
          color: Colors
              .white, // Ensure text is visible on the dark teal appbar in light mode
        ),
        iconTheme: IconThemeData(
          color: dark ? const Color(0xFF9D97FF) : Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: dark
            ? const Color(0xFF1A1A3E).withOpacity(0.55)
            : const Color(0xFF0E6463).withOpacity(0.75),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1A1A3E) : const Color(0xFF68B7B3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
