import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../keyer/morse_decoder.dart';
import '../content/cw_content.dart';
import 'widgets/paddle_widgets.dart';
import 'widgets/pinch_zoom_text.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';

enum _State { idle, playing, receiving, correct, wrong }

class EchoTrainerScreen extends StatefulWidget {
  // When set, locks onto this single character instead of picking a random
  // target: the same char repeats every round (M32 Koch Trainer "Learn New
  // Chr" / "Preview Char" — both funnel into the Echo Trainer engine drilling
  // one fixed character; see Koch::getNewChar()/getKochChar()).
  final String? fixedTarget;
  final String? title;
  const EchoTrainerScreen({super.key, this.fixedTarget, this.title});

  @override
  State<EchoTrainerScreen> createState() => _EchoTrainerScreenState();
}

class _EchoTrainerScreenState extends State<EchoTrainerScreen> {
  static const _genChannel    = MethodChannel('at.oe1wkl.morserino_mobile/cw_generator');
  static const _genEvents     = EventChannel('at.oe1wkl.morserino_mobile/cw_gen_events');
  static const _keyerChannel  = MethodChannel('at.oe1wkl.morserino_mobile/cw_keyer');
  static const _symbolStream  = EventChannel('at.oe1wkl.morserino_mobile/cw_symbols');
  static const _toneChannel   = MethodChannel('at.oe1wkl.morserino_mobile/cw_tone');

  static const _dispCodeOnly    = 1;  // Sound only
  static const _dispDispOnly    = 2;  // Display only (no audio)
  static const _dispCodeAndDisp = 3;  // Sound & Display

  _State _state    = _State.idle;
  int    _wpm      = 20;
  int    _kochLevel = 5;
  // Content mode: 0=Random (single active Koch char), 1..5 map 1:1 onto
  // CwGenerator.Mode's WORDS/CALLSIGNS/MIXED/PRACTICE_SET/ABBREVS ordinals
  int    _modeIndex = 0;
  int    _kochSeq         = 0;
  String _customKochChars = '';
  List<String> get _activeKochChars => kochSequenceChars(_kochSeq, _customKochChars);
  int  _abbrevLengthMax = 0;
  int  _callLengthOpt   = 0;
  int  _callRegionOpt   = 0;
  bool _callCommonOnly  = true;
  int  _outputCase      = 0;   // 0=lower, 1=UPPER — display only

  // Touch paddle: 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight
  int _keyerMode = 0;
  bool _touchDit = false;
  bool _touchDah = false;

  // Echo settings (from SharedPreferences)
  int  _echoThinkTime = 8;   // seconds
  int  _echoRepeats   = 0;   // replays on wrong answer
  int  _echoDisplay   = _dispCodeOnly;  // matches M32 "Echo Prompt": sound/display/both
  bool _confirmTone   = false;
  bool _adaptiveSpeed = false;
  int  _echoSpeedMax  = 35;

  String _target  = '';
  String _attempt = '';

  int _correct = 0;
  int _total   = 0;
  int _wrongStreak = 0;   // consecutive wrong answers for current item
  bool _sessionActive = false;   // guards against a stale target fetch after Stop

  // Adaptive speed tracking
  int _currentWpm = 20;

  // Decoder + silence timer
  late final MorseDecoder _decoder;
  Timer? _silenceTimer;
  StreamSubscription? _genSub;
  StreamSubscription? _symbolSub;

  final _random = Random();

  int get _silenceMs => _echoThinkTime * 1000;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _decoder = MorseDecoder(onChar: _onDecodedChar);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _wpm            = p.getInt('wpm')            ?? 20;
      _kochLevel      = p.getInt('kochLevel')      ?? 5;
      _echoThinkTime  = p.getInt('echoThinkTime')  ?? 8;
      _echoRepeats    = p.getInt('echoRepeats')    ?? 0;
      _echoDisplay    = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _confirmTone    = p.getBool('confirmTone')   ?? false;
      _adaptiveSpeed  = p.getBool('adaptiveSpeed') ?? false;
      _echoSpeedMax   = p.getInt('echoSpeedMax')   ?? 35;
      _modeIndex      = (p.getInt('echoModeIndex') ?? 0).clamp(0, 5);
      _keyerMode      = p.getInt('keyerMode')      ?? 0;
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = p.getString('customKochChars') ?? '';
      _abbrevLengthMax = (p.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      _outputCase      = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
      _currentWpm     = _wpm;
    });
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm',       _wpm);
    await p.setInt('kochLevel', _kochLevel);
    await p.setInt('echoModeIndex', _modeIndex);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _silenceTimer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stop');
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  // ── Session control ────────────────────────────────────────────────────────

  void _startSession() {
    _correct = 0; _total = 0; _wrongStreak = 0;
    _currentWpm = _wpm;
    _sessionActive = true;
    _playNext();
  }

  void _stopSession() {
    _sessionActive = false;
    _silenceTimer?.cancel();
    _genSub?.cancel();   _genSub   = null;
    _symbolSub?.cancel(); _symbolSub = null;
    _genChannel.invokeMethod('stop');
    _keyerChannel.invokeMethod('stop');
    setState(() => _state = _State.idle);
  }

  void _playNext({bool sameTarget = false}) async {
    _symbolSub?.cancel(); _symbolSub = null;
    _silenceTimer?.cancel();
    _decoder.reset();

    if (!sameTarget) {
      final fetched = await _fetchTarget();
      // Session may have been stopped while we were awaiting the fetch.
      if (!mounted || !_sessionActive) return;
      _target  = fetched;
      _wrongStreak = 0;
    }
    _attempt = '';

    setState(() => _state = _State.playing);

    // Echo Prompt = Display only: no audio at all, just show the target briefly
    // (mirrors the real device's "silentEcho": genTimer skips almost instantly).
    if (_echoDisplay == _dispDispOnly) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_state == _State.playing && mounted) _beginReceive();
      });
      return;
    }

    _genSub?.cancel();
    _genSub = _genEvents.receiveBroadcastStream().listen((raw) {
      final ev = raw as Map;
      if (ev['type'] == 'done' && _state == _State.playing) {
        _genSub?.cancel(); _genSub = null;
        _beginReceive();
      }
    });

    _genChannel.invokeMethod('setWpm', _currentWpm).catchError((_) {});
    _genChannel.invokeMethod('playOne', _target);
  }

  void _beginReceive() {
    _keyerChannel.invokeMethod('start');
    setState(() => _state = _State.receiving);
    // Start the timeout immediately — otherwise it only ever gets (re)armed
    // reactively by an incoming symbol, so giving no echo at all waits forever.
    _resetSilenceTimer();
    _symbolSub = _symbolStream.receiveBroadcastStream().listen((sym) {
      _decoder.add(sym as String);
      _resetSilenceTimer();
    });
  }

  void _onDecodedChar(String ch) {
    if (_state != _State.receiving) return;
    if (ch == ' ') return;  // ignore word-gap spaces mid-attempt
    setState(() => _attempt += ch);
    _resetSilenceTimer();
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: _silenceMs), _evaluate);
  }

  void _evaluate() {
    if (_state != _State.receiving) return;
    _symbolSub?.cancel(); _symbolSub = null;
    _keyerChannel.invokeMethod('stop');

    _decoder.flush();

    // Learn New Chr / Preview Char (fixedTarget): giving no answer at all is
    // optional and silently ignored — no error, no stats, no feedback shown —
    // then it just repeats. Mirrors the real device's EVAL_FEEDBACK, which
    // skips the ERR branch specifically for KOCH_LEARN/KOCH_PREVIEW when
    // echoResponse is empty (an actual — even wrong — answer still evaluates
    // normally, same as the regular Echo Trainer).
    if (widget.fixedTarget != null && _attempt.trim().isEmpty) {
      Timer(const Duration(milliseconds: 400), () {
        if (mounted) _playNext(sameTarget: true);
      });
      return;
    }

    _total++;

    final ok = _attempt.trim().toUpperCase() == _target.toUpperCase();
    if (ok) {
      _correct++;
      _wrongStreak = 0;
      // Adaptive speed: every 10 correct, bump by 1 WPM up to max
      if (_adaptiveSpeed && _correct % 10 == 0) {
        _currentWpm = (_currentWpm + 1).clamp(_wpm, _echoSpeedMax);
      }
    } else {
      _wrongStreak++;
    }

    setState(() => _state = ok ? _State.correct : _State.wrong);
    if (_confirmTone) _toneChannel.invokeMethod('playConfirmTone', ok);

    if (!ok && _echoRepeats > 0 && _wrongStreak <= _echoRepeats) {
      // Replay the target after a short pause, don't count as new attempt
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted) _playNext(sameTarget: true);
      });
    } else {
      Timer(Duration(milliseconds: ok ? 1200 : 2000), () {
        if (mounted && (_state == _State.correct || _state == _State.wrong)) {
          _playNext();
        }
      });
    }
  }

  // ── Touch paddle (only useful while receiving, but always available like
  // the real device — a hardware vband adapter works the same way, this just
  // adds a touch alternative) ─────────────────────────────────────────────
  void _setTouchInputs({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  void _ditDown() => _setTouchInputs(dit: true);
  void _ditUp()   => _setTouchInputs(dit: false);
  void _dahDown() => _setTouchInputs(dah: true);
  void _dahUp()   => _setTouchInputs(dah: false);

  Future<String> _fetchTarget() async {
    if (widget.fixedTarget != null) return widget.fixedTarget!;
    if (_modeIndex == 0) {
      // Random: single active Koch character (unchanged, well-tuned Koch drill)
      final active = kochActiveChars(_kochLevel, _activeKochChars);
      return active[_random.nextInt(active.length)];
    }
    // Words/Callsigns/Mixed/Practice Set/Abbrevs: generated Kotlin-side from the
    // same content pools as the CW Generator (mode ordinals 1..5 line up directly).
    final result = await _genChannel.invokeMethod('getNextContent', {
      'mode': _modeIndex,
      'kochLevel': _kochLevel,
      'abbrevLengthMax': _abbrevLengthMax,
      'callLengthOpt': _callLengthOpt,
      'callRegionOpt': _callRegionOpt,
      'callCommonOnly': _callCommonOnly,
    });
    return (result as String?) ?? '';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(widget.title ?? 'Echo Trainer',
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () { _stopSession(); Navigator.pop(context); },
        ),
      ),
      body: Column(
        children: [
          // ── Content mode (hidden when locked to a fixed target) ─────────
          if (widget.fixedTarget == null) ...[
            _EchoModeSelector(
              selected: _modeIndex,
              enabled: _state == _State.idle,
              onChanged: (i) { setState(() => _modeIndex = i); _savePrefs(); },
            ),
            if (_modeIndex == 0) _KochCharsRow(level: _kochLevel, sequence: _activeKochChars),
          ],

          // ── Main display ─────────────────────────────────────────────────
          Expanded(child: PinchZoomFontSize(
            prefsKey: 'echoFontSize',
            initialSize: 72,
            minSize: 36,
            maxSize: 140,
            builder: (context, fontSize) => _MainDisplay(
              state: _state,
              target: _target,
              revealTarget: _echoDisplay != _dispCodeOnly,
              attempt: _attempt,
              outputCase: _outputCase,
              fontSize: fontSize,
            ),
          )),

          // ── Stats bar ────────────────────────────────────────────────────
          if (_total > 0) _StatsBar(correct: _correct, total: _total,
              currentWpm: _adaptiveSpeed ? _currentWpm : null),

          // ── Status label ─────────────────────────────────────────────────
          _StatusLabel(state: _state),

          // ── Sliders ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _SliderRow(label: 'WPM',  value: _wpm.toDouble(),
                  min: 5, max: 60, divisions: 55,
                  onChanged: (v) { setState(() => _wpm = v.round()); _savePrefs(); }),
              if (_modeIndex == 0 && widget.fixedTarget == null)
                _SliderRow(label: 'KOCH', value: _kochLevel.toDouble(),
                    min: 2, max: _activeKochChars.length.toDouble(),
                    divisions: _activeKochChars.length - 2,
                    onChanged: (v) { setState(() => _kochLevel = v.round()); _savePrefs(); }),
            ]),
          ),

          // ── Touch paddle ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            child: _keyerMode == 4
                ? StraightKeyPaddle(onDown: _ditDown, onUp: _ditUp)
                : IambicPaddles(onDitDown: _ditDown, onDitUp: _ditUp,
                    onDahDown: _dahDown, onDahUp: _dahUp),
          ),

          // ── Start / Stop ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_state != _State.idle)
                      ? c.danger.withOpacity(0.2)
                      : c.accent.withOpacity(0.2),
                  foregroundColor: (_state != _State.idle)
                      ? c.danger
                      : c.accent,
                  side: BorderSide(color: (_state != _State.idle)
                      ? c.danger : c.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: (_state == _State.idle) ? _startSession : _stopSession,
                child: Text((_state == _State.idle) ? '▶  START' : '■  STOP',
                    style: const TextStyle(fontFamily: 'CwMono', fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _MainDisplay extends StatelessWidget {
  final _State state;
  final String target, attempt;
  // Echo Prompt = Sound only: the real device never prints the target text at
  // all — not while playing, not while receiving, not even on the OK/ERR
  // verdict — training is audio-only. Display/Both modes show it throughout.
  final bool revealTarget;
  // Output Case ("posOutputCase") — display-only, applies to both the
  // generated target text and the keyed/decoded attempt text.
  final int outputCase;
  // Pinch-to-zoom base size for the target text; the attempt text keeps the
  // same 48/72 ratio as the original fixed sizes.
  final double fontSize;
  const _MainDisplay({required this.state, required this.target, required this.attempt,
      this.revealTarget = false, this.outputCase = 0, this.fontSize = 72});

  String _cased(String s) => outputCase == 1 ? s.toUpperCase() : s.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor(c)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Target
          Text(
            revealTarget ? _cased(target) : '?',
            style: TextStyle(
              fontFamily: 'CwMono',
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: _targetColor(c),
            ),
          ),
          const SizedBox(height: 24),
          // User attempt
          if (state == _State.receiving || state == _State.correct || state == _State.wrong)
            Text(
              attempt.isEmpty ? '_' : _cased(attempt),
              style: TextStyle(
                fontFamily: 'CwMono',
                fontSize: fontSize * 48 / 72,
                color: _attemptColor(c),
              ),
            ),
        ],
      ),
    );
  }

  Color _targetColor(AppColors c) => switch (state) {
    _State.correct  => c.accent,
    _State.wrong    => c.danger,
    _State.playing  => c.textDisabled,
    _             => c.textPrimary,
  };

  Color _attemptColor(AppColors c) => switch (state) {
    _State.correct => c.accent,
    _State.wrong   => c.danger,
    _              => c.textMuted,
  };

  Color _borderColor(AppColors c) => switch (state) {
    _State.correct => c.accent.withOpacity(0.5),
    _State.wrong   => c.danger.withOpacity(0.5),
    _State.playing => c.warning.withOpacity(0.3),
    _              => c.border,
  };
}

class _StatusLabel extends StatelessWidget {
  final _State state;
  const _StatusLabel({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (text, color) = switch (state) {
      _State.idle      => ('Drücke START', c.textDisabled),
      _State.playing   => ('Anhören …', c.warning),
      _State.receiving => ('Senden …', c.info),
      _State.correct   => ('✓ Richtig!', c.accent),
      _State.wrong     => ('✗ Falsch', c.danger),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: color)),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int correct, total;
  final int? currentWpm;
  const _StatsBar({required this.correct, required this.total, this.currentWpm});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pct = (correct * 100 ~/ total);
    final wrong = total - correct;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: c.surfaceAlt,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _chip('✓ $correct', c.accent),
          const SizedBox(width: 12),
          _chip('✗ $wrong', c.danger),
          const SizedBox(width: 12),
          _chip('$pct %',
              pct >= 90 ? c.accent
            : pct >= 70 ? c.warning
                        : c.danger),
          if (currentWpm != null) ...[
            const SizedBox(width: 12),
            _chip('⚡ $currentWpm WPM', c.info),
          ],
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withOpacity(0.3)),
    ),
    child: Text(t, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c)),
  );
}

class _EchoModeSelector extends StatelessWidget {
  static const _labels = ['Zufall (Koch)', 'Wörter', 'Rufzeichen', 'Gemischt', 'Practice Set', 'Abkürzungen'];
  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _EchoModeSelector({required this.selected, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        const perRow = 3;
        const gap = 6.0;
        final itemWidth = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap, runSpacing: gap,
          children: List.generate(_labels.length, (i) {
            final active = i == selected;
            return SizedBox(width: itemWidth, child: GestureDetector(
              onTap: enabled ? () => onChanged(i) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? c.accentPurple.withOpacity(0.15) : c.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: active ? c.accentPurple : c.border),
                ),
                child: Text(_labels[i], textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 10,
                        color: !enabled
                            ? c.textDisabled
                            : active ? c.accentPurple : c.textMuted)),
              ),
            ));
          }),
        );
      }),
    );
  }
}

class _KochCharsRow extends StatelessWidget {
  final int level;
  final List<String> sequence;
  const _KochCharsRow({required this.level, required this.sequence});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = kochActiveChars(level, sequence);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceAlt, borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(spacing: 6, children: active.map((ch) =>
          Text(ch, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
              color: c.accent))).toList()),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min,
      required this.max, required this.divisions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
    children: [
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
        child: Slider(value: value, min: min, max: max,
            divisions: divisions, onChanged: onChanged),
      )),
      SizedBox(width: 40, child: Text(value.round().toString(),
          textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
              color: c.accent))),
    ],
  );
  }
}
