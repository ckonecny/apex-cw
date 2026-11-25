import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../util/key_adapter_state.dart';
import '../util/paddle_layout.dart';
import 'widgets/setting_rows.dart';
import '../keyer/channels.dart';

/// Settings card for the keyer: mode, touch paddle layout, CurtisB timing
/// (Iambic B), AutoChar spacing or the straight key's start speed, and the
/// timing analysis. Shown in the settings and on its own page (key icon,
/// keyer screen), so a jump there needs no scrolling.
class KeyerSettingsCard extends StatefulWidget {
  const KeyerSettingsCard({super.key});

  @override
  State<KeyerSettingsCard> createState() => _KeyerSettingsCardState();
}

class _KeyerSettingsCardState extends State<KeyerSettingsCard> {
  static const _settings = Channels.settings;

  int _keyerMode = 0; // 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight
  // "CurtisB DitT%"/"CurtisB DahT%" (M32 defaults 75/45): only meaningful in
  // Iambic B (Ultimatic ignores them, as in the firmware) — how far into the
  // current element (as a % of its length) the keyer starts looking ahead for
  // the opposite paddle.
  int _curtisBDit = 75;
  int _curtisBDah = 45;
  // "AutoChar Spc" (M32 posACS, default 0=off): minimum pause enforced
  // between characters — 1/2/3 = 2/3/4 dits.
  int _acs = 0;
  // Start speed estimate for the straight key (the measurement adapts from there).
  int _straightStartWpm = 15;
  bool _fistAnalyzer = false; // straight key: timing panel in the CW Keyer (#164)

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _keyerMode = p.getInt('keyerMode') ?? 0;
        _fistAnalyzer = p.getBool('fistAnalyzer') ?? false;
        _curtisBDit = (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100);
        _curtisBDah = (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100);
        _acs = (p.getInt('acs') ?? 0).clamp(0, 3);
        _straightStartWpm = (p.getInt('straightStartWpm') ?? 15).clamp(5, 40);
      });
    });
  }

  Future<void> _setInt(String key, int v) async =>
      (await SharedPreferences.getInstance()).setInt(key, v);

  Future<void> _applyKeyerMode(int mode) async {
    setState(() => _keyerMode = mode);
    await _settings.invokeMethod('setKeyerMode', mode);
    await _setInt('keyerMode', mode);
  }

  Future<void> _applyCurtisB({int? dit, int? dah}) async {
    setState(() {
      if (dit != null) _curtisBDit = dit;
      if (dah != null) _curtisBDah = dah;
    });
    await _settings.invokeMethod('setCurtisBTiming', {'dit': _curtisBDit, 'dah': _curtisBDah});
    await _setInt('curtisBDitTiming', _curtisBDit);
    await _setInt('curtisBDahTiming', _curtisBDah);
  }

  Future<void> _applyAcs(int v) async {
    setState(() => _acs = v);
    await _settings.invokeMethod('setAcs', v);
    await _setInt('acs', v);
  }

  Future<void> _applyStraightStartWpm(int v) async {
    setState(() => _straightStartWpm = v);
    await _settings.invokeMethod('setStraightStartWpm', v);
    await _setInt('straightStartWpm', v);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(children: [
      SegmentRow(
        label: Strings.t('settings_mode'),
        options: const ['Iambic A', 'Iambic B', 'Ultimatic', 'Non-Squeeze', 'Straight'],
        selected: _keyerMode,
        onChanged: _applyKeyerMode,
      ),
      // On-screen paddles only; learned hardware keys stay as learned.
      if (_keyerMode != 4) ...[
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: PaddleLayout.swapped,
          builder: (context, on, _) => ToggleRow(
            label: Strings.t('settings_swap_touch_paddles'),
            value: on,
            onChanged: PaddleLayout.setSwapped,
          ),
        ),
      ],
      // Real key on an adapter detected (#95): the touch keys only take space.
      const SettingsDivider(),
      ValueListenableBuilder<bool>(
        valueListenable: KeyAdapterState.hideEnabled,
        builder: (context, on, _) => ToggleRow(
          label: Strings.t('settings_hide_softkeys_adapter'),
          value: on,
          onChanged: KeyAdapterState.setHideEnabled,
        ),
      ),
      if (_keyerMode == 1) ...[
        const SettingsDivider(),
        LabeledSlider(label: Strings.t('settings_curtisb_dit'),
            value: _curtisBDit.toDouble(),
            min: 0, max: 100, divisions: 20, display: '$_curtisBDit%',
            onChanged: (v) => _applyCurtisB(dit: v.round())),
        const SettingsDivider(),
        LabeledSlider(label: Strings.t('settings_curtisb_dah'),
            value: _curtisBDah.toDouble(),
            min: 0, max: 100, divisions: 20, display: '$_curtisBDah%',
            onChanged: (v) => _applyCurtisB(dah: v.round())),
      ],
      const SettingsDivider(),
      // Straight key: no AutoChar Spc (a paddle aid), but the start speed
      // of the adaptive measurement.
      if (_keyerMode == 4)
        LabeledSlider(label: Strings.t('settings_straight_start'),
            value: _straightStartWpm.toDouble(),
            min: 5, max: 40, divisions: 35, display: '$_straightStartWpm WPM',
            onChanged: (v) => _applyStraightStartWpm(v.round()))
      else
        SegmentRow(
          label: Strings.t('settings_acs'),
          options: [Strings.t('opt_off'), for (final n in [2, 3, 4])
              Strings.t('unit_dits').replaceFirst('{n}', '$n')],
          selected: _acs,
          onChanged: _applyAcs,
        ),
      if (_keyerMode == 4) ...[
        const SettingsDivider(),
        ToggleRow(
          label: Strings.t('settings_fist_analyzer'),
          value: _fistAnalyzer,
          onChanged: (v) async {
            setState(() => _fistAnalyzer = v);
            (await SharedPreferences.getInstance()).setBool('fistAnalyzer', v);
          },
        ),
      ],
    ]);
  }
}
