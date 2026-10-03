// Fight the Pileup — single-player port of MorsePileup.cpp (game rules in
// content/pileup_engine.dart). Call signs queue up; the oldest one plays in
// CW (a little below your sidetone pitch) and you key it back. After enough
// plays its text is revealed. A correct call earns you one keyed "attack"
// call during which the pileup pauses. Multiplayer (ESP-NOW) is not ported.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/pileup_engine.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/interference_button.dart';
import 'widgets/paddle_widgets.dart';

enum _Phase { lobby, playing, over }

const _tickMs = 100;
const _flashMs = 700;       // firmware 400 ms; a bit longer on a phone
const _submitHoldMs = 2000; // no replay within this time of a submit (firmware)
const _typingHoldMs = 1500; // a pause shorter than this still counts as typing

// Firmware sound effects ({Hz, ms}); durations tripled — 15..40 ms are clicks.
const _sndCorrect = [[1200, 45], [1600, 45]];
const _sndWrong = [[300, 75]];
const _sndTimeout = [[400, 90], [300, 90]];
const _sndLifeLost = [[600, 90], [400, 90], [300, 120]];

class PileupScreen extends StatefulWidget {
  const PileupScreen({super.key});

  @override
  State<PileupScreen> createState() => _PileupScreenState();
}

class _PileupScreenState extends State<PileupScreen> with WidgetsBindingObserver {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  final _random = Random();
  late final PileupEngine _engine;
  late final MorseDecoder _decoder;
  StreamSubscription? _genSub, _symbolSub;
  Timer? _timer;

  bool _ready = false;
  _Phase _phase = _Phase.lobby;
  int _level = 0;            // difficulty index, remembered between visits
  final _clock = Stopwatch()..start();
  int get _now => _clock.elapsedMilliseconds;

  // Settings
  int _keyWpm = 20;
  int _keyerMode = 0;
  int _pitch = 600;
  int _interWord = 7;
  int _callRegion = 0;
  bool _callCommon = false;
  final List<String> _callBuffer = [];

  // Play state
  String _input = '';
  int _lastCharAt = 0;       // last decoded character (auto-submit timer)
  int _lastActivity = 0;     // last keyed element (typing hold)
  int _lastSubmitAt = 0;
  PileupCaller? _playing;    // caller whose CW is sounding now
  PileupCaller? _loaded;     // caller the play counter belongs to
  int _plays = 0;
  int _nextPlayAt = 0;
  String _flash = '';
  Color _flashColor = Colors.white;
  int _flashUntil = 0;
  bool _touchDit = false, _touchDah = false;

  int get _attackPitch => (_pitch * 15 / 18).round();
  int get _ditMs => 1200 ~/ _keyWpm;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('game');
    WidgetsBinding.instance.addObserver(this);
    _engine = PileupEngine(_takeCall);
    _decoder = MorseDecoder(onChar: _onDecodedChar, unknown: '*');
    _load();
  }

  @override
  void dispose() {
    InterferenceProfile.releaseAmbient(this);
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stopOne');
    _toneChannel.invokeMethod('stopEffect');
    _toneChannel.invokeMethod('setFreq', _pitch);
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) _toLobby();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _level = (p.getInt('pileupLevel') ?? 0).clamp(0, pileupDifficulties.length - 1);
    _keyWpm = (p.getInt('wpm') ?? 20).clamp(5, 60);
    _keyerMode = p.getInt('keyerMode') ?? 0;
    _pitch = p.getInt('pitch') ?? 600;
    _callRegion = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
    _callCommon = p.getBool('callCommonOnly') ?? false;
    _interWord = (p.getInt('profile.keyer.interWordSpace') ?? 7).clamp(6, 105);

    // Shared native engine: push everything this screen relies on.
    await _toneChannel.invokeMethod('setFreq', _pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs',
        ((p.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
    await _keyerChannel.invokeMethod('setWpm', _keyWpm);
    await _keyerChannel.invokeMethod('setMode', _keyerMode);
    await _keyerChannel.invokeMethod('setCurtisBTiming', {
      'dit': (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
      'dah': (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
    });
    await _keyerChannel.invokeMethod('setAcs', (p.getInt('acs') ?? 0).clamp(0, 3));
    await _keyerChannel.invokeMethod('setInterWordSpace', _interWord);
    await _keyerChannel.invokeMethod('stop');

    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    _symbolSub = _symbolStream.receiveBroadcastStream().listen(_onSymbol);
    _refillCalls();
    if (mounted) setState(() => _ready = true);
  }

  // ── Call signs ───────────────────────────────────────────────────────────

  // Firmware getRandomCall(0), honouring the call-sign preferences; prefetched
  // so a new caller never waits on the channel.
  Future<void> _refillCalls() async {
    while (_callBuffer.length < 4) {
      try {
        final m = await _genChannel.invokeMethod('randomCallInfo', {
          'callLengthOpt': 0,
          'callRegionOpt': _callRegion,
          'callCommonOnly': _callCommon,
        }) as Map;
        _callBuffer.add((m['call'] as String).toUpperCase());
      } catch (_) {
        return;
      }
    }
  }

  String _takeCall() {
    String call;
    if (_callBuffer.isNotEmpty) {
      call = _callBuffer.removeAt(0);
    } else {
      const l = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      String r() => l[_random.nextInt(26)];
      call = 'D${r()}${_random.nextInt(10)}${r()}${r()}${r()}';
    }
    _refillCalls();
    return call;
  }

  // ── Game flow ────────────────────────────────────────────────────────────

  void _start() {
    _engine.difficulty = pileupDifficulties[_level];
    _engine.start(_now);
    _input = '';
    _lastCharAt = 0;
    _lastActivity = 0;
    _lastSubmitAt = 0;
    _playing = _loaded = null;
    _plays = 0;
    _nextPlayAt = 0;
    _flashUntil = 0;
    _decoder.reset();
    InterferenceProfile.requestAmbient(this);
    SharedPreferences.getInstance().then((p) => p.setInt('pileupLevel', _level));
    _keyerChannel.invokeMethod('start');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _tick());
    setState(() => _phase = _Phase.playing);
  }

  bool get _typing =>
      _input.isNotEmpty || _touchDit || _touchDah || _now - _lastActivity < _typingHoldMs;

  void _tick() {
    if (_phase != _Phase.playing) return;
    final now = _now;

    // Auto-submit after a word gap of silence (firmware: max(interWord + dit, 1200 ms)).
    if (_input.isNotEmpty && _lastCharAt > 0 && !_touchDit && !_touchDah) {
      final gap = max(1200, _ditMs * _interWord + _ditMs);
      if (now - _lastCharAt > gap) _submit();
    }

    final events = _engine.tick(now, typing: _typing);
    for (final e in events) {
      _react(e);
    }
    if (_engine.over) {
      _finish();
      return;
    }
    _managePlayback(now);
    setState(() {});
  }

  void _react(PileupEvent e) {
    switch (e) {
      case PileupEvent.timeout:
        _stopPlayback();
        _sound(_sndTimeout);
        _showFlash(Strings.t('pu_timeout'), true);
        _input = '';
        _lastSubmitAt = _now;
      case PileupEvent.missed:
        _showFlash(Strings.t('pu_missed'), true);
      case PileupEvent.lifeLost:
        _sound(_sndLifeLost);
        _showFlash(Strings.t('pu_life_lost'), true);
      case PileupEvent.correct:
        _stopPlayback();
        _sound(_sndCorrect);
        _showFlash('+${_engine.lastBonus}', false);
      case PileupEvent.wrong:
        _sound(_sndWrong);
        _showFlash(Strings.t('pu_wrong'), true);
      case PileupEvent.attackSent:
        _sound(_sndCorrect);
        _showFlash(Strings.t('pu_attack_sent'), false);
      case PileupEvent.tryAgain:
        _sound(_sndWrong);
        _showFlash(Strings.t('pu_try_again'), true);
      case PileupEvent.over:
      case PileupEvent.none:
        break;
    }
  }

  void _showFlash(String text, bool bad) {
    _flash = text;
    _flashColor = bad ? AppColors.of(context).danger : AppColors.of(context).accent;
    _flashUntil = _now + _flashMs;
  }

  void _sound(List<List<int>> notes) {
    if (_playing != null || _touchDit || _touchDah) return;
    _toneChannel.invokeMethod('playEffect', notes);
  }

  void _finish() {
    _endPlay();
    setState(() => _phase = _Phase.over);
  }

  void _endPlay() {
    InterferenceProfile.releaseAmbient(this);
    _timer?.cancel();
    _stopPlayback();
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    _touchDit = _touchDah = false;
  }

  void _toLobby() {
    _endPlay();
    setState(() => _phase = _Phase.lobby);
  }

  // ── Caller playback ──────────────────────────────────────────────────────
  // The active caller loops in CW (a gap of a word space plus 3 dits between
  // plays) at the player's speed, a little below the sidetone pitch. Keying a
  // response stops it; it resumes once the input is clear again.

  void _managePlayback(int now) {
    final cur = _engine.current;
    if (cur == null || _engine.attackMode) {
      _loaded = null;
      return;
    }
    if (!identical(cur, _loaded)) {   // a fresh caller: start from play count 0
      _loaded = cur;
      _plays = 0;
      _nextPlayAt = now;
      _input = '';
      _stopPlayback();
    }
    if (_playing != null) {
      if (_typing) _stopPlayback();
      return;
    }
    if (_typing || now - _lastSubmitAt < _submitHoldMs || now < _nextPlayAt) return;
    _playCaller(cur);
  }

  Future<void> _playCaller(PileupCaller cur) async {
    _playing = cur;
    await _genChannel.invokeMethod('setWpm', _keyWpm);
    await _genChannel.invokeMethod('setInterCharSpace', 3);
    await _toneChannel.invokeMethod('setFreq', _attackPitch);
    await _genChannel.invokeMethod('playOne', cur.call);
  }

  void _stopPlayback() {
    if (_playing == null) return;
    _playing = null;
    _genChannel.invokeMethod('stopOne');
    _toneChannel.invokeMethod('setFreq', _pitch);
  }

  void _onGenEvent(dynamic raw) {
    if ((raw as Map)['type'] != 'done' || _playing == null) return;
    _playing = null;
    _toneChannel.invokeMethod('setFreq', _pitch);
    _plays++;
    _nextPlayAt = _now + _ditMs * (_interWord + 3);
  }

  // ── Input ────────────────────────────────────────────────────────────────

  void _onSymbol(dynamic sym) {
    if (_phase != _Phase.playing) return;
    _lastActivity = _now;
    if (_playing != null) _stopPlayback();
    _decoder.add(sym as String);
  }

  void _onDecodedChar(String ch) {
    if (_phase != _Phase.playing) return;
    if (ch == ' ') {
      if (_input.isNotEmpty) _submit();
      return;
    }
    if (ch == '*' || _input.length >= 12) return;
    _input += ch.toUpperCase();
    _lastCharAt = _now;
    setState(() {});
  }

  void _submit() {
    if (_input.isEmpty) return;
    final ev = _engine.submit(_input, _now);
    _input = '';
    _lastCharAt = 0;
    _lastSubmitAt = _now;
    _decoder.reset();
    _react(ev);
    setState(() {});
  }

  void _setTouch({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _lastActivity = _now;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  Future<void> _changeKeyWpm(int delta) async {
    setState(() => _keyWpm = (_keyWpm + delta).clamp(5, 60));
    await _keyerChannel.invokeMethod('setWpm', _keyWpm);
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm', _keyWpm);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
        canPop: _phase != _Phase.playing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toLobby();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, 'Fight the Pileup'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => Navigator.maybePop(context),
            ),
            actions: const [InterferenceButton()],
          ),
          body: !_ready
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : switch (_phase) {
                  _Phase.lobby => _buildLobby(c),
                  _Phase.playing => _buildPlay(c),
                  _Phase.over => _buildOver(c),
                },
        ),
      ),
    );
  }

  TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
      fontFamily: 'CwMono', fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  Widget _buildLobby(AppColors c) {
    final d = pileupDifficulties[_level];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('pu_rules'),
            style: _mono(13, c.textMuted).copyWith(height: 1.45))),
        const SizedBox(height: 16),
        AppCaption(Strings.t('pu_difficulty')),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.chevron_left, color: c.textMuted),
              onPressed: _level > 0 ? () => setState(() => _level--) : null,
            ),
            Expanded(child: Column(children: [
              Text(Strings.t('pu_level_${d.label.toLowerCase()}'),
                  style: _mono(20, c.textPrimary)),
              Text(Strings.t('pu_level_info')
                      .replaceAll('{t}', '${d.callerTimeout ~/ 1000}')
                      .replaceAll('{n}', '${d.initialCallers}')
                      .replaceAll('{d}', '${d.dropsPerLife}'),
                  textAlign: TextAlign.center, style: _mono(11, c.textFaint)),
            ])),
            IconButton(
              icon: Icon(Icons.chevron_right, color: c.textMuted),
              onPressed: _level < pileupDifficulties.length - 1
                  ? () => setState(() => _level++) : null,
            ),
          ]),
        ),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_start'), color: c.accent, onTap: _start),
      ],
    );
  }

  Widget _buildPlay(AppColors c) {
    final cur = _engine.current;
    final d = _engine.difficulty;
    final flashing = _now < _flashUntil;
    final reveal = _plays >= d.playsBeforeReveal;
    final remaining = cur == null
        ? 1.0
        : (1 - (_now - cur.activeSince) / d.callerTimeout).clamp(0.0, 1.0);

    Widget center;
    if (_engine.attackMode) {
      center = Column(children: [
        Text(Strings.t('pu_your_attack'), style: _mono(12, c.accentPurple)),
        const SizedBox(height: 6),
        Text(Strings.t('pu_send'), style: _mono(14, c.accentPurple)),
        const SizedBox(height: 6),
        Text(_engine.attackPrompt, style: _mono(30, c.accentPurple, bold: true)),
      ]);
    } else if (cur == null) {
      center = Text(Strings.t('pu_waiting'), style: _mono(13, c.textFaint));
    } else {
      center = Column(children: [
        Text(Strings.t('pu_defend'), style: _mono(12, c.danger)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: remaining, minHeight: 8,
            backgroundColor: c.surface,
            color: remaining > 0.5 ? c.accent : remaining > 0.25 ? c.warning : c.danger,
          ),
        ),
        const SizedBox(height: 12),
        if (reveal)
          Text(cur.call, style: _mono(30, c.textPrimary, bold: true))
        else
          Text(Strings.t('pu_listen')
                  .replaceAll('{n}', '${min(_plays + 1, d.playsBeforeReveal)}')
                  .replaceAll('{m}', '${d.playsBeforeReveal}'),
              style: _mono(13, c.textFaint)),
        if (_engine.callers.length > 1) ...[
          const SizedBox(height: 8),
          Text(Strings.t('pu_queued').replaceAll('{n}', '${_engine.callers.length - 1}'),
              style: _mono(12, c.textFaint)),
        ],
      ]);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(children: [
          for (var i = 0; i < _engine.lives; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.favorite, size: 18, color: c.danger),
            ),
          const Spacer(),
          if (_engine.streak > 0)
            Text('x${_engine.streak}  ', style: _mono(14, c.warning)),
          Text('${_engine.score}', style: _mono(20, c.accent, bold: true)),
        ]),
      ),
      Divider(color: c.border, height: 1),
      Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 8), child: center),
      SizedBox(
        height: 28,
        child: flashing
            ? Text(_flash, style: _mono(18, _flashColor, bold: true))
            : null,
      ),
      Divider(color: c.border, height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Column(children: [
          Text(Strings.t(_engine.attackMode ? 'pu_key_attack' : 'pu_response'),
              style: _mono(11, _engine.attackMode ? c.accentPurple : c.textFaint)),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: _input.isEmpty
                ? Text(Strings.t('pu_key_hint'), style: _mono(12, c.textFaint))
                : Text(_input, style: _mono(24, c.info, bold: true)),
          ),
          OutlinedButton(
            onPressed: _input.isEmpty ? null : _submit,
            child: Text(Strings.t('pu_submit'), style: _mono(13, c.info)),
          ),
        ]),
      ),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          Text(pileupDifficulties[_level].label, style: _mono(12, c.textMuted)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove, size: 18, color: c.textMuted),
            onPressed: () => _changeKeyWpm(-1),
          ),
          Text('$_keyWpm WPM', style: _mono(12, c.textMuted)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 18, color: c.textMuted),
            onPressed: () => _changeKeyWpm(1),
          ),
        ]),
      ),
      if (_keyerMode == 4)
        StraightKeyPaddle(onDown: () => _setTouch(dit: true), onUp: () => _setTouch(dit: false))
      else
        IambicPaddles(
          onDitDown: () => _setTouch(dit: true), onDitUp: () => _setTouch(dit: false),
          onDahDown: () => _setTouch(dah: true), onDahUp: () => _setTouch(dah: false)),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildOver(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(Strings.t('pu_over'), style: _mono(22, c.danger, bold: true)),
            const SizedBox(height: 12),
            Text('${Strings.t('pu_score')} ${_engine.score}',
                style: _mono(26, c.warning, bold: true)),
            const SizedBox(height: 12),
            Text('${Strings.t('pu_defended')} ${_engine.blocked}   '
                '${Strings.t('pu_dropped')} ${_engine.dropped}',
                style: _mono(14, c.textPrimary)),
            const SizedBox(height: 4),
            Text('${Strings.t('pu_accuracy')} ${_engine.accuracy}%',
                style: _mono(14, _engine.accuracy >= 70 ? c.accent : c.danger)),
            const SizedBox(height: 4),
            Text('${Strings.t('pu_best_streak')} ${_engine.bestStreak}',
                style: _mono(14, c.textPrimary)),
            const SizedBox(height: 8),
            Text('$_keyWpm WPM / ${Strings.t('pu_level_${_engine.difficulty.label.toLowerCase()}')}',
                style: _mono(12, c.textFaint)),
          ]),
        ),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('pu_again'), color: c.accent, onTap: _start),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('msl_continue'), color: c.accent, primary: false,
            onTap: () => setState(() => _phase = _Phase.lobby)),
      ],
    );
  }
}
