// Engine config from the user's settings, pushed in one call (#18).
//
// The tone engine, CwGenerator and CwKeyer are shared native singletons
// (CLAUDE.md rule 2): nothing re-syncs them, so every screen pushes its own
// config on entry. These helpers hold the preference keys, defaults and
// clamps in one place, so a screen cannot read a wrong key or default.
// Each call goes out awaited, one after the other, in the order the screens
// always sent them (test/engine_trace_test.dart checks this).
import 'package:shared_preferences/shared_preferences.dart';

import 'channels.dart';

/// Sidetone pitch in Hz.
int prefPitch(SharedPreferences p) => p.getInt('pitch') ?? 600;

/// Tone softness 0..8 (Settings → General); the envelope is softness + 1 ms.
int prefToneSoftness(SharedPreferences p) => (p.getInt('toneSoftness') ?? 4).clamp(0, 8);

/// Pitch and envelope to the tone engine; [volume] in between when given.
Future<void> pushTone({required int pitch, required int softness, double? volume}) async {
  await Channels.tone.invokeMethod('setFreq', pitch);
  if (volume != null) await Channels.tone.invokeMethod('setVolume', volume);
  await Channels.tone.invokeMethod('setEnvelopeMs', (softness + 1).toDouble());
}

/// [pushTone] with pitch and softness from the settings.
Future<void> pushToneSettings(SharedPreferences p, {double? volume}) =>
    pushTone(pitch: prefPitch(p), softness: prefToneSoftness(p), volume: volume);

/// Curtis-B timing (dit/dah, percent) and ACS to the keyer.
Future<void> pushKeyerTiming(SharedPreferences p) async {
  await Channels.keyer.invokeMethod('setCurtisBTiming', {
    'dit': (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
    'dah': (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
  });
  await Channels.keyer.invokeMethod('setAcs', (p.getInt('acs') ?? 0).clamp(0, 3));
}

/// Keyer [mode], then [pushKeyerTiming].
Future<void> pushKeyerSettings(SharedPreferences p, {required int mode}) async {
  await Channels.keyer.invokeMethod('setMode', mode);
  await pushKeyerTiming(p);
}
