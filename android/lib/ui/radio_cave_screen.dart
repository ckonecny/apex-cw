// Radio Cave — port of MorseRadioCave.cpp (game logic in
// content/radio_cave_engine.dart). A text adventure in an abandoned radio
// station: every command is keyed, clues arrive as CW audio. Short commands
// (S E W I H) act at once, everything else after a pause of silence.
// The game is saved after every command.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/radio_cave_engine.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/paddle_widgets.dart';

enum _View { lobby, play, dead, won }

const _saveKey = 'radioCaveSave';
const _tickMs = 100;

class RadioCaveScreen extends StatefulWidget {
  const RadioCaveScreen({super.key});

  @override
  State<RadioCaveScreen> createState() => _RadioCaveScreenState();
}

class _RadioCaveScreenState extends State<RadioCaveScreen> with WidgetsBindingObserver {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  final _engine = RadioCaveEngine();
  late final MorseDecoder _decoder;
  StreamSubscription? _genSub, _symbolSub;
  Timer? _timer;
  SharedPreferences? _prefs;

  bool _ready = false;
  _View _view = _View.lobby;
  final _clock = Stopwatch()..start();
  int get _now => _clock.elapsedMilliseconds;

  int _keyWpm = 20;
  int _keyerMode = 0;
  int _pitch = 600;
  int _interWord = 7;

  String _input = '';          // command buffer: lower-case letters, prosigns upper case
  String _message = '';        // result line (engine message or a local note)
  int _lastElementAt = 0;      // last keyed dit/dah, for the silence timeout
  bool _clueActive = false;    // a CW clue is sounding: keying is muted
  bool _touchDit = false, _touchDah = false;

  int get _ditMs => 1200 ~/ _keyWpm;
  bool get _hasSave => _prefs?.getString(_saveKey) != null;

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
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stopOne');
    _toneChannel.invokeMethod('setFreq', _pitch);
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _view != _View.lobby) _toLobby();
  }

  Future<void> _load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    _keyWpm = (p.getInt('wpm') ?? 20).clamp(5, 60);
    _keyerMode = p.getInt('keyerMode') ?? 0;
    _pitch = p.getInt('pitch') ?? 600;
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
    if (mounted) setState(() => _ready = true);
  }

  // ── Game flow ────────────────────────────────────────────────────────────

  void _start({required bool resume}) {
    if (!resume) _prefs?.remove(_saveKey);
    _engine.begin(resume ? _prefs?.getString(_saveKey) : null);
    _input = '';
    _message = _engine.message;
    _lastElementAt = 0;
    _clueActive = false;
    _decoder.reset();
    _keyerChannel.invokeMethod('start');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _tick());
    setState(() => _view = _View.play);
  }

  void _endPlay() {
    _timer?.cancel();
    _stopClue();
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
    _touchDit = _touchDah = false;
  }

  void _toLobby() {
    _endPlay();
    setState(() => _view = _View.lobby);
  }

  void _tick() {
    if (_view != _View.play || _clueActive) return;
    // Command ends after 2.5 inter-word spaces of real silence (firmware).
    if (_input.isNotEmpty && !_touchDit && !_touchDah && _lastElementAt > 0) {
      final timeout = max(400, _ditMs * _interWord * 5 ~/ 2);
      if (_now - _lastElementAt >= timeout) {
        _decoder.flush();
        _dispatchBuffer();
        return;
      }
    }
    if (_input.isNotEmpty) setState(() {});   // cursor blink
  }

  void _dispatchBuffer() {
    final cmd = _input;
    _input = '';
    _decoder.reset();
    _engine.dispatch(cmd);
    _message = _engine.message;
    _afterDispatch();
  }

  void _afterDispatch() {
    final save = _prefs;
    switch (_engine.phase) {
      case RcPhase.playing:
        save?.setString(_saveKey, _engine.toSave());
      case RcPhase.dead:
        save?.remove(_saveKey);
        _stopClue();
        _view = _View.dead;
      case RcPhase.won:
        save?.remove(_saveKey);
        _view = _View.won;
        _playClue(RadioCaveEngine.wonClue);
    }
    final clue = _engine.clue;
    if (clue != null && _engine.phase == RcPhase.playing) {
      _engine.clue = null;
      _playClue(clue);
    }
    setState(() {});
  }

  // ── CW clues ─────────────────────────────────────────────────────────────

  Future<void> _playClue(RcClue clue) async {
    _clueActive = true;
    _decoder.reset();
    _input = '';
    await _genChannel.invokeMethod('stopOne');
    await _genChannel.invokeMethod('setWpm', clue.wpm);
    await _genChannel.invokeMethod('setInterCharSpace', 3);
    await _genChannel.invokeMethod('setInterWordSpace', 7);
    await _toneChannel.invokeMethod('setFreq', rcCluePitchHz);
    await _genChannel.invokeMethod('playOne', clue.text);
  }

  void _stopClue() {
    if (!_clueActive) return;
    _clueActive = false;
    _genChannel.invokeMethod('stopOne');
    _toneChannel.invokeMethod('setFreq', _pitch);
  }

  void _onGenEvent(dynamic raw) {
    if ((raw as Map)['type'] != 'done' || !_clueActive) return;
    _clueActive = false;
    _toneChannel.invokeMethod('setFreq', _pitch);
    _lastElementAt = 0;
    if (mounted) setState(() {});
  }

  // ── Input ────────────────────────────────────────────────────────────────

  void _onSymbol(dynamic sym) {
    if (_view != _View.play || _clueActive) return;
    if (sym == '·' || sym == '—') _lastElementAt = _now;
    _decoder.add(sym as String);
  }

  void _onDecodedChar(String ch) {
    if (_view != _View.play || _clueActive) return;
    if (ch == ' ') {                       // word gap: a space between words
      if (_input.isNotEmpty && !_input.endsWith(' ')) _input += ' ';
      setState(() {});
      return;
    }
    if (ch == MorseDecoder.err) {          // error sign clears the input
      _input = '';
      _message = Strings.t('rc_cleared');
      setState(() {});
      return;
    }
    final c = rcBufferChar(ch);
    if (c == null || _input.length >= rcInputMax) return;
    _input += c;
    _lastElementAt = _now;
    if (_input.endsWith('eeee')) {         // four E in a row: start the command anew
      _input = '';
      _message = Strings.t('rc_cleared');
      setState(() {});
      return;
    }
    if (rcIsInstantCommand(_input, pendingNewConfirm: _engine.pendingNewConfirm)) {
      _dispatchBuffer();
      return;
    }
    setState(() {});
  }

  void _setTouch({bool? dit, bool? dah}) {
    if (_clueActive) return;
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  Future<void> _changeKeyWpm(int delta) async {
    setState(() => _keyWpm = (_keyWpm + delta).clamp(5, 60));
    await _keyerChannel.invokeMethod('setWpm', _keyWpm);
    await _prefs?.setInt('wpm', _keyWpm);
  }

  Future<void> _newGameFromLobby() async {
    if (_hasSave) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(Strings.t('rc_new_title')),
          content: Text(Strings.t('rc_new_body')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text(Strings.t('cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(Strings.t('rc_new_game'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _start(resume: false);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
        canPop: _view == _View.lobby,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toLobby();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, 'Radio Cave'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          body: !_ready
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : switch (_view) {
                  _View.lobby => _buildLobby(c),
                  _View.play => _buildPlay(c),
                  _View.dead => _buildEnd(c, dead: true),
                  _View.won => _buildEnd(c, dead: false),
                },
        ),
      ),
    );
  }

  TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
      fontFamily: 'CwMono', fontSize: size, color: color,
      fontWeight: bold ? FontWeight.bold : null);

  Widget _buildLobby(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('rc_rules'),
            style: _mono(13, c.textMuted).copyWith(height: 1.45))),
        const SizedBox(height: 24),
        if (_hasSave) ...[
          AppButton(label: Strings.t('rc_continue'), color: c.accent,
              onTap: () => _start(resume: true)),
          const SizedBox(height: 10),
          AppButton(label: Strings.t('rc_new_game'), color: c.accent, primary: false,
              onTap: _newGameFromLobby),
        ] else
          AppButton(label: Strings.t('rc_start'), color: c.accent,
              onTap: () => _start(resume: false)),
      ],
    );
  }

  Widget _buildPlay(AppColors c) {
    final cursor = (_now ~/ 400).isOdd;
    final Widget inputLine;
    if (_input.isNotEmpty) {
      inputLine = Text('> ${_input.toUpperCase()}${cursor ? '▌' : ' '}',
          style: _mono(18, c.accent, bold: true));
    } else if (_message.isNotEmpty) {
      inputLine = Text('= $_message', style: _mono(14, c.textPrimary));
    } else {
      inputLine = Text(Strings.t('rc_key_hint'), style: _mono(13, c.textFaint));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          SizedBox(
            width: 64, height: 48,
            child: CustomPaint(painter: _CaveMapPainter(
                room: _engine.room, dim: c.border, here: c.warning, frame: c.textFaint)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(rcRoomNames[_engine.room],
              style: _mono(18, c.accent, bold: true))),
        ]),
      ),
      Divider(color: c.border, height: 1),
      Expanded(
        child: SingleChildScrollView(
          key: ValueKey(_engine.bodyVersion),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(_engine.body,
              style: TextStyle(fontSize: 16, height: 1.35, color: c.textPrimary)),
        ),
      ),
      Divider(color: c.border, height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(height: 30, child: Align(
            alignment: Alignment.centerLeft, child: inputLine)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
        child: Row(children: [
          if (_clueActive)
            Text(Strings.t('rc_cw_playing'), style: _mono(12, c.warning))
          else ...[
            Text(_engine.exitLetters.isEmpty ? '-' : _engine.exitLetters.join(' '),
                style: _mono(12, c.accent)),
            const SizedBox(width: 16),
            Text('${_engine.invCount}/$rcInvMax • ${_engine.steps}',
                style: _mono(12, c.textFaint)),
          ],
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
      IgnorePointer(
        ignoring: _clueActive,
        child: Opacity(
          opacity: _clueActive ? 0.4 : 1,
          child: _keyerMode == 4
              ? StraightKeyPaddle(
                  onDown: () => _setTouch(dit: true), onUp: () => _setTouch(dit: false))
              : IambicPaddles(
                  onDitDown: () => _setTouch(dit: true), onDitUp: () => _setTouch(dit: false),
                  onDahDown: () => _setTouch(dah: true), onDahUp: () => _setTouch(dah: false)),
        ),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildEnd(AppColors c, {required bool dead}) {
    final color = dead ? c.danger : c.accent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(Strings.t(dead ? 'rc_dead' : 'rc_won'),
                style: _mono(22, color, bold: true)),
            const SizedBox(height: 16),
            Text(dead ? RadioCaveEngine.deathText : _engine.wonText,
                textAlign: dead ? TextAlign.start : TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.35, color: c.textPrimary)),
          ]),
        ),
        const SizedBox(height: 24),
        if (dead)
          AppButton(label: Strings.t('rc_restart'), color: c.accent,
              onTap: () => _start(resume: false)),
        if (dead) const SizedBox(height: 10),
        AppButton(label: Strings.t('rc_back'), color: c.accent, primary: !dead,
            onTap: _toLobby),
      ],
    );
  }
}

// The firmware's 32x24 floor plan of the cave, drawn twice as large; the
// current room is highlighted. Rooms 4/5/6 sit in the west column, 12 (the
// safe) is not on the map.
class _CaveMapPainter extends CustomPainter {
  final int room;
  final Color dim, here, frame;
  _CaveMapPainter({required this.room, required this.dim, required this.here, required this.frame});

  // x, y, w, h in firmware map units (index = room number).
  static const _rects = <List<int>>[
    [0, 0, 0, 0],
    [1, 20, 29, 2], [9, 16, 10, 2], [9, 6, 10, 9], [1, 6, 6, 2],
    [1, 9, 6, 2], [1, 12, 6, 3], [20, 9, 5, 6], [20, 6, 5, 2],
    [9, 3, 10, 2], [4, 0, 20, 2], [26, 6, 4, 9], [0, 0, 0, 0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = min(size.width / 32, size.height / 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, 32 * k, 24 * k), const Radius.circular(3)),
      Paint()..color = frame..style = PaintingStyle.stroke..strokeWidth = 1,
    );
    for (var r = 1; r <= rcNumRooms; r++) {
      final q = _rects[r];
      if (q[2] == 0) continue;
      canvas.drawRect(Rect.fromLTWH(q[0] * k, q[1] * k, q[2] * k, q[3] * k),
          Paint()..color = r == room ? here : dim);
    }
  }

  @override
  bool shouldRepaint(_CaveMapPainter old) => old.room != room || old.here != here || old.dim != dim;
}
