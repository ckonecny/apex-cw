// Morse Invaders — arcade game, ported from MorseGame.cpp.
//
// Characters of the Koch lesson fall down four lanes; keying one destroys
// the lowest invader showing it. An invader that reaches the bottom costs a
// life (3 at the start, max 5, +1 every 1000 points). Ten hits per level;
// each level falls faster, spawns more often and allows more invaders.
// The Koch lesson is the one set for sending (Echo Trainer profile), the
// keying speed is the keyer's own global 'wpm' (firmware: MorsePreferences::wpm).
//
// Game logic runs in the firmware's own units: a 33 ms frame, a 170 px wide
// field from y=24 to y=262 with 38x32 invaders, so speeds, spawn intervals
// and the "urgency" bonus zone stay exactly as on the device; only the
// drawing is scaled to the screen.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

// MorseGame.h constants.
const _maxInvaders = 6;
const _lanes = 4;
const _fieldTop = 24.0;
const _fieldBottom = 262.0;
const _invW = 38.0;
const _invH = 32.0;
const _laneW = 42.0;
const _laneMargin = 1.0;
const _screenW = 170.0;
const _hiN = 5;
const _destroysPerLevel = 10;
const _frameMs = 33;          // statePlaying(): one game frame every 33 ms
const _maxStartLevel = 50;

// Invader colours: the firmware palette entries (GamePalette.h, RGB565
// converted). Fill by character class, dimmed outline.
const _colLetters = Color(0xFF008200), _colLettersB = Color(0xFF004100);
const _colNumbers = Color(0xFF848200), _colNumbersB = Color(0xFF424100);
const _colPunct = Color(0xFF844100), _colPunctB = Color(0xFF422000);
const _colProsign = Color(0xFF840084), _colProsignB = Color(0xFF420042);

// Sound effects (MorseGame.cpp playSound*): [Hz, ms] notes.
const _sndHit = [[880, 40], [1320, 40]];
const _sndMiss = [[330, 60]];
const _sndLifeLost = [[660, 80], [440, 80], [330, 120]];
const _sndLevelUp = [[523, 60], [659, 60], [784, 60], [1047, 100]];
const _sndExtraLife = [[1047, 50], [1319, 50]];
const _sndGameOver = [[440, 200], [349, 200], [294, 200], [262, 400]];

enum _Phase { menu, countdown, playing, paused, levelUp, gameOver }

class _Invader {
  String ch = '';
  int lane = 0;
  double y = 0, speed = 0;
  bool active = false;
  int explodeFrame = 0;
  List<Offset> particles = const [];
}

class _HighScore {
  final int score, koch, level, wpm;
  const _HighScore(this.score, this.koch, this.level, this.wpm);
  Map<String, int> toJson() => {'s': score, 'k': koch, 'l': level, 'w': wpm};
  static _HighScore fromJson(Map m) => _HighScore(m['s'], m['k'], m['l'], m['w']);
}

class InvadersScreen extends StatefulWidget {
  const InvadersScreen({super.key});

  @override
  State<InvadersScreen> createState() => _InvadersScreenState();
}

class _InvadersScreenState extends State<InvadersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  final _random = Random();
  late final MorseDecoder _decoder;
  late final Ticker _ticker;
  StreamSubscription? _symbolSub;
  int _gen = 0;   // bumped on every phase change; stale delayed steps check it

  bool _ready = false;
  _Phase _phase = _Phase.menu;

  // Settings
  List<String> _pool = [];
  int _koch = 5;
  int _wpm = 20;
  int _keyerMode = 0;
  int _pitch = 600;
  bool _upper = false;
  int _startLevel = 1;   // persisted (firmware: per visit)
  List<_HighScore> _hi = [];
  int _lastRank = -1;

  // Game (GameData)
  int _score = 0, _subLevel = 1, _lives = 3, _streak = 0;
  int _hits = 0, _misses = 0, _dropped = 0;
  int _spawnInterval = 120, _spawnCounter = 60, _maxActive = 2;
  double _baseSpeed = 0.8;
  int _destroysThisLevel = 0;
  int _nextLifeAt = 1000;
  final _inv = List.generate(_maxInvaders, (_) => _Invader());
  String _lastDecoded = '';
  String _countText = '';
  Duration _lastTick = Duration.zero;
  double _pendingMs = 0;

  bool _touchDit = false, _touchDah = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    WidgetsBinding.instance.addObserver(this);
    _decoder = MorseDecoder(onChar: _onDecodedChar);
    _ticker = createTicker(_onTick);
    _load();
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    WidgetsBinding.instance.removeObserver(this);
    _gen++;
    _ticker.dispose();
    _symbolSub?.cancel();
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    _toneChannel.invokeMethod('stopEffect');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) _pause();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final echo = await TrainingProfile.open(TrainingProfile.echo);
    final custom = p.getString('customKochChars') ?? '';
    final seq = kochSequenceChars((p.getInt('kochSeq') ?? 0).clamp(0, 4),
        custom.isNotEmpty ? custom : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?',
        licwCarouselStart: (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13));
    // The Koch lesson set for sending (koch.getCharSet() in the firmware).
    _koch = (echo.getInt('kochLevel') ?? 5).clamp(2, seq.length);
    _pool = kochActiveChars(_koch, seq);
    _wpm = (p.getInt('wpm') ?? 20).clamp(5, 60);
    _keyerMode = p.getInt('keyerMode') ?? 0;
    _pitch = p.getInt('pitch') ?? 600;
    _upper = (p.getInt('outputCase') ?? 0) == 1;
    _startLevel = (p.getInt('invadersStartLevel') ?? 1).clamp(1, _maxStartLevel);
    _hi = _loadHi(p);

    // Shared native engine: push everything this screen relies on.
    await _toneChannel.invokeMethod('setFreq', _pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs',
        ((p.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
    await _keyerChannel.invokeMethod('setWpm', _wpm);
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

    _symbolSub = _symbolStream.receiveBroadcastStream().listen(_onSymbol);
    if (mounted) setState(() => _ready = true);
  }

  List<_HighScore> _loadHi(SharedPreferences p) {
    try {
      final raw = p.getString('invadersHi');
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((m) => _HighScore.fromJson(m as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveHi() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('invadersHi', jsonEncode(_hi.map((s) => s.toJson()).toList()));
  }

  // ── Sound ────────────────────────────────────────────────────────────────

  // Like startSound(): never while the player is keying (the keyer owns the
  // tone); the native side also drops an effect as soon as keying starts.
  void _sound(List<List<int>> notes) {
    if (_touchDit || _touchDah) return;
    _toneChannel.invokeMethod('playEffect', notes);
  }

  // ── Game data ────────────────────────────────────────────────────────────

  void _initGameData() {
    _score = 0;
    _subLevel = _startLevel;
    _lives = 3;
    _streak = 0;
    _hits = _misses = _dropped = 0;
    _destroysThisLevel = 0;
    // Firmware keeps this in a function-static that is never reset, so a
    // second game in one session only earns its first extra life later.
    // Reset per game here (docs/DECISIONS.md).
    _nextLifeAt = 1000;
    _lastDecoded = '';
    for (final v in _inv) {
      v.active = false;
      v.explodeFrame = 0;
    }
    _updateLevelParams();
  }

  void _updateLevelParams() {
    _baseSpeed = 0.8 + (_subLevel - 1) * 0.15;
    _spawnInterval = max(20, 120 - (_subLevel - 1) * 8);
    _spawnCounter = _spawnInterval ~/ 2;
    _maxActive = (2 + (_subLevel - 1) ~/ 2).clamp(2, _maxInvaders);
  }

  // ── Flow ─────────────────────────────────────────────────────────────────

  void _startGame() {
    _initGameData();
    _lastRank = -1;
    _countdown();
  }

  Future<void> _countdown() async {
    final g = ++_gen;
    _updateLevelParams();
    setState(() => _phase = _Phase.countdown);
    for (var i = 0; i < 4; i++) {
      setState(() => _countText = i < 3 ? '${3 - i}' : 'GO!');
      await Future.delayed(Duration(milliseconds: i < 3 ? 600 : 400));
      if (!mounted || g != _gen) return;
    }
    _lastDecoded = '';
    _enterPlaying();
  }

  void _enterPlaying() {
    _gen++;
    _decoder.reset();
    _pendingMs = 0;
    _lastTick = Duration.zero;
    setState(() => _phase = _Phase.playing);
    _keyerChannel.invokeMethod('start');
    _ticker.start();
  }

  // leavePlayingState(): keyer off, effect off.
  void _leavePlaying() {
    _gen++;
    if (_ticker.isActive) _ticker.stop();
    _touchDit = _touchDah = false;
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    _toneChannel.invokeMethod('stopEffect');
  }

  void _pause() {
    if (_phase != _Phase.playing) return;
    _leavePlaying();
    setState(() => _phase = _Phase.paused);
  }

  Future<void> _levelUp() async {
    _leavePlaying();
    final g = _gen;
    setState(() => _phase = _Phase.levelUp);
    _sound(_sndLevelUp);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || g != _gen) return;
    for (final v in _inv) {
      if (v.active) { v.active = false; _score += 5; }
      v.explodeFrame = 0;
    }
    _enterPlaying();
  }

  void _gameOver() {
    _leavePlaying();
    _lives = 0;
    _sound(_sndGameOver);
    _lastRank = _insertHighScore();
    setState(() => _phase = _Phase.gameOver);
  }

  void _toMenu() {
    _leavePlaying();
    setState(() => _phase = _Phase.menu);
  }

  int _insertHighScore() {
    for (var i = 0; i < _hiN; i++) {
      if (i >= _hi.length || _score > _hi[i].score) {
        if (_score == 0) return -1;
        _hi.insert(i, _HighScore(_score, _koch, _subLevel, _wpm));
        if (_hi.length > _hiN) _hi.removeLast();
        _saveHi();
        return i;
      }
    }
    return -1;
  }

  // ── Frame loop ───────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_phase != _Phase.playing) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    // Catch up at most a few frames after a hiccup instead of teleporting.
    _pendingMs = min(_pendingMs + dt, _frameMs * 4.0);
    var stepped = false;
    while (_pendingMs >= _frameMs && _phase == _Phase.playing) {
      _pendingMs -= _frameMs;
      _step();
      stepped = true;
    }
    if (stepped && mounted) setState(() {});
  }

  // One firmware frame of statePlaying(), after the input handling (that
  // runs on decode, see _onDecodedChar).
  void _step() {
    if (--_spawnCounter <= 0) {
      _spawn();
      _spawnCounter = _spawnInterval;
    }
    _move();
    // Explosion animation advances once per drawn frame (drawInvader()).
    for (final v in _inv) {
      if (v.explodeFrame == 0) continue;
      if (v.explodeFrame >= 3 && v.explodeFrame <= 4) {
        v.particles = [
          for (var p = 0; p < 5; p++)
            Offset(_random.nextInt(32) - 16.0, _random.nextInt(32) - 16.0),
        ];
      }
      v.explodeFrame++;
      if (v.explodeFrame > 5) v.explodeFrame = 0;
    }
    if (_lives <= 0) {
      _gameOver();
      return;
    }
    if (_destroysThisLevel >= _destroysPerLevel) {
      _subLevel++;
      _destroysThisLevel = 0;
      _updateLevelParams();
      _levelUp();
    }
  }

  void _spawn() {
    if (_inv.where((v) => v.active).length >= _maxActive) return;
    final slot = _inv.indexWhere((v) => !v.active && v.explodeFrame == 0);
    if (slot < 0) return;
    var lane = 0;
    for (var attempts = 0; attempts < 10; attempts++) {
      lane = _random.nextInt(_lanes);
      final blocked = _inv.any((v) => v.active && v.lane == lane && v.y < _fieldTop + 60);
      if (!blocked) break;
    }
    final v = _inv[slot];
    v.ch = _pool[_random.nextInt(_pool.length)];
    v.lane = lane;
    v.y = _fieldTop;
    v.speed = _baseSpeed + _random.nextInt(30) / 100.0;
    v.active = true;
    v.explodeFrame = 0;
  }

  void _move() {
    for (final v in _inv) {
      if (!v.active) continue;
      v.y += v.speed;
      if (v.y >= _fieldBottom - _invH) {
        v.active = false;
        _lives--;
        _dropped++;
        _streak = 0;
        _sound(_sndLifeLost);
      }
    }
  }

  // ── Input ────────────────────────────────────────────────────────────────

  void _onSymbol(dynamic sym) {
    if (_phase != _Phase.playing) return;
    _decoder.add(sym as String);
  }

  void _onDecodedChar(String ch) {
    if (_phase != _Phase.playing || ch == ' ') return;
    _lastDecoded = ch;
    // findMatchingInvader(): the lowest active invader with that character.
    var best = -1;
    for (var i = 0; i < _inv.length; i++) {
      final v = _inv[i];
      if (v.active && v.ch == ch && (best < 0 || v.y > _inv[best].y)) best = i;
    }
    if (best >= 0) {
      _destroy(best);
    } else {
      _misses++;
      _streak = 0;
      _sound(_sndMiss);
    }
    setState(() {});
  }

  void _destroy(int idx) {
    final v = _inv[idx];
    v.active = false;
    v.explodeFrame = 1;
    final speedMult = _wpm / 10.0;
    final urgencyMult = v.y > _fieldBottom * 0.7 ? 2.0 : 1.0;
    _streak++;
    final streakMult = _streak >= 20 ? 3.0 : _streak >= 10 ? 2.0 : _streak >= 5 ? 1.5 : 1.0;
    _score += (10 * speedMult * urgencyMult * streakMult).toInt();
    _hits++;
    _destroysThisLevel++;
    _sound(_sndHit);
    if (_score >= _nextLifeAt && _lives < 5) {
      _lives++;
      _nextLifeAt += 1000;
      _sound(_sndExtraLife);
    }
  }

  void _setTouch({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  Future<void> _changeWpm(int delta) async {
    setState(() => _wpm = (_wpm + delta).clamp(5, 60));
    await _keyerChannel.invokeMethod('setWpm', _wpm);
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm', _wpm);
  }

  Future<void> _changeStartLevel(int delta) async {
    setState(() => _startLevel = (_startLevel + delta).clamp(1, _maxStartLevel));
    final p = await SharedPreferences.getInstance();
    await p.setInt('invadersStartLevel', _startLevel);
  }

  // getDisplayStr(): prosign <AR> as "AR" (drawn with an overline), the
  // rest in the chosen output case.
  String _display(String ch) {
    final s = ch == '+' ? 'AR' : ch;
    return _upper ? s.toUpperCase() : s.toLowerCase();
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
      fontFamily: 'CwMono', fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => PopScope(
        canPop: _phase == _Phase.menu,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_phase == _Phase.playing) {
            _pause();
          } else {
            _toMenu();
          }
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, 'Morse Invaders'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => Navigator.maybePop(context),
            ),
            actions: [
              if (_phase == _Phase.playing)
                IconButton(
                  icon: Icon(Icons.pause, color: c.textMuted),
                  onPressed: _pause,
                ),
            ],
          ),
          body: !_ready
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : switch (_phase) {
                  _Phase.menu => _buildMenu(c),
                  _Phase.gameOver => _buildGameOver(c),
                  _ => _buildGame(c),
                },
        ),
      ),
    );
  }

  Widget _stepper(AppColors c, String value, String? sub,
      VoidCallback? onMinus, VoidCallback? onPlus) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        IconButton(icon: Icon(Icons.remove, color: c.textMuted), onPressed: onMinus),
        Expanded(child: Column(children: [
          Text(value, style: _mono(22, c.textPrimary)),
          if (sub != null)
            Text(sub, textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis, style: _mono(11, c.textFaint)),
        ])),
        IconButton(icon: Icon(Icons.add, color: c.textMuted), onPressed: onPlus),
      ]),
    );
  }

  Widget _buildMenu(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('inv_rules'),
            style: _mono(13, c.textMuted).copyWith(height: 1.45))),
        const SizedBox(height: 16),
        AppCaption(Strings.t('inv_koch')),
        const SizedBox(height: 8),
        AppCard(child: Column(children: [
          Text('$_koch  (${_pool.length} ${Strings.t('inv_chars')})',
              style: _mono(20, c.textPrimary)),
          const SizedBox(height: 4),
          Text(_pool.map(_display).join(' '), textAlign: TextAlign.center,
              style: _mono(12, c.textFaint)),
          const SizedBox(height: 6),
          Text(Strings.t('inv_koch_hint'), textAlign: TextAlign.center,
              style: _mono(11, c.textFaint)),
        ])),
        const SizedBox(height: 16),
        AppCaption(Strings.t('inv_start_level')),
        const SizedBox(height: 8),
        _stepper(c, '$_koch-$_startLevel', null,
            _startLevel > 1 ? () => _changeStartLevel(-1) : null,
            _startLevel < _maxStartLevel ? () => _changeStartLevel(1) : null),
        const SizedBox(height: 16),
        AppCaption(Strings.t('inv_key_wpm')),
        const SizedBox(height: 8),
        _stepper(c, '$_wpm WPM', Strings.t('inv_wpm_hint'),
            _wpm > 5 ? () => _changeWpm(-1) : null,
            _wpm < 60 ? () => _changeWpm(1) : null),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('inv_start'), color: c.accent, onTap: _startGame),
        const SizedBox(height: 24),
        AppCaption(Strings.t('inv_hiscores')),
        const SizedBox(height: 8),
        _hiscoreCard(c),
      ],
    );
  }

  Widget _hiscoreCard(AppColors c) {
    Widget row(List<String> cells, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 28, child: Text(cells[0], style: _mono(13, color))),
        Expanded(flex: 3, child: Text(cells[1], style: _mono(13, color))),
        Expanded(flex: 3, child: Text(cells[2], style: _mono(13, color))),
        Expanded(flex: 2, child: Text(cells[3], textAlign: TextAlign.right,
            style: _mono(13, color))),
      ]),
    );
    return AppCard(child: Column(children: [
      row(['#', Strings.t('inv_score'), Strings.t('inv_level'), 'WPM'], c.textMuted),
      Divider(color: c.border, height: 12),
      if (_hi.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(Strings.t('inv_no_scores'), style: _mono(13, c.textFaint)),
        ),
      for (var i = 0; i < _hi.length; i++)
        row(['${i + 1}', '${_hi[i].score}', '${_hi[i].koch}-${_hi[i].level}',
            '${_hi[i].wpm}'], i == _lastRank ? c.warning : c.textPrimary),
    ]));
  }

  Widget _buildGame(AppColors c) {
    return Column(children: [
      // HUD (drawHUD): lives, level, score.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(children: [
          Expanded(child: Row(children: [
            for (var i = 0; i < _lives; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.circle, size: 12, color: c.danger),
              ),
          ])),
          Text('$_koch-$_subLevel', style: _mono(16, c.textPrimary)),
          Expanded(child: Text('$_score', textAlign: TextAlign.right,
              style: _mono(18, c.info, bold: true))),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: c.surfaceDark,
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _FieldPainter(
                  invaders: _inv, display: _display, lane: c.border))),
                if (_phase != _Phase.playing)
                  Positioned.fill(child: _overlay(c)),
              ]),
            ),
          ),
        ),
      ),
      // Keying zone (drawKeyingZone): speed, last decoded character, streak.
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
        child: Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove, size: 18, color: c.textMuted),
            onPressed: () => _changeWpm(-1),
          ),
          Text('$_wpm WPM', style: _mono(12, c.textMuted)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 18, color: c.textMuted),
            onPressed: () => _changeWpm(1),
          ),
          Expanded(child: Text(_lastDecoded.isEmpty ? '' : _decodedLabel(_lastDecoded),
              textAlign: TextAlign.center, style: _mono(24, c.textPrimary, bold: true))),
          SizedBox(width: 56, child: Text(_streak >= 5 ? 'x$_streak' : '',
              textAlign: TextAlign.right, style: _mono(16, c.warning, bold: true))),
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

  String _decodedLabel(String ch) {
    if (ch == MorseDecoder.err) return _upper ? 'ERR' : 'err';
    return ch.length > 1 ? (_upper ? ch : ch.toLowerCase()) : _display(ch);
  }

  Widget _overlay(AppColors c) {
    final Widget content = switch (_phase) {
      _Phase.countdown => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_countText, style: _mono(56, _countText == 'GO!' ? c.accent : c.textPrimary,
              bold: true)),
          const SizedBox(height: 16),
          Text('${Strings.t('inv_level')} $_koch-$_subLevel', style: _mono(16, c.warning)),
        ]),
      _Phase.levelUp => Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${Strings.t('inv_level').toUpperCase()} $_koch-$_subLevel',
              style: _mono(30, c.warning, bold: true)),
          const SizedBox(height: 16),
          Text('${Strings.t('inv_score')}: $_score', style: _mono(16, c.info)),
        ]),
      _Phase.paused => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Strings.t('inv_paused'), style: _mono(28, c.textPrimary, bold: true)),
          const SizedBox(height: 20),
          SizedBox(width: 200, child: AppButton(label: Strings.t('inv_resume'),
              color: c.accent, onTap: _enterPlaying)),
          const SizedBox(height: 10),
          SizedBox(width: 200, child: AppButton(label: Strings.t('inv_quit'),
              color: c.accent, primary: false, onTap: _toMenu)),
        ]),
      _ => const SizedBox.shrink(),
    };
    return Container(
      color: c.surfaceDark.withOpacity(_phase == _Phase.countdown ? 1 : 0.75),
      alignment: Alignment.center,
      child: content,
    );
  }

  Widget _buildGameOver(AppColors c) {
    final total = _hits + _misses + _dropped;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(Strings.t('msl_game_over'), style: _mono(22, c.danger, bold: true)),
            const SizedBox(height: 12),
            Text('${Strings.t('inv_score')}  $_score', style: _mono(30, c.info)),
            const SizedBox(height: 10),
            Text('$_koch-$_subLevel   $_wpm WPM', style: _mono(14, c.textPrimary)),
            if (total > 0) ...[
              const SizedBox(height: 6),
              Text('${Strings.t('inv_accuracy')}: ${_hits * 100 ~/ total}%',
                  style: _mono(14, c.textPrimary)),
            ],
            const SizedBox(height: 6),
            Text(Strings.t('inv_stats').replaceAll('{h}', '$_hits')
                .replaceAll('{m}', '$_misses').replaceAll('{d}', '$_dropped'),
                style: _mono(12, c.textMuted)),
            if (_lastRank >= 0) ...[
              const SizedBox(height: 14),
              Text(Strings.t('msl_new_hi').replaceAll('{r}', '${_lastRank + 1}'), style: _mono(15, c.warning, bold: true)),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        _hiscoreCard(c),
        const SizedBox(height: 24),
        AppButton(label: Strings.t('inv_again'), color: c.accent, onTap: _startGame),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('inv_quit'), color: c.accent, primary: false,
            onTap: _toMenu),
      ],
    );
  }
}

// Draws the lanes and invaders (drawGameField/drawInvader). X is scaled from
// the firmware's 170 px width; y maps the invader's travel (fieldTop down to
// the drop line) onto the available height, so fall times stay the same.
class _FieldPainter extends CustomPainter {
  final List<_Invader> invaders;
  final String Function(String) display;
  final Color lane;

  _FieldPainter({required this.invaders, required this.display, required this.lane});

  static (Color, Color) _colors(String ch) {
    if (RegExp(r'^[0-9]$').hasMatch(ch)) return (_colNumbers, _colNumbersB);
    if ('.,?/-=:'.contains(ch)) return (_colPunct, _colPunctB);
    if (ch == '+') return (_colProsign, _colProsignB);
    return (_colLetters, _colLettersB);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _screenW;
    final boxW = _invW * sx;
    final boxH = min(_invH * sx, size.height / 5);
    final travel = size.height - boxH - 4;
    double top(double y) => 2 + (y - _fieldTop) / (_fieldBottom - _invH - _fieldTop) * travel;

    final lanePaint = Paint()..color = lane..strokeWidth = 1;
    for (var i = 0; i <= _lanes; i++) {
      final x = (_laneMargin + i * _laneW) * sx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), lanePaint);
    }

    for (final v in invaders) {
      if (!v.active && v.explodeFrame == 0) continue;
      final x = (_laneMargin + v.lane * _laneW + (_laneW - _invW) / 2) * sx;
      final y = top(v.y);
      final (fill, border) = _colors(v.ch);
      final r = Radius.circular(4 * sx);
      if (v.explodeFrame > 0) {
        // Frame counter already advanced by the game step: 2-3 = shrinking
        // white box, 4-5 = particles (firmware frames 1-2 and 3-4).
        final f = v.explodeFrame - 1;
        if (f >= 1 && f <= 2) {
          final s = f * 4 * sx;
          canvas.drawRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(x + s, y + s, boxW - 2 * s, boxH - 2 * s), r),
              Paint()..color = Colors.white);
        } else if (f >= 3 && f <= 4) {
          final p = Paint()..color = fill;
          for (final o in v.particles) {
            canvas.drawRect(Rect.fromLTWH(x + boxW / 2 + o.dx * sx,
                y + boxH / 2 + o.dy * sx, 3 * sx, 3 * sx), p);
          }
        }
        continue;
      }
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, boxW, boxH), r);
      canvas.drawRRect(rect, Paint()..color = fill);
      canvas.drawRRect(rect, Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      final label = display(v.ch);
      final prosign = label.length > 1;
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(
            fontFamily: 'CwMono', fontWeight: FontWeight.bold,
            fontSize: boxH * (prosign ? 0.5 : 0.7), color: Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      final tx = x + (boxW - tp.width) / 2;
      final ty = y + (boxH - tp.height) / 2 + (prosign ? boxH * 0.06 : 0);
      tp.paint(canvas, Offset(tx, ty));
      if (prosign) {
        canvas.drawLine(Offset(tx, ty + 1), Offset(tx + tp.width, ty + 1),
            Paint()..color = Colors.white..strokeWidth = 1.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
