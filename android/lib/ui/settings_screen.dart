import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import '../theme/theme_controller.dart';
import '../l10n/strings.dart';
import '../licenses.dart';
import 'widgets/setting_rows.dart';
import 'interference_settings_card.dart';
import '../util/bluetooth_hint.dart';
import '../util/break_reminder.dart';
import '../util/paddle_layout.dart';
import '../util/practice_clock.dart';
import '../util/reminder.dart';

enum _LearnState { idle, waitDit, waitDah, done }

class SettingsScreen extends StatefulWidget {
  /// Opens scrolled to the "Audio output" section (used by the Bluetooth hint
  /// above the paddles, so the output can be switched right there).
  final bool scrollToAudio;
  const SettingsScreen({super.key, this.scrollToAudio = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _settingsChannel = MethodChannel('at.oe1cko.nextcwtrainer/settings');
  static const _settingsEvents  = EventChannel('at.oe1cko.nextcwtrainer/settings_events');
  static const _toneChannel     = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  final _scroll = ScrollController();
  final _audioKey = GlobalKey();

  // ── General ────────────────────────────────────────────────────────────────
  // Which training's profile the profile-backed fields below edit (P2 D5;
  // temporary switch until settings move into the training screens).
  int  _pitch     = 600;
  // outputCase: 0=lower, 1=UPPER (matches M32 "Output Case"; applies to all
  // displayed generated/decoded text, not stored — content stays uppercase internally)
  int  _outputCase = 0;
  // "Tone Softness" (M32 posToneSoftness, default 4): sidetone attack/release
  // time, prefValue 0..8 maps to 1..9 ms (MorseOutput::setSidetoneEnvelope()).
  int  _toneSoftness = 4;

  // ── Practice Set ──────────────────────────────────────────────────────────

  // ── Keyer ──────────────────────────────────────────────────────────────────
  int  _keyerMode   = 0;    // 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight
  // "CurtisB DitT%"/"CurtisB DahT%" (M32 defaults 75/45): only meaningful in
  // Iambic B/Ultimatic — how far into the current element (as a % of its
  // length) the keyer starts looking ahead for the opposite paddle.
  int  _curtisBDitTiming = 75;
  int  _curtisBDahTiming = 45;
  // "AutoChar Spc" (M32 posACS, default 0=off): minimum pause enforced
  // between characters — 1/2/3 = 2/3/4 dits.
  int  _acs = 0;
  // Start speed estimate for the straight key (the measurement adapts from there).
  int  _straightStartWpm = 15;
  // "Tone Shift" (M32 posEchoToneShift, default 1): shifts the operator's own
  // echoed-answer sidetone in the Echo Trainer up/down a half-tone from the
  // target word's pitch, so the two are audibly distinguishable. Has no
  // effect on the standalone CW Keyer, matching the real device.

  // ── Spacing ────────────────────────────────────────────────────────────────
  // Absolute gap length in dits, exactly like the real M32 (Interchar 3..45,
  // InterWord 6..105; default = normal Morse timing 3/7).

  // ── CW Generator ──────────────────────────────────────────────────────────
  // genDisplay: 0=Display off, 1=Char by char, 2=Word by word (matches M32 "CW Gen Displ")
  // randomOption: which alphabet subset "Zufallszeichen" draws from when NOT
  // in Koch mode (matches M32 "Random Groups" / posRandomOption exactly).

  // ── Rufzeichen ────────────────────────────────────────────────────────────
  // callLengthOpt: 0=Unlimited,1="3",2="4",3="5",4="6" (M32 "Length Calls")
  int  _callLengthOpt = 0;
  // callRegionOpt: 0=All,1=EU,2=NA,3=SA,4=AF,5=AS,6=OC,7=VK/ZL (M32 "Calls Region")
  int  _callRegionOpt = 0;
  bool _callCommonOnly = true;  // M32 default: "Common only"

  // ── Echo Trainer ───────────────────────────────────────────────────────────
  // M32 "Echo Repeats": 0-6 = that many replays after a wrong/missed answer
  // before the word is revealed and the trainer moves on; 7 = "Forever"
  // (never gives up). Default 3, matching the real device's default.
  // echoDisplay: 1=Sound only, 2=Display only, 3=Sound & Disp (matches M32 "Echo Prompt")

  // ── Adaptive Mode (Adaptive Copy engine thresholds) ─────────────────────
  // See docs/ADAPTIVE-COPY.md "Decisions: weighting/recency questions" and
  // AdaptiveCopyThresholds (content/adaptive_copy_engine.dart) for what
  // these drive. Stored as percent ints for slider-friendliness; converted
  // to the 0..1 doubles AdaptiveCopyThresholds expects where consumed.

  // ── Audio Output ──────────────────────────────────────────────────────────
  // Kind values match AudioRouteManager.kt's KIND_* constants exactly.
  int _outputKindPref = 0;
  List<int> _outputKindsAvailable = const [0];
  String _activeOutputLabel = '…';

  // ── Paddle ────────────────────────────────────────────────────────────────
  String _ditDesc = '…';
  String _dahDesc = '…';
  _LearnState _learnState  = _LearnState.idle;
  String _learnMessage = '';

  // ── Key diagnostics ───────────────────────────────────────────────────────
  bool _keyDiagActive = false;
  final List<String> _keyDiagLog = [];

  // ── Info ──────────────────────────────────────────────────────────────────
  // Version/build identification from native BuildConfig (git commit, dirty
  // flag, build time are stamped in by app/build.gradle.kts).
  String _version = '…';
  String _build   = '…';
  String _buildTime = '…';

  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPaddleDesc();
    _loadOutputDeviceKinds();
    _loadAppVersion();
    _eventSub = _settingsEvents.receiveBroadcastStream().listen(_onSettingsEvent);
    if (widget.scrollToAudio) WidgetsBinding.instance.addPostFrameCallback((_) => _revealAudio());
  }

  // The list builds its children lazily, so the section may not exist yet:
  // step down the page until its context appears, then bring it into view.
  Future<void> _revealAudio() async {
    for (var i = 0; i < 20 && mounted; i++) {
      final ctx = _audioKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
        return;
      }
      if (!_scroll.hasClients) return;
      _scroll.jumpTo((_scroll.offset + 500).clamp(0, _scroll.position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _scroll.dispose();
    _settingsChannel.invokeMethod('cancelLearnPaddle');
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _pitch          = p.getInt('pitch')          ?? 600;
      _outputCase     = (p.getInt('outputCase')    ?? 0).clamp(0, 1);
      _toneSoftness   = (p.getInt('toneSoftness')  ?? 4).clamp(0, 8);
      _keyerMode      = p.getInt('keyerMode')      ?? 0;
      _curtisBDitTiming = (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100);
      _curtisBDahTiming = (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100);
      _acs              = (p.getInt('acs') ?? 0).clamp(0, 3);
      _straightStartWpm = (p.getInt('straightStartWpm') ?? 15).clamp(5, 40);
      // clamp() guards against stale values from the old 1..8 multiplier scale
      // genDisplayMode/echoDisplayMode: new int-valued keys (old genDisplay/echoPrompt
      // keys were bool — renamed to avoid a SharedPreferences type-cast crash on upgrade)
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      // Capped below 100: the per-char EMA error rate only decays toward 0
      // asymptotically and a single historical error (ever, since it's never
      // reset) keeps it from hitting exact 0 again — a 100% threshold is a
      // permanent, invisible trap for that character. See ADAPTIVE-COPY.md.
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('pitch',          _pitch);
    await p.setInt('outputCase',     _outputCase);
    await p.setInt('toneSoftness',   _toneSoftness);
    await p.setInt('keyerMode',      _keyerMode);
    await p.setInt('curtisBDitTiming', _curtisBDitTiming);
    await p.setInt('curtisBDahTiming', _curtisBDahTiming);
    await p.setInt('acs',            _acs);
    await p.setInt('straightStartWpm', _straightStartWpm);
    await p.setInt('callLengthOpt',   _callLengthOpt);
    await p.setInt('callRegionOpt',   _callRegionOpt);
    await p.setBool('callCommonOnly', _callCommonOnly);
  }

  void _saveLive() => _save();  // called on every interactive change

  Future<void> _loadAppVersion() async {
    final v = await _settingsChannel.invokeMapMethod<String, dynamic>('getAppVersion');
    if (v == null || !mounted) return;
    setState(() {
      _version = '${v['versionName']} (Build ${v['versionCode']})';
      _build = '${v['gitSha']}${v['gitDirty'] == true ? '-dirty' : ''}'
          '${v['buildType'] == 'release' ? '' : ' · ${v['buildType']}'}';
      _buildTime = '${v['buildTime']}';
    });
  }

  Future<void> _loadPaddleDesc() async {
    final result = await _settingsChannel.invokeMapMethod<String, String>('getPaddleChars');
    if (result != null && mounted) {
      setState(() {
      _ditDesc = result['dit'] ?? '?';
      _dahDesc = result['dah'] ?? '?';
    });
    }
  }

  void _onSettingsEvent(dynamic raw) {
    if (!mounted) return;
    final ev   = raw as Map;
    final type = ev['type']  as String;
    final val  = ev['value'] as String;
    setState(() {
      switch (type) {
        case 'step':
          if (val == '1') { _learnState = _LearnState.waitDit; _learnMessage = Strings.t('settings_press_dit_key'); }
          else            { _learnState = _LearnState.waitDah; _learnMessage = Strings.t('settings_press_dah_key'); }
        case 'done':
          _learnState = _LearnState.done; _learnMessage = Strings.t('settings_saved').replaceFirst('{val}', val);
          _loadPaddleDesc();
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _learnState = _LearnState.idle);
          });
        case 'keyDiag':
          _keyDiagLog.insert(0, val);
          if (_keyDiagLog.length > 20) _keyDiagLog.removeLast();
        case 'audioRoute':
          _activeOutputLabel = val;
      }
    });
  }

  // Native-side labels ("Lautsprecher"/"Kabel/USB"/"Bluetooth") are matched
  // back to localized strings here rather than sent pre-translated, since the
  // same event also fires from a background AudioDeviceCallback.
  String _localizedActiveLabel() => switch (_activeOutputLabel) {
    'Kabel/USB' => Strings.t('opt_audio_wired'),
    'Bluetooth' => Strings.t('opt_audio_bluetooth'),
    _           => Strings.t('opt_audio_speaker'),
  };

  Future<void> _loadOutputDeviceKinds() async {
    final result = await _settingsChannel.invokeMapMethod<String, dynamic>('getOutputDeviceKinds');
    if (result == null || !mounted) return;
    setState(() {
      _outputKindPref = result['preferred'] as int? ?? 0;
      _outputKindsAvailable = (result['available'] as List?)?.cast<int>() ?? const [0];
    });
  }

  Future<void> _applyOutputKind(int kind) async {
    setState(() => _outputKindPref = kind);
    await _settingsChannel.invokeMethod('setOutputDeviceKind', kind);
  }

  String _outputKindLabel(int kind) => switch (kind) {
    1 => Strings.t('opt_audio_speaker'),
    2 => Strings.t('opt_audio_wired'),
    3 => Strings.t('opt_audio_bluetooth'),
    _ => Strings.t('opt_audio_auto'),
  };

  Future<void> _startLearn()  async { await _settingsChannel.invokeMethod('startLearnPaddle'); }
  Future<void> _cancelLearn() async {
    await _settingsChannel.invokeMethod('cancelLearnPaddle');
    setState(() { _learnState = _LearnState.idle; _learnMessage = ''; });
  }

  Future<void> _toggleKeyDiag() async {
    if (_keyDiagActive) {
      await _settingsChannel.invokeMethod('stopKeyDiag');
      setState(() { _keyDiagActive = false; });
    } else {
      _keyDiagLog.clear();
      await _settingsChannel.invokeMethod('startKeyDiag');
      setState(() { _keyDiagActive = true; });
    }
  }

  Future<void> _applyKeyerMode(int mode) async {
    setState(() => _keyerMode = mode);
    await _settingsChannel.invokeMethod('setKeyerMode', mode);
    _saveLive();
  }

  Future<void> _applyToneSoftness(double v) async {
    final ms = v.round();
    setState(() => _toneSoftness = ms);
    await _toneChannel.invokeMethod('setEnvelopeMs', (ms + 1).toDouble());
    _saveLive();
  }

  Future<void> _applyCurtisBTiming({int? dit, int? dah}) async {
    setState(() {
      if (dit != null) _curtisBDitTiming = dit;
      if (dah != null) _curtisBDahTiming = dah;
    });
    await _settingsChannel.invokeMethod('setCurtisBTiming',
        {'dit': _curtisBDitTiming, 'dah': _curtisBDahTiming});
    _saveLive();
  }

  Future<void> _applyAcs(int value) async {
    setState(() => _acs = value);
    await _settingsChannel.invokeMethod('setAcs', value);
    _saveLive();
  }

  Future<void> _applyStraightStartWpm(int v) async {
    setState(() => _straightStartWpm = v);
    await _settingsChannel.invokeMethod('setStraightStartWpm', v);
    _saveLive();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Rebuild this whole screen the instant the language changes — Strings.t()
    // is a plain static lookup, not an InheritedWidget, so without this the
    // already-built widgets here would only pick up the new language on their
    // next unrelated rebuild (e.g. a slider drag), not immediately like Theme.
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('settings_title')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () { _save(); Navigator.pop(context); },
        ),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(20),
        children: [

          // ── Darstellung ───────────────────────────────────────────────────
          SettingsSectionHeader(Strings.t('settings_appearance')),
          const SizedBox(height: 12),
          SettingsCard(children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => SegmentRow(
                label: Strings.t('settings_theme'),
                options: [Strings.t('theme_system'), Strings.t('theme_light'), Strings.t('theme_dark')],
                selected: switch (mode) {
                  ThemeMode.light => 1,
                  ThemeMode.dark  => 2,
                  _               => 0,
                },
                onChanged: (v) => ThemeController.set(
                    [ThemeMode.system, ThemeMode.light, ThemeMode.dark][v]),
              ),
            ),
            const SettingsDivider(),
            ValueListenableBuilder<int>(
              valueListenable: Strings.lang,
              builder: (context, lang, _) => SegmentRow(
                label: Strings.t('settings_language'),
                options: const ['Deutsch', 'English'],
                selected: lang,
                onChanged: Strings.set,
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── Allgemein ──────────────────────────────────────────────────────
          SettingsSectionHeader(Strings.t('settings_general')),
          const SizedBox(height: 12),
          SettingsCard(children: [
            LabeledSlider(label: Strings.t('settings_pitch'), value: _pitch.toDouble(),
                min: 300, max: 900, divisions: 12, display: '$_pitch Hz',
                onChanged: (v) { setState(() => _pitch = (v / 50).round() * 50); _saveLive(); }),
            const SettingsDivider(),
            LabeledSlider(label: Strings.t('settings_tone_softness'), value: _toneSoftness.toDouble(),
                min: 0, max: 8, divisions: 8, display: '${_toneSoftness + 1} ms',
                onChanged: _applyToneSoftness),
            const SettingsDivider(),
            SegmentRow(
              label: Strings.t('settings_output_case'),
              options: [Strings.t('opt_lower'), Strings.t('opt_upper')],
              selected: _outputCase,
              onChanged: (v) { setState(() => _outputCase = v); _saveLive(); },
            ),
            const SettingsDivider(),
            ValueListenableBuilder<bool>(
              valueListenable: BreakReminder.enabled,
              builder: (context, on, _) => ToggleRow(
                label: Strings.t('settings_break_hint'),
                value: on,
                onChanged: BreakReminder.setEnabled,
              ),
            ),
            const SettingsDivider(),
            // Also in the goal settings; this is the way back once hidden.
            ToggleRow(
              label: Strings.t('goal_show'),
              value: PracticeClock.instance.log.enabled,
              onChanged: (v) async {
                final p = await SharedPreferences.getInstance();
                await PracticeClock.instance.log.setEnabled(p, v);
                Reminder.refresh();
                if (mounted) setState(() {});
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── Störungen ──────────────────────────────────────────────────────
          SettingsSectionHeader(Strings.t('interf_header')),
          const SizedBox(height: 12),
          const InterferenceSettingsCard(),

          const SizedBox(height: 24),

          // ── Keyer ──────────────────────────────────────────────────────────
          SettingsSectionHeader('Keyer'),
          const SizedBox(height: 12),
          SettingsCard(children: [
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
            if (_keyerMode == 1 || _keyerMode == 2) ...[
              const SettingsDivider(),
              LabeledSlider(label: Strings.t('settings_curtisb_dit'),
                  value: _curtisBDitTiming.toDouble(),
                  min: 0, max: 100, divisions: 20, display: '$_curtisBDitTiming%',
                  onChanged: (v) => _applyCurtisBTiming(dit: v.round())),
              const SettingsDivider(),
              LabeledSlider(label: Strings.t('settings_curtisb_dah'),
                  value: _curtisBDahTiming.toDouble(),
                  min: 0, max: 100, divisions: 20, display: '$_curtisBDahTiming%',
                  onChanged: (v) => _applyCurtisBTiming(dah: v.round())),
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
          ]),

          const SizedBox(height: 24),

          // ── Audioausgabe ─────────────────────────────────────────────────────
          SettingsSectionHeader(Strings.t('settings_audio_output'), key: _audioKey),
          const SizedBox(height: 4),
          Text(Strings.t('settings_audio_output_desc'),
              style: TextStyle(fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          SettingsCard(children: [
            SegmentRow(
              label: Strings.t('settings_audio_output_active').replaceFirst('{val}', _localizedActiveLabel()),
              options: _outputKindsAvailable.map(_outputKindLabel).toList(),
              selected: _outputKindsAvailable.indexOf(_outputKindPref).clamp(0, _outputKindsAvailable.length - 1),
              onChanged: (i) => _applyOutputKind(_outputKindsAvailable[i]),
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

          const SizedBox(height: 24),

          // ── Rufzeichen ───────────────────────────────────────────────────────
          SettingsSectionHeader(Strings.t('settings_call_signs')),
          const SizedBox(height: 12),
          SettingsCard(children: [
            SegmentRow(
              label: Strings.t('settings_call_length'),
              options: [Strings.t('opt_unlim_short'), '3', '4', '5', '6'],
              selected: _callLengthOpt,
              onChanged: (v) { setState(() => _callLengthOpt = v); _saveLive(); },
            ),
            const SettingsDivider(),
            SegmentRow(
              label: Strings.t('settings_call_region'),
              options: [Strings.t('opt_all_cap'), 'EU', 'NA', 'SA', 'AF', 'AS', 'OC', 'VK/ZL'],
              selected: _callRegionOpt,
              onChanged: (v) { setState(() => _callRegionOpt = v); _saveLive(); },
            ),
            const SettingsDivider(),
            ToggleRow(label: Strings.t('settings_common_prefixes_only'), value: _callCommonOnly,
                onChanged: (v) { setState(() => _callCommonOnly = v); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── vband Morse Key ───────────────────────────────────────────────────
          SettingsSectionHeader('vband Morse Key'),
          const SizedBox(height: 12),
          SettingsCard(children: [
            _InfoRow(label: 'Dit', value: _ditDesc),
            const SettingsDivider(),
            _InfoRow(label: 'Dah', value: _dahDesc),
          ]),
          const SizedBox(height: 12),
          if (_learnState == _LearnState.idle)
            _ActionButton(label: Strings.t('settings_learn_paddle_keys'),
                icon: Icons.settings_remote, color: c.info, onTap: _startLearn)
          else
            _LearnCard(state: _learnState, message: _learnMessage, onCancel: _cancelLearn),

          const SizedBox(height: 24),

          // ── Key-Events analysieren ─────────────────────────────────────────
          SettingsSectionHeader(Strings.t('settings_analyze_key_events')),
          const SizedBox(height: 8),
          Text(Strings.t('settings_analyze_key_events_desc'),
              style: TextStyle(fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          _ActionButton(
            label: _keyDiagActive ? Strings.t('settings_stop_analyzer') : Strings.t('settings_start_analyzer'),
            icon: _keyDiagActive ? Icons.stop_circle_outlined : Icons.search,
            color: _keyDiagActive ? c.danger : c.info,
            onTap: _toggleKeyDiag,
          ),
          if (_keyDiagLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: c.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.borderAlt)),
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shrinkWrap: true,
                itemCount: _keyDiagLog.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_keyDiagLog[i],
                      style: TextStyle(fontSize: 10,
                          color: c.logText)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ── Info ───────────────────────────────────────────────────────────
          SettingsSectionHeader('Info'),
          const SizedBox(height: 12),
          SettingsCard(children: [
            _InfoRow(label: Strings.t('settings_developer'),
                value: 'Christian Konecny, OE1CKO'),
            const SettingsDivider(),
            _InfoRow(label: Strings.t('settings_thanks'),
                value: Strings.t('settings_thanks_value')),
            const SettingsDivider(),
            _InfoRow(label: 'Version', value: _version),
            const SettingsDivider(),
            _InfoRow(label: 'Commit', value: _build),
            const SettingsDivider(),
            _InfoRow(label: Strings.t('settings_build_time'), value: _buildTime),
            const SettingsDivider(),
            InkWell(
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Next CW Trainer',
                applicationVersion: _version,
                applicationLegalese: appLegalese,
              ),
              child: _InfoRow(label: Strings.t('settings_licenses'),
                  value: 'GPL-3.0 ›'),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 13,
          color: c.textMuted)),
      const SizedBox(width: 16),
      Expanded(child: Text(value, textAlign: TextAlign.right,
          style: TextStyle(fontSize: 13, color: c.textPrimary))),
    ]),
  );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 14, color: color))),
      ]),
    ),
  );
}

class _LearnCard extends StatelessWidget {
  final _LearnState state;
  final String message;
  final VoidCallback onCancel;
  const _LearnCard({required this.state, required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = state == _LearnState.done
        ? c.accent : c.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(children: [
        state == _LearnState.done
            ? Icon(Icons.check_circle, color: color)
            : SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Text(message,
            style: TextStyle(fontSize: 14, color: color))),
        if (state != _LearnState.done)
          TextButton(onPressed: onCancel,
              child: Text(Strings.t('cancel'),
                  style: TextStyle(fontSize: 12,
                      color: c.textMuted))),
      ]),
    );
  }
}

