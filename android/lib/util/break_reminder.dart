import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/break_hint.dart';

/// App-wide state of the break reminder (issue #5): the user setting, the
/// shared session watch and whether the hint is currently due. Shared by the
/// Hören and Geben screens, not per screen.
class BreakReminder {
  BreakReminder._();

  static const prefKey = 'breakHint';

  /// User setting (Settings → General); default on.
  static final enabled = ValueNotifier<bool>(true);

  /// True from the block that triggers the hint until it is answered or the
  /// next block starts.
  static final due = ValueNotifier<bool>(false);

  static BreakWatch _watch = BreakWatch();

  static Future<void> init() async {
    enabled.value = (await SharedPreferences.getInstance()).getBool(prefKey) ?? true;
  }

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    if (!on) due.value = false;
    (await SharedPreferences.getInstance()).setBool(prefKey, on);
  }

  /// Call once per finished block. [signature] must change with everything
  /// that sets the difficulty (speed, spacing, characters, interference).
  static void onBlock(String track, double rate, String signature, {DateTime? now}) {
    if (!enabled.value) return;
    if (_watch.add(track, rate, signature, now ?? DateTime.now())) due.value = true;
  }

  /// The next block starts: the hint was seen.
  static void dismiss() => due.value = false;

  @visibleForTesting
  static void reset() {
    _watch = BreakWatch();
    due.value = false;
    enabled.value = true;
  }
}
