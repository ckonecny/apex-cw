import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/util/interference_profile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every preset has all seven values in range', () {
    for (final p in InterferenceProfile.presets) {
      expect(p.length, 7);
      for (final v in p) {
        expect(v, inInclusiveRange(0, 100));
      }
    }
  });

  test('withPreset applies the levels and keeps the switch', () {
    const on = InterferenceProfile(enabled: true);
    final p = on.withPreset(2);
    expect(p.enabled, isTrue);
    expect(p.preset, 2);
    expect([p.noise, p.qrm, p.qsb, p.drift, p.jitter, p.filter, p.color],
        InterferenceProfile.presets[2]);
  });

  test('engine levels are all 0 when switched off, else percent / 100', () {
    const off = InterferenceProfile(noise: 40, qrm: 20, filter: 50);
    expect(off.engineLevels, List.filled(7, 0.0));
    final on = off.copyWith(enabled: true, qsb: 10, drift: 5, jitter: 15, color: 60);
    expect(on.engineLevels, [0.4, 0.2, 0.1, 0.05, 0.15, 0.5, 0.6]);
  });

  test('SNR display: +20 dB at 0 %, -10 dB at 100 %', () {
    expect(const InterferenceProfile(noise: 0).snrDb, 20);
    expect(const InterferenceProfile(noise: 100).snrDb, -10);
    expect(const InterferenceProfile(noise: 50).snrDb, 5);
  });

  test('save and load round trip, defaults when nothing is stored', () async {
    final d = await InterferenceProfile.load();
    expect(d.enabled, isFalse);
    expect(d.filter, 50);
    expect(d.color, 50);
    expect(d.ambient, isFalse);
    const p = InterferenceProfile(
        enabled: true, preset: 3, noise: 55, qrm: 60, qsb: 35, drift: 15, jitter: 30, filter: 60, color: 40, ambient: true);
    await p.save();
    final r = await InterferenceProfile.load();
    expect([r.enabled, r.preset, r.noise, r.qrm, r.qsb, r.drift, r.jitter, r.filter, r.color, r.ambient],
        [true, 3, 55, 60, 35, 15, 30, 60, 40, true]);
  });
}
