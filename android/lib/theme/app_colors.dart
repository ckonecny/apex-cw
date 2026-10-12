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

  /// Amber night look: near-black warm background, amber text (dark
  /// brightness, so everything that checks `Brightness.dark` keeps working).
  static const amber = AppColors(
    background:    Color(0xFF120C04),
    surface:       Color(0xFF1F1508),
    surfaceAlt:    Color(0xFF0D0802),
    surfaceDark:   Color(0xFF080501),
    border:        Color(0xFF4A3510),
    borderAlt:     Color(0xFF33250C),
    textPrimary:   Color(0xFFFFC76A),
    textMuted:     Color(0xFFC08A30),
    textFaint:     Color(0xFF7A5A20),
    textDisabled:  Color(0xFF584218),
    textMutedAlt:  Color(0xFF946A24),
    logText:       Color(0xFFE0A850),
    accent:        Color(0xFFC98A12),
    warning:       Color(0xFFFF7A1A),
    danger:        Color(0xFFE5533D),
    info:          Color(0xFFF0CF8E),
    accentPurple:  Color(0xFFD08A5A),
  );

  /// Red night look (dark brightness): keeps dark adaptation, hues carry little
  /// meaning here so states differ mainly by brightness and saturation.
  static const red = AppColors(
    background:    Color(0xFF0C0505),
    surface:       Color(0xFF170A0A),
    surfaceAlt:    Color(0xFF080303),
    surfaceDark:   Color(0xFF050202),
    border:        Color(0xFF4A1A1A),
    borderAlt:     Color(0xFF2E1010),
    textPrimary:   Color(0xFFE85A4F),
    textMuted:     Color(0xFFA8403A),
    textFaint:     Color(0xFF6E2A27),
    textDisabled:  Color(0xFF4C1D1B),
    textMutedAlt:  Color(0xFF8A3732),
    logText:       Color(0xFFD4574C),
    accent:        Color(0xFFD8645A),
    warning:       Color(0xFFC9602A),
    danger:        Color(0xFFB01C34),
    info:          Color(0xFFFF8A66),
    accentPurple:  Color(0xFFB05A5A),
  );

  /// Green phosphor look (dark brightness).
  static const green = AppColors(
    background:    Color(0xFF050E07),
    surface:       Color(0xFF0B1A0E),
    surfaceAlt:    Color(0xFF030A04),
    surfaceDark:   Color(0xFF020703),
    border:        Color(0xFF1E4A26),
    borderAlt:     Color(0xFF12301A),
    textPrimary:   Color(0xFF7FD98A),
    textMuted:     Color(0xFF4FA05C),
    textFaint:     Color(0xFF2E6A38),
    textDisabled:  Color(0xFF245230),
    textMutedAlt:  Color(0xFF3E8548),
    logText:       Color(0xFF6CC078),
    accent:        Color(0xFF2FA547),
    warning:       Color(0xFF86BE52),
    danger:        Color(0xFFF0604A),
    info:          Color(0xFFB8F0C0),
    accentPurple:  Color(0xFF5AB0A0),
  );

  /// Soft warm grey, low contrast (dark brightness).
  static const warmGrey = AppColors(
    background:    Color(0xFF1E1B18),
    surface:       Color(0xFF272320),
    surfaceAlt:    Color(0xFF171513),
    surfaceDark:   Color(0xFF12100F),
    border:        Color(0xFF3E3832),
    borderAlt:     Color(0xFF322D28),
    textPrimary:   Color(0xFFE6DCCB),
    textMuted:     Color(0xFFA39785),
    textFaint:     Color(0xFF6E6558),
    textDisabled:  Color(0xFF574F45),
    textMutedAlt:  Color(0xFF8A7F6E),
    logText:       Color(0xFFC4B8A4),
    accent:        Color(0xFFC9B77A),
    warning:       Color(0xFFD08A4A),
    danger:        Color(0xFFC86058),
    info:          Color(0xFFE8D8B0),
    accentPurple:  Color(0xFFA890B0),
  );

  /// Navy and orange (watch-face look, dark brightness): blue-black grounds,
  /// silver text, orange accent. Only orange and silver tones (no cyan or pink),
  /// so menu icons stay within the theme.
  static const navyOrange = AppColors(
    background:    Color(0xFF05080F),
    surface:       Color(0xFF0D1826),
    surfaceAlt:    Color(0xFF08111C),
    surfaceDark:   Color(0xFF050B14),
    border:        Color(0xFF1F3550),
    borderAlt:     Color(0xFF142840),
    textPrimary:   Color(0xFFE4E8EE),
    textMuted:     Color(0xFF8A9BB2),
    textFaint:     Color(0xFF56677F),
    textDisabled:  Color(0xFF3A4A60),
    textMutedAlt:  Color(0xFF6A7C95),
    logText:       Color(0xFFA8B8CC),
    accent:        Color(0xFFF28A2E),
    warning:       Color(0xFFF5B642),
    danger:        Color(0xFFE5483D),
    info:          Color(0xFFB9C6D8),
    accentPurple:  Color(0xFFF0A050),
  );

  /// True for the dark-brightness variants (amber, red, green, warm grey).
  static bool isVariant(BuildContext context) =>
      Theme.of(context).extension<ThemeVariantMarker>() != null;

  static AppColors of(BuildContext context) {
    final t = Theme.of(context);
    final v = t.extension<ThemeVariantMarker>();
    if (v != null) return v.colors;
    return t.brightness == Brightness.dark ? dark : light;
  }
}

/// Tags a dark-brightness ThemeData that uses its own palette (amber, red,
/// green, warm grey), so [AppColors.of] can tell it from plain dark (and
/// dependents rebuild when switching between them).
class ThemeVariantMarker extends ThemeExtension<ThemeVariantMarker> {
  final AppColors colors;
  const ThemeVariantMarker(this.colors);
  @override
  ThemeVariantMarker copyWith({AppColors? colors}) => ThemeVariantMarker(colors ?? this.colors);
  @override
  ThemeVariantMarker lerp(ThemeVariantMarker? other, double t) => other ?? this;
}
