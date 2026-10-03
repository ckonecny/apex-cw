import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User setting for the interference simulation (issue #6): noise, QRM, QSB,
/// pitch drift and timing jitter ("bad fist") on the other station's signal.
/// Levels are 0..100 (percent). Global, not per screen: it is pushed to the
/// native engine at app start and whenever it changes; the engine applies it
/// only while the generator plays (see CwGenerator rx flag), so the user's own
/// keying stays clean. Optional "ambient": the noise also stands between
/// signals while a screen or block asks for it (requestAmbient).
class InterferenceProfile {
  static const _tone = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  /// 0 = custom, then the presets below.
  static const presetCustom = 0;
  static const presets = <List<int>>[
    // noise, qrm, qsb, drift, jitter, filter, color
    [0, 0, 0, 0, 0, 0, 50], // custom (placeholder, never applied)
    [15, 0, 10, 0, 0, 30, 50], // light
    [35, 20, 45, 10, 15, 50, 50], // HF in the evening
    [55, 60, 35, 15, 30, 60, 50], // pile-up
  ];

  final bool enabled;
  final int preset;
  final int noise, qrm, qsb, drift, jitter;

  /// Receiver filter narrowness: 0 = wide open, 100 = narrow CW filter.
  final int filter;

  /// Noise colour: 0 = dull (800 Hz roll-off), 100 = bright (3.2 kHz).
  final int color;

  /// Band noise and QRM stay audible for as long as a screen or training
  /// block is active (also under the own keying), not only while the other
  /// station is played. The own sidetone itself stays clean.
  final bool ambient;

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
    this.ambient = false,
  });

  InterferenceProfile copyWith({
    bool? enabled,
    int? preset,
    int? noise,
    int? qrm,
    int? qsb,
    int? drift,
    int? jitter,
    int? filter,
    int? color,
    bool? ambient,
  }) => InterferenceProfile(
    enabled: enabled ?? this.enabled,
    preset: preset ?? this.preset,
    noise: noise ?? this.noise,
    qrm: qrm ?? this.qrm,
    qsb: qsb ?? this.qsb,
    drift: drift ?? this.drift,
    jitter: jitter ?? this.jitter,
    filter: filter ?? this.filter,
    color: color ?? this.color,
    ambient: ambient ?? this.ambient,
  );

  /// The profile with preset [i]'s levels (keeps the enabled flag).
  InterferenceProfile withPreset(int i) {
    final p = presets[i];
    return copyWith(
      preset: i,
      noise: p[0],
      qrm: p[1],
      qsb: p[2],
      drift: p[3],
      jitter: p[4],
      filter: p[5],
      color: p[6],
    );
  }

  static Future<InterferenceProfile> load() async {
    final p = await SharedPreferences.getInstance();
    int lvl(String k) => (p.getInt(k) ?? 0).clamp(0, 100);
    return InterferenceProfile(
      enabled: p.getBool('interfOn') ?? false,
      preset: (p.getInt('interfPreset') ?? presetCustom).clamp(
        0,
        presets.length - 1,
      ),
      noise: lvl('interfNoise'),
      qrm: lvl('interfQrm'),
      qsb: lvl('interfQsb'),
      drift: lvl('interfDrift'),
      jitter: lvl('interfJitter'),
      filter: (p.getInt('interfFilter') ?? 50).clamp(0, 100),
      color: (p.getInt('interfColor') ?? 50).clamp(0, 100),
      ambient: p.getBool('interfAmbient') ?? false,
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
    await p.setBool('interfAmbient', ambient);
  }

  /// Noise as SNR in dB in a 2.4 kHz reference bandwidth (matches the engine).
  int get snrDb => (20 - 30 * noise / 100).round();

  /// Levels as the native engine gets them: all 0 when switched off.
  List<double> get engineLevels => enabled
      ? [
          noise / 100,
          qrm / 100,
          qsb / 100,
          drift / 100,
          jitter / 100,
          filter / 100,
          color / 100,
        ]
      : const [0, 0, 0, 0, 0, 0, 0];

  Future<void> push() async {
    _current = this;
    await _tone
        .invokeMethod('setInterference', engineLevels)
        .catchError((_) {});
    await _pushAmbient();
  }

  // ── Ambient (permanent noise while a screen / block is active) ──
  // Screens ask for it with a token (their State) and give it back when they
  // are done; several screens can be stacked, so it counts owners instead of
  // one flag. The engine only gets it when the profile is on and the
  // "ambient" setting is on.
  static InterferenceProfile _current = const InterferenceProfile();
  static final Set<Object> _owners = {};

  static Future<void> _pushAmbient() => _tone
      .invokeMethod(
        'setAmbient',
        _owners.isNotEmpty && _current.enabled && _current.ambient,
      )
      .catchError((_) {});

  /// [owner] wants the noise to stand permanently (until [releaseAmbient]).
  static Future<void> requestAmbient(Object owner) async {
    if (_owners.isEmpty && !_loadedOnce) {
      _current = await load();
      _loadedOnce = true;
    }
    _owners.add(owner);
    await _pushAmbient();
  }

  static Future<void> releaseAmbient(Object owner) async {
    _owners.remove(owner);
    await _pushAmbient();
  }

  static bool _loadedOnce = false;

  /// Reads the saved profile and pushes it (app start).
  static Future<void> pushSaved() async {
    _loadedOnce = true;
    await (await load()).push();
  }
}
