import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/break_hint.dart';

/// App-wide state of the break reminder (issue #5, #48): the user settings,
/// the shared session watch and whether the hint is currently due. Shared by
/// the Hören and Geben screens, not per screen.
class BreakReminder {
  BreakReminder._();

  static const prefKey = 'breakHint';
  static const levelKey = 'breakHintLevel';

  /// User setting (Settings → General); default on.
  static final enabled = ValueNotifier<bool>(true);

  /// How early the hint fires; default [BreakSensitivity.normal].
  static final level = ValueNotifier<BreakSensitivity>(BreakSensitivity.normal);

  /// True from the block that triggers the hint until it is answered or the
  /// next block starts.
  static final due = ValueNotifier<bool>(false);

  static BreakWatch _watch = BreakWatch();

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool(prefKey) ?? true;
    final i = p.getInt(levelKey) ?? BreakSensitivity.normal.index;
    level.value = BreakSensitivity.values[i.clamp(0, BreakSensitivity.values.length - 1)];
    _watch.sensitivity = level.value;
  }

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    if (!on) due.value = false;
    (await SharedPreferences.getInstance()).setBool(prefKey, on);
  }

  static Future<void> setLevel(BreakSensitivity s) async {
    level.value = s;
    _watch.sensitivity = s;
    (await SharedPreferences.getInstance()).setInt(levelKey, s.index);
  }

  /// Call once per finished block. [correct]: one entry per answered
  /// character in order (true = right). [signature] must change with
  /// everything that sets the difficulty (speed, spacing, characters,
  /// interference).
  static void onBlock(String track, List<bool> correct, String signature, {DateTime? now}) {
    if (!enabled.value) return;
    if (_watch.add(track, correct, signature, now ?? DateTime.now())) due.value = true;
  }

  /// The next block starts: the hint was seen.
  static void dismiss() => due.value = false;

  @visibleForTesting
  static void reset() {
    _watch = BreakWatch();
    due.value = false;
    enabled.value = true;
    level.value = BreakSensitivity.normal;
  }
}
