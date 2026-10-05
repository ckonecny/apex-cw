import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Side of the two on-screen paddles (soft keys). Only the touch buttons swap;
/// hardware paddles keep whatever "Learn dit/dah keys" assigned, so a learned
/// reversal is never undone by this setting. Shared by all paddle widgets.
class PaddleLayout {
  PaddleLayout._();

  static const prefKey = 'touchPaddlesSwapped';

  /// True: dah on the left, dit on the right. Default false (dit left).
  static final swapped = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    swapped.value = p.getBool(prefKey) ?? false;
  }

  static Future<void> setSwapped(bool v) async {
    swapped.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, v);
  }
}
