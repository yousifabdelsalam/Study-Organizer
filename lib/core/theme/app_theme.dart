import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData getTheme(Brightness b) {
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
            ? const Color(0xFF12122A).withValues(alpha: 0.9)
            : const Color(0xFF0E6463).withValues(alpha: 0.9),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 19,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(
          color: dark ? const Color(0xFF9D97FF) : Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: dark
            ? const Color(0xFF1A1A3E).withValues(alpha: 0.55)
            : const Color(0xFF0E6463).withValues(alpha: 0.75),
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

  static ThemeData get lightTheme => getTheme(Brightness.light);
  static ThemeData get darkTheme => getTheme(Brightness.dark);
}
