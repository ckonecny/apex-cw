import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional "do not disturb while training" (issue #55, docs/DECISIONS.md
/// "Focus mode"). While a training screen is open the system interruption
/// filter is set to Priority (the user's own DND exceptions still apply) and
/// put back when practice pauses. Off by default; needs the user's "Do Not
/// Disturb access" grant. Native side: FocusMode.kt, which also repairs a
/// filter left behind by a crash.
class FocusMode {
  FocusMode._();

  static const prefKey = 'focusMode';
  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/settings');

  /// User setting (Settings → General); default off.
  static final enabled = ValueNotifier<bool>(false);

  /// Whether the system grant is in place (refreshed on app resume).
  static final hasAccess = ValueNotifier<bool>(false);

  static Future<void> init() async {
    enabled.value = (await SharedPreferences.getInstance()).getBool(prefKey) ?? false;
    await refreshAccess();
    WidgetsBinding.instance.addObserver(_Resume());
  }

  static Future<void> refreshAccess() async {
    try {
      hasAccess.value = await _channel.invokeMethod<bool>('focusHasAccess') ?? false;
    } on MissingPluginException {
      hasAccess.value = false;
    }
  }

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    (await SharedPreferences.getInstance()).setBool(prefKey, on);
    if (!on) release();
  }

  /// Practice starts: switch to Priority if the setting and the grant allow.
  static Future<void> engage() async {
    if (!enabled.value) return;
    try {
      await _channel.invokeMethod('focusEngage');
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }

  /// Practice pauses: put the previous filter back.
  static Future<void> release() async {
    try {
      await _channel.invokeMethod('focusRestore');
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }

  static Future<void> openAccessSettings() async {
    try {
      await _channel.invokeMethod('focusOpenAccess');
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }

  static Future<void> openDndSettings() async {
    try {
      await _channel.invokeMethod('focusOpenDnd');
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }
}

class _Resume with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) FocusMode.refreshAccess();
  }
}
