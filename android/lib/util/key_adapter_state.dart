import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether a real key/paddle on an adapter is in use (#95), and what the
/// on-screen paddles do about it. The native side reports a physical input
/// device as soon as it sends one of the learned dit/dah keys (never for a
/// plain keyboard) and drops it when it is unplugged. Shared by all paddle
/// widgets (paddle_widgets.dart); not per screen.
class KeyAdapterState {
  KeyAdapterState._();

  static const prefKey = 'hideSoftKeysOnAdapter';
  static const _settings = MethodChannel('at.oe1cko.nextcwtrainer/settings');
  static const _events = EventChannel('at.oe1cko.nextcwtrainer/key_adapter_events');

  /// True while a key adapter is detected.
  static final detected = ValueNotifier<bool>(false);

  /// User setting (Settings → Keyer); default off.
  static final hideEnabled = ValueNotifier<bool>(false);

  /// Hint closed with the X; shown again the next time an adapter is detected.
  static final dismissed = ValueNotifier<bool>(false);

  /// Rebuild trigger for everything that depends on the three values above.
  static final listenable = Listenable.merge([detected, hideEnabled, dismissed]);

  /// The touch paddles are hidden (and the hint takes their place).
  static bool get paddlesHidden => detected.value && hideEnabled.value;

  static StreamSubscription? _sub;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    hideEnabled.value = prefs.getBool(prefKey) ?? false;
    _sub ??= _events.receiveBroadcastStream().listen(
      (v) => setDetected(v == true),
      onError: (_) {},
    );
    try {
      setDetected(await _settings.invokeMethod<bool>('isKeyAdapterDetected') ?? false);
    } on PlatformException {
      setDetected(false);
    }
  }

  static void setDetected(bool on) {
    if (on && !detected.value) dismissed.value = false;
    detected.value = on;
  }

  static Future<void> setHideEnabled(bool on) async {
    hideEnabled.value = on;
    (await SharedPreferences.getInstance()).setBool(prefKey, on);
  }
}
