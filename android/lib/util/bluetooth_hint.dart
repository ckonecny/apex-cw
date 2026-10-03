import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the sidetone currently plays on a Bluetooth output, so every
/// screen that shows keying paddles can warn about the 100–250 ms delay.
/// Shared by all paddle widgets (paddle_widgets.dart); not per screen.
class BluetoothHint {
  BluetoothHint._();

  static const prefKey = 'btLatencyHint';
  static const _settings = MethodChannel('at.oe1cko.nextcwtrainer/settings');
  static const _events = EventChannel('at.oe1cko.nextcwtrainer/audio_route_events');

  /// True while a Bluetooth output is the active route.
  static final bluetoothActive = ValueNotifier<bool>(false);

  /// User setting (Settings → Audio output); default on.
  static final enabled = ValueNotifier<bool>(true);

  /// Closed with the X for this app run; shown again after a restart.
  static final dismissed = ValueNotifier<bool>(false);

  static StreamSubscription? _sub;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(prefKey) ?? true;
    _sub ??= _events.receiveBroadcastStream().listen(
      (v) => bluetoothActive.value = v == true,
      onError: (_) {},
    );
    try {
      bluetoothActive.value =
          await _settings.invokeMethod<bool>('isBluetoothOutput') ?? false;
    } on PlatformException {
      bluetoothActive.value = false;
    }
  }

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    if (on) dismissed.value = false;
    (await SharedPreferences.getInstance()).setBool(prefKey, on);
  }
}
