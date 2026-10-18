import 'package:flutter/material.dart';

/// Colours taken from the CSS variables in index.html.
class AppColors {
  static const bg = Color(0xFF0A0E13);
  static const bgElevated = Color(0xFF10151D);
  static const bgCard = Color(0xFF151B24);
  static const bgCard2 = Color(0xFF1A212B);
  static const bgInput = Color(0xFF1C232E);
  static const border = Color(0xFF212A36);
  static const borderSoft = Color(0xFF1A212B);
  static const accent = Color(0xFF22D47B);
  static const accentDark = Color(0xFF17A862);
  static const text = Color(0xFFF2F5F8);
  static const textDim = Color(0xFF8D97A5);
  static const textFaint = Color(0xFF586374);
  static const danger = Color(0xFFEF5A5A);
  static const blue = Color(0xFF3B9EFF);
  static const onAccent = Color(0xFF04140C);

  // light theme
  static const lBg = Color(0xFFF0F2F5);
  static const lBgElevated = Color(0xFFE4E6EB);
  static const lBgCard = Color(0xFFFFFFFF);
  static const lBgCard2 = Color(0xFFF0F2F5);
  static const lBorder = Color(0xFFD0D4DC);
  static const lText = Color(0xFF1A1A2E);
  static const lTextDim = Color(0xFF4A4A5A);
  static const lTextFaint = Color(0xFF8A8A9A);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? AppColors.bg : AppColors.lBg;
  final surface = dark ? AppColors.bgElevated : AppColors.lBgElevated;
  final text = dark ? AppColors.text : AppColors.lText;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: b,
      primary: AppColors.accent,
      surface: surface,
      onSurface: text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
    ),
    dividerColor: dark ? AppColors.border : AppColors.lBorder,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? AppColors.bgInput : AppColors.lBgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? AppColors.border : AppColors.lBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? AppColors.border : AppColors.lBorder),
      ),
    ),
  );
}
