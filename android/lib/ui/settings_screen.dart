import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/cw_content.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../l10n/strings.dart';

enum _LearnState { idle, waitDit, waitDah, done }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _settingsChannel = MethodChannel('at.oe1wkl.morserino_mobile/settings');
  static const _settingsEvents  = EventChannel('at.oe1wkl.morserino_mobile/settings_events');
  static const _genChannel      = MethodChannel('at.oe1wkl.morserino_mobile/cw_generator');
  static const _toneChannel     = MethodChannel('at.oe1wkl.morserino_mobile/cw_tone');

  // ── General ────────────────────────────────────────────────────────────────
  int  _wpm       = 20;
  int  _kochLevel = 5;
  int  _pitch     = 600;
  // outputCase: 0=lower, 1=UPPER (matches M32 "Output Case"; applies to all
  // displayed generated/decoded text, not stored — content stays uppercase internally)
  int  _outputCase = 0;
  // "Tone Softness" (M32 posToneSoftness, default 4): sidetone attack/release
  // time, prefValue 0..8 maps to 1..9 ms (MorseOutput::setSidetoneEnvelope()).
  int  _toneSoftness = 4;

  // ── Koch Sequence ─────────────────────────────────────────────────────────
  // 0=M32, 1=LCWO, 2=CW Academy, 3=LICW, 4=Custom (matches M32 "Koch Sequence")
  int    _kochSeq          = 0;
  String _customKochChars  = '';
  // "LICW Carousel" entry point (posCarouselStart, 0-13) — only relevant when
  // Koch Sequence = LICW; rotates which slice of the LICW curriculum is active.
  int    _licwCarouselStart = 0;
  static const _kochSeqLabels = ['M32', 'LCWO', 'CW Academy', 'LICW', 'Custom'];
  List<String> get _activeKochChars =>
      kochSequenceChars(_kochSeq, _customKochChars, licwCarouselStart: _licwCarouselStart);

  // ── Practice Set ──────────────────────────────────────────────────────────
  String _practiceChars = '';
  int    _boostLevel    = 0;   // 0=Off, 1=Moderate, 2=Strong (matches M32 "Boost Practice")
  List<String> get _activePracticeChars => parsePracticeChars(_practiceChars);

  // ── Keyer ──────────────────────────────────────────────────────────────────
  int  _keyerMode   = 0;    // 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight
  bool _confirmTone = false;
  // "CurtisB DitT%"/"CurtisB DahT%" (M32 defaults 75/45): only meaningful in
  // Iambic B/Ultimatic — how far into the current element (as a % of its
  // length) the keyer starts looking ahead for the opposite paddle.
  int  _curtisBDitTiming = 75;
  int  _curtisBDahTiming = 45;
  // "AutoChar Spc" (M32 posACS, default 0=off): minimum pause enforced
  // between characters — 1/2/3 = 2/3/4 dits.
  int  _acs = 0;
  // "Tone Shift" (M32 posEchoToneShift, default 1): shifts the operator's own
  // echoed-answer sidetone in the Echo Trainer up/down a half-tone from the
  // target word's pitch, so the two are audibly distinguishable. Has no
  // effect on the standalone CW Keyer, matching the real device.
  int  _toneShift = 1;

  // ── Spacing ────────────────────────────────────────────────────────────────
  // Absolute gap length in dits, exactly like the real M32 (Interchar 3..45,
  // InterWord 6..105; default = normal Morse timing 3/7).
  int _interCharSpace = 3;
  int _interWordSpace = 7;

  // ── CW Generator ──────────────────────────────────────────────────────────
  // genDisplay: 0=Display off, 1=Char by char, 2=Word by word (matches M32 "CW Gen Displ")
  int  _genDisplay     = 1;
  bool _stopAfterItem = false;  // Morserino "Stop<>Next"
  bool _eachWordTwice  = false;
  int  _wordLengthMax  = 0;     // 0 = no filter
  int  _groupLength    = 5;
  // randomOption: which alphabet subset "Zufallszeichen" draws from when NOT
  // in Koch mode (matches M32 "Random Groups" / posRandomOption exactly).
  int  _randomOption   = 0;
  static const _randomOptionLabels = [
    'All Chars', 'Alpha', 'Numerals', 'Interpunct.', 'Pro Signs',
    'Alpha + Num', 'Num+Interp.', 'Interp+ProSn', 'Alph+Num+Int', 'Num+Int+ProS',
  ];
  int  _abbrevLengthMax = 0;    // 0=unlimited, 1..5 -> max length 2..6 (M32 "Length Abbrev")
  int  _maxWords        = 0;    // 0=unlimited, step 5 (M32 "Max # of Words")

  // ── Call Signs ────────────────────────────────────────────────────────────
  // callLengthOpt: 0=Unlimited,1="3",2="4",3="5",4="6" (M32 "Length Calls")
  int  _callLengthOpt = 0;
  // callRegionOpt: 0=All,1=EU,2=NA,3=SA,4=AF,5=AS,6=OC,7=VK/ZL (M32 "Calls Region")
  int  _callRegionOpt = 0;
  bool _callCommonOnly = true;  // M32 default: "Common only"

  // ── Echo Trainer ───────────────────────────────────────────────────────────
  int  _echoThinkTime  = 8;   // seconds
  // M32 "Echo Repeats": 0-6 = that many replays after a wrong/missed answer
  // before the word is revealed and the trainer moves on; 7 = "Forever"
  // (never gives up). Default 3, matching the real device's default.
  int  _echoRepeats    = 3;
  // echoDisplay: 1=Sound only, 2=Display only, 3=Sound & Disp (matches M32 "Echo Prompt")
  int  _echoDisplay    = 1;
  bool _adaptiveSpeed  = false;
  int  _echoSpeedMax   = 35;

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

  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPaddleDesc();
    _loadOutputDeviceKinds();
    _eventSub = _settingsEvents.receiveBroadcastStream().listen(_onSettingsEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _settingsChannel.invokeMethod('cancelLearnPaddle');
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _wpm            = p.getInt('wpm')            ?? 20;
      _kochLevel      = p.getInt('kochLevel')      ?? 5;
      _pitch          = p.getInt('pitch')          ?? 600;
      _outputCase     = (p.getInt('outputCase')    ?? 0).clamp(0, 1);
      _toneSoftness   = (p.getInt('toneSoftness')  ?? 4).clamp(0, 8);
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = p.getString('customKochChars') ?? '';
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _practiceChars   = p.getString('practiceChars') ?? '';
      _boostLevel      = (p.getInt('boostLevel') ?? 0).clamp(0, 2);
      _keyerMode      = p.getInt('keyerMode')      ?? 0;
      _confirmTone    = p.getBool('confirmTone')   ?? false;
      _curtisBDitTiming = (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100);
      _curtisBDahTiming = (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100);
      _acs              = (p.getInt('acs') ?? 0).clamp(0, 3);
      _toneShift        = (p.getInt('toneShift') ?? 1).clamp(0, 2);
      // clamp() guards against stale values from the old 1..8 multiplier scale
      _interCharSpace = (p.getInt('interCharSpace') ?? 3).clamp(3, 45);
      _interWordSpace = (p.getInt('interWordSpace') ?? 7).clamp(6, 105);
      // genDisplayMode/echoDisplayMode: new int-valued keys (old genDisplay/echoPrompt
      // keys were bool — renamed to avoid a SharedPreferences type-cast crash on upgrade)
      _genDisplay     = (p.getInt('genDisplayMode') ?? 1).clamp(0, 2);
      _stopAfterItem  = p.getBool('stopAfterItem') ?? false;
      _eachWordTwice  = p.getBool('eachWordTwice') ?? false;
      _wordLengthMax  = p.getInt('wordLengthMax')  ?? 0;
      _groupLength    = p.getInt('groupLength')    ?? 5;
      _randomOption   = (p.getInt('randomOption')  ?? 0).clamp(0, 9);
      _abbrevLengthMax = (p.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords        = p.getInt('maxWords')        ?? 0;
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      _echoThinkTime  = p.getInt('echoThinkTime')  ?? 8;
      _echoRepeats    = (p.getInt('echoRepeats')   ?? 3).clamp(0, 7);
      _echoDisplay    = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _adaptiveSpeed  = p.getBool('adaptiveSpeed') ?? false;
      _echoSpeedMax   = p.getInt('echoSpeedMax')   ?? 35;
      _kochLevel      = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _syncKochChars();
    _syncPracticeSettings();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm',            _wpm);
    await p.setInt('kochLevel',      _kochLevel);
    await p.setInt('pitch',          _pitch);
    await p.setInt('outputCase',     _outputCase);
    await p.setInt('toneSoftness',   _toneSoftness);
    await p.setInt('kochSeq',         _kochSeq);
    await p.setString('customKochChars', _customKochChars);
    await p.setInt('licwCarouselStart', _licwCarouselStart);
    await p.setString('practiceChars', _practiceChars);
    await p.setInt('boostLevel',     _boostLevel);
    await p.setInt('keyerMode',      _keyerMode);
    await p.setBool('confirmTone',   _confirmTone);
    await p.setInt('curtisBDitTiming', _curtisBDitTiming);
    await p.setInt('curtisBDahTiming', _curtisBDahTiming);
    await p.setInt('acs',            _acs);
    await p.setInt('toneShift',      _toneShift);
    await p.setInt('interCharSpace', _interCharSpace);
    await p.setInt('interWordSpace', _interWordSpace);
    await p.setInt('genDisplayMode', _genDisplay);
    await p.setBool('stopAfterItem', _stopAfterItem);
    await p.setBool('eachWordTwice', _eachWordTwice);
    await p.setInt('wordLengthMax',  _wordLengthMax);
    await p.setInt('groupLength',    _groupLength);
    await p.setInt('randomOption',   _randomOption);
    await p.setInt('abbrevLengthMax', _abbrevLengthMax);
    await p.setInt('maxWords',        _maxWords);
    await p.setInt('callLengthOpt',   _callLengthOpt);
    await p.setInt('callRegionOpt',   _callRegionOpt);
    await p.setBool('callCommonOnly', _callCommonOnly);
    await p.setInt('echoThinkTime',  _echoThinkTime);
    await p.setInt('echoRepeats',    _echoRepeats);
    await p.setInt('echoDisplayMode', _echoDisplay);
    await p.setBool('adaptiveSpeed', _adaptiveSpeed);
    await p.setInt('echoSpeedMax',   _echoSpeedMax);
  }

  void _saveLive() => _save();  // called on every interactive change

  // Keeps the shared native generator's Koch pool in sync so Generator/Koch/Echo
  // screens (which may reuse the instance without reloading it) see the right chars.
  Future<void> _syncKochChars() async {
    await _genChannel.invokeMethod('setKochChars', _activeKochChars);
  }

  Future<void> _syncPracticeSettings() async {
    await _genChannel.invokeMethod('setPracticeChars', _activePracticeChars);
    await _genChannel.invokeMethod('setBoostLevel', _boostLevel);
  }

  void _applyPracticeChars(String value) {
    setState(() => _practiceChars = value);
    _saveLive();
    _syncPracticeSettings();
  }

  void _applyBoostLevel(int level) {
    setState(() => _boostLevel = level);
    _saveLive();
    _syncPracticeSettings();
  }

  void _applyKochSeq(int seq) {
    setState(() {
      _kochSeq = seq;
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _saveLive();
    _syncKochChars();
  }

  void _applyLicwCarouselStart(int start) {
    setState(() {
      _licwCarouselStart = start;
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _saveLive();
    _syncKochChars();
  }

  void _applyCustomKochChars(String value) {
    setState(() {
      _customKochChars = value;
      if (_kochSeq == 4) _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _saveLive();
    if (_kochSeq == 4) _syncKochChars();
  }

  Future<void> _loadPaddleDesc() async {
    final result = await _settingsChannel.invokeMapMethod<String, String>('getPaddleChars');
    if (result != null && mounted) setState(() {
      _ditDesc = result['dit'] ?? '?';
      _dahDesc = result['dah'] ?? '?';
    });
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
      builder: (context, _, __) => Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(Strings.t('settings_title'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () { _save(); Navigator.pop(context); },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── Darstellung ───────────────────────────────────────────────────
          _SectionHeader(Strings.t('settings_appearance')),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => _SegmentRow(
                label: 'Theme',
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
            const _Div(),
            ValueListenableBuilder<int>(
              valueListenable: Strings.lang,
              builder: (context, lang, _) => _SegmentRow(
                label: Strings.t('settings_language'),
                options: const ['Deutsch', 'English'],
                selected: lang,
                onChanged: Strings.set,
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── Allgemein ──────────────────────────────────────────────────────
          _SectionHeader(Strings.t('settings_general')),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _LabeledSlider(label: Strings.t('settings_default_wpm'), value: _wpm.toDouble(),
                min: 5, max: 60, divisions: 55, display: '$_wpm',
                onChanged: (v) { setState(() => _wpm = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_default_koch_level'), value: _kochLevel.toDouble(),
                min: 2, max: _activeKochChars.length.toDouble(),
                divisions: _activeKochChars.length - 2,
                display: '$_kochLevel',
                onChanged: (v) { setState(() => _kochLevel = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_pitch'), value: _pitch.toDouble(),
                min: 300, max: 900, divisions: 12, display: '$_pitch Hz',
                onChanged: (v) { setState(() => _pitch = (v / 50).round() * 50); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_tone_softness'), value: _toneSoftness.toDouble(),
                min: 0, max: 8, divisions: 8, display: '${_toneSoftness + 1} ms',
                onChanged: _applyToneSoftness),
            const _Div(),
            _SegmentRow(
              label: 'Output Case',
              options: const ['lower', 'UPPER'],
              selected: _outputCase,
              onChanged: (v) { setState(() => _outputCase = v); _saveLive(); },
            ),
          ]),
          const SizedBox(height: 8),
          _KochLevelPreview(level: _kochLevel, sequence: _activeKochChars),

          const SizedBox(height: 24),

          // ── Koch Sequence ────────────────────────────────────────────────────
          _SectionHeader('Koch Sequence'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: Strings.t('settings_sequence'),
              options: _kochSeqLabels,
              selected: _kochSeq,
              onChanged: _applyKochSeq,
            ),
            if (_kochSeq == 3) ...[
              const _Div(),
              _LabeledSlider(
                label: Strings.t('settings_licw_entry_point'),
                value: _licwCarouselStart.toDouble(),
                min: 0, max: 13, divisions: 13,
                display: '$_licwCarouselStart',
                onChanged: (v) => _applyLicwCarouselStart(v.round()),
              ),
            ],
            if (_kochSeq == 4) ...[
              const _Div(),
              _CharSetField(
                label: Strings.t('settings_custom_chars_label'),
                initialValue: _customKochChars,
                onChanged: _applyCustomKochChars,
                countLabel: Strings.t('settings_unique_chars_detected').replaceFirst('{n}', '${_activeKochChars.length}'),
              ),
            ],
          ]),

          const SizedBox(height: 24),

          // ── Practice Set ─────────────────────────────────────────────────────
          _SectionHeader('Practice Set'),
          const SizedBox(height: 4),
          Text(Strings.t('settings_practice_set_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _CharSetField(
              label: Strings.t('settings_characters'),
              initialValue: _practiceChars,
              onChanged: _applyPracticeChars,
              countLabel: Strings.t('settings_unique_chars_detected').replaceFirst('{n}', '${_activePracticeChars.length}'),
              hint: 'e.g. QXZJ...',
            ),
            const _Div(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SegmentRow(
                  label: 'Boost Practice',
                  options: const ['Off', 'Moderate', 'Strong'],
                  selected: _boostLevel,
                  onChanged: _applyBoostLevel,
                ),
                Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(Strings.t('settings_boost_practice_desc'),
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                          color: c.textFaint)),
                ),
              ]),
            ),
          ]),

          const SizedBox(height: 24),

          // ── Keyer ──────────────────────────────────────────────────────────
          _SectionHeader('Keyer'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: Strings.t('settings_mode'),
              options: const ['Iambic A', 'Iambic B', 'Ultimatic', 'Non-Squeeze', 'Straight'],
              selected: _keyerMode,
              onChanged: _applyKeyerMode,
            ),
            if (_keyerMode == 1 || _keyerMode == 2) ...[
              const _Div(),
              _LabeledSlider(label: Strings.t('settings_curtisb_dit'),
                  value: _curtisBDitTiming.toDouble(),
                  min: 0, max: 100, divisions: 20, display: '$_curtisBDitTiming%',
                  onChanged: (v) => _applyCurtisBTiming(dit: v.round())),
              const _Div(),
              _LabeledSlider(label: Strings.t('settings_curtisb_dah'),
                  value: _curtisBDahTiming.toDouble(),
                  min: 0, max: 100, divisions: 20, display: '$_curtisBDahTiming%',
                  onChanged: (v) => _applyCurtisBTiming(dah: v.round())),
            ],
            const _Div(),
            _SegmentRow(
              label: Strings.t('settings_acs'),
              options: [Strings.t('opt_off'), '2 dits', '3 dits', '4 dits'],
              selected: _acs,
              onChanged: _applyAcs,
            ),
            const _Div(),
            _ToggleRow(label: Strings.t('settings_confirm_tone'), value: _confirmTone,
                onChanged: (v) { setState(() => _confirmTone = v); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Abstände ───────────────────────────────────────────────────────
          _SectionHeader(Strings.t('settings_spacing')),
          const SizedBox(height: 4),
          Text(Strings.t('settings_spacing_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _LabeledSlider(label: 'Interchar Spc', value: _interCharSpace.toDouble(),
                min: 3, max: 45, divisions: 42, display: '$_interCharSpace dits',
                onChanged: (v) { setState(() => _interCharSpace = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'InterWord Spc', value: _interWordSpace.toDouble(),
                min: 6, max: 105, divisions: 99, display: '$_interWordSpace dits',
                onChanged: (v) { setState(() => _interWordSpace = v.round()); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Audioausgabe ─────────────────────────────────────────────────────
          _SectionHeader(Strings.t('settings_audio_output')),
          const SizedBox(height: 4),
          Text(Strings.t('settings_audio_output_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: Strings.t('settings_audio_output_active').replaceFirst('{val}', _localizedActiveLabel()),
              options: _outputKindsAvailable.map(_outputKindLabel).toList(),
              selected: _outputKindsAvailable.indexOf(_outputKindPref).clamp(0, _outputKindsAvailable.length - 1),
              onChanged: (i) => _applyOutputKind(_outputKindsAvailable[i]),
            ),
          ]),

          const SizedBox(height: 24),

          // ── CW Generator ───────────────────────────────────────────────────
          _SectionHeader('CW Generator'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: 'CW Gen Displ',
              options: [Strings.t('opt_off'), Strings.t('opt_by_char'), Strings.t('opt_by_word')],
              selected: _genDisplay,
              onChanged: (v) { setState(() => _genDisplay = v); _saveLive(); },
            ),
            const _Div(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ToggleRow(label: 'Stop<Next>Rep', value: _stopAfterItem,
                    onChanged: (v) { setState(() => _stopAfterItem = v); _saveLive(); }),
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(Strings.t('settings_stop_next_rep_desc'),
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                          color: c.textFaint)),
                ),
              ]),
            ),
            const _Div(),
            _ToggleRow(label: Strings.t('settings_each_word_twice'), value: _eachWordTwice,
                onChanged: (v) { setState(() => _eachWordTwice = v); _saveLive(); }),
            const _Div(),
            _SegmentRow(
              label: 'Random Groups',
              options: _randomOptionLabels,
              selected: _randomOption,
              onChanged: (v) { setState(() => _randomOption = v); _saveLive(); },
            ),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_group_length'), value: _groupLength.toDouble(),
                min: 2, max: 8, divisions: 6, display: '$_groupLength',
                onChanged: (v) { setState(() => _groupLength = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_max_word_length'), value: _wordLengthMax.toDouble(),
                min: 0, max: 8, divisions: 8,
                display: _wordLengthMax == 0 ? Strings.t('opt_all') : '$_wordLengthMax',
                onChanged: (v) { setState(() => _wordLengthMax = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_max_abbrev_length'), value: _abbrevLengthMax.toDouble(),
                min: 0, max: 5, divisions: 5,
                display: _abbrevLengthMax == 0 ? Strings.t('opt_all') : '${_abbrevLengthMax + 1}',
                onChanged: (v) { setState(() => _abbrevLengthMax = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Max # of Words', value: _maxWords.toDouble(),
                min: 0, max: 250, divisions: 50,
                display: _maxWords == 0 ? Strings.t('opt_unlimited') : '$_maxWords',
                onChanged: (v) { setState(() => _maxWords = (v / 5).round() * 5); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Call Signs ───────────────────────────────────────────────────────
          _SectionHeader('Call Signs'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: 'Length Calls',
              options: [Strings.t('opt_unlim_short'), '3', '4', '5', '6'],
              selected: _callLengthOpt,
              onChanged: (v) { setState(() => _callLengthOpt = v); _saveLive(); },
            ),
            const _Div(),
            _SegmentRow(
              label: 'Calls Region',
              options: const ['All', 'EU', 'NA', 'SA', 'AF', 'AS', 'OC', 'VK/ZL'],
              selected: _callRegionOpt,
              onChanged: (v) { setState(() => _callRegionOpt = v); _saveLive(); },
            ),
            const _Div(),
            _ToggleRow(label: Strings.t('settings_common_prefixes_only'), value: _callCommonOnly,
                onChanged: (v) { setState(() => _callCommonOnly = v); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Echo Trainer ───────────────────────────────────────────────────
          _SectionHeader('Echo Trainer'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _LabeledSlider(label: Strings.t('settings_think_time'), value: _echoThinkTime.toDouble(),
                min: 1, max: 20, divisions: 19, display: '${_echoThinkTime}s',
                onChanged: (v) { setState(() => _echoThinkTime = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: Strings.t('settings_repeats'), value: _echoRepeats.toDouble(),
                min: 0, max: 7, divisions: 7,
                display: _echoRepeats == 7 ? 'Forever' : '$_echoRepeats ×',
                onChanged: (v) { setState(() => _echoRepeats = v.round()); _saveLive(); }),
            const _Div(),
            _SegmentRow(
              label: 'Echo Prompt',
              options: [Strings.t('opt_sound'), Strings.t('opt_display'), Strings.t('opt_both')],
              selected: _echoDisplay - 1,
              onChanged: (v) { setState(() => _echoDisplay = v + 1); _saveLive(); },
            ),
            const _Div(),
            _ToggleRow(label: 'Adaptive Speed', value: _adaptiveSpeed,
                onChanged: (v) { setState(() => _adaptiveSpeed = v); _saveLive(); }),
            if (_adaptiveSpeed) ...[
              const _Div(),
              _LabeledSlider(label: Strings.t('settings_max_speed'), value: _echoSpeedMax.toDouble(),
                  min: 10, max: 50, divisions: 40, display: '$_echoSpeedMax WPM',
                  onChanged: (v) { setState(() => _echoSpeedMax = v.round()); _saveLive(); }),
            ],
            const _Div(),
            _SegmentRow(
              label: Strings.t('settings_tone_shift'),
              options: [Strings.t('opt_tone_shift_off'), Strings.t('opt_tone_shift_up'), Strings.t('opt_tone_shift_down')],
              selected: _toneShift,
              onChanged: (v) { setState(() => _toneShift = v); _saveLive(); },
            ),
          ]),

          const SizedBox(height: 24),

          // ── vband Paddle ───────────────────────────────────────────────────
          _SectionHeader('vband Paddle'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _InfoRow(label: 'Dit', value: _ditDesc),
            const _Div(),
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
          _SectionHeader(Strings.t('settings_analyze_key_events')),
          const SizedBox(height: 8),
          Text(Strings.t('settings_analyze_key_events_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
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
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 10,
                          color: c.logText)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Divider(color: c.border, height: 1);
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Text(text,
      style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
          color: c.textMuted, letterSpacing: 1.2));
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
    decoration: BoxDecoration(color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border)),
    child: Column(children: children),
  );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label, display;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _LabeledSlider({required this.label, required this.value, required this.min,
      required this.max, required this.divisions, required this.display,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
            color: c.textPrimary)),
        const Spacer(),
        Text(display, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
            color: c.accent)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: c.accent,
          inactiveTrackColor: c.border,
          thumbColor: c.accent,
          overlayColor: c.accent.withOpacity(0.1),
          trackHeight: 3,
        ),
        child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ),
    ]),
  );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textPrimary)),
      const Spacer(),
      Switch(
        value: value,
        onChanged: onChanged,
        activeColor: c.accent,
        inactiveTrackColor: c.border,
      ),
    ]),
  );
  }
}

class _KochLevelPreview extends StatelessWidget {
  final int level;
  final List<String> sequence;
  const _KochLevelPreview({required this.level, required this.sequence});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = kochActiveChars(level, sequence);
    final newest = active.isNotEmpty ? active.last : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderAlt),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Strings.t('settings_level_includes_chars')
                .replaceFirst('{level}', '$level').replaceFirst('{n}', '${active.length}'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                color: c.textMuted)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: active.map((ch) {
          final isNewest = ch == newest;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isNewest ? c.warning.withOpacity(0.18)
                               : c.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: isNewest
                  ? c.warning : c.accent.withOpacity(0.4)),
            ),
            child: Text(ch, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
                fontWeight: isNewest ? FontWeight.bold : FontWeight.normal,
                color: isNewest ? c.warning : c.accent)),
          );
        }).toList()),
      ]),
    );
  }
}

class _CharSetField extends StatelessWidget {
  final String label, initialValue, countLabel;
  final String? hint;
  final ValueChanged<String> onChanged;
  const _CharSetField({required this.label, required this.initialValue,
      required this.onChanged, required this.countLabel, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textPrimary)),
      const SizedBox(height: 8),
      TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
            color: c.accent),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.background,
          hintText: hint ?? Strings.t('settings_char_hint_default'),
          hintStyle: TextStyle(fontFamily: 'CwMono', color: c.textDisabled),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.accent)),
        ),
      ),
      const SizedBox(height: 6),
      Text(countLabel, style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
          color: c.textFaint)),
    ]),
  );
  }
}

class _SegmentRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const _SegmentRow({required this.label, required this.options,
      required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textPrimary)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        // Wrap onto multiple rows once options no longer fit comfortably in one.
        final perRow = options.length <= 3 ? options.length : 3;
        final gap = 6.0;
        final itemWidth = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap, runSpacing: gap,
          children: List.generate(options.length, (i) {
            final active = i == selected;
            return SizedBox(width: itemWidth, child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? c.accent.withOpacity(0.15) : c.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: active ? c.accent : c.border),
                ),
                child: Text(options[i], textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                        color: active ? c.accent : c.textMuted)),
              ),
            ));
          }),
        );
      }),
    ]),
  );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textMuted)),
      const SizedBox(width: 16),
      Expanded(child: Text(value, textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary))),
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
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: color)),
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
      decoration: BoxDecoration(color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Row(children: [
        state == _LearnState.done
            ? Icon(Icons.check_circle, color: color)
            : SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Text(message,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: color))),
        if (state != _LearnState.done)
          TextButton(onPressed: onCancel,
              child: Text(Strings.t('cancel'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                      color: c.textMuted))),
      ]),
    );
  }
}

