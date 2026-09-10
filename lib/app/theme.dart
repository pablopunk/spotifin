import 'package:flutter/material.dart';

class SpotifinColors {
  static const background = Color(0xFF0D0F12);
  static const surface = Color(0xFF171A20);
  static const raised = Color(0xFF22262E);
  static const accent = Color(0xFF8BE28B);
  static const coral = Color(0xFFFF8A72);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SpotifinColors.accent,
    brightness: Brightness.dark,
    surface: SpotifinColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SpotifinColors.background,
    fontFamily: 'SF Pro Display',
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: SpotifinColors.surface,
      indicatorColor: Color(0x338BE28B),
      height: 70,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: SpotifinColors.surface,
      indicatorColor: Color(0x338BE28B),
    ),
    cardTheme: const CardThemeData(
      color: SpotifinColors.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SpotifinColors.raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
