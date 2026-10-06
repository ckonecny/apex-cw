// Memory Chain — grow-a-chain keying memory game, ported from
// MorseMemoryChain.cpp.
//
// One new character per round, shown on screen or sounded in CW; the player
// keys the whole growing chain from memory, untimed. A row of boxes is the
// only feedback (grey = pending, yellow frame = next, green = correct, red
// with the correct character = the tolerated error). Two content modes:
// Characters (random from the Koch lesson, one tolerated error per round,
// the second error in a round ends the game) and Call Signs (one random call
// is the chain, revealed letter by letter, call after call, no tolerated
// error). Separate high-score tables per mode.
import 'widgets/interference_button.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/cw_content.dart';
import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/paddle_widgets.dart';

// Same values as the firmware.
const _perRow = 12;                    // a call (max 12 chars) always fits one row
const _rows = 4;
const _maxChain = _perRow * _rows;     // 48 — beyond human memory
const _roundPauseMs = 600;             // full-green row stays visible this long
const _callPauseMs = 900;              // completed call (letters revealed)
const _hiN = 7;

enum _Phase { lobby, playing, over, hiscores }

// One high-score row. Characters: primary = completed chain length,
// secondary = boxes reached in the failed round; Calls: primary = completed
// calls, secondary = letters banked in the failed call.
class _Score {
  final int primary, secondary, errs, koch, prompt;
  const _Score(this.primary, this.secondary, this.errs, this.koch, this.prompt);
  Map<String, int> toJson() =>
      {'p': primary, 's': secondary, 'e': errs, 'k': koch, 'm': prompt};
  static _Score fromJson(Map m) => _Score(m['p'], m['s'], m['e'], m['k'], m['m']);
}

class MemoryChainScreen extends StatefulWidget {
  const MemoryChainScreen({super.key});

  @override
  State<MemoryChainScreen> createState() => _MemoryChainScreenState();
}

class _MemoryChainScreenState extends State<MemoryChainScreen>
    with WidgetsBindingObserver {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _hiKeys = ['memChainHi', 'memChainHiCalls'];

  // Character -> dit/dah pattern; the prompt goes out as an exact pattern,
  // never through playWord()'s text parsing.
  static final _patterns = {
    for (final e in MorseDecoder.table.entries)
      if (e.value.length == 1) e.value: e.key,
  };

  final _random = Random();
  late final MorseDecoder _decoder;
  StreamSubscription? _genSub, _symbolSub;
  int _gen = 0;   // bumped on leaving play; stale delayed steps check it

  bool _ready = false;
  _Phase _phase = _Phase.lobby;

  // Settings
  bool _callsMode = false;   // persisted (firmware "mcopt" bit 0)
  bool _soundPrompt = false; // persisted (firmware "mcopt" bit 1)
  List<String> _kochSeq = kochSeqM32;
  int _koch = 10;            // lesson for this visit only
  int _keyWpm = 20;          // player's keyer speed = prompt speed (firmware wpm=0)
  int _keyerMode = 0;
  int _pitch = 600;
  int _toneShift = 1;        // firmware posEchoToneShift, applied to the prompt
  int _callRegion = 0;
  bool _callCommon = false;
  final List<List<_Score>> _hi = [[], []];
  int _lastRank = -1;

  // Game. In Characters mode _chain holds random Koch-set characters; in
  // Call Signs mode it is the revealed-so-far prefix of _call.
  List<String> _pool = [];
  final List<String> _chain = [];
  int _pos = 0;              // next chain index to key this round
  int _errPos = -1;          // Characters: tolerated error this round
  int _totalErrs = 0;
  bool _promptShown = false; // Display prompt still on screen
  String _call = '';
  int _callsDone = 0;
  int _deathPos = -1;        // fatal error position (-1 = perfect game)
  bool _callComplete = false;
  bool _busy = false;        // prompt playing or pause: input is ignored
  bool _promptPlaying = false;
  _Score? _result;
  final List<String> _callBuffer = [];

  bool _touchDit = false, _touchDah = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('game');
    WidgetsBinding.instance.addObserver(this);
    _decoder = MorseDecoder(onChar: _onDecodedChar, unknown: '*');
    _load();
  }

  @override
  void dispose() {
    InterferenceProfile.releaseAmbient(this);
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    WidgetsBinding.instance.removeObserver(this);
    _gen++;
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stop');
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
    final echo = await TrainingProfile.open(TrainingProfile.echo);
    final custom = p.getString('customKochChars') ?? '';
    _kochSeq = kochSequenceChars((p.getInt('kochSeq') ?? 0).clamp(0, 4),
        custom.isNotEmpty ? custom : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?',
        licwCarouselStart: (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13));
    _koch = (echo.getInt('kochLevel') ?? 5).clamp(2, _kochSeq.length);
    final opt = p.getInt('memChainOpt') ?? 0;
    _callsMode = opt & 1 != 0;
    _soundPrompt = opt & 2 != 0;
    _keyWpm = (p.getInt('wpm') ?? 20).clamp(5, 60);
    _keyerMode = p.getInt('keyerMode') ?? 0;
    _pitch = p.getInt('pitch') ?? 600;
    _toneShift = (p.getInt('toneShift') ?? 1).clamp(0, 2);
    _callRegion = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
    _callCommon = p.getBool('callCommonOnly') ?? false;
    for (var m = 0; m < 2; m++) {
      _hi[m] = _loadHi(p, _hiKeys[m]);
    }

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
    await _keyerChannel.invokeMethod('setInterWordSpace',
        (p.getInt('profile.keyer.interWordSpace') ??
            TrainingProfile.defaultInterWord(TrainingProfile.keyer)).clamp(6, 105));
    await _keyerChannel.invokeMethod('stop');

    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    _symbolSub = _symbolStream.receiveBroadcastStream().listen(_onSymbol);
    if (mounted) setState(() => _ready = true);
  }

  List<_Score> _loadHi(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((m) => _Score.fromJson(m as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('memChainOpt', (_callsMode ? 1 : 0) | (_soundPrompt ? 2 : 0));
  }

  // ── Content ──────────────────────────────────────────────────────────────

  // Characters mode pool: the Koch lesson set minus prosigns (a prosign has
  // no single glyph that fits a box).
  List<String> _buildPool() {
    final pool = [
      for (final c in kochActiveChars(_koch, _kochSeq))
        if (c.length == 1 && _patterns.containsKey(c.toUpperCase())) c.toUpperCase(),
    ];
    return pool.isEmpty ? ['E', 'I', 'S', 'H', '5'] : pool;
  }

  // Append one random pool character, avoiding an immediate repeat (a doubled
  // letter is indistinguishable from an echo when the prompt is sounded).
  // False when the chain is at its cap — a "perfect game".
  bool _growChain() {
    if (_chain.length >= _maxChain) return false;
    String c;
    do {
      c = _pool[_random.nextInt(_pool.length)];
    } while (_pool.length > 1 && _chain.isNotEmpty && c == _chain.last);
    _chain.add(c);
    return true;
  }

  // Call Signs mode: firmware getRandomCall(0), honouring the call-sign
  // preferences; prefetched so a new call never waits on the channel.
  Future<void> _refillCalls() async {
    while (_callBuffer.length < 3) {
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

  void _newCall() {
    if (_callBuffer.isNotEmpty) {
      _call = _callBuffer.removeAt(0);
    } else {
      const l = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      String r() => l[_random.nextInt(26)];
      _call = 'D${r()}${_random.nextInt(10)}${r()}${r()}${r()}';
    }
    if (_call.length > _perRow) _call = _call.substring(0, _perRow);
    _refillCalls();
    _chain.clear();
  }

  // ── Game flow ────────────────────────────────────────────────────────────

  Future<void> _startGame() async {
    _chain.clear();
    _pos = 0;
    _errPos = -1;
    _totalErrs = 0;
    _callsDone = 0;
    _deathPos = -1;
    _lastRank = -1;
    _callComplete = false;
    if (_callsMode) {
      await _refillCalls();
      _newCall();
    } else {
      _pool = _buildPool();
    }
    if (!mounted) return;
    // The noise stands for the whole game, until it is over.
    InterferenceProfile.requestAmbient(this);
    setState(() => _phase = _Phase.playing);
    _startRound();
  }

  // Grow the chain by one, present the newest character, arm the round.
  void _startRound() {
    if (_callsMode) {
      _chain.add(_call[_chain.length]);
    } else if (!_growChain()) {
      _deathPos = -1;
      _gameOver();
      return;
    }
    _pos = 0;
    _errPos = -1;
    _callComplete = false;
    _promptShown = !_soundPrompt;
    _decoder.reset();
    setState(() {});
    if (_soundPrompt) {
      _playPrompt(_chain.last);
    } else {
      _busy = false;
      _keyerChannel.invokeMethod('start');
    }
  }

  int get _promptPitch => switch (_toneShift) {
        1 => (_pitch * 18 / 17).round(),
        2 => (_pitch * 17 / 18).round(),
        _ => _pitch,
      };

  // The prompt plays at the player's keyer speed with the Echo Trainer's
  // half-tone shift; the keyer is off meanwhile (it shares the sidetone),
  // so nothing keyed during playback can leak into the round.
  Future<void> _playPrompt(String ch) async {
    _busy = true;
    _promptPlaying = true;
    await _keyerChannel.invokeMethod('stop');
    await _genChannel.invokeMethod('setWpm', _keyWpm);
    await _genChannel.invokeMethod('setInterCharSpace', 3);
    await _toneChannel.invokeMethod('setFreq', _promptPitch);
    await _genChannel.invokeMethod('playPatterns', [_patterns[ch] ?? '']);
  }

  void _onGenEvent(dynamic raw) {
    if ((raw as Map)['type'] != 'done' || !_promptPlaying) return;
    _promptPlaying = false;
    _toneChannel.invokeMethod('setFreq', _pitch);
    if (_phase != _Phase.playing) return;
    _decoder.reset();
    _busy = false;
    _keyerChannel.invokeMethod('start');
  }

  void _onSymbol(dynamic sym) {
    if (_phase != _Phase.playing || _busy) return;
    _decoder.add(sym as String);
  }

  void _onDecodedChar(String ch) {
    if (_phase != _Phase.playing || _busy) return;
    if (ch == ' ') return;             // word gap — not an answer
    _handleAnswer(ch);
  }

  // One keyed character, judged against the chain. Deliberately no OK/ERR
  // sounds (firmware): the boxes are the only feedback.
  void _handleAnswer(String c) {
    _promptShown = false;
    if (c == _chain[_pos]) {
      _pos++;
      if (_pos == _chain.length) {
        _roundDone();
      } else {
        setState(() {});
      }
      return;
    }
    if (!_callsMode && _errPos < 0) {  // the one tolerated error per round
      _errPos = _pos;
      _totalErrs++;
      _pos++;
      if (_pos == _chain.length) {
        _roundDone();
      } else {
        setState(() {});
      }
      return;
    }
    _deathPos = _pos;                  // second error (Characters) or any (Calls)
    _gameOver();
  }

  // The row is fully resolved: pause on it, then grow (and in Call Signs
  // mode bank a completed call and start a fresh one).
  Future<void> _roundDone() async {
    final g = _gen;
    _busy = true;
    _keyerChannel.invokeMethod('stop');
    setState(() {});
    await Future.delayed(const Duration(milliseconds: _roundPauseMs));
    if (!mounted || g != _gen) return;
    if (_callsMode && _chain.length == _call.length) {
      _callsDone++;
      setState(() => _callComplete = true);
      await Future.delayed(const Duration(milliseconds: _callPauseMs));
      if (!mounted || g != _gen) return;
      _newCall();
    }
    _startRound();
  }

  void _gameOver() {
    _endPlay();
    final int m = _callsMode ? 1 : 0;
    final _Score s;
    if (_callsMode) {
      s = _Score(_callsDone, max(0, _chain.length - 1), 0, 0, _soundPrompt ? 1 : 0);
    } else {
      final win = _deathPos < 0;
      s = _Score(win ? _chain.length : _chain.length - 1, win ? 0 : _pos, _totalErrs,
          _koch, _soundPrompt ? 1 : 0);
    }
    _result = s;
    _lastRank = _recordScore(m, s);
    setState(() => _phase = _Phase.over);
  }

  // Insert if it qualifies (rank by primary, then secondary); an all-zero
  // score never displaces an empty slot.
  int _recordScore(int m, _Score s) {
    if (s.primary == 0 && s.secondary == 0) return -1;
    final t = _hi[m];
    for (var i = 0; i < _hiN; i++) {
      if (i >= t.length || s.primary > t[i].primary ||
          (s.primary == t[i].primary && s.secondary > t[i].secondary)) {
        t.insert(i, s);
        if (t.length > _hiN) t.removeLast();
        SharedPreferences.getInstance().then((p) =>
            p.setString(_hiKeys[m], jsonEncode(t.map((e) => e.toJson()).toList())));
        return i;
      }
    }
    return -1;
  }

  void _endPlay() {
    InterferenceProfile.releaseAmbient(this);
    _gen++;
    _busy = false;
    if (_promptPlaying) {
      _promptPlaying = false;
      _genChannel.invokeMethod('stop');
      _toneChannel.invokeMethod('setFreq', _pitch);
    }
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    _touchDit = _touchDah = false;
  }

  void _toLobby() {
    _endPlay();
    setState(() => _phase = _Phase.lobby);
  }

  // ── Touch paddles ────────────────────────────────────────────────────────

  void _setTouch({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
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
        canPop: _phase == _Phase.lobby,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toLobby();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, 'Memory Chain'),
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
                  _Phase.hiscores => _buildHiscores(c),
                },
        ),
      ),
    );
  }

  TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
      fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  TextStyle _morse(double size, Color color, {bool bold = false}) => TextStyle(
      fontFamily: 'CwMono', fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  Widget _chips(AppColors c, List<String> labels, int selected, ValueChanged<int> onSel) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < labels.length; i++)
          ChoiceChip(
            label: Text(labels[i], style: _mono(13, i == selected ? c.accent : c.textMuted)),
            selected: i == selected,
            showCheckmark: false,
            selectedColor: c.accent.withValues(alpha: 0.18),
            backgroundColor: c.surface,
            side: BorderSide.none,
            onSelected: (_) => onSel(i),
          ),
      ]);

  Widget _buildLobby(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('mc_rules'),
            style: _mono(13, c.textMuted).copyWith(height: 1.45))),
        const SizedBox(height: 16),
        AppCaption(Strings.t('mc_mode')),
        const SizedBox(height: 8),
        _chips(c, [Strings.t('mc_mode_chars'), Strings.t('mc_mode_calls')],
            _callsMode ? 1 : 0, (i) {
          setState(() => _callsMode = i == 1);
          _saveSettings();
        }),
        const SizedBox(height: 16),
        AppCaption(Strings.t('mc_prompt')),
        const SizedBox(height: 8),
        _chips(c, [Strings.t('opt_display'), Strings.t('opt_sound')],
            _soundPrompt ? 1 : 0, (i) {
          setState(() => _soundPrompt = i == 1);
          _saveSettings();
        }),
        if (!_callsMode) ...[
          const SizedBox(height: 16),
          AppCaption(Strings.t('msl_koch')),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.remove, color: c.textMuted),
                onPressed: _koch > 2 ? () => setState(() => _koch--) : null,
              ),
              Expanded(child: Column(children: [
                Text('$_koch', style: _mono(22, c.textPrimary)),
                Text(kochActiveChars(_koch, _kochSeq).join(' '),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: _morse(11, c.textFaint)),
              ])),
              IconButton(
                icon: Icon(Icons.add, color: c.textMuted),
                onPressed: _koch < _kochSeq.length ? () => setState(() => _koch++) : null,
              ),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_start'), color: c.accent, onTap: _startGame),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('msl_hiscores'), color: c.accent, primary: false,
            onTap: () => setState(() { _lastRank = -1; _phase = _Phase.hiscores; })),
      ],
    );
  }

  Widget _buildPlay(AppColors c) {
    final count = _callsMode
        ? '${Strings.t('mc_calls')}: $_callsDone'
        : '${Strings.t('mc_chain')}: ${_chain.length}';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Row(children: [
          Text(count, style: _mono(16, _callComplete ? c.accent : c.textPrimary)),
          const Spacer(),
          if (!_callsMode && _totalErrs > 0)
            Text('${Strings.t('mc_err')} $_totalErrs', style: _mono(14, c.danger)),
        ]),
      ),
      SizedBox(
        height: 96 * textScaleOf(context),
        child: Center(
          child: _promptShown && _chain.isNotEmpty
              ? Text(_chain.last, style: _morse(64, c.warning, bold: true))
              : _promptPlaying
                  ? Icon(Icons.volume_up, size: 40, color: c.info)
                  : null,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _boxGrid(c, _callComplete ? _playCompleteBoxes(c) : _playBoxes(c)),
      ),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          if (!_callsMode) Text('Koch $_koch', style: _mono(12, c.textMuted)),
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

  // A box spec: frame, fill, letter (null = empty), letter colour.
  (Color, Color, String?, Color) _spec(Color frame, Color fill, String? ch, Color fg) =>
      (frame, fill, ch, fg);

  // During play: green = keyed correctly (kept empty — the row must not
  // become a crib sheet), red with the correct character = the tolerated
  // error, yellow frame = current position, grey = pending.
  List<(Color, Color, String?, Color)> _playBoxes(AppColors c) => [
        for (var i = 0; i < _chain.length; i++)
          if (i == _errPos)
            _spec(c.danger, c.danger, _chain[i], Colors.white)
          else if (i < _pos)
            _spec(c.accent, c.accent, null, c.background)
          else if (i == _pos)
            _spec(c.warning, c.surface, null, c.textPrimary)
          else
            _spec(c.border, c.surface, null, c.textPrimary),
      ];

  // A just-completed call, letters revealed (the player earned the look).
  List<(Color, Color, String?, Color)> _playCompleteBoxes(AppColors c) => [
        for (var i = 0; i < _call.length; i++)
          _spec(c.accent, c.accent, _call[i], c.background),
      ];

  // Game-over reveal: every character visible, the fatal position (and a
  // tolerated error of the final round) red; in Call Signs mode the not yet
  // revealed rest of the call is dimmed.
  List<(Color, Color, String?, Color)> _revealBoxes(AppColors c) {
    final total = _callsMode ? _call.length : _chain.length;
    return [
      for (var i = 0; i < total; i++)
        if (i == _deathPos || i == _errPos)
          _spec(c.danger, c.danger, _callsMode ? _call[i] : _chain[i], Colors.white)
        else if (i < _pos)
          _spec(c.accent, c.accent, _callsMode ? _call[i] : _chain[i], c.background)
        else if (i < _chain.length)
          _spec(c.border, c.surface, _callsMode ? _call[i] : _chain[i], c.textPrimary)
        else
          _spec(c.border, c.surface, _call[i], c.textFaint),
    ];
  }

  Widget _boxGrid(AppColors c, List<(Color, Color, String?, Color)> boxes) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 5.0;
      final w = min(34.0, (box.maxWidth - (_perRow - 1) * gap) / _perRow);
      final rows = <Widget>[];
      for (var r = 0; r * _perRow < boxes.length; r++) {
        final slice = boxes.skip(r * _perRow).take(_perRow).toList();
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(children: [
            for (var i = 0; i < slice.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Container(
                width: w, height: w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: slice[i].$2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: slice[i].$1, width: 2),
                ),
                child: slice[i].$3 == null
                    ? null
                    : Text(slice[i].$3!, style: _morse(w * 0.5, slice[i].$4, bold: true)),
              ),
            ],
          ]),
        ));
      }
      return SizedBox(
        width: _perRow * w + (_perRow - 1) * gap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      );
    });
  }

  String _promptLabel(int p) => Strings.t(p == 1 ? 'opt_sound' : 'opt_display');

  Widget _buildOver(AppColors c) {
    final s = _result!;
    final win = !_callsMode && _deathPos < 0;
    final line = _callsMode
        ? '${Strings.t('mc_calls')} ${s.primary}  +${s.secondary}    ${_promptLabel(s.prompt)}'
        : '${Strings.t('mc_chain')} ${s.primary}    ${Strings.t('mc_err')} ${s.errs}    '
            'Koch ${s.koch}    ${_promptLabel(s.prompt)}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(Strings.t(win ? 'mc_perfect' : 'msl_game_over'),
                style: _mono(20, win ? c.accent : c.danger, bold: true)),
            const SizedBox(height: 12),
            Text(line, textAlign: TextAlign.center, style: _mono(14, c.textPrimary)),
            if (_lastRank >= 0) ...[
              const SizedBox(height: 12),
              Text(Strings.t('msl_new_hi').replaceAll('{r}', '${_lastRank + 1}'),
                  style: _mono(15, c.accent, bold: true)),
            ],
            const SizedBox(height: 18),
            _boxGrid(c, _revealBoxes(c)),
          ]),
        ),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_hiscores'), color: c.accent,
            onTap: () => setState(() => _phase = _Phase.hiscores)),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('msl_continue'), color: c.accent, primary: false,
            onTap: () => setState(() => _phase = _Phase.lobby)),
      ],
    );
  }

  Widget _buildHiscores(AppColors c) {
    final m = _callsMode ? 1 : 0;
    Widget row(List<String> cells, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 28, child: Text(cells[0], style: _mono(13, color))),
        for (var i = 1; i < cells.length; i++)
          Expanded(child: Text(cells[i], style: _mono(13, color))),
      ]),
    );
    final head = m == 1
        ? ['#', Strings.t('mc_calls'), '+${Strings.t('mc_letters')}', Strings.t('mc_prompt')]
        : ['#', Strings.t('mc_chain'), Strings.t('mc_err'), 'Koch', Strings.t('mc_prompt')];
    final t = _hi[m];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCaption('${Strings.t('msl_hiscores')} – '
            '${Strings.t(m == 1 ? 'mc_mode_calls' : 'mc_mode_chars')}'),
        const SizedBox(height: 8),
        AppCard(child: Column(children: [
          row(head, c.textMuted),
          Divider(color: c.border, height: 12),
          if (t.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(Strings.t('msl_no_scores'), style: _mono(13, c.textFaint)),
            ),
          for (var i = 0; i < t.length; i++)
            row([
              '${i + 1}', '${t[i].primary}',
              if (m == 1) '+${t[i].secondary}' else '${t[i].errs}',
              if (m == 0) 'K${t[i].koch}',
              _promptLabel(t[i].prompt),
            ], i == _lastRank ? c.accent : c.textPrimary),
        ])),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_continue'), color: c.accent,
            onTap: () => setState(() => _phase = _Phase.lobby)),
      ],
    );
  }
}
