import 'package:flutter/services.dart';

/// Keeps the display awake only while an actual training screen is open
/// (Keyer/Generator/Koch/Echo) — call enable() in initState, disable() in
/// dispose. Not applied on Home or Settings.
class KeepScreenOn {
  static const _channel = MethodChannel('at.oe1wkl.morserino_mobile/settings');

  static void enable()  => _channel.invokeMethod('setKeepScreenOn', true);
  static void disable() => _channel.invokeMethod('setKeepScreenOn', false);
}
