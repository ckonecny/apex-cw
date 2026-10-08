import 'package:flutter/material.dart';

/// Named semantic color tokens. Every screen reads colors through this
/// instead of hardcoding hex values, so Light/Dark/System all just work.
class AppColors {
  final Color background;
  final Color surface;
  final Color surfaceAlt;   // slightly darker panel (e.g. status bars, log boxes)
  final Color surfaceDark;  // deepest nested panel
  final Color border;
  final Color borderAlt;
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color textDisabled;
  final Color textMutedAlt;
  final Color logText;
  final Color accent;        // primary/success — teal
  final Color warning;       // amber
  final Color danger;        // red
  final Color info;          // blue
  final Color accentPurple;  // echo trainer accent

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceDark,
    required this.border,
    required this.borderAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.textDisabled,
    required this.textMutedAlt,
    required this.logText,
    required this.accent,
    required this.warning,
    required this.danger,
    required this.info,
    required this.accentPurple,
  });

  static const dark = AppColors(
    background:    Color(0xFF111827),
    surface:       Color(0xFF1C2540),
    surfaceAlt:    Color(0xFF0F1520),
    surfaceDark:   Color(0xFF0D1220),
    border:        Color(0xFF2C3A58),
    borderAlt:     Color(0xFF1E2E48),
    textPrimary:   Color(0xFFDCE4F8),
    textMuted:     Color(0xFF7A8FB5),
    textFaint:     Color(0xFF4A5A78),
    textDisabled:  Color(0xFF3A4A60),
    textMutedAlt:  Color(0xFF56618A),
    logText:       Color(0xFF8BAACC),
    accent:        Color(0xFF3ECAA8),
    warning:       Color(0xFFE09638),
    danger:        Color(0xFFE06060),
    info:          Color(0xFF5B8DEF),
    accentPurple:  Color(0xFFB06EF0),
  );

  static const light = AppColors(
    background:    Color(0xFFDCE1EE),
    surface:       Color(0xFFEEF1F8),
    surfaceAlt:    Color(0xFFD1D8E8),
    surfaceDark:   Color(0xFFC6CEE1),
    border:        Color(0xFFB8C1D8),
    borderAlt:     Color(0xFFBEC6DB),
    textPrimary:   Color(0xFF16203A),
    textMuted:     Color(0xFF526082),
    textFaint:     Color(0xFF8591AF),
    textDisabled:  Color(0xFFA8B1C9),
    textMutedAlt:  Color(0xFF6A7699),
    logText:       Color(0xFF3E4C74),
    accent:        Color(0xFF12907A),
    warning:       Color(0xFF9A5A0A),
    danger:        Color(0xFFC94F4F),
    info:          Color(0xFF2F58B8),
    accentPurple:  Color(0xFF7A3FC0),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
