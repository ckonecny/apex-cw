import 'dart:async';
import 'widgets/keyer_status_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/paddle_widgets.dart';
import 'widgets/pinch_zoom_text.dart';
import '../content/training_profile.dart';
import '../keyer/decoder_chars.dart';
import '../keyer/fist_analyzer.dart';
import '../util/key_adapter_state.dart';
import 'widgets/fist_panel.dart';
import 'widgets/key_adapter_hint.dart';
import 'settings_screen.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import 'widgets/training_settings_sheet.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/slider_row.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';

class KeyerScreen extends StatefulWidget {
  const KeyerScreen({super.key});

  @override
  State<KeyerScreen> createState() => _KeyerScreenState();
}

class _KeyerScreenState extends State<KeyerScreen> {
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _straightWpmStream = EventChannel('at.oe1cko.nextcwtrainer/cw_straight_wpm');
  static const _edgeStream = EventChannel('at.oe1cko.nextcwtrainer/cw_straight_edges');
  StreamSubscription? _wpmSub;
  StreamSubscription? _edgeSub;
  // Straight-key timing (#164): only fed by a physical key on an adapter.
  final _fist = FistAnalyzer();
  final _fistHints = FistHints();
  FistReport _fistReport = const FistReport(
      ditMs: 0, wpm: 0, index: null, stats: {}, elements: 0);
  int _measuredWpm = 15;   // straight key: display only, never saved

  // Decoded text (mirrors the real device's CW Keyer, which decodes keyed
  // input via keyerTable/displayDecodedMorse() rather than showing raw
  // dit/dah symbols — see doPaddleIambic()'s IDLE_STATE in m32_v6.ino).
  late final MorseDecoder _decoder;
  String _decodedText = '';
  static const _maxText = 4000;
  int    _outputCase  = 0;   // 0=lower, 1=UPPER — display only
  bool   _ready    = false;
  int    _wpm      = 20;
  bool   _fistNoAdapterSeen = true;
  bool   _fistHintSeen = true;  // closed once with the X, never shown again
  bool   _fistOn   = false;   // Settings → Keyer: timing analysis (straight key only)
  int    _keyerMode = 0;   // 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight

  bool _touchDit = false;
  bool _touchDah = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('keyer');
    _decoder = MorseDecoder(onChar: (ch) {
      if (mounted) {
        setState(() {
        // Cap only to bound memory; the display scrolls, so this must be far
        // more than fits on screen (a small cap here made the text shift
        // after ~4 lines even with free space left).
        final t = _decodedText + ch;
        _decodedText = t.length > _maxText ? t.substring(t.length - _maxText) : t;
      });
      }
    });
    _symbolStream.receiveBroadcastStream().listen((sym) {
      PracticeClock.instance.touch();
      _decoder.add(sym as String);
    });
    _wpmSub = _straightWpmStream.receiveBroadcastStream().listen((w) {
      if (mounted) setState(() => _measuredWpm = (w as int).clamp(5, 60));
    });
    _edgeSub = _edgeStream.receiveBroadcastStream().listen((e) {
      if (!_fistActive || !KeyAdapterState.detected.value) {
        _resetFist();
        return;
      }
      final l = e as List;
      _fist.add(l[0] == 1, l[1] as int);
      if (l[0] == 0 && mounted) {
        setState(() {
          _fistReport = _fist.report();
          _fistHints.update(_fistReport);
        });
      }
    }, onError: (_) {});
    KeyAdapterState.detected.addListener(_onAdapterChange);
    _loadPrefsAndInit();
  }

  void _onAdapterChange() {
    if (!KeyAdapterState.detected.value) _resetFist();
  }

  // A tip line with a lightbulb; the X closes it for good (see _closeTip).
  Widget _tip(String key, VoidCallback onTap, VoidCallback onClose) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Row(children: [
              Icon(Icons.lightbulb_outline, size: 16, color: c.info),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(Strings.t(key),
                      style: TextStyle(fontSize: 13, color: c.textMuted))),
            ]),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 18, color: c.textFaint),
          visualDensity: VisualDensity.compact,
          onPressed: onClose,
        ),
      ]),
    );
  }

  Future<void> _closeTip(String pref, VoidCallback mark) async {
    setState(mark);
    (await SharedPreferences.getInstance()).setBool(pref, true);
  }

  Future<void> _openFistSettings() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const SettingsScreen(scrollToKeyer: true)));
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _fistOn = p.getBool('fistAnalyzer') ?? false);
    if (!_fistActive) _resetFist();
  }

  // Nothing from an earlier stretch (analysis off, adapter out) may mix with
  // new keying.
  void _resetFist() {
    if (_fist.presses.isEmpty && _fistReport.elements == 0) return;
    _fist.clear();
    _fistHints.clear();
    if (mounted) setState(() => _fistReport = _fist.report());
  }

  bool get _fistActive => _keyerMode == 4 && _fistOn;

  Future<void> _loadPrefsAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
      _wpm        = prefs.getInt('wpm')        ?? 20;
      _keyerMode  = prefs.getInt('keyerMode')  ?? 0;
      _fistOn     = prefs.getBool('fistAnalyzer') ?? false;
      _fistHintSeen = prefs.getBool('fistHintSeen') ?? false;
      _fistNoAdapterSeen = prefs.getBool('fistNoAdapterHintSeen') ?? false;
      _outputCase = (prefs.getInt('outputCase') ?? 0).clamp(0, 1);
      _decoder.chars = DecoderChars.values[(prefs.getInt(decoderCharsKey) ?? 0).clamp(0, DecoderChars.values.length - 1)];
    });
    }
    final pitch = prefs.getInt('pitch') ?? 600;
    final toneSoftness = (prefs.getInt('toneSoftness') ?? 4).clamp(0, 8);
    final curtisBDit = (prefs.getInt('curtisBDitTiming') ?? 75).clamp(0, 100);
    final curtisBDah = (prefs.getInt('curtisBDahTiming') ?? 45).clamp(0, 100);
    final acs = (prefs.getInt('acs') ?? 0).clamp(0, 3);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setVolume', 0.7);
    await _toneChannel.invokeMethod('setEnvelopeMs', (toneSoftness + 1).toDouble());
    await _keyerChannel.invokeMethod('setWpm',  _wpm);
    await _keyerChannel.invokeMethod('setMode', _keyerMode);
    await _keyerChannel.invokeMethod('setCurtisBTiming', {'dit': curtisBDit, 'dah': curtisBDah});
    await _keyerChannel.invokeMethod('setAcs', acs);
    await _keyerChannel.invokeMethod('setInterWordSpace', (prefs.getInt('profile.keyer.interWordSpace') ?? TrainingProfile.defaultInterWord(TrainingProfile.keyer)).clamp(6, 105));
    await _keyerChannel.invokeMethod('start');
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _saveWpm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wpm', _wpm);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    _wpmSub?.cancel();
    _edgeSub?.cancel();
    KeyAdapterState.detected.removeListener(_onAdapterChange);
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  void _setTouchInputs({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  void _ditDown()  => _setTouchInputs(dit: true);
  void _ditUp()    => _setTouchInputs(dit: false);
  void _dahDown()  => _setTouchInputs(dah: true);
  void _dahUp()    => _setTouchInputs(dah: false);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, 'CW Keyer'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const KeyerStatusButton(sound: false),
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            tooltip: Strings.t('settings_title'),
            onPressed: () async {
              await showTrainingSettingsSheet(context,
                  profile: TrainingProfile.keyer,
                  sections: const [TrainingSection.wordSpacing, TrainingSection.decoderChars]);
              _decoder.chars = await loadDecoderChars();
              final p = await SharedPreferences.getInstance();
              await _keyerChannel.invokeMethod('setInterWordSpace',
                  (p.getInt('profile.keyer.interWordSpace') ?? 7).clamp(6, 105));
            },
          ),
        ],
      ),
      body: _ready ? _buildBody() : Center(
        child: CircularProgressIndicator(color: c.accent),
      ),
    );
  }

  Widget _buildBody() {
    final c = AppColors.of(context);
    return Column(
      children: [
        Expanded(
          child: PinchZoomFontSize(
            prefsKey: 'keyerFontSize',
            initialSize: 28,
            builder: (context, fontSize) => Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              // reverse: anchors the text at the bottom and keeps the newest
              // characters in view; older lines can be scrolled back to.
              child: SingleChildScrollView(
                reverse: true,
                child: SizedBox(width: double.infinity, child: Text(
                  _outputCase == 1 ? _decodedText.toUpperCase() : _decodedText.toLowerCase(),
                  style: TextStyle(
                    fontFamily: 'CwMono', fontSize: fontSize,
                    color: c.accent, height: 1.4,
                  ),
                )),
              ),
            ),
          ),
        ),

        // Straight key on an adapter, analysis still off: point to the switch.
        // Analysis on but no adapter: say why nothing is measured.
        if (_keyerMode == 4)
          ValueListenableBuilder<bool>(
            valueListenable: KeyAdapterState.detected,
            builder: (context, adapter, _) {
              if (!adapter && _fistOn && !_fistNoAdapterSeen) {
                return _tip('fist_no_adapter', () => openKeyAdapterManual(context),
                    () => _closeTip('fistNoAdapterHintSeen', () => _fistNoAdapterSeen = true));
              }
              if (adapter && !_fistOn && !_fistHintSeen) {
                return _tip('fist_hint', _openFistSettings,
                    () => _closeTip('fistHintSeen', () => _fistHintSeen = true));
              }
              if (adapter && _fistOn) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: FistPanel(
                      report: _fistReport,
                      hints: _fistHints.shown,
                      onReset: _resetFist),
                );
              }
              return const SizedBox.shrink();
            },
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            // Straight key: the speed is measured from the operator's keying, so
            // the slider is disabled and just follows the measured value.
            child: _keyerMode == 4
                ? SliderRow(
                    label: 'WPM', value: _measuredWpm.toDouble(), min: 5, max: 60,
                    divisions: 55, showTicks: true, onChanged: null)
                : SliderRow(
                    label: 'WPM', value: _wpm.toDouble(), min: 5, max: 60, divisions: 55,
                    showTicks: true,
                    onChanged: (d) {
                      final v = d.round();
                      setState(() => _wpm = v);
                      _keyerChannel.invokeMethod('setWpm', v);
                      _saveWpm();
                    },
                  ),
          ),
        ),

        if (_keyerMode == 4)
          StraightKeyPaddle(onDown: _ditDown, onUp: _ditUp)
        else
          IambicPaddles(onDitDown: _ditDown, onDitUp: _ditUp,
              onDahDown: _dahDown, onDahUp: _dahUp),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

