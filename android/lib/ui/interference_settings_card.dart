import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import 'widgets/setting_rows.dart';

/// Settings card for the interference simulation (issue #6): master switch,
/// presets, one slider per implemented effect and a "try it" button.
class InterferenceSettingsCard extends StatefulWidget {
  const InterferenceSettingsCard({super.key});

  @override
  State<InterferenceSettingsCard> createState() =>
      _InterferenceSettingsCardState();
}

class _InterferenceSettingsCardState extends State<InterferenceSettingsCard> {
  static const _gen = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _tone = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _genEvents = EventChannel(
    'at.oe1cko.nextcwtrainer/cw_gen_events',
  );

  InterferenceProfile _p = const InterferenceProfile();
  bool _loaded = false;
  bool _trying = false;
  StreamSubscription? _doneSub;

  @override
  void initState() {
    super.initState();
    InterferenceProfile.load().then((p) {
      if (mounted) setState(() { _p = p; _loaded = true; });
    });
  }

  @override
  void dispose() {
    _doneSub?.cancel();
    if (_trying) _gen.invokeMethod('stopOne').catchError((_) {});
    super.dispose();
  }

  void _apply(InterferenceProfile p) {
    setState(() => _p = p);
    p.save();
    p.push();
  }

  // Plays a short CQ so the current levels can be judged. Pitch and speed are
  // pushed first (the native engine is a shared singleton, CLAUDE.md rule 2).
  Future<void> _toggleTry() async {
    if (_trying) {
      setState(() => _trying = false);
      _doneSub?.cancel();
      await _gen.invokeMethod('stopOne');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await _tone.invokeMethod(
      'setFreq',
      (prefs.getInt('pitch') ?? 600).toDouble(),
    );
    await _tone.invokeMethod(
      'setEnvelopeMs',
      ((prefs.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble(),
    );
    // Same speed and spacing as the listening trainer, and unpredictable
    // text: a known phrase is much easier to read through noise than the
    // random groups of a real exercise.
    final wpm = (prefs.getInt('profile.hear.wpm') ?? prefs.getInt('wpm') ?? 20)
        .clamp(5, 60);
    await _gen.invokeMethod('setWpm', wpm);
    await _gen.invokeMethod(
      'setInterCharSpace',
      (prefs.getInt('profile.hear.interCharSpace') ?? 3).clamp(3, 45),
    );
    await _gen.invokeMethod(
      'setInterWordSpace',
      (prefs.getInt('profile.hear.interWordSpace') ?? 7).clamp(6, 105),
    );
    await _p.push();
    if (!mounted) return;
    setState(() => _trying = true);
    _doneSub = _genEvents.receiveBroadcastStream().listen((e) {
      if (e is Map && e['type'] == 'done') {
        _doneSub?.cancel();
        if (mounted) setState(() => _trying = false);
      }
    });
    final rnd = Random();
    const pool = 'ETAOINSRHLDCUMFPGWYBVKXJQZ0123456789';
    final text = List.generate(
      4,
      (_) => String.fromCharCodes(
        List.generate(5, (_) => pool.codeUnitAt(rnd.nextInt(pool.length))),
      ),
    ).join(' ');
    await _gen.invokeMethod('playOne', text);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final labels = [
      Strings.t('interf_preset_custom'),
      Strings.t('interf_preset_light'),
      Strings.t('interf_preset_hf'),
      Strings.t('interf_preset_pileup'),
    ];
    return SettingsCard(
      children: [
        ToggleRow(
          label: Strings.t('interf_enable'),
          value: _p.enabled,
          onChanged: _loaded ? (v) => _apply(_p.copyWith(enabled: v)) : (_) {},
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            Strings.t('interf_enable_desc'),
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
        ),
        // Switched off: the settings are folded away, not greyed out.
        if (_p.enabled) ...[
          const SettingsDivider(),
          Column(
            children: [
              SegmentRow(
                label: Strings.t('interf_preset'),
                options: labels,
                selected: _p.preset,
                onChanged: (i) => _apply(
                  i == InterferenceProfile.presetCustom
                      ? _p.copyWith(preset: i)
                      : _p.withPreset(i),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_noise'),
                value: _p.noise.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: 'SNR ${_p.snrDb} dB',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    noise: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_color'),
                value: _p.color.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '${_p.color} %',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    color: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_filter'),
                value: _p.filter.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '${_p.filter} %',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    filter: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_qsb'),
                value: _p.qsb.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '${_p.qsb} %',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    qsb: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_qrm'),
                value: _p.qrm.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '${_p.qrm} %',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    qrm: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_drift'),
                value: _p.drift.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '${_p.drift} %',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    drift: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              LabeledSlider(
                label: Strings.t('interf_jitter'),
                value: _p.jitter.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                display: '${_p.jitter} %',
                onChanged: (v) => _apply(
                  _p.copyWith(
                    preset: InterferenceProfile.presetCustom,
                    jitter: v.round(),
                  ),
                ),
              ),
              const SettingsDivider(),
              ToggleRow(
                label: Strings.t('interf_ambient'),
                value: _p.ambient,
                onChanged: (v) => _apply(_p.copyWith(ambient: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  Strings.t('interf_ambient_desc'),
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
              const SettingsDivider(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: _toggleTry,
                  icon: Icon(_trying ? Icons.stop : Icons.play_arrow, size: 18),
                  label: Text(
                    Strings.t(_trying ? 'interf_try_stop' : 'interf_try'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
