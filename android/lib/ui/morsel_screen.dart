// Morsel — word-guessing game, ported from MorseMorsel.cpp (single player;
// the ESP-NOW multiplayer part has no phone counterpart).
//
// A hidden word is played in CW, one letter is shown in clear text. The
// player keys the whole word; a pause of one word gap submits it, the <err>
// prosign deletes the last letter. A wrong guess replays the word 5 WPM
// slower (48 down to 18). Ten words per game; the score is the total time
// plus 5 s per guess and 60 s per skipped word.
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
import '../util/keep_screen_on.dart';
import 'widgets/app_ui.dart';
import 'widgets/paddle_widgets.dart';

// Tunables, same values as the firmware's S1 block.
const _startWpmDefault = 48; // clue speed in round 1 (firmware: fixed)
const _wpmStep = 5;          // clue slows this much per round
const _minWpm = 18;          // clue speed floor (round 7+)
const _startWpmMin = 10;     // lowest selectable start speed (app only)
const _minPool = 6;          // minimum eligible words to start
const _hiN = 7;              // high-score table size
const _feedbackMs = 1500;    // coloured result after a wrong guess
const _correctMs = 1100;     // all-green "solved"
const _idleReplayMs = 12000; // no input this long -> replay the clue
const _idleExitMs = 60000;   // total idle this long -> back to the lobby
const _gameWords = 10;       // words per game
const _guessPenaltyS = 5;    // seconds added per guess
const _skipPenaltyS = 60;    // flat seconds added for a skipped word
const _skipMs = 900;         // how long "Skipped" is shown

// Word length options: "max N" = any length 3..N, otherwise exactly N.
const _wlenMin = [3, 4, 3, 5, 3, 6, 3];
const _wlenMax = [3, 4, 4, 5, 5, 6, 6];
const _wlenLabel = ['3', '4', 'max 4', '5', 'max 5', '6', 'max 6'];
// Suggested minimum Koch lesson per word length (index by length).
const _recKoch = [0, 0, 0, 8, 10, 14, 16];

enum _Phase { lobby, playing, results, hiscores }
enum _Cell { neutral, green, red, grey }

class _Score {
  final int adjMs, guesses, wlen, koch, solved, total, startWpm;
  const _Score(this.adjMs, this.guesses, this.wlen, this.koch, this.solved, this.total,
      this.startWpm);
  Map<String, int> toJson() => {'t': adjMs, 'g': guesses, 'w': wlen, 'k': koch,
      's': solved, 'n': total, 'c': startWpm};
  static _Score fromJson(Map m) => _Score(m['t'], m['g'], m['w'], m['k'], m['s'], m['n'],
      m['c'] ?? _startWpmDefault);
}

class MorselScreen extends StatefulWidget {
  const MorselScreen({super.key});

  @override
  State<MorselScreen> createState() => _MorselScreenState();
}

class _MorselScreenState extends State<MorselScreen> {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  // Letter -> dit/dah pattern. The clue goes out as exact patterns, not
  // text, so it never depends on playWord()'s prosign parsing.
  static final _patterns = {
    for (final e in MorseDecoder.table.entries)
      if (e.value.length == 1) e.value: e.key,
  };

  final _random = Random();
  late final MorseDecoder _decoder;
  StreamSubscription? _genSub, _symbolSub;
  Timer? _submitTimer, _idleTimer;
  int _gen = 0;   // bumped on leaving play; stale delayed steps check it

  bool _ready = false;
  _Phase _phase = _Phase.lobby;
  bool _poolWarning = false;

  // Settings
  List<String> _words = [], _abbrevs = [];
  List<String> _kochSeq = kochSeqM32;
  int _koch = 10;           // lesson for this visit only (firmware restores it on exit)
  int _wlenOpt = 1;         // persisted
  int _startWpm = _startWpmDefault;  // clue speed in round 1, persisted
  int _keyWpm = 20;         // player's own keyer speed (global 'wpm')
  int _keyerMode = 0;
  int _wordGapDits = 7;     // keyer word gap, for the submit pause
  int _pitch = 600;
  List<_Score> _hi = [];
  int _lastRank = -1;

  // Game
  List<String> _pool = [];
  List<String> _game = [];
  int _wordIndex = 0, _totalAdjMs = 0, _totalGuesses = 0, _solved = 0, _skipped = 0;
  int _gameKoch = 0, _gameWlen = 0, _gameStartWpm = _startWpmDefault;

  // Round
  String _target = '';
  int _reveal = 0;
  final List<String> _guess = [];
  bool _evaluated = false;
  List<_Cell> _cells = [];
  int _roundNo = 1;
  int _clueWpm = _startWpmDefault;
  DateTime _wordStart = DateTime.now();
  String _status = '';
  bool _cluePlaying = false, _clueDone = false;
  DateTime _idleSince = DateTime.now();
  DateTime _nextReplayAt = DateTime.now();

  bool _touchDit = false, _touchDah = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _decoder = MorseDecoder(onChar: _onDecodedChar);
    _load();
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _gen++;
    _submitTimer?.cancel();
    _idleTimer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stop');
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final echo = await TrainingProfile.open(TrainingProfile.echo);
    final lists = await _genChannel.invokeMethod('getWordLists') as Map;
    final custom = p.getString('customKochChars') ?? '';
    _kochSeq = kochSequenceChars((p.getInt('kochSeq') ?? 0).clamp(0, 4),
        custom.isNotEmpty ? custom : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?',
        licwCarouselStart: (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13));
    _words = List<String>.from(lists['words']);
    _abbrevs = List<String>.from(lists['abbrevs']);
    _koch = (echo.getInt('kochLevel') ?? 5).clamp(2, _kochSeq.length);
    _wlenOpt = (p.getInt('morselWlen') ?? 1).clamp(0, _wlenLabel.length - 1);
    _startWpm = (p.getInt('morselStartWpm') ?? _startWpmDefault)
        .clamp(_startWpmMin, _startWpmDefault);
    _keyWpm = (p.getInt('wpm') ?? 20).clamp(5, 60);
    _keyerMode = p.getInt('keyerMode') ?? 0;
    _wordGapDits = (p.getInt('profile.keyer.interWordSpace') ??
        TrainingProfile.defaultInterWord(TrainingProfile.keyer)).clamp(6, 105);
    _pitch = p.getInt('pitch') ?? 600;
    _hi = _loadHi(p);

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
    await _keyerChannel.invokeMethod('setInterWordSpace', _wordGapDits);

    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    _symbolSub = _symbolStream.receiveBroadcastStream().listen(_onSymbol);
    if (mounted) setState(() => _ready = true);
  }

  List<_Score> _loadHi(SharedPreferences p) {
    try {
      final raw = p.getString('morselHi');
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((m) => _Score.fromJson(m as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveHi() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('morselHi', jsonEncode(_hi.map((s) => s.toJson()).toList()));
  }

  // ── Word pool ────────────────────────────────────────────────────────────

  // Words and abbreviations of the chosen lengths whose letters are all in
  // the Koch lesson. Only letters and digits: those are all a guess can hold.
  List<String> _buildPool() {
    final set = kochActiveChars(_koch, _kochSeq).map((c) => c.toUpperCase()).toSet();
    final minL = _wlenMin[_wlenOpt], maxL = _wlenMax[_wlenOpt];
    final alnum = RegExp(r'^[A-Z0-9]+$');
    return [
      for (final w in [..._words, ..._abbrevs])
        if (w.length >= minL && w.length <= maxL && alnum.hasMatch(w) &&
            w.split('').every(set.contains))
          w,
    ];
  }

  // ── Game flow ────────────────────────────────────────────────────────────

  void _startGame() {
    _pool = _buildPool();
    if (_pool.length < _minPool) {
      setState(() => _poolWarning = true);
      return;
    }
    _pool.shuffle(_random);
    _game = _pool.take(_gameWords).toList();
    _wordIndex = 0;
    _totalAdjMs = 0;
    _totalGuesses = 0;
    _solved = 0;
    _skipped = 0;
    _gameKoch = _koch;
    _gameWlen = _wlenOpt;
    _gameStartWpm = _startWpm;
    _lastRank = -1;
    _poolWarning = false;
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _idleTick());
    setState(() => _phase = _Phase.playing);
    _startRound();
  }

  void _startRound() {
    _target = _game[_wordIndex].toUpperCase();
    _reveal = _random.nextInt(_target.length);
    _guess.clear();
    _evaluated = false;
    _cells = List.filled(_target.length, _Cell.neutral);
    _roundNo = 1;
    _clueWpm = _clueWpmForRound(1);
    _wordStart = DateTime.now();
    _status = Strings.t('msl_listen');
    setState(() {});
    _playClue();
    _noteActivity();
  }

  // Firmware schedule, shifted by the start speed; a start below the floor
  // simply stays there.
  int get _floorWpm => min(_minWpm, _startWpm);
  int _clueWpmForRound(int r) => max(_floorWpm, _startWpm - (r - 1) * _wpmStep);

  // The clue plays at its own speed with standard spacing; the keyer is
  // off meanwhile (it shares the sidetone) and starts when the clue ends.
  Future<void> _playClue() async {
    _submitTimer?.cancel();
    _decoder.reset();
    _cluePlaying = true;
    _clueDone = false;
    await _keyerChannel.invokeMethod('stop');
    await _genChannel.invokeMethod('setWpm', _clueWpm);
    await _genChannel.invokeMethod('setInterCharSpace', 3);
    await _toneChannel.invokeMethod('setFreq', _pitch);
    await _genChannel.invokeMethod('playPatterns',
        [for (final ch in _target.split('')) _patterns[ch] ?? '']);
  }

  void _onGenEvent(dynamic raw) {
    if ((raw as Map)['type'] != 'done' || !_cluePlaying) return;
    _cluePlaying = false;
    _clueDone = true;
    _nextReplayAt = DateTime.now().add(const Duration(milliseconds: _idleReplayMs));
    if (_phase == _Phase.playing && !_evaluated) _keyerChannel.invokeMethod('start');
  }

  void _noteActivity() {
    _idleSince = DateTime.now();
    _nextReplayAt = _idleSince.add(const Duration(milliseconds: _idleReplayMs));
  }

  // Idle handling (quality of life, no penalty): replay the clue after a
  // spell without input, go back to the lobby after a long one.
  void _idleTick() {
    if (_phase != _Phase.playing || _evaluated || _guess.isNotEmpty ||
        !_clueDone || _cluePlaying || _touchDit || _touchDah) return;
    final now = DateTime.now();
    if (now.difference(_idleSince).inMilliseconds > _idleExitMs) {
      _toLobby();
    } else if (!now.isBefore(_nextReplayAt)) {
      _nextReplayAt = now.add(const Duration(milliseconds: _idleReplayMs));
      _playClue();
    }
  }

  void _onSymbol(dynamic sym) {
    if (_phase != _Phase.playing || _evaluated) return;
    _noteActivity();
    if (sym == '·' || sym == '—') _submitTimer?.cancel();
    _decoder.add(sym as String);
  }

  void _onDecodedChar(String ch) {
    if (_phase != _Phase.playing || _evaluated) return;
    if (ch == MorseDecoder.err) {              // <err> = backspace
      if (_guess.isNotEmpty) _guess.removeLast();
    } else if (RegExp(r'^[A-Z0-9]$').hasMatch(ch)) {
      if (_guess.length < _target.length) _guess.add(ch);
    } else {
      return;                                  // other prosigns are ignored
    }
    setState(() {});
    _armSubmit();
  }

  // A word-gap pause submits, but only once the entry is full length, so
  // correcting with <err> never submits early.
  void _armSubmit() {
    _submitTimer?.cancel();
    if (_guess.length != _target.length) return;
    final ditMs = 1200 / _keyWpm;
    final gapMs = max(1200, ((_wordGapDits + 1) * ditMs).round());
    _submitTimer = Timer(Duration(milliseconds: gapMs), () {
      if (_touchDit || _touchDah) { _armSubmit(); return; }
      _submit();
    });
  }

  Future<void> _submit() async {
    if (_phase != _Phase.playing || _evaluated) return;
    final g = _gen;
    await _keyerChannel.invokeMethod('stop');
    var allRight = true;
    for (var i = 0; i < _target.length; i++) {
      final right = i < _guess.length && _guess[i] == _target[i];
      _cells[i] = right ? _Cell.green : (i == _reveal ? _Cell.grey : _Cell.red);
      if (!right) allRight = false;
    }
    _evaluated = true;
    if (allRight) {
      final secs = DateTime.now().difference(_wordStart).inMilliseconds / 1000;
      _status = '${Strings.t('msl_correct')}  ${secs.toStringAsFixed(1)} s  '
          '$_roundNo ${Strings.t(_roundNo == 1 ? 'msl_try' : 'msl_tries')}';
    } else {
      _status = Strings.t('msl_again');
    }
    setState(() {});
    await Future.delayed(Duration(milliseconds: allRight ? _correctMs : _feedbackMs));
    if (!mounted || g != _gen) return;
    if (allRight) {
      _finishWord(skipped: false);
    } else {
      // Same word: next round, the clue replays slower.
      _roundNo++;
      _clueWpm = _clueWpmForRound(_roundNo);
      _guess.clear();
      _evaluated = false;
      _cells = List.filled(_target.length, _Cell.neutral);
      _status = Strings.t('msl_listen');
      setState(() {});
      _playClue();
      _noteActivity();
    }
  }

  Future<void> _skip() async {
    if (_phase != _Phase.playing || _evaluated) return;
    final g = _gen;
    _submitTimer?.cancel();
    _cluePlaying = false;
    await _genChannel.invokeMethod('stop');
    await _keyerChannel.invokeMethod('stop');
    setState(() {
      _evaluated = true;
      _status = Strings.t('msl_skipped_note').replaceAll('{s}', '$_skipPenaltyS');
    });
    await Future.delayed(const Duration(milliseconds: _skipMs));
    if (!mounted || g != _gen) return;
    _finishWord(skipped: true);
  }

  // Adds the word to the running score (time since the first clue, +5 s per
  // guess, +60 s if skipped), then the next word or the results.
  void _finishWord({required bool skipped}) {
    final raw = DateTime.now().difference(_wordStart).inMilliseconds;
    final guesses = skipped ? _roundNo - 1 : _roundNo;
    _totalAdjMs += raw + guesses * _guessPenaltyS * 1000 +
        (skipped ? _skipPenaltyS * 1000 : 0);
    _totalGuesses += guesses;
    if (skipped) _skipped++; else _solved++;
    _wordIndex++;
    if (_wordIndex >= _game.length) {
      _endPlay();
      _recordScore();
      setState(() => _phase = _Phase.results);
    } else {
      _startRound();
    }
  }

  void _recordScore() {
    final s = _Score(_totalAdjMs, _totalGuesses, _gameWlen, _gameKoch, _solved,
        _game.length, _gameStartWpm);
    _lastRank = -1;
    for (var i = 0; i < _hiN; i++) {
      if (i >= _hi.length || s.adjMs < _hi[i].adjMs) {
        _hi.insert(i, s);
        if (_hi.length > _hiN) _hi.removeLast();
        _lastRank = i;
        _saveHi();
        return;
      }
    }
  }

  void _endPlay() {
    _gen++;
    _submitTimer?.cancel();
    _idleTimer?.cancel();
    _cluePlaying = false;
    _genChannel.invokeMethod('stop');
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
    if (_touchDit || _touchDah) {
      _noteActivity();
      _submitTimer?.cancel();
    }
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
    if (!_touchDit && !_touchDah) _armSubmit();
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
      builder: (context, _, __) => PopScope(
        canPop: _phase == _Phase.lobby,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toLobby();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, 'Morsel'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          body: !_ready
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : switch (_phase) {
                  _Phase.lobby => _buildLobby(c),
                  _Phase.playing => _buildPlay(c),
                  _Phase.results => _buildResults(c),
                  _Phase.hiscores => _buildHiscores(c),
                },
        ),
      ),
    );
  }

  TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
      fontFamily: 'CwMono', fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  Widget _buildLobby(AppColors c) {
    final maxLen = _wlenMax[_wlenOpt];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('msl_rules'),
            style: _mono(13, c.textMuted).copyWith(height: 1.45))),
        const SizedBox(height: 16),
        AppCaption(Strings.t('msl_koch')),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.remove, color: c.textMuted),
              onPressed: _koch > 2 ? () => setState(() {
                _koch--; _poolWarning = false;
              }) : null,
            ),
            Expanded(child: Column(children: [
              Text('$_koch', style: _mono(22, c.textPrimary)),
              Text(kochActiveChars(_koch, _kochSeq).join(' '),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: _mono(11, c.textFaint)),
            ])),
            IconButton(
              icon: Icon(Icons.add, color: c.textMuted),
              onPressed: _koch < _kochSeq.length ? () => setState(() {
                _koch++; _poolWarning = false;
              }) : null,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        AppCaption(Strings.t('msl_start_wpm')),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Row(children: [
            Expanded(child: Slider(
              value: _startWpm.toDouble(),
              min: _startWpmMin.toDouble(), max: _startWpmDefault.toDouble(),
              divisions: _startWpmDefault - _startWpmMin,
              activeColor: c.accent, inactiveColor: c.border,
              onChanged: (v) => setState(() => _startWpm = v.round()),
              onChangeEnd: (v) async {
                final p = await SharedPreferences.getInstance();
                await p.setInt('morselStartWpm', v.round());
              },
            )),
            SizedBox(width: 72, child: Text('$_startWpm WPM', textAlign: TextAlign.right,
                style: _mono(13, c.accent))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(Strings.t('msl_start_wpm_hint')
              .replaceAll('{step}', '$_wpmStep').replaceAll('{min}', '$_floorWpm'),
              style: _mono(11, c.textFaint)),
        ),
        const SizedBox(height: 16),
        AppCaption(Strings.t('msl_wlen')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _wlenLabel.length; i++)
            ChoiceChip(
              label: Text(_wlenLabel[i], style: _mono(13,
                  i == _wlenOpt ? c.accent : c.textMuted)),
              selected: i == _wlenOpt,
              showCheckmark: false,
              selectedColor: c.accent.withOpacity(0.18),
              backgroundColor: c.surface,
              side: BorderSide.none,
              onSelected: (_) async {
                setState(() { _wlenOpt = i; _poolWarning = false; });
                final p = await SharedPreferences.getInstance();
                await p.setInt('morselWlen', i);
              },
            ),
        ]),
        if (_poolWarning) ...[
          const SizedBox(height: 16),
          AppCard(
            borderColor: c.danger,
            child: Text(Strings.t('msl_pool_small')
                .replaceAll('{len}', _wlenLabel[_wlenOpt])
                .replaceAll('{k}', '${_recKoch[maxLen]}')
                .replaceAll('{n}', '$_koch'),
                style: _mono(13, c.danger)),
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
    final n = _target.length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Row(children: [
          Text('${Strings.t('msl_round')} $_roundNo', style: _mono(16, c.textPrimary)),
          Expanded(child: Text('${_wordIndex + 1}/${_game.length}',
              textAlign: TextAlign.center, style: _mono(13, c.textMuted))),
          Text('${Strings.t('msl_clue')} $_clueWpm',
              style: _mono(16, _clueWpm <= _floorWpm ? c.warning : c.info)),
        ]),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, box) {
          const gap = 8.0;
          final w = min(56.0, (box.maxWidth - (n - 1) * gap) / n);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _box(c, i, w),
              ],
            ],
          );
        }),
      ),
      const SizedBox(height: 20),
      Text(_status, textAlign: TextAlign.center, style: _mono(15, c.textPrimary)),
      const SizedBox(height: 6),
      Text(Strings.t('msl_err_hint'), textAlign: TextAlign.center,
          style: _mono(11, c.textFaint)),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          Text('Koch $_koch', style: _mono(12, c.textMuted)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove, size: 18, color: c.textMuted),
            onPressed: () => _changeKeyWpm(-1),
          ),
          Text('${Strings.t('msl_key')} $_keyWpm WPM', style: _mono(12, c.textMuted)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 18, color: c.textMuted),
            onPressed: () => _changeKeyWpm(1),
          ),
          const Spacer(),
          TextButton(
            onPressed: _evaluated ? null : _skip,
            child: Text(Strings.t('msl_skip'), style: _mono(13, c.warning)),
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

  // One letter box. Before a submit it shows what was keyed, or the clue
  // letter at the revealed slot; afterwards the coloured result.
  Widget _box(AppColors c, int i, double w) {
    final isReveal = i == _reveal;
    Color border = c.border, fill = c.surface, fg = c.textPrimary;
    String ch = '';
    if (!_evaluated) {
      if (isReveal) border = c.info;
      if (i < _guess.length) {
        ch = _guess[i];
      } else if (isReveal) {
        ch = _target[i];
        fg = c.info;
      }
    } else {
      switch (_cells[i]) {
        case _Cell.green:
          fill = c.accent; border = c.accent; fg = c.background; ch = _target[i];
        case _Cell.red:
          fill = c.danger; border = c.danger; fg = Colors.white;
          ch = i < _guess.length ? _guess[i] : '';
        case _Cell.grey:
          fill = c.textFaint; border = c.textFaint; fg = c.background; ch = _target[i];
        case _Cell.neutral:
          break;
      }
    }
    return Column(children: [
      Container(
        width: w, height: w * 1.15,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 2),
        ),
        child: Text(ch, style: _mono(w * 0.5, fg, bold: true)),
      ),
      const SizedBox(height: 4),
      Text('${i + 1}', style: _mono(11, isReveal ? c.info : c.textFaint)),
    ]);
  }

  static String _mmss(int ms) {
    final s = (ms + 500) ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _buildResults(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(Strings.t('msl_game_over'), style: _mono(14, c.textMuted)),
            const SizedBox(height: 12),
            Text('${Strings.t('msl_time')}  ${_mmss(_totalAdjMs)}',
                style: _mono(30, c.textPrimary)),
            const SizedBox(height: 12),
            Text('${Strings.t('msl_solved')} $_solved / ${_game.length}    '
                '${Strings.t('msl_skipped')} $_skipped',
                style: _mono(14, c.textPrimary)),
            const SizedBox(height: 6),
            Text(Strings.t('msl_guesses')
                .replaceAll('{n}', '$_totalGuesses')
                .replaceAll('{s}', '$_guessPenaltyS'),
                style: _mono(12, c.textMuted)),
            if (_lastRank >= 0) ...[
              const SizedBox(height: 14),
              Text(Strings.t('msl_new_hi').replaceAll('{r}', '${_lastRank + 1}'),
                  style: _mono(15, c.accent, bold: true)),
            ],
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
    Widget row(List<String> cells, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 28, child: Text(cells[0], style: _mono(13, color))),
        Expanded(flex: 3, child: Text(cells[1], style: _mono(13, color))),
        Expanded(flex: 3, child: Text(cells[2], style: _mono(13, color))),
        Expanded(flex: 2, child: Text(cells[3], style: _mono(13, color))),
        Expanded(flex: 2, child: Text(cells[5], style: _mono(13, color))),
        Expanded(flex: 2, child: Text(cells[4], textAlign: TextAlign.right,
            style: _mono(13, color))),
      ]),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCaption(Strings.t('msl_hiscores')),
        const SizedBox(height: 8),
        AppCard(child: Column(children: [
          row(['#', Strings.t('msl_time'), Strings.t('msl_wlen_short'), 'Koch',
              Strings.t('msl_solved'), 'WPM'], c.textMuted),
          Divider(color: c.border, height: 12),
          if (_hi.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(Strings.t('msl_no_scores'), style: _mono(13, c.textFaint)),
            ),
          for (var i = 0; i < _hi.length; i++)
            row([
              '${i + 1}', _mmss(_hi[i].adjMs),
              _wlenLabel[_hi[i].wlen.clamp(0, _wlenLabel.length - 1)],
              'K${_hi[i].koch}', '${_hi[i].solved}/${_hi[i].total}', '${_hi[i].startWpm}',
            ], i == _lastRank ? c.accent : c.textPrimary),
        ])),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_continue'), color: c.accent,
            onTap: () => setState(() => _phase = _Phase.lobby)),
      ],
    );
  }
}
