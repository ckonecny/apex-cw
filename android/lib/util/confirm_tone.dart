import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sound that follows a right/wrong grading (Hören typing, Geben, Echo
/// Trainer, character practice). One global choice, set in Settings → General.
///
/// The index is the stored value and what the native side gets as `style`
/// (CwTonePlugin.STYLE_*): [off] never reaches it.
enum ConfirmTone {
  off,

  /// The firmware's two sine tones (MorseOutput::soundSignalOK/ERR).
  classic,

  /// Two soft marimba notes up for right, two flute-like notes down for wrong.
  marimba,

  /// One note with a gentle vibrato in a small room: higher / lower.
  sanft;

  static const prefKey = 'confirmToneStyle';

  /// Order of the choices in the settings sheet.
  static const uiOrder = [classic, marimba, sanft, off];

  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  // Pause between the two halves of the preview (the longest tone lasts ~0.6 s).
  static const _previewGap = Duration(milliseconds: 1000);
  static int _previewGen = 0;

  /// The saved choice. Before the choice existed there was an on/off switch
  /// (`confirmTone`): off stays off, on becomes the firmware tone. Default:
  /// the firmware tone.
  static ConfirmTone fromPrefs(SharedPreferences p) {
    final v = p.getInt(prefKey);
    if (v != null && v >= 0 && v < values.length) return values[v];
    return (p.getBool('confirmTone') ?? true) ? classic : off;
  }

  Future<void> save(SharedPreferences p) => p.setInt(prefKey, index);

  /// Plays the right ([ok]) or wrong tone; nothing when [off].
  void play(MethodChannel channel, bool ok) {
    if (this == off) return;
    channel.invokeMethod('playConfirmTone', {'ok': ok, 'style': index})
        .catchError((_) {});
  }

  /// The sample played when picking this in the settings: right, then wrong.
  /// A newer preview (or [cancelPreview]) stops an older one from going on.
  Future<void> preview() async {
    final gen = ++_previewGen;
    if (this == off) return;
    play(_channel, true);
    await Future<void>.delayed(_previewGap);
    if (gen == _previewGen) play(_channel, false);
  }

  /// Call when the settings sheet goes away mid-preview.
  static void cancelPreview() => _previewGen++;
}
