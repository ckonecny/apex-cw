// Trailblazer and Fox Hunt — the firmware's two maze games, ported from
// MorseTrailblazer.cpp / MorseFoxHunt.cpp on top of the shared grid engine
// (content/grid_engine.dart, MorseGridEngine.cpp).
//
// A 12x4 grid of Koch characters hides a path from the left to the right
// edge. Trailblazer highlights the next cell and you key its letter; Fox
// Hunt only plays the next cell's letter in CW and you key the direction
// (the legend assigns N/S/W/E letters from your Koch set). A correct answer
// moves the token one cell, a wrong one costs 5 s on the score. The walked
// part of the trail is drawn, the path ahead never is. Score: characters per
// minute over the solve time; one high-score table per game.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/cw_content.dart';
import '../content/grid_engine.dart';
import '../content/grid_score.dart';
import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/interference_button.dart';
import 'widgets/paddle_widgets.dart';

enum MazeGame { trailblazer, foxHunt }

// Same values as the firmware (MorseFoxHunt.cpp).
const _idleReplayMs = 5500;   // Fox Hunt: clue repeats after this much idle time
const _okPauseMs = 600;       // OK tone (~290 ms) + 300 ms breath before the next clue
const _typingHoldMs = 1500;   // don't replay right after the last keyed element

// Signal tones (MorseOutput::soundSignalOK / soundSignalERR): [Hz, ms].
const _sndOk = [[440, 97], [587, 193]];
const _sndErr = [[366, 97], [330, 193]];

enum _Phase { lobby, playing, solved, hiscores }

class MazeGameScreen extends StatefulWidget {
  final MazeGame game;
  const MazeGameScreen({super.key, required this.game});

  @override
  State<MazeGameScreen> createState() => _MazeGameScreenState();
}

class _MazeGameScreenState extends State<MazeGameScreen> with WidgetsBindingObserver {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  // Character -> dit/dah pattern; the clue goes out as an exact pattern.
  static final _patterns = {
    for (final e in MorseDecoder.table.entries)
      if (e.value.length == 1) e.value: e.key,
  };

  bool get _fox => widget.game == MazeGame.foxHunt;
  String get _hiKey => _fox ? 'foxHuntHi' : 'trailblazerHi';
  String get _title => _fox ? 'Fox Hunt' : 'Trailblazer';

  final _engine = GridEngine();
  late final MorseDecoder _decoder;
  StreamSubscription? _genSub, _symbolSub;
  Timer? _replayTimer;
  int _gen = 0;   // bumped on leaving play; stale delayed steps check it

  bool _ready = false;
  _Phase _phase = _Phase.lobby;

  // Settings
  List<String> _kochSeq = kochSeqM32;
  int _koch = 10;            // lesson for this visit only
  int _keyWpm = 20;          // player's keyer speed = clue speed (firmware wpm=0)
  int _keyerMode = 0;
  int _pitch = 600;
  int _toneShift = 1;        // firmware posEchoToneShift, applied to the clue
  List<GridScore> _hi = [];
  int _lastRank = -1;

  // Game
  List<String> _pool = [];
  DateTime _startedAt = DateTime.now();
  int _wrong = 0;
  GridScore? _result;
  bool _busy = false;        // clue playing or OK pause: input is ignored
  bool _cluePlaying = false;
  DateTime _nextReplayAt = DateTime.now();
  DateTime _lastActivity = DateTime.now();

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
    _replayTimer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stop');
    _toneChannel.invokeMethod('stopEffect');
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
    _keyWpm = (p.getInt('wpm') ?? 20).clamp(5, 60);
    _keyerMode = p.getInt('keyerMode') ?? 0;
    _pitch = p.getInt('pitch') ?? 600;
    _toneShift = (p.getInt('toneShift') ?? 1).clamp(0, 2);
    _hi = gridTableFromJson(p.getString(_hiKey));

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

  // ── Game flow ────────────────────────────────────────────────────────────

  // The Koch lesson set; every cell is drawn from it verbatim.
  List<String> _buildPool() {
    final pool = [
      for (final c in kochActiveChars(_koch, _kochSeq))
        if (c.length == 1 && _patterns.containsKey(c.toUpperCase())) c.toUpperCase(),
    ];
    return pool.isEmpty ? ['M'] : pool;
  }

  void _startMaze() {
    _pool = _buildPool();
    _engine.generate(_pool);
    _wrong = 0;
    _lastRank = -1;
    _result = null;
    _startedAt = DateTime.now();
    _lastActivity = _startedAt;
    _decoder.reset();
    // The noise stands for the whole maze, until it is solved.
    InterferenceProfile.requestAmbient(this);
    setState(() => _phase = _Phase.playing);
    if (_fox) {
      _replayTimer?.cancel();
      _replayTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _replayTick());
      _playClue();
    } else {
      _busy = false;
      _keyerChannel.invokeMethod('start');
    }
  }

  int get _cluePitch => switch (_toneShift) {
        1 => (_pitch * 18 / 17).round(),
        2 => (_pitch * 17 / 18).round(),
        _ => _pitch,
      };

  // Fox Hunt clue: the next cell's letter at the player's keyer speed with
  // the Echo Trainer's half-tone shift. The keyer is off meanwhile (it shares
  // the sidetone), so a clue is never cut short mid-letter by stray input —
  // the clue is one letter, a fraction of a second.
  Future<void> _playClue() async {
    if (_phase != _Phase.playing) return;
    _busy = true;
    _cluePlaying = true;
    _nextReplayAt = DateTime.now().add(const Duration(milliseconds: _idleReplayMs));
    await _keyerChannel.invokeMethod('stop');
    await _genChannel.invokeMethod('setWpm', _keyWpm);
    await _genChannel.invokeMethod('setInterCharSpace', 3);
    await _toneChannel.invokeMethod('setFreq', _cluePitch);
    await _genChannel.invokeMethod('playPatterns', [_patterns[_engine.nextChar] ?? '']);
  }

  void _onGenEvent(dynamic raw) {
    if ((raw as Map)['type'] != 'done' || !_cluePlaying) return;
    _cluePlaying = false;
    _toneChannel.invokeMethod('setFreq', _pitch);
    if (_phase != _Phase.playing) return;
    _decoder.reset();
    _busy = false;
    _keyerChannel.invokeMethod('start');
  }

  // Idle-input auto-replay of the clue (guarded off while keying).
  void _replayTick() {
    if (_phase != _Phase.playing || _busy || _touchDit || _touchDah) return;
    final now = DateTime.now();
    if (now.isBefore(_nextReplayAt)) return;
    if (now.difference(_lastActivity).inMilliseconds < _typingHoldMs) return;
    _playClue();
  }

  void _onSymbol(dynamic sym) {
    if (_phase != _Phase.playing || _busy) return;
    _lastActivity = DateTime.now();
    _decoder.add(sym as String);
  }

  void _onDecodedChar(String ch) {
    if (_phase != _Phase.playing || _busy) return;
    if (ch == ' ') return;             // word gap — not an answer
    _handleAnswer(ch);
  }

  void _sound(List<List<int>> notes) {
    if (_touchDit || _touchDah) return;
    _toneChannel.invokeMethod('playEffect', notes);
  }

  // One keyed character, judged against the next path cell.
  void _handleAnswer(String c) {
    final bool right;
    if (_fox) {
      final legend = GridEngine.directionLegend(_pool);
      final d = legend.indexWhere((e) => e.ltr == c);
      right = d >= 0 && _engine.directionMatchesNext(GridDir.values[d]);
    } else {
      right = c == _engine.nextChar;
    }
    if (!right) {
      _sound(_sndErr);   // wrong direction, or not a legend letter: same treatment
      _wrong++;
      return;
    }
    _sound(_sndOk);
    _engine.advance();
    if (_engine.atEnd) {
      _solved();
      return;
    }
    if (_fox) {
      _afterOkPause();
    } else {
      setState(() {});
    }
  }

  // Deliberate breath between the OK tone and the next clue.
  Future<void> _afterOkPause() async {
    final g = _gen;
    _busy = true;
    setState(() {});
    await Future.delayed(const Duration(milliseconds: _okPauseMs));
    if (!mounted || g != _gen) return;
    _playClue();
  }

  void _solved() {
    final elapsed = DateTime.now().difference(_startedAt).inMilliseconds;
    _endPlay();
    final s = gridScore(elapsed, _engine.pathLength - 1, _wrong, _koch);
    _result = s;
    _lastRank = gridRecord(_hi, s);
    if (_lastRank >= 0) {
      SharedPreferences.getInstance().then((p) => p.setString(_hiKey, gridTableToJson(_hi)));
    }
    setState(() => _phase = _Phase.solved);
  }

  void _endPlay() {
    InterferenceProfile.releaseAmbient(this);
    _gen++;
    _busy = false;
    _replayTimer?.cancel();
    if (_cluePlaying) {
      _cluePlaying = false;
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
    _lastActivity = DateTime.now();
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
          if (didPop) return;
          if (_phase == _Phase.playing) {
            _toLobby();
          } else {
            setState(() => _phase = _Phase.lobby);
          }
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, _title),
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
                  _Phase.solved => _buildSolved(c),
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
      fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  Widget _buildLobby(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t(_fox ? 'fh_rules' : 'tb_rules'),
            style: _mono(13, c.textMuted).copyWith(height: 1.45))),
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
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_start'), icon: Icons.play_arrow_rounded, color: c.accent, onTap: _startMaze),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('msl_hiscores'), color: c.accent, primary: false,
            onTap: () => setState(() { _lastRank = -1; _phase = _Phase.hiscores; })),
      ],
    );
  }

  Widget _buildPlay(AppColors c) {
    final steps = _engine.pathLength - 1;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(children: [
          Text('${_engine.currentIndex} / $steps', style: _mono(16, c.textPrimary)),
          const Spacer(),
          if (_wrong > 0)
            Text('${Strings.t('maze_wrong')} $_wrong', style: _mono(14, c.danger)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _board(c, highlightNext: !_fox),
      ),
      if (_fox) ...[
        const SizedBox(height: 12),
        _legend(c),
        const SizedBox(height: 8),
        Text(Strings.t('maze_fh_hint'),
            textAlign: TextAlign.center, style: _mono(12, c.textFaint)),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _playClue,
            icon: Icon(Icons.replay, size: 18, color: c.info),
            label: Text(Strings.t('maze_replay'), style: _mono(13, c.info)),
          ),
        ),
      ] else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(Strings.t('maze_tb_hint'),
              textAlign: TextAlign.center, style: _mono(12, c.textFaint)),
        ),
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

  Widget _board(AppColors c, {required bool highlightNext}) {
    return LayoutBuilder(builder: (context, box) {
      final cellH = min(52.0, box.maxWidth / gridCols * 1.6);
      return CustomPaint(
        size: Size(box.maxWidth, cellH * gridRows),
        painter: _MazePainter(_engine, c, highlightNext),
      );
    });
  }

  // N/S/W/E letters of this Koch lesson; a substituted slot (the canonical
  // compass letter isn't learned yet) has a yellow frame.
  Widget _legend(AppColors c) {
    const arrows = [
      Icons.arrow_upward, Icons.arrow_downward, Icons.arrow_back, Icons.arrow_forward,
    ];
    final legend = GridEngine.directionLegend(_pool);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var d = 0; d < 4; d++) ...[
        if (d > 0) const SizedBox(width: 8),
        Container(
          width: 64, height: 40,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: legend[d].substituted ? c.warning : c.info, width: 2),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(arrows[d], size: 18, color: c.textMuted),
            const SizedBox(width: 4),
            Text(legend[d].ltr,
                style: _morse(18, legend[d].substituted ? c.warning : c.textPrimary,
                    bold: true)),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildSolved(AppColors c) {
    final s = _result!;
    final secs = (s.elapsedMs + 500) ~/ 1000;
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(Strings.t('maze_solved'), style: _mono(20, c.accent, bold: true)),
            const SizedBox(height: 12),
            Text('${s.cpm} CPM', style: _mono(34, c.warning, bold: true)),
            const SizedBox(height: 12),
            Text('${Strings.t('maze_steps')} ${s.steps}    ${Strings.t('maze_wrong')} ${s.wrong}',
                style: _mono(14, c.textPrimary)),
            const SizedBox(height: 4),
            Text('${Strings.t('msl_time')} $time    Koch ${s.koch}',
                style: _mono(13, c.textMuted)),
            if (_lastRank >= 0) ...[
              const SizedBox(height: 12),
              Text(Strings.t('msl_new_hi').replaceAll('{r}', '${_lastRank + 1}'),
                  style: _mono(15, c.accent, bold: true)),
            ],
            const SizedBox(height: 18),
            _board(c, highlightNext: false),
          ]),
        ),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('maze_again'), color: c.accent, onTap: _startMaze),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('msl_hiscores'), color: c.accent, primary: false,
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
        for (var i = 1; i < cells.length; i++)
          Expanded(child: Text(cells[i], style: _mono(13, color))),
      ]),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCaption('${Strings.t('msl_hiscores')} – $_title'),
        const SizedBox(height: 8),
        AppCard(child: Column(children: [
          row(['#', 'CPM', Strings.t('maze_steps'), 'Koch'], c.textMuted),
          Divider(color: c.border, height: 12),
          if (_hi.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(Strings.t('msl_no_scores'), style: _mono(13, c.textFaint)),
            ),
          for (var i = 0; i < _hi.length; i++)
            row(['${i + 1}', '${_hi[i].cpm}', '${_hi[i].steps}', 'K${_hi[i].koch}'],
                i == _lastRank ? c.accent : c.textPrimary),
        ])),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('msl_continue'), color: c.accent,
            onTap: () => setState(() => _phase = _Phase.lobby)),
      ],
    );
  }
}

// The board (MorseGridEngine::drawBoard): only the walked part of the trail
// is drawn — the path ahead is never previewed, which matters most for Fox
// Hunt where a visible path would let you skip decoding. Trailblazer
// highlights the next cell; the token sits on the current one.
class _MazePainter extends CustomPainter {
  final GridEngine e;
  final AppColors c;
  final bool highlightNext;
  _MazePainter(this.e, this.c, this.highlightNext);

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 14.0;
    final cw = (size.width - 2 * margin) / gridCols;
    final ch = size.height / gridRows;
    double cx(int col) => margin + (col + 0.5) * cw;
    double cy(int row) => (row + 0.5) * ch;

    // Trail (walked segments only): axis-aligned bars.
    final trailW = max(3.0, min(cw, ch) * 0.28);
    final trail = Paint()..color = c.info.withValues(alpha: 0.55);
    for (var i = 0; i < e.currentIndex; i++) {
      final x1 = cx(e.pathColAt(i)), y1 = cy(e.pathRowAt(i));
      final x2 = cx(e.pathColAt(i + 1)), y2 = cy(e.pathRowAt(i + 1));
      canvas.drawRect(
          Rect.fromLTRB(min(x1, x2) - trailW / 2, min(y1, y2) - trailW / 2,
              max(x1, x2) + trailW / 2, max(y1, y2) + trailW / 2),
          trail);
    }

    final nextIdx = e.currentIndex + 1 < e.pathLength ? e.currentIndex + 1 : -1;
    final curCol = e.pathColAt(e.currentIndex), curRow = e.pathRowAt(e.currentIndex);
    final fontSize = min(cw * 0.62, ch * 0.5);

    void letter(String s, double x, double y, Color color) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(
            fontSize: fontSize, color: color,
            fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    if (highlightNext && nextIdx >= 0) {
      final bx = cx(e.pathColAt(nextIdx)), by = cy(e.pathRowAt(nextIdx));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(bx, by), width: cw * 0.88, height: ch * 0.84),
              const Radius.circular(3)),
          Paint()..color = c.warning);
    }

    for (var r = 0; r < gridRows; r++) {
      for (var col = 0; col < gridCols; col++) {
        if (col == curCol && r == curRow) continue;   // drawn as the token
        final isNext = highlightNext && nextIdx >= 0 &&
            col == e.pathColAt(nextIdx) && r == e.pathRowAt(nextIdx);
        letter(e.cell(col, r), cx(col), cy(r), isNext ? Colors.black : c.textPrimary);
      }
    }

    canvas.drawCircle(Offset(cx(curCol), cy(curRow)), min(cw, ch) * 0.40,
        Paint()..color = c.textMuted);
    letter(e.cell(curCol, curRow), cx(curCol), cy(curRow), Colors.black);

    // Start / end edge markers.
    final red = Paint()..color = c.danger;
    final sy = cy(e.pathRowAt(0));
    canvas.drawPath(
        Path()
          ..moveTo(margin - 11, sy - 4)
          ..lineTo(margin - 11, sy + 4)
          ..lineTo(margin - 3, sy)
          ..close(),
        red);
    final ey = cy(e.pathRowAt(e.pathLength - 1));
    final ex = size.width - margin;
    canvas.drawPath(
        Path()
          ..moveTo(ex + 3, ey - 4)
          ..lineTo(ex + 3, ey + 4)
          ..lineTo(ex + 11, ey)
          ..close(),
        red);
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}
