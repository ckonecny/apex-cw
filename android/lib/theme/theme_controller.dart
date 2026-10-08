import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme mode, persisted and shared between Settings and main.dart.
/// 0=System (default), 1=Light, 2=Dark — matches the usual convention.
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode.value = _fromInt(p.getInt('themeMode') ?? 0);
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', _toInt(m));
  }

  static int _toInt(ThemeMode m) => switch (m) {
        ThemeMode.light => 1,
        ThemeMode.dark  => 2,
        _               => 0,
      };

  static ThemeMode _fromInt(int v) => switch (v) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Optional warm "blue light" filter over the whole app, for both themes.
/// Off by default; [strength] runs 10–100 (%).
class BlueLightFilter {
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<int> strength = ValueNotifier(50);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool('blueLightOn') ?? false;
    strength.value = (p.getInt('blueLightStrength') ?? 50).clamp(10, 100);
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('blueLightOn', v);
  }

  static Future<void> setStrength(int v) async {
    strength.value = v.clamp(10, 100);
    final p = await SharedPreferences.getInstance();
    await p.setInt('blueLightStrength', strength.value);
  }

  /// Colour matrix that scales blue down hardest, green a little and red only
  /// by the overall dimming, so white turns a warm peach.
  static ColorFilter filter(int strength) {
    final t = strength / 100;
    // Also dims overall brightness (up to 20 %), so the brightest text
    // (stat values, quotas) stops glaring in the warm tone.
    final d = 1 - 0.20 * t;
    final g = (1 - 0.265 * t) * d;
    final b = (1 - 0.69 * t) * d;
    return ColorFilter.matrix(<double>[
      d, 0, 0, 0, 0,
      0, g, 0, 0, 0,
      0, 0, b, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Optionally hides the Android status bar (swipe down from the top edge shows
/// it briefly). Off by default. Re-applied on resume, as the system may bring
/// the bars back after another app was in front.
class StatusBarMode {
  static final ValueNotifier<bool> hidden = ValueNotifier(false);
  static AppLifecycleListener? _listener;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    hidden.value = p.getBool('hideStatusBar') ?? false;
    _listener ??= AppLifecycleListener(onResume: _apply);
    _apply();
  }

  static Future<void> set(bool v) async {
    hidden.value = v;
    _apply();
    final p = await SharedPreferences.getInstance();
    await p.setBool('hideStatusBar', v);
  }

  static void _apply() => hidden.value
      ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.bottom])
      : SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
