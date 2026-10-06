// CW Decoder — decodes CW from the microphone (backlog #8), the firmware's
// "CW Decoder" mode (m32_v6.ino morseDecoder, audioDecoder.decode()).
//
// The microphone PCM comes from MicInput.kt; Goertzel tone detection and the
// firmware's timing decoder run in lib/keyer/cw_audio_decoder.dart. Decoded
// text scrolls like the device's display, the decoded speed is shown in the
// status line (displayCWspeed with the decoder's d_wpm). Options as the
// firmware's decoderOptions: Bandwidth (Wide/Narrow); plus what the phone
// needs in place of the device's tuned line input: target pitch, threshold
// (the magnitude floor) with a level meter, and an optional monitor tone.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../keyer/cw_audio_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import 'widgets/app_ui.dart';

class DecoderScreen extends StatefulWidget {
  const DecoderScreen({super.key});

  @override
  State<DecoderScreen> createState() => _DecoderScreenState();
}

class _DecoderScreenState extends State<DecoderScreen> with WidgetsBindingObserver {
  static const _micChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_mic');
  static const _pcmChannel   = EventChannel('at.oe1cko.nextcwtrainer/cw_mic_pcm');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  static const _maxText = 3000;
  static const _dbMin = -70.0;

  // Settings (prefs: decNarrow, decFreq, decFloorDb, decMonitor).
  bool _narrow = false;       // firmware posGoertzelBandwidth default: Wide
  int _freq = 698;            // firmware target_freq
  double _floorDb = -40;      // magnitude floor in dBFS
  bool _monitor = false;
  int _pitch = 600;

  bool _running = false;
  String? _error;
  String _text = '';
  bool _tone = false;
  int _wpm = 0;
  double _levelDb = _dbMin;
  double _threshDb = _dbMin;

  int _sampleRate = 16000;
  late AudioCwDecoder _decoder;
  MicCwDecoder? _mic;
  StreamSubscription? _pcmSub;
  Timer? _meterTimer;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    WidgetsBinding.instance.addObserver(this);
    _decoder = AudioCwDecoder(onSymbol: _onSymbol, onTone: _onTone, onWpm: _onWpm);
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _narrow  = p.getBool('decNarrow') ?? false;
    _freq    = p.getInt('decFreq') ?? 698;
    _floorDb = p.getDouble('decFloorDb') ?? -40;
    _monitor = p.getBool('decMonitor') ?? false;
    _pitch   = p.getInt('pitch') ?? 600;
    // Shared native engine: the paddles would key the sidetone into the
    // microphone; the monitor tone uses the pitch setting (keyOut with posPitch).
    await _keyerChannel.invokeMethod('stop');
    await _toneChannel.invokeMethod('setFreq', _pitch);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('decNarrow', _narrow);
    await p.setInt('decFreq', _freq);
    await p.setDouble('decFloorDb', _floorDb);
    await p.setBool('decMonitor', _monitor);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _running) {
      _stop();
      if (mounted) setState(() {});
    }
  }

  double get _floor => math.pow(10, _floorDb / 20).toDouble();

  GoertzelDetector _detector() => GoertzelDetector(
      sampleRate: _sampleRate, targetFreq: _freq.toDouble(),
      narrow: _narrow, limitLow: _floor);

  // ── Start / stop ────────────────────────────────────────────────────────

  Future<void> _start() async {
    setState(() => _error = null);
    final granted = await _micChannel.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) {
      if (mounted) setState(() => _error = Strings.t('dec_no_permission'));
      return;
    }
    _pcmSub = _pcmChannel.receiveBroadcastStream().listen(_onPcm);
    final rate = await _micChannel.invokeMethod<int>('start') ?? 0;
    if (rate <= 0) {
      await _pcmSub?.cancel();
      _pcmSub = null;
      if (mounted) setState(() => _error = Strings.t('dec_mic_failed'));
      return;
    }
    _sampleRate = rate;
    _decoder.reset();
    _mic = MicCwDecoder(_detector(), _decoder);
    _meterTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _updateMeter());
    if (mounted) setState(() { _running = true; _wpm = _decoder.wpm; });
  }

  void _stop() {
    _meterTimer?.cancel();
    _meterTimer = null;
    _pcmSub?.cancel();
    _pcmSub = null;
    _micChannel.invokeMethod('stop');
    _toneChannel.invokeMethod('setPlaying', false);
    _mic = null;
    _running = false;
    _tone = false;
    _levelDb = _threshDb = _dbMin;
  }

  // Settings changed while listening: new detector, decoder keeps its speed.
  void _reconfigure() {
    if (_mic != null) _mic = MicCwDecoder(_detector(), _decoder);
    _save();
  }

  // ── Audio → decoder ─────────────────────────────────────────────────────

  void _onPcm(dynamic data) {
    if (data is! Uint8List || _mic == null) return;
    final pcm = data.offsetInBytes.isEven
        ? data.buffer.asInt16List(data.offsetInBytes, data.lengthInBytes ~/ 2)
        : Int16List.sublistView(Uint8List.fromList(data));
    _mic!.addSamples(pcm);
  }

  void _onSymbol(String s) {
    var t = _text + s.toUpperCase();   // prosigns as the firmware shows them: <KA>
    if (t.length > _maxText) t = t.substring(t.length - _maxText);
    setState(() => _text = t);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _onTone(bool on) {
    if (_monitor) _toneChannel.invokeMethod('setPlaying', on);
    setState(() => _tone = on);
  }

  void _onWpm(int wpm) => setState(() => _wpm = wpm);

  double _db(double v) =>
      v <= 0 ? _dbMin : (20 * math.log(v) / math.ln10).clamp(_dbMin, 0.0);

  void _updateMeter() {
    final d = _mic?.detector;
    if (d == null || !mounted) return;
    setState(() {
      _levelDb = _db(d.level);
      _threshDb = _db(d.limit * 0.6);
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
      fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  TextStyle _morse(double size, Color color, {bool bold = false}) => TextStyle(
      fontFamily: 'CwMono', fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('dec_title')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: c.textMuted),
            tooltip: Strings.t('dec_clear'),
            onPressed: () => setState(() => _text = ''),
          ),
          IconButton(
            icon: Icon(Icons.tune, color: c.textMuted),
            onPressed: () => _openSettings(c),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusBar(c),
            const SizedBox(height: 10),
            _meter(c),
            const SizedBox(height: 12),
            Expanded(child: AppCard(
              child: _text.isEmpty
                  ? Center(child: Text(
                      _error ?? Strings.t(_running ? 'dec_listening' : 'dec_idle'),
                      textAlign: TextAlign.center,
                      style: _mono(14, _error != null ? c.danger : c.textMuted)))
                  : SingleChildScrollView(
                      controller: _scroll,
                      child: SizedBox(width: double.infinity, child: Text(_text,
                          style: _morse(22, c.textPrimary, bold: true)
                              .copyWith(height: 1.35, letterSpacing: 1))),
                    ),
            )),
            if (_error != null && _text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error!, style: _mono(13, c.danger)),
            ],
            const SizedBox(height: 12),
            AppButton(
              label: Strings.t(_running ? 'dec_stop' : 'dec_start'),
              color: _running ? c.danger : c.accent,
              onTap: () {
                if (_running) {
                  setState(_stop);
                } else {
                  _start();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(AppColors c) {
    return Row(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        width: 16, height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _tone ? c.accent : c.surfaceAlt,
          border: Border.all(color: _running ? c.accent : c.border),
        ),
      ),
      const SizedBox(width: 12),
      Text(_running && _wpm > 0 ? '$_wpm WPM' : '– WPM', style: _mono(16, c.textPrimary)),
      const SizedBox(width: 12),
      Expanded(
        child: Text('$_freq Hz · ${Strings.t(_narrow ? 'dec_narrow_short' : 'dec_wide_short')}',
            textAlign: TextAlign.end, style: _mono(13, c.textMuted)),
      ),
    ]);
  }

  // Level meter: the block magnitude, the automatic threshold (0.6 × limit)
  // and the floor (threshold setting), in dBFS.
  Widget _meter(AppColors c) {
    double frac(double db) => ((db - _dbMin) / -_dbMin).clamp(0.0, 1.0);
    return SizedBox(
      height: 14,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        return Stack(children: [
          Container(decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(7))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: w * frac(_levelDb),
            decoration: BoxDecoration(
                color: (_tone ? c.accent : c.info).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(7)),
          ),
          if (_running)
            Positioned(left: w * frac(_threshDb) - 1, top: 0, bottom: 0,
                child: Container(width: 2, color: c.warning)),
          Positioned(left: w * frac(_floorDb) - 1, top: 0, bottom: 0,
              child: Container(width: 2, color: c.textMuted)),
        ]);
      }),
    );
  }

  Widget _chips(AppColors c, List<String> labels, int selected, ValueChanged<int> onSel) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < labels.length; i++)
          ChoiceChip(
            label: Text(labels[i], style: _mono(13, i == selected ? c.accent : c.textMuted)),
            selected: i == selected,
            showCheckmark: false,
            selectedColor: c.accent.withValues(alpha: 0.18),
            backgroundColor: c.background,
            side: BorderSide.none,
            onSelected: (_) => onSel(i),
          ),
      ]);

  void _openSettings(AppColors c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void apply(VoidCallback f) {
          setSheet(f);
          setState(() {});
          _reconfigure();
        }
        return SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCaption(Strings.t('dec_bandwidth')),
              const SizedBox(height: 8),
              _chips(c, [Strings.t('dec_wide'), Strings.t('dec_narrow')],
                  _narrow ? 1 : 0, (i) => apply(() => _narrow = i == 1)),
              const SizedBox(height: 18),
              AppCaption('${Strings.t('dec_freq')}: $_freq Hz'),
              Slider(
                value: _freq.toDouble(), min: 300, max: 1200, divisions: 90,
                activeColor: c.accent,
                onChanged: (v) => apply(() => _freq = v.round()),
              ),
              AppCaption('${Strings.t('dec_floor')}: ${_floorDb.round()} dBFS'),
              Slider(
                value: _floorDb, min: -65, max: -10, divisions: 55,
                activeColor: c.accent,
                onChanged: (v) => apply(() => _floorDb = v.roundToDouble()),
              ),
              Text(Strings.t('dec_floor_hint'), style: _mono(12, c.textMuted)),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _monitor,
                activeThumbColor: c.accent,
                title: Text(Strings.t('dec_monitor'), style: _mono(15, c.textPrimary)),
                subtitle: Text(Strings.t('dec_monitor_hint'), style: _mono(12, c.textMuted)),
                onChanged: (v) => apply(() {
                  _monitor = v;
                  if (!v) _toneChannel.invokeMethod('setPlaying', false);
                }),
              ),
            ],
          ),
        ));
      }),
    );
  }
}
