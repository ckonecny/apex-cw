import 'package:flutter/material.dart';
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
