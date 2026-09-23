import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/paddle_widgets.dart';
import 'widgets/pinch_zoom_text.dart';
import '../keyer/morse_decoder.dart';
import '../theme/app_colors.dart';
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
        _decodedText = (_decodedText + ch).characters.toList().reversed
            .take(80).toList().reversed.join();
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
        backgroundColor: c.surface,
        title: Text('CW Keyer',
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _ready ? _buildBody() : Center(
        child: CircularProgressIndicator(color: c.accent),
      ),
    );
  }

  Widget _buildBody() {
    final c = AppColors.of(context);
    final modeLabel = const ['Iambic A', 'Iambic B', 'Ultimatic', 'Non-Squeeze', 'Straight'][_keyerMode];
    return Column(
      children: [
        _StatusBar(wpm: _wpm, modeLabel: modeLabel),

        Expanded(
          child: PinchZoomFontSize(
            prefsKey: 'keyerFontSize',
            initialSize: 28,
            builder: (context, fontSize) => Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  _decodedText.isEmpty ? '·' :
                      (_outputCase == 1 ? _decodedText.toUpperCase() : _decodedText.toLowerCase()),
                  style: TextStyle(
                    fontFamily: 'CwMono', fontSize: fontSize,
                    color: c.accent, height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SliderRow(
            label: 'WPM', value: _wpm.toDouble(), min: 5, max: 60, divisions: 55,
            onChanged: (v) {
              setState(() => _wpm = v);
              _keyerChannel.invokeMethod('setWpm', v);
              _saveWpm();
            },
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

class _StatusBar extends StatelessWidget {
  final int wpm;
  final String modeLabel;
  const _StatusBar({required this.wpm, required this.modeLabel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: c.surfaceAlt,
      child: Row(children: [
        _chip('$wpm WPM', c.accent),
        const SizedBox(width: 10),
        _chip(modeLabel, c.textMuted),
        const SizedBox(width: 10),
        _chip('native keyer', c.accent),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Text(text, style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: color)),
  );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<int> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min,
      required this.max, required this.divisions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(children: [
    SizedBox(width: 50, child: Text(label,
        style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
            color: c.textMuted))),
    Expanded(child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.border,
        thumbColor: c.accent,
        overlayColor: c.accent.withOpacity(0.1),
        trackHeight: 3,
      ),
      child: Slider(value: value, min: min, max: max, divisions: divisions,
          onChanged: (v) => onChanged(v.round())),
    )),
    SizedBox(width: 40, child: Text(value.round().toString(),
        textAlign: TextAlign.right,
        style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
            color: c.accent))),
  ]);
  }
}

