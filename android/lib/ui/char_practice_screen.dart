import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/echo_suggestions.dart';
import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/char_color.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart';
import 'widgets/interference_button.dart';
import 'widgets/paddle_widgets.dart';
import 'widgets/setting_rows.dart';

/// Long press on a Koch character in Hören or Geben (user request 2026-09-27,
/// replaces the fixedTarget echo drill): the same tile as the tap playback,
/// replayed in a loop. After each play a pause runs (own setting, gear icon):
/// keying the character back within it is optional and gets right/wrong
/// feedback; silence just replays it. No error, no counting, no statistics.
class CharPracticeScreen extends StatefulWidget {
  final String ch;
  const CharPracticeScreen({super.key, required this.ch});

  @override
  State<CharPracticeScreen> createState() => _CharPracticeScreenState();
}

class _CharPracticeScreenState extends State<CharPracticeScreen> {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _straightWpmStream = EventChannel('at.oe1cko.nextcwtrainer/cw_straight_wpm');
  StreamSubscription? _wpmSub;
  int _measuredWpm = 15;   // straight key: measured speed (display and timing only)
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  // Settings, read from the Geben profile and the global keyer/tone prefs
  // (same keys as the Echo Trainer).
  int _wpm = 20;
  // Pause after each play before it repeats, if nothing is keyed. Its own
  // setting: the Echo Trainer's start deadline (~12 s at the defaults) was
  // far too long here (user feedback 2026-09-27).
  static const _pauseKey = 'charPracticePause';
  static const _pauseDefault = 4;
  int _pauseS = _pauseDefault;
  int _answerWpmMax = 0;
  int _pitch = 600;
  int _toneShift = 1;
  int _toneSoftness = 4;
  int _keyerMode = 0;
  int _curtisBDit = 75, _curtisBDah = 45;
  int _acs = 0;
  int _outputCase = 0;
  bool _confirmTone = true;

  late final MorseDecoder _decoder;
  StreamSubscription? _genSub;
  StreamSubscription? _symbolSub;
  Completer<void>? _playDone;
  Timer? _timer;           // start deadline, answer safety net, or replay delay
  bool _active = true;     // false once the page is left
  bool _answered = false;  // a keyed character was evaluated for this play

  bool _ready = false;
  bool _playing = false;
  int _lit = 0;
  bool _sounding = false;

  String _keyed = '';   // dits/dahs of the current attempt ('.'/'-')
  bool? _ok;            // feedback for the last keyed character, null = none
  String _given = '';

  bool _touchDit = false, _touchDah = false;

  String get _pattern => morsePattern(widget.ch);
  int get _answerWpm => _answerWpmMax > 0 ? min(_wpm, _answerWpmMax) : _wpm;

  int get _startDeadlineMs => _pauseS * 1000;

  // Safety net only: the keyer normally reports the character gap itself.
  int get _answerSafetyMs => max(3000, (20 * 1200 / (_keyerMode == 4 ? _measuredWpm : _answerWpm)).round());

  @override
  void initState() {
    super.initState();
    InterferenceProfile.requestAmbient(this);
    KeepScreenOn.enable();
    PracticeClock.instance.enter('hear');
    _decoder = MorseDecoder(onChar: _onDecodedChar);
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.echo);
    _wpm          = TrainingProfile.clampWpm(pf.getInt('wpm'));
    _pauseS         = (p.getInt(_pauseKey) ?? _pauseDefault).clamp(1, 20);
    _answerWpmMax = kGiveWpmCap(p.getInt('echoAnswerWpmMax') ?? 0);
    _pitch        = p.getInt('pitch') ?? 600;
    _toneShift    = (p.getInt('toneShift') ?? 1).clamp(0, 2);
    _toneSoftness = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    _keyerMode    = p.getInt('keyerMode') ?? 0;
    _measuredWpm  = (p.getInt('straightStartWpm') ?? 15).clamp(5, 40);
    _curtisBDit   = (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100);
    _curtisBDah   = (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100);
    _acs          = (p.getInt('acs') ?? 0).clamp(0, 3);
    _outputCase   = (p.getInt('outputCase') ?? 0).clamp(0, 1);
    _confirmTone  = p.getBool('confirmTone') ?? true;
    if (!mounted) return;

    // Rule 2: the shared keyer/tone keep whatever the last screen set.
    await _keyerChannel.invokeMethod('setMode', _keyerMode).catchError((_) {});
    await _keyerChannel.invokeMethod('setCurtisBTiming',
        {'dit': _curtisBDit, 'dah': _curtisBDah}).catchError((_) {});
    await _keyerChannel.invokeMethod('setAcs', _acs).catchError((_) {});
    await _keyerChannel.invokeMethod('setInterWordSpace', 7).catchError((_) {});
    await _toneChannel.invokeMethod('setEnvelopeMs', (_toneSoftness + 1).toDouble()).catchError((_) {});

    _genSub = cwGenEvents.listen(_onGenEvent);
    _symbolSub = _symbolStream.receiveBroadcastStream().listen((s) {
      PracticeClock.instance.touch();
      _onSymbol(s);
    });
    _wpmSub = _straightWpmStream.receiveBroadcastStream().listen((w) {
      if (mounted) setState(() => _measuredWpm = (w as int).clamp(5, 60));
    });
    setState(() => _ready = true);
    await _play();
  }

  @override
  void dispose() {
    InterferenceProfile.releaseAmbient(this);
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    _active = false;
    _timer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _wpmSub?.cancel();
    _genChannel.invokeMethod('stopOne');
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  void _onGenEvent(dynamic raw) {
    final ev = raw as Map;
    if (!mounted) return;
    switch (ev['type']) {
      case 'elementOn':
        setState(() { _lit = int.parse(ev['value'] as String) + 1; _sounding = true; });
      case 'elementOff':
        setState(() => _sounding = false);
      case 'done':
        if (_playDone != null && !_playDone!.isCompleted) _playDone!.complete();
    }
  }

  /// Plays the character once. The keyer is off meanwhile so the prompt and
  /// the operator's own keying never overlap; afterwards it listens again at
  /// the answer speed and the shifted pitch (Tone Shift, as in the Echo Trainer).
  Future<void> _play() async {
    if (_playing || !_ready || !_active) return;
    _timer?.cancel();
    _answered = false;
    setState(() { _playing = true; _lit = 0; _keyed = ''; _ok = null; });
    _decoder.reset();
    await _keyerChannel.invokeMethod('stop').catchError((_) {});
    await _toneChannel.invokeMethod('setFreq', _pitch).catchError((_) {});
    await _genChannel.invokeMethod('setWpm', _wpm).catchError((_) {});
    _playDone = Completer<void>();
    await _genChannel.invokeMethod('playOne', widget.ch.toUpperCase());
    await _playDone!.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    if (!mounted) return;
    final shifted = switch (_toneShift) {
      1 => (_pitch * 18 / 17).round(),
      2 => (_pitch * 17 / 18).round(),
      _ => _pitch,
    };
    await _toneChannel.invokeMethod('setFreq', shifted).catchError((_) {});
    await _keyerChannel.invokeMethod('setWpm', _answerWpm).catchError((_) {});
    await _keyerChannel.invokeMethod('start').catchError((_) {});
    if (!mounted || !_active) return;
    setState(() => _playing = false);
    _armTimer(_startDeadlineMs, _onSilence);
  }

  void _armTimer(int ms, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: ms), f);
  }

  void _replayAfter(int ms) {
    _armTimer(ms, () { if (mounted && _active) _play(); });
  }

  // Nothing keyed (or only an unfinished attempt) by the deadline.
  void _onSilence() {
    if (_keyed.isNotEmpty) {
      _decoder.flush();   // evaluates what was keyed so far
      if (_answered) return;
    }
    _replayAfter(400);
  }

  void _onSymbol(dynamic sym) {
    if (_playing || _answered || !mounted) return;
    final s = sym as String;
    if (s == '·' || s == '—') {
      setState(() => _keyed += s == '·' ? '.' : '-');
      // Keying has begun: think time no longer applies.
      _armTimer(_answerSafetyMs, _onSilence);
    }
    _decoder.add(s);
  }

  void _onDecodedChar(String ch) {
    if (ch == ' ' || !mounted) return;
    if (_answered || _playing) return;
    if (ch == MorseDecoder.err) {
      // <err>: start the attempt over, with a fresh deadline.
      setState(() { _keyed = ''; _ok = null; });
      _armTimer(_startDeadlineMs, _onSilence);
      return;
    }
    _answered = true;
    final ok = ch.toUpperCase() == widget.ch.toUpperCase();
    setState(() { _ok = ok; _given = ch; });
    if (_confirmTone) _toneChannel.invokeMethod('playConfirmTone', ok);
    // Same pauses as the Echo Trainer before the next play.
    _replayAfter(ok ? 1200 : 1500);
  }

  void _setTouchInputs({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  Future<void> _openSettings() {
    final c = AppColors.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.background,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              LabeledSlider(
                label: Strings.t('cp_pause'),
                value: _pauseS.toDouble(), min: 1, max: 20, divisions: 19,
                display: '$_pauseS s',
                onChanged: (v) async {
                  setSheet(() {});
                  setState(() => _pauseS = v.round());
                  final p = await SharedPreferences.getInstance();
                  await p.setInt(_pauseKey, _pauseS);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(Strings.t('cp_pause_desc'),
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                        color: c.textFaint, fontStyle: FontStyle.italic)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _shown(String ch) => _outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final feedbackColor = _ok == null ? c.accentPurple : (_ok! ? c.accent : c.danger);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('char_echo_title').replaceFirst('{ch}', widget.ch.toUpperCase())),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          const InterferenceButton(),
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    constraints: const BoxConstraints(minWidth: 240),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_shown(widget.ch),
                          style: TextStyle(fontFamily: 'CwMono', fontSize: 56,
                              fontWeight: FontWeight.bold, color: charTypeColor(widget.ch, c))),
                      const SizedBox(height: 16),
                      MorseElementRow(pattern: _pattern, lit: _lit, sounding: _sounding),
                      const SizedBox(height: 20),
                      Container(width: 180, height: 1, color: c.border),
                      const SizedBox(height: 16),
                      // The operator's own keying: grows element by element,
                      // then turns green/red once the character is complete.
                      SizedBox(
                        height: 14,
                        child: MorseElementRow(
                            pattern: _keyed, lit: _keyed.length, color: feedbackColor),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 20 * textScaleOf(context),
                        child: _ok == null
                            ? null
                            : Text(
                                _ok!
                                    ? Strings.t('cp_correct')
                                    : Strings.t('cp_wrong').replaceFirst('{ch}', _shown(_given)),
                                style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
                                    color: feedbackColor)),
                      ),
                    ]),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(Strings.t('cp_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                          color: c.textFaint, fontStyle: FontStyle.italic)),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _keyerMode == 4
                ? StraightKeyPaddle(
                    onDown: () => _setTouchInputs(dit: true),
                    onUp: () => _setTouchInputs(dit: false))
                : IambicPaddles(
                    onDitDown: () => _setTouchInputs(dit: true),
                    onDitUp: () => _setTouchInputs(dit: false),
                    onDahDown: () => _setTouchInputs(dah: true),
                    onDahUp: () => _setTouchInputs(dah: false)),
          ),
        ]),
      ),
    );
  }
}
