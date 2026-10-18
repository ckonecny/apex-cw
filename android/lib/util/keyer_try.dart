import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/echo_suggestions.dart' show kGiveWpmCap;
import '../content/training_profile.dart';

/// Lets an external key be tried out on screens that do not key themselves
/// (#116): pushes the general Send settings (speed, pitch, mode, Curtis-B, ACS,
/// softness, tone shift) to the shared keyer and starts it, so dit/dah sound.
/// Rule 2 (CLAUDE.md): the keyer is a shared singleton, so this sets
/// everything it relies on itself.
class KeyerTry {
  KeyerTry._();

  static const _keyer = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _tone = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  static Future<void> start() async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.echo);
    final wpm = TrainingProfile.clampWpm(pf.getInt('wpm'));
    final cap = kGiveWpmCap(p.getInt('echoAnswerWpmMax') ?? 0);
    final pitch = p.getInt('pitch') ?? 600;
    final shifted = switch ((p.getInt('toneShift') ?? 1).clamp(0, 2)) {
      1 => (pitch * 18 / 17).round(),
      2 => (pitch * 17 / 18).round(),
      _ => pitch,
    };
    await _keyer.invokeMethod('setMode', p.getInt('keyerMode') ?? 0).catchError((_) {});
    await _keyer.invokeMethod('setCurtisBTiming', {
      'dit': (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
      'dah': (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
    }).catchError((_) {});
    await _keyer.invokeMethod('setAcs', (p.getInt('acs') ?? 0).clamp(0, 3)).catchError((_) {});
    await _keyer.invokeMethod('setWpm', cap > 0 ? min(wpm, cap) : wpm).catchError((_) {});
    await _tone.invokeMethod('setEnvelopeMs', ((p.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble())
        .catchError((_) {});
    await _tone.invokeMethod('setFreq', shifted).catchError((_) {});
    await _keyer.invokeMethod('start').catchError((_) {});
  }

  static Future<void> stop() => _keyer.invokeMethod('stop').catchError((_) {});
}
