import 'package:flutter/material.dart';

/// Centralized theme configuration for the app.
///
/// Provides light and dark themes with consistent styling across all screens.
class AppTheme {
  // ─── Common Card Theme ─────────────────────────────────────────

  static CardThemeData _cardTheme(Brightness brightness) {
    return CardThemeData(
      elevation: brightness == Brightness.light ? 2 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    );
  }

  // ─── Common AppBar Theme ───────────────────────────────────────

  static AppBarTheme _appBarTheme(Brightness brightness) {
    return AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: brightness == Brightness.light
          ? Colors.white
          : Colors.grey.shade900,
    );
  }

  // ─── Common Input Decoration ───────────────────────────────────

  static InputDecorationTheme _inputDecorationTheme(Brightness brightness) {
    return InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: brightness == Brightness.light
          ? Colors.grey.shade50
          : Colors.grey.shade800,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // ─── Common Floating Action Button Theme ───────────────────────

  static FloatingActionButtonThemeData _fabTheme(Brightness brightness) {
    return FloatingActionButtonThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  // ─── Common Elevated Button Theme ──────────────────────────────

  static ElevatedButtonThemeData _elevatedButtonTheme(Brightness brightness) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    );
  }

  // ─── Light Theme ───────────────────────────────────────────────

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    cardTheme: _cardTheme(Brightness.light),
    appBarTheme: _appBarTheme(Brightness.light),
    inputDecorationTheme: _inputDecorationTheme(Brightness.light),
    floatingActionButtonTheme: _fabTheme(Brightness.light),
    elevatedButtonTheme: _elevatedButtonTheme(Brightness.light),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  // ─── Dark Theme ────────────────────────────────────────────────

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    cardTheme: _cardTheme(Brightness.dark),
    appBarTheme: _appBarTheme(Brightness.dark),
    inputDecorationTheme: _inputDecorationTheme(Brightness.dark),
    floatingActionButtonTheme: _fabTheme(Brightness.dark),
    elevatedButtonTheme: _elevatedButtonTheme(Brightness.dark),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}