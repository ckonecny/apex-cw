import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/bluetooth_hint.dart';
import '../util/settings_events.dart';
import 'widgets/setting_rows.dart';
import '../keyer/channels.dart';

/// Audio output: which device plays the sidetone, and the Bluetooth latency
/// hint. Shown in the settings and on its own page (Bluetooth hint above the
/// paddles), so a jump there needs no scrolling.
class AudioOutputCard extends StatefulWidget {
  const AudioOutputCard({super.key});

  @override
  State<AudioOutputCard> createState() => _AudioOutputCardState();
}

class _AudioOutputCardState extends State<AudioOutputCard> {
  static const _settings = Channels.settings;

  // Kind values match AudioRouteManager.kt's KIND_* constants exactly.
  int _kindPref = 0;
  List<int> _kindsAvailable = const [0];
  String _activeLabel = '…';
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadKinds();
    _eventSub = SettingsEvents.stream.listen((e) {
      if (e['type'] == 'audioRoute' && mounted) {
        setState(() => _activeLabel = e['value'] as String);
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadKinds() async {
    final r = await _settings.invokeMapMethod<String, dynamic>('getOutputDeviceKinds');
    if (r == null || !mounted) return;
    setState(() {
      _kindPref = r['preferred'] as int? ?? 0;
      _kindsAvailable = (r['available'] as List?)?.cast<int>() ?? const [0];
    });
  }

  Future<void> _apply(int kind) async {
    setState(() => _kindPref = kind);
    await _settings.invokeMethod('setOutputDeviceKind', kind);
  }

  // Native-side labels ("Lautsprecher"/"Kabel/USB"/"Bluetooth") are matched
  // back to localized strings here rather than sent pre-translated, since the
  // same event also fires from a background AudioDeviceCallback.
  String _localizedActive() => switch (_activeLabel) {
        'Kabel/USB' => Strings.t('opt_audio_wired'),
        'Bluetooth' => Strings.t('opt_audio_bluetooth'),
        _ => Strings.t('opt_audio_speaker'),
      };

  String _kindLabel(int kind) => switch (kind) {
        1 => Strings.t('opt_audio_speaker'),
        2 => Strings.t('opt_audio_wired'),
        3 => Strings.t('opt_audio_bluetooth'),
        _ => Strings.t('opt_audio_auto'),
      };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(Strings.t('settings_audio_output_desc'),
          style: TextStyle(fontSize: 11, color: c.textFaint)),
      const SizedBox(height: 12),
      SettingsCard(children: [
        SegmentRow(
          label: Strings.t('settings_audio_output_active').replaceFirst('{val}', _localizedActive()),
          options: _kindsAvailable.map(_kindLabel).toList(),
          selected: _kindsAvailable.indexOf(_kindPref).clamp(0, _kindsAvailable.length - 1),
          onChanged: (i) => _apply(_kindsAvailable[i]),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: BluetoothHint.enabled,
          builder: (context, on, _) => ToggleRow(
            label: Strings.t('settings_bt_latency_hint'),
            value: on,
            onChanged: BluetoothHint.setEnabled,
          ),
        ),
      ]),
    ]);
  }
}
