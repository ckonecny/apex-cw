import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/paddle_widgets.dart';
import 'widgets/pinch_zoom_text.dart';
import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import 'widgets/training_settings_sheet.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/slider_row.dart';
import '../util/keep_screen_on.dart';

class KeyerScreen extends StatefulWidget {
  const KeyerScreen({super.key});

  @override
  State<KeyerScreen> createState() => _KeyerScreenState();
}

class _KeyerScreenState extends State<KeyerScreen> {
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');

  // Decoded text (mirrors the real device's CW Keyer, which decodes keyed
  // input via keyerTable/displayDecodedMorse() rather than showing raw
  // dit/dah symbols — see doPaddleIambic()'s IDLE_STATE in m32_v6.ino).
  late final MorseDecoder _decoder;
  String _decodedText = '';
  static const _maxText = 4000;
  int    _outputCase  = 0;   // 0=lower, 1=UPPER — display only
  bool   _ready    = false;
  int    _wpm      = 20;
  int    _keyerMode = 0;   // 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight

  bool _touchDit = false;
  bool _touchDah = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _decoder = MorseDecoder(onChar: (ch) {
      if (mounted) setState(() {
        // Cap only to bound memory; the display scrolls, so this must be far
        // more than fits on screen (a small cap here made the text shift
        // after ~4 lines even with free space left).
        final t = _decodedText + ch;
        _decodedText = t.length > _maxText ? t.substring(t.length - _maxText) : t;
      });
    });
    _symbolStream.receiveBroadcastStream().listen((sym) => _decoder.add(sym as String));
    _loadPrefsAndInit();
  }

  Future<void> _loadPrefsAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _wpm        = prefs.getInt('wpm')        ?? 20;
      _keyerMode  = prefs.getInt('keyerMode')  ?? 0;
      _outputCase = (prefs.getInt('outputCase') ?? 0).clamp(0, 1);
    });
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
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            tooltip: Strings.t('settings_title'),
            onPressed: () async {
              await showTrainingSettingsSheet(context,
                  profile: TrainingProfile.keyer,
                  sections: const [TrainingSection.wordSpacing]);
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
                  _decodedText.isEmpty ? '·' :
                      (_outputCase == 1 ? _decodedText.toUpperCase() : _decodedText.toLowerCase()),
                  style: TextStyle(
                    fontFamily: 'CwMono', fontSize: fontSize,
                    color: c.accent, height: 1.4,
                  ),
                )),
              ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: SliderRow(
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

