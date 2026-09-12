import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/cw_content.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

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

  // ── General ────────────────────────────────────────────────────────────────
  int  _wpm       = 20;
  int  _kochLevel = 5;
  int  _pitch     = 600;
  // outputCase: 0=lower, 1=UPPER (matches M32 "Output Case"; applies to all
  // displayed generated/decoded text, not stored — content stays uppercase internally)
  int  _outputCase = 0;

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
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = p.getString('customKochChars') ?? '';
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _practiceChars   = p.getString('practiceChars') ?? '';
      _boostLevel      = (p.getInt('boostLevel') ?? 0).clamp(0, 2);
      _keyerMode      = p.getInt('keyerMode')      ?? 0;
      _confirmTone    = p.getBool('confirmTone')   ?? false;
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
    await p.setInt('kochSeq',         _kochSeq);
    await p.setString('customKochChars', _customKochChars);
    await p.setInt('licwCarouselStart', _licwCarouselStart);
    await p.setString('practiceChars', _practiceChars);
    await p.setInt('boostLevel',     _boostLevel);
    await p.setInt('keyerMode',      _keyerMode);
    await p.setBool('confirmTone',   _confirmTone);
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
          if (val == '1') { _learnState = _LearnState.waitDit; _learnMessage = 'Dit-Taste drücken …'; }
          else            { _learnState = _LearnState.waitDah; _learnMessage = 'Dah-Taste drücken …'; }
        case 'done':
          _learnState = _LearnState.done; _learnMessage = 'Gespeichert: $val';
          _loadPaddleDesc();
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _learnState = _LearnState.idle);
          });
        case 'keyDiag':
          _keyDiagLog.insert(0, val);
          if (_keyDiagLog.length > 20) _keyDiagLog.removeLast();
      }
    });
  }

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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text('Einstellungen',
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
          _SectionHeader('Darstellung'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => _SegmentRow(
                label: 'Theme',
                options: const ['System', 'Hell', 'Dunkel'],
                selected: switch (mode) {
                  ThemeMode.light => 1,
                  ThemeMode.dark  => 2,
                  _               => 0,
                },
                onChanged: (v) => ThemeController.set(
                    [ThemeMode.system, ThemeMode.light, ThemeMode.dark][v]),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── Allgemein ──────────────────────────────────────────────────────
          _SectionHeader('Allgemein'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _LabeledSlider(label: 'Standard-WPM',        value: _wpm.toDouble(),
                min: 5, max: 60, divisions: 55, display: '$_wpm',
                onChanged: (v) { setState(() => _wpm = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Standard Koch-Level', value: _kochLevel.toDouble(),
                min: 2, max: _activeKochChars.length.toDouble(),
                divisions: _activeKochChars.length - 2,
                display: '$_kochLevel',
                onChanged: (v) { setState(() => _kochLevel = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Tonhöhe (Hz)',        value: _pitch.toDouble(),
                min: 300, max: 900, divisions: 12, display: '$_pitch Hz',
                onChanged: (v) { setState(() => _pitch = (v / 50).round() * 50); _saveLive(); }),
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
              label: 'Reihenfolge',
              options: _kochSeqLabels,
              selected: _kochSeq,
              onChanged: _applyKochSeq,
            ),
            if (_kochSeq == 3) ...[
              const _Div(),
              _LabeledSlider(
                label: 'LICW Einstiegspunkt',
                value: _licwCarouselStart.toDouble(),
                min: 0, max: 13, divisions: 13,
                display: '$_licwCarouselStart',
                onChanged: (v) => _applyLicwCarouselStart(v.round()),
              ),
            ],
            if (_kochSeq == 4) ...[
              const _Div(),
              _CharSetField(
                label: 'Eigene Zeichen (Reihenfolge = Lernreihenfolge)',
                initialValue: _customKochChars,
                onChanged: _applyCustomKochChars,
                countLabel: '${_activeKochChars.length} eindeutige Zeichen erkannt',
              ),
            ],
          ]),

          const SizedBox(height: 24),

          // ── Practice Set ─────────────────────────────────────────────────────
          _SectionHeader('Practice Set'),
          const SizedBox(height: 4),
          Text('Eigene Zeichenauswahl für CW-Gen-Modus "Practice Set" und Boost',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _CharSetField(
              label: 'Zeichen',
              initialValue: _practiceChars,
              onChanged: _applyPracticeChars,
              countLabel: '${_activePracticeChars.length} eindeutige Zeichen erkannt',
              hint: 'z.B. QXZJ...',
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
                  child: Text('Practice-Set-Zeichen in Zufallszeichen-Übungen häufiger ziehen',
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
              label: 'Modus',
              options: const ['Iambic A', 'Iambic B', 'Ultimatic', 'Non-Squeeze', 'Straight'],
              selected: _keyerMode,
              onChanged: _applyKeyerMode,
            ),
            const _Div(),
            _ToggleRow(label: 'Bestätigungston', value: _confirmTone,
                onChanged: (v) { setState(() => _confirmTone = v); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Abstände ───────────────────────────────────────────────────────
          _SectionHeader('Abstände'),
          const SizedBox(height: 4),
          Text('Abstand in Dit-Längen, wie am Morserino (normal = 3 / 7)',
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

          // ── CW Generator ───────────────────────────────────────────────────
          _SectionHeader('CW Generator'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: 'CW Gen Displ',
              options: const ['Aus', 'Zeichenweise', 'Wortweise'],
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
                  child: Text('Pausiert nach jedem Wort: Dit = wiederholen, Dah = nächstes Wort',
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                          color: c.textFaint)),
                ),
              ]),
            ),
            const _Div(),
            _ToggleRow(label: 'Jedes Wort 2×', value: _eachWordTwice,
                onChanged: (v) { setState(() => _eachWordTwice = v); _saveLive(); }),
            const _Div(),
            _SegmentRow(
              label: 'Random Groups',
              options: _randomOptionLabels,
              selected: _randomOption,
              onChanged: (v) { setState(() => _randomOption = v); _saveLive(); },
            ),
            const _Div(),
            _LabeledSlider(label: 'Gruppen-Länge', value: _groupLength.toDouble(),
                min: 2, max: 8, divisions: 6, display: '$_groupLength',
                onChanged: (v) { setState(() => _groupLength = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Max. Wortlänge', value: _wordLengthMax.toDouble(),
                min: 0, max: 8, divisions: 8,
                display: _wordLengthMax == 0 ? 'alle' : '$_wordLengthMax',
                onChanged: (v) { setState(() => _wordLengthMax = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Max. Abkürzungslänge', value: _abbrevLengthMax.toDouble(),
                min: 0, max: 5, divisions: 5,
                display: _abbrevLengthMax == 0 ? 'alle' : '${_abbrevLengthMax + 1}',
                onChanged: (v) { setState(() => _abbrevLengthMax = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Max # of Words', value: _maxWords.toDouble(),
                min: 0, max: 250, divisions: 50,
                display: _maxWords == 0 ? 'unbegrenzt' : '$_maxWords',
                onChanged: (v) { setState(() => _maxWords = (v / 5).round() * 5); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Call Signs ───────────────────────────────────────────────────────
          _SectionHeader('Call Signs'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _SegmentRow(
              label: 'Length Calls',
              options: const ['Unbegr.', '3', '4', '5', '6'],
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
            _ToggleRow(label: 'Nur gängige Präfixe', value: _callCommonOnly,
                onChanged: (v) { setState(() => _callCommonOnly = v); _saveLive(); }),
          ]),

          const SizedBox(height: 24),

          // ── Echo Trainer ───────────────────────────────────────────────────
          _SectionHeader('Echo Trainer'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _LabeledSlider(label: 'Denkzeit', value: _echoThinkTime.toDouble(),
                min: 1, max: 20, divisions: 19, display: '${_echoThinkTime}s',
                onChanged: (v) { setState(() => _echoThinkTime = v.round()); _saveLive(); }),
            const _Div(),
            _LabeledSlider(label: 'Wiederholungen', value: _echoRepeats.toDouble(),
                min: 0, max: 7, divisions: 7,
                display: _echoRepeats == 7 ? 'Forever' : '$_echoRepeats ×',
                onChanged: (v) { setState(() => _echoRepeats = v.round()); _saveLive(); }),
            const _Div(),
            _SegmentRow(
              label: 'Echo Prompt',
              options: const ['Sound', 'Anzeige', 'Beides'],
              selected: _echoDisplay - 1,
              onChanged: (v) { setState(() => _echoDisplay = v + 1); _saveLive(); },
            ),
            const _Div(),
            _ToggleRow(label: 'Adaptive Speed', value: _adaptiveSpeed,
                onChanged: (v) { setState(() => _adaptiveSpeed = v); _saveLive(); }),
            if (_adaptiveSpeed) ...[
              const _Div(),
              _LabeledSlider(label: 'Max. Speed', value: _echoSpeedMax.toDouble(),
                  min: 10, max: 50, divisions: 40, display: '$_echoSpeedMax WPM',
                  onChanged: (v) { setState(() => _echoSpeedMax = v.round()); _saveLive(); }),
            ],
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
            _ActionButton(label: 'Paddle-Tasten anlernen',
                icon: Icons.settings_remote, color: c.info, onTap: _startLearn)
          else
            _LearnCard(state: _learnState, message: _learnMessage, onCancel: _cancelLearn),

          const SizedBox(height: 24),

          // ── Voreinstellungen ───────────────────────────────────────────────
          _SectionHeader('Voreinstellungen'),
          const SizedBox(height: 12),
          _SettingsCard(children: [
            _PresetRow(label: 'Original vband Adapter', subtitle: "Dit='[', Dah=']'",
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Originalen vband-Adapter einstecken und "Paddle-Tasten anlernen" verwenden.',
                      style: TextStyle(fontFamily: 'CwMono')),
                  backgroundColor: c.surface))),
            const _Div(),
            _PresetRow(label: 'Selbstbau (Arduino)', subtitle: "Dit='ü', Dah='+'",
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Arduino-Adapter einstecken und "Paddle-Tasten anlernen" verwenden.',
                      style: TextStyle(fontFamily: 'CwMono')),
                  backgroundColor: c.surface))),
          ]),

          const SizedBox(height: 24),

          // ── Key-Events analysieren ─────────────────────────────────────────
          _SectionHeader('Key-Events analysieren'),
          const SizedBox(height: 8),
          Text('Adapter einstecken, Analyser starten, dann Tasten drücken.',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
          const SizedBox(height: 12),
          _ActionButton(
            label: _keyDiagActive ? 'Analyser stoppen' : 'Analyser starten',
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
        Text('Level $level umfasst ${active.length} Zeichen:',
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
  final String hint;
  final ValueChanged<String> onChanged;
  const _CharSetField({required this.label, required this.initialValue,
      required this.onChanged, required this.countLabel, this.hint = 'z.B. KMRSUAPTLO...'});

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
          hintText: hint,
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
              child: Text('Abbrechen',
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                      color: c.textMuted))),
      ]),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final String label, subtitle;
  final VoidCallback onTap;
  const _PresetRow({required this.label, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
              color: c.textPrimary)),
          Text(subtitle, style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
              color: c.textMuted)),
        ])),
        Icon(Icons.info_outline, color: c.textDisabled, size: 18),
      ]),
    ),
  );
  }
}
