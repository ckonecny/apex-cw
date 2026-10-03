import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User setting for the interference simulation (issue #6): noise, QRM, QSB,
/// pitch drift and timing jitter ("bad fist") on the other station's signal.
/// Levels are 0..100 (percent). Global, not per screen: it is pushed to the
/// native engine at app start and whenever it changes; the engine applies it
/// only while the generator plays (see CwGenerator rx flag), so the user's own
/// keying stays clean.
class InterferenceProfile {
  static const _tone = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  /// 0 = custom, then the presets below.
  static const presetCustom = 0;
  static const presets = <List<int>>[
    // noise, qrm, qsb, drift, jitter, filter, color
    [0, 0, 0, 0, 0, 0, 50],      // custom (placeholder, never applied)
    [15, 0, 10, 0, 0, 30, 50],    // light
    [35, 20, 45, 10, 15, 50, 50],   // HF in the evening
    [55, 60, 35, 15, 30, 60, 50],   // pile-up
  ];

  final bool enabled;
  final int preset;
  final int noise, qrm, qsb, drift, jitter;
  /// Receiver filter narrowness: 0 = wide open, 100 = narrow CW filter.
  final int filter;
  /// Noise colour: 0 = dull (800 Hz roll-off), 100 = bright (3.2 kHz).
  final int color;

  const InterferenceProfile({
    this.enabled = false,
    this.preset = presetCustom,
    this.noise = 0,
    this.qrm = 0,
    this.qsb = 0,
    this.drift = 0,
    this.jitter = 0,
    this.filter = 50,
    this.color = 50,
  });

  InterferenceProfile copyWith({
    bool? enabled, int? preset, int? noise, int? qrm, int? qsb, int? drift, int? jitter, int? filter, int? color,
  }) =>
      InterferenceProfile(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        noise: noise ?? this.noise,
        qrm: qrm ?? this.qrm,
        qsb: qsb ?? this.qsb,
        drift: drift ?? this.drift,
        jitter: jitter ?? this.jitter,
        filter: filter ?? this.filter,
        color: color ?? this.color,
      );

  /// The profile with preset [i]'s levels (keeps the enabled flag).
  InterferenceProfile withPreset(int i) {
    final p = presets[i];
    return copyWith(preset: i, noise: p[0], qrm: p[1], qsb: p[2], drift: p[3], jitter: p[4], filter: p[5], color: p[6]);
  }

  static Future<InterferenceProfile> load() async {
    final p = await SharedPreferences.getInstance();
    int lvl(String k) => (p.getInt(k) ?? 0).clamp(0, 100);
    return InterferenceProfile(
      enabled: p.getBool('interfOn') ?? false,
      preset: (p.getInt('interfPreset') ?? presetCustom).clamp(0, presets.length - 1),
      noise: lvl('interfNoise'),
      qrm: lvl('interfQrm'),
      qsb: lvl('interfQsb'),
      drift: lvl('interfDrift'),
      jitter: lvl('interfJitter'),
      filter: (p.getInt('interfFilter') ?? 50).clamp(0, 100),
      color: (p.getInt('interfColor') ?? 50).clamp(0, 100),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('interfOn', enabled);
    await p.setInt('interfPreset', preset);
    await p.setInt('interfNoise', noise);
    await p.setInt('interfQrm', qrm);
    await p.setInt('interfQsb', qsb);
    await p.setInt('interfDrift', drift);
    await p.setInt('interfJitter', jitter);
    await p.setInt('interfFilter', filter);
    await p.setInt('interfColor', color);
  }

  /// Noise as SNR in dB in a 2.4 kHz reference bandwidth (matches the engine).
  int get snrDb => (20 - 30 * noise / 100).round();

  /// Levels as the native engine gets them: all 0 when switched off.
  List<double> get engineLevels => enabled
      ? [noise / 100, qrm / 100, qsb / 100, drift / 100, jitter / 100, filter / 100, color / 100]
      : const [0, 0, 0, 0, 0, 0, 0];

  Future<void> push() =>
      _tone.invokeMethod('setInterference', engineLevels).catchError((_) {});

  /// Reads the saved profile and pushes it (app start).
  static Future<void> pushSaved() async => (await load()).push();
}
