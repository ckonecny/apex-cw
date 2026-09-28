// Text adventure: one game (Zork I–III) played through the Z-machine
// interpreter, the answers played in CW (DECISIONS.md "Text adventure").
//
// The screen shows the game's text unchanged; cw_text.dart adapts only the
// audio. Settings live in their own profile (adv.*), pushed to the shared
// generator on entry and on every change (rule 2). Every command is
// autosaved; ↶ undoes up to 20 moves (the original has no UNDO).
import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adventure/adventure_map.dart';
import '../adventure/adventure_store.dart';
import '../adventure/cw_text.dart';
import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import '../zmachine/zmachine.dart';
import 'adventure_map_screen.dart';
import 'adventure_sheets.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart' show cwGenEvents;
import 'widgets/cw_keyboard.dart';
import 'widgets/paddle_widgets.dart';

/// Settings of the adventure profile, shared by all three games.
class AdventureSettings {
  int wpm = 20, interChar = 3, interWord = 7;
  /// Keying speed; 0 = like listening.
  int giveWpm = 0;
  int input = 0; // 0 paddle / touch keyer, 1 keyboard
  int send = 0; // 0 <AR>, 1 <AR> or K as its own word, 2 button only
  CwScope scope = CwScope.all;
  int show = 1; // 0 always, 1 after playing, 2 only on tap
  int verbosity = 0; // 0 brief, 1 superbrief, 2 verbose
  bool mapWarn = true; // ask before showing the whole map

  static const verbs = ['brief', 'superbrief', 'verbose'];

  int get keyWpm => giveWpm == 0 ? wpm : giveWpm;

  /// When a keyed word counts as finished: silence after its last
  /// character, in dits at the keying speed — the Geben learn mode's rule
  /// (firmware echoTrainer interWordTimer): 2 × IC + 1 + max(IW, IC + 4) / 8.
  int get wordEndDits => (2 * interChar + 1 + max(interWord, interChar + 4) / 8).round();
  /// Straight key: IW + 1 dits after key-up (MorseDecoder.cpp, echo mode).
  int get wordEndDitsStraight => interWord + 1;

  static Future<AdventureSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = AdventureSettings();
    if (p.getInt('adv.wpm') == null) {
      // First visit: start from the Hören profile's speed and spacing.
      final hear = await TrainingProfile.open(TrainingProfile.hear);
      await p.setInt('adv.wpm', TrainingProfile.clampWpm(hear.getInt('wpm')));
      await p.setInt('adv.interCharSpace', (hear.getInt('interCharSpace') ?? 3).clamp(3, 45));
      await p.setInt('adv.interWordSpace', (hear.getInt('interWordSpace') ?? 7).clamp(6, 105));
    }
    s.wpm = TrainingProfile.clampWpm(p.getInt('adv.wpm'));
    s.interChar = (p.getInt('adv.interCharSpace') ?? 3).clamp(3, 45);
    s.interWord = (p.getInt('adv.interWordSpace') ?? 7).clamp(s.interChar < 6 ? 6 : s.interChar, 105);
    s.scope = CwScope.values[(p.getInt('adv.scope') ?? 0).clamp(0, CwScope.values.length - 1)];
    s.show = (p.getInt('adv.show') ?? 1).clamp(0, 2);
    s.verbosity = (p.getInt('adv.verbosity') ?? 0).clamp(0, 2);
    final g = p.getInt('adv.giveWpm') ?? 0;
    s.giveWpm = g == 0 ? 0 : TrainingProfile.clampWpm(g);
    s.input = (p.getInt('adv.input') ?? 0).clamp(0, 1);
    s.send = (p.getInt('adv.send') ?? 0).clamp(0, 2);
    s.mapWarn = p.getBool(mapWarnKey) ?? true;
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('adv.wpm', wpm);
    await p.setInt('adv.interCharSpace', interChar);
    await p.setInt('adv.interWordSpace', interWord);
    await p.setInt('adv.scope', scope.index);
    await p.setInt('adv.show', show);
    await p.setInt('adv.verbosity', verbosity);
    await p.setInt('adv.giveWpm', giveWpm);
    await p.setInt('adv.input', input);
    await p.setInt('adv.send', send);
    await p.setBool(mapWarnKey, mapWarn);
  }

  static const mapWarnKey = 'adv.mapWarn';
}

String romanPart(int n) => const ['', 'I', 'II', 'III'][n];

class AdventureScreen extends StatefulWidget {
  final AdventureGame game;
  /// Start a new game instead of continuing the automatic save.
  final bool newGame;
  /// Open this save (slot id, or 'auto').
  final String? loadId;
  const AdventureScreen({super.key, required this.game, this.newGame = false, this.loadId});

  @override
  State<AdventureScreen> createState() => _AdventureScreenState();
}

class _AdventureScreenState extends State<AdventureScreen> {
  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _undoMax = 20;

  late final AdventureStore _store = AdventureStore(widget.game.id);
  late AdventureSettings _s;
  ZMachine? _z;
  bool _ready = false;
  String? _error;

  final List<LogEntry> _log = [];
  final List<(ZSnapshot, int, int)> _undo = []; // state before a command + log / walked length
  AdventureMap? _map; // null: no layout for this game yet
  final List<(int, int)> _walked = []; // paths walked, for the map's "visited" view
  final _scroll = ScrollController();
  final _curKey = GlobalKey();
  String _input = '';

  // Current answer (the last output entry) and its playback.
  int _curEntry = -1;
  Passage? _passage;
  bool _revealed = false;
  final Set<int> _heard = {};
  bool _playing = false;
  int? _pausedAt; // word to go on from after a pause
  int _lastWord = -1; // word played most recently (for Nochmal = word)
  int? _thenPauseAt; // a word / sentence replay ends paused here
  List<int> _order = [];
  int _orderPos = 0, _charInWord = 0;
  StreamSubscription? _genSub;
  bool _restoring = false;

  // Keying: the shared keyer + decoder, like the QSO Bot. Hardware paddles
  // are always decoded; the touch paddles show with input = paddle.
  StreamSubscription? _symSub;
  late final MorseDecoder _decoder = MorseDecoder(onChar: _onKeyedChar, unknown: '*');
  String _elements = ''; // the character being keyed, as · and —
  int _keyerMode = 0;
  bool _touchDit = false, _touchDah = false;

  String get _partTitle =>
      Strings.t('adv_part').replaceAll('{n}', romanPart(widget.game.part));

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _init();
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _genSub?.cancel();
    _symSub?.cancel();
    _genChannel.invokeMethod('stopOne');
    _keyerChannel.invokeMethod('stop');
    // Don't leave the long word end on the shared keyer (rule 2).
    _keyerChannel.invokeMethod('setInterWordSpace', 7);
    _autosave();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _s = await AdventureSettings.load();
      final p = await SharedPreferences.getInstance();
      await _toneChannel.invokeMethod('setFreq', p.getInt('pitch') ?? 600);
      await _toneChannel.invokeMethod('setEnvelopeMs',
          ((p.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
      await _pushSpeed();
      _genSub = cwGenEvents.listen(_onGenEvent);
      _keyerMode = p.getInt('keyerMode') ?? 0;
      await _keyerChannel.invokeMethod('setMode', _keyerMode);
      await _keyerChannel.invokeMethod('setCurtisBTiming', {
        'dit': (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
        'dah': (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
      });
      await _keyerChannel.invokeMethod('setAcs', (p.getInt('acs') ?? 0).clamp(0, 3));
      await _genChannel.invokeMethod('setPaddleChoice', false);
      await _pushKeyer();
      await _keyerChannel.invokeMethod('start');
      _symSub = _symbolStream.receiveBroadcastStream().listen(_onSymbol);

      final bytes = await rootBundle.load(widget.game.asset);
      final z = ZMachine(bytes.buffer.asUint8List());
      z.onSave = _onGameSave;
      _z = z;

      SaveData? save;
      if (!widget.newGame) {
        save = await _store.loadSlot(widget.loadId ?? 'auto');
        if (save != null && !z.matches(save.snapshot)) save = null;
      }
      if (save != null) {
        z.load(save.snapshot);
        _log.addAll(save.log);
        _walked.addAll(save.walked);
        if (widget.loadId != null && widget.loadId != 'auto') {
          _log.add(LogEntry(LogEntry.info, Strings.t('adv_loaded').replaceAll('{n}', save.info.name)));
        }
        _applyVerbosity();
        _setCurrent(play: false);
        _revealed = true; // heard before
      } else {
        final out = z.start();
        _applyVerbosity();
        _addOutput(out);
        _autosave();
      }
      // The map finds the rooms through the current room, so only now.
      try {
        final layout = await rootBundle.loadString('assets/zork/${widget.game.id}_map.json',
            cache: false); // a few KB, read once per screen
        final m = AdventureMap.build(z, layout);
        _map = m.rooms.isEmpty ? null : m;
      } catch (_) {
        _map = null; // no map for this part yet
      }
      if (mounted) setState(() => _ready = true);
      _scrollToEnd();
      if (save == null) _play();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pushSpeed() async {
    await _genChannel.invokeMethod('setWpm', _s.wpm);
    await _genChannel.invokeMethod('setInterCharSpace', _s.interChar);
    await _genChannel.invokeMethod('setInterWordSpace', _s.interWord);
  }

  /// Keying speed and word end. The native side subtracts 1 from the inter-
  /// word space and resets the straight-key gap, so that one goes second.
  Future<void> _pushKeyer() async {
    await _keyerChannel.invokeMethod('setWpm', _s.keyWpm);
    await _keyerChannel.invokeMethod('setInterWordSpace', _s.wordEndDits + 1);
    await _keyerChannel.invokeMethod('setStraightWordGap', _s.wordEndDitsStraight);
  }

  /// Sends BRIEF/SUPERBRIEF/VERBOSE silently: they cost no move in any of
  /// the three games, and the mode lives in the game's memory.
  void _applyVerbosity() {
    final z = _z;
    if (z == null || z.state != ZState.waitingForInput) return;
    z.input(AdventureSettings.verbs[_s.verbosity]);
  }

  // ---- transcript ----

  static String _clean(String out) {
    var t = out.replaceAll('\r', '');
    t = t.trimRight();
    if (t.endsWith('>')) t = t.substring(0, t.length - 1).trimRight();
    // Drop leading blank lines, keep inner paragraphs.
    while (t.startsWith('\n')) {
      t = t.substring(1);
    }
    return t;
  }

  void _addOutput(String out) {
    var t = _clean(out);
    if (t.isEmpty) return;
    // The opening banner (title, copyright, release) is shown, not played:
    // everything before the first room's name line.
    if (t.contains('Copyright')) {
      final lines = t.split('\n');
      final room = _z?.status.room ?? '';
      final at = room.isEmpty ? -1 : lines.lastIndexOf(room);
      if (at > 0) {
        final banner = lines.sublist(0, at).join('\n').trim();
        if (banner.isNotEmpty) _log.add(LogEntry(LogEntry.banner, banner));
        t = lines.sublist(at).join('\n');
      }
    }
    _log.add(LogEntry(LogEntry.output, t));
    _setCurrent(play: false);
  }

  /// Makes the last output entry the current answer.
  void _setCurrent({required bool play}) {
    _stopPlayback();
    _curEntry = _log.lastIndexWhere((e) => e.kind == LogEntry.output);
    _heard.clear();
    _lastWord = -1;
    _revealed = _s.show == 0;
    _passage = _curEntry < 0
        ? null
        : Passage.parse(_log[_curEntry].text, scope: _s.scope, roomName: _z?.status.room);
    if (play) _play();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _autosave() async {
    final z = _z;
    if (z == null || z.state != ZState.waitingForInput) return;
    await _store.saveAuto(z.snapshot(), z.status, List.of(_log), List.of(_walked));
  }

  // ---- playback ----

  /// Plays words [from] to [to] (default: to the end). A replay that stops
  /// before the end leaves Pause on "Weiter" at the next word.
  Future<void> _play({int from = 0, int? to}) async {
    final p = _passage;
    if (p == null) return;
    _genChannel.invokeMethod('stopOne');
    _pausedAt = null;
    final (text, order) = p.audioFrom(from, to);
    final rest = to == null ? const <int>[] : p.playedIndices.where((i) => i > to);
    _thenPauseAt = rest.isEmpty ? null : rest.first;
    if (order.isEmpty) {
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _order = order;
      _orderPos = 0;
      _charInWord = 0;
      _playing = true;
      _lastWord = order.first;
    });
    await _pushSpeed();
    await _genChannel.invokeMethod('playOne', text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  /// Keeps the word being played in view: scrolls in proportion to how far
  /// into the current answer the playback is.
  void _follow() {
    final ctx = _curKey.currentContext;
    final p = _passage;
    final cur = _currentWord;
    if (ctx == null || p == null || cur < 0 || !_scroll.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    final pos = _scroll.position;
    final target = (top + cur / p.words.length * box.size.height - pos.viewportDimension * 0.3)
        .clamp(0.0, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() > 30) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _stopPlayback() {
    if (_playing) _genChannel.invokeMethod('stopOne');
    _playing = false;
    _pausedAt = null;
  }

  /// Stops and remembers the word being played; [_resume] starts again
  /// from the beginning of that word.
  void _pause() {
    final w = _currentWord;
    setState(() {
      _stopPlayback();
      _pausedAt = w >= 0 ? w : null;
    });
  }

  void _resume() {
    final w = _pausedAt;
    if (w != null) _play(from: w);
  }

  /// Whether the whole current answer can be read right now.
  bool get _textVisible {
    final p = _passage;
    if (p == null) return false;
    if (_revealed) return true;
    return _s.show != 2 && p.playedIndices.every(_heard.contains);
  }

  /// Text button: shows the whole answer, or hides it again — then words
  /// reappear as they are played (Nochmal), as with "After playing".
  void _toggleText() => setState(() {
        if (_textVisible) {
          _revealed = false;
          _heard.clear();
        } else {
          _revealed = true;
        }
      });

  void _onGenEvent(dynamic raw) {
    if (!_playing || !mounted) return;
    final m = raw as Map;
    switch (m['type']) {
      case 'char':
        if (_orderPos >= _order.length) return;
        _charInWord++;
        final w = _order[_orderPos];
        if (_charInWord >= _passage!.words[w].cw.length) {
          _heard.add(w);
          _orderPos++;
          _charInWord = 0;
          if (_orderPos < _order.length) _lastWord = _order[_orderPos];
          WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
        }
        setState(() {});
      case 'done':
        setState(() {
          _heard.addAll(_order);
          _playing = false;
          _pausedAt = _thenPauseAt;
        });
    }
  }

  int get _currentWord => _playing && _orderPos < _order.length ? _order[_orderPos] : -1;

  /// Whole answer: Nochmal held, `?`, the tempo sheet.
  void _again() => _play();

  /// The word whose sentence Nochmal repeats: the one playing — or, in the gap right
  /// after a word, that word — else where it paused, else the last one.
  int _replayWord() {
    if (_playing && _currentWord >= 0) {
      return _charInWord == 0 && _orderPos > 0 ? _order[_orderPos - 1] : _currentWord;
    }
    if (_pausedAt != null) return _pausedAt!;
    if (_lastWord >= 0) return _lastWord;
    final played = _passage!.playedIndices;
    return played.isEmpty ? 0 : played.last;
  }

  /// Nochmal (tap): only the sentence playing (or last played), then
  /// paused at the next word. Tapping a word plays only that word, the same way.
  void _againSentence() {
    final p = _passage;
    if (p == null) return;
    final w = _replayWord();
    _play(from: p.sentenceStart(w), to: p.sentenceEnd(w));
  }

  // ---- keying ----

  void _onSymbol(dynamic raw) {
    final sym = raw as String;
    if (!_acceptsKeying) {
      _decoder.reset();
      _elements = '';
      return;
    }
    if (sym == '·' || sym == '—') {
      if (_playing) _stopPlayback(); // keying stops the output
      setState(() => _elements += sym);
    } else if (_elements.isNotEmpty) {
      setState(() => _elements = '');
    }
    _decoder.add(sym);
  }

  bool get _acceptsKeying {
    if (!mounted || !_ready || _z?.state != ZState.waitingForInput) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  void _onKeyedChar(String ch) {
    if (ch == ' ') {
      // Word gap. With "<AR> or K", a K on its own sends: no word in the
      // three games is K.
      final words = _input.trim().split(' ');
      if (_s.send == 1 && words.last == 'K') {
        setState(() => _input = words.sublist(0, words.length - 1).join(' '));
        _submit();
      } else if (_input.isNotEmpty && !_input.endsWith(' ')) {
        setState(() => _input += ' ');
      }
    } else if (ch == '+') {
      // <AR> (same code as +, which no game uses).
      if (_s.send != 2) _submit();
    } else if (ch == MorseDecoder.err) {
      _deleteWord();
    } else if (ch.length == 1) {
      setState(() => _input += ch);
    } // other prosigns: ignored
  }

  void _deleteWord() {
    final t = _input.trimRight();
    final i = t.lastIndexOf(' ');
    setState(() => _input = i < 0 ? '' : t.substring(0, i + 1));
  }

  void _setTouch({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  // ---- commands ----

  void _submit() {
    final cmd = _input.trim();
    final z = _z;
    if (cmd.isEmpty || z == null) return;
    setState(() {
      _input = '';
      _elements = '';
    });
    if (cmd == '?') {
      _again();
      return;
    }
    if (z.state != ZState.waitingForInput) return;
    _stopPlayback();
    _undo.add((z.snapshot(), _log.length, _walked.length));
    if (_undo.length > _undoMax) _undo.removeAt(0);
    _log.add(LogEntry(LogEntry.command, cmd.toUpperCase()));
    final from = z.status.roomObject, moves = z.status.moves;
    final out = z.input(cmd);
    // The game's own RESTART starts over at move 0: forget the paths.
    if (z.state == ZState.waitingForInput && moves > 0 && z.status.moves == 0) _walked.clear();
    _recordWalk(from, z.status.roomObject);
    _afterGame(out);
  }

  void _afterGame(String out) {
    final z = _z!;
    if (z.state == ZState.waitingForRestore) {
      _addOutput(out);
      setState(() {});
      _pickRestore();
      return;
    }
    _addOutput(out);
    setState(() {});
    _scrollToEnd();
    _autosave();
    _play();
  }

  /// A path for the map: only between rooms the story connects, so a
  /// teleport or several moves in one line don't draw a false path.
  void _recordWalk(int from, int to) {
    final m = _map;
    if (m == null || from == to || from == 0 || to == 0 || !m.connected(from, to)) return;
    final p = from < to ? (from, to) : (to, from);
    if (!_walked.contains(p)) _walked.add(p);
  }

  bool _onGameSave(ZSnapshot snap) {
    final st = _z!.status;
    final name = '${st.room} · ${st.score}';
    // The machine is inside SAVE here; the write happens in the background.
    _store.addSlot(snap, st, List.of(_log), List.of(_walked), name);
    return true;
  }

  Future<void> _pickRestore() async {
    if (_restoring) return;
    _restoring = true;
    final id = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => AdventureSavesScreen(store: _store, pickOnly: true)));
    _restoring = false;
    final z = _z!;
    SaveData? save = id == null ? null : await _store.loadSlot(id);
    if (save != null && !z.matches(save.snapshot)) save = null;
    if (!mounted) return;
    final out = z.completeRestore(save?.snapshot);
    if (save != null) {
      _log
        ..clear()
        ..addAll(save.log)
        ..add(LogEntry(LogEntry.info, Strings.t('adv_loaded').replaceAll('{n}', save.info.name)));
      _walked
        ..clear()
        ..addAll(save.walked);
      _undo.clear();
      _applyVerbosity();
    }
    _afterGame(out);
  }

  Future<void> _loadSave(String id) async {
    final z = _z;
    if (z == null) return;
    await _autosave();
    final save = await _store.loadSlot(id);
    if (save == null || !z.matches(save.snapshot) || !mounted) return;
    _stopPlayback();
    z.load(save.snapshot);
    setState(() {
      _log
        ..clear()
        ..addAll(save.log);
      _walked
        ..clear()
        ..addAll(save.walked);
      if (id != 'auto') {
        _log.add(LogEntry(LogEntry.info, Strings.t('adv_loaded').replaceAll('{n}', save.info.name)));
      }
      _undo.clear();
      _applyVerbosity();
      _setCurrent(play: false);
    });
    _scrollToEnd();
    _autosave();
  }

  Future<void> _saveNow() async {
    final z = _z;
    if (z == null || z.state != ZState.waitingForInput) return;
    final st = z.status;
    final info = await _store.addSlot(z.snapshot(), st, List.of(_log), List.of(_walked),
        '${st.room} · ${st.score}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.t('adv_saved').replaceAll('{n}', info.name))));
  }

  void _undoMove() {
    final z = _z;
    if (z == null) return;
    if (_undo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.t('adv_undo_none'))));
      return;
    }
    final (snap, logLen, walkedLen) = _undo.removeLast();
    _stopPlayback();
    z.load(snap);
    setState(() {
      _log.length = logLen;
      _walked.length = walkedLen;
      _setCurrent(play: false);
      _revealed = true;
    });
    _scrollToEnd();
    _autosave();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.t('adv_undone')), duration: const Duration(seconds: 1)));
  }

  Future<void> _restart() async {
    final ok = await confirmRestart(context, onSaveFirst: _saveNow);
    if (ok != true || !mounted) return;
    final z = _z!;
    _stopPlayback();
    setState(() {
      _log.clear();
      _undo.clear();
      _walked.clear();
    });
    final out = z.start();
    _applyVerbosity();
    _afterGame(out);
  }

  // ---- sheets ----

  Future<void> _openTempo() async {
    await showAdventureTempoSheet(context, _s,
        onChanged: () async {
          await _s.save();
          await _pushSpeed();
          await _pushKeyer();
          if (mounted) setState(() {});
        },
        onAgain: _again);
  }

  Future<void> _openSettings() async {
    // The map's "Don't ask again" writes the pref directly.
    _s.mapWarn = (await SharedPreferences.getInstance()).getBool(AdventureSettings.mapWarnKey) ?? true;
    if (!mounted) return;
    final before = (_s.scope, _s.verbosity, _s.show);
    await showAdventureSettingsSheet(context, _s, onChanged: () async {
      await _s.save();
      await _pushSpeed();
      await _pushKeyer();
      if (mounted) setState(() {});
    });
    if (!mounted) return;
    if (before.$2 != _s.verbosity) _applyVerbosity();
    if (before.$3 != _s.show && _s.show == 0) setState(() => _revealed = true);
    if (before.$1 != _s.scope) {
      final keepHeard = Set.of(_heard);
      setState(() {
        _setCurrent(play: false);
        _heard.addAll(keepHeard);
      });
    }
  }

  void _openMap() {
    final z = _z, m = _map;
    if (z == null || m == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => AdventureMapScreen(
        game: widget.game, map: m, visited: m.visited(z), walked: List.of(_walked),
        here: z.status.roomObject)));
  }

  Future<void> _openSaves() async {
    final action = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => AdventureSavesScreen(store: _store, pickOnly: false)));
    if (!mounted || action == null) return;
    if (action == 'save') {
      await _saveNow();
    } else if (action == 'restart') {
      await _restart();
    } else {
      await _loadSave(action);
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, _partTitle),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
                tooltip: Strings.t('adv_commands'),
                icon: Icon(Icons.help_outline, color: c.textMuted),
                onPressed: () => showAdventureCommandsSheet(context, widget.game.part)),
            if (_map != null)
              IconButton(
                  tooltip: Strings.t('adv_map'),
                  icon: Icon(Icons.map_outlined, color: c.textMuted),
                  onPressed: _openMap),
            IconButton(
                tooltip: Strings.t('adv_tempo'),
                icon: Icon(Icons.speed, color: c.textMuted),
                onPressed: _ready ? _openTempo : null),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: c.textMuted),
              color: c.surface,
              enabled: _ready,
              onSelected: (v) {
                switch (v) {
                  case 'save': _saveNow();
                  case 'load': _openSaves();
                  case 'undo': _undoMove();
                  case 'settings': _openSettings();
                  case 'restart': _restart();
                }
              },
              itemBuilder: (_) => [
                _menuItem(c, 'save', Icons.save_outlined, Strings.t('adv_save')),
                _menuItem(c, 'load', Icons.folder_open_outlined, Strings.t('adv_load')),
                _menuItem(c, 'undo', Icons.undo, Strings.t('adv_undo_menu')),
                const PopupMenuDivider(),
                _menuItem(c, 'settings', Icons.settings_outlined, Strings.t('adv_settings')),
                const PopupMenuDivider(),
                _menuItem(c, 'restart', Icons.restart_alt, Strings.t('adv_restart'), color: c.danger),
              ],
            ),
          ],
        ),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text(_error!, style: TextStyle(fontFamily: 'CwMono', color: c.danger))))
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : _body(c),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(AppColors c, String v, IconData icon, String label, {Color? color}) =>
      PopupMenuItem(value: v, child: Row(children: [
        Icon(icon, size: 20, color: color ?? c.textMuted),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: color ?? c.textPrimary)),
      ]));

  /// Small phones (or a large font): drop the speed strip and key hint so
  /// the transcript keeps some room above the keyboard.
  bool get _compact => MediaQuery.of(context).size.height / textScaleOf(context) < 700;

  Widget _body(AppColors c) {
    final z = _z!;
    final st = z.status;
    final ended = z.state == ZState.quit;
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: c.surfaceAlt,
            border: Border.symmetric(horizontal: BorderSide(color: c.border))),
        child: Row(children: [
          Expanded(child: Text(st.room, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.logText))),
          Text('Score ${st.score} · Moves ${st.moves}',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.logText)),
        ]),
      ),
      Expanded(child: _transcript(c)),
      // Short screens: the ⏱ icon still opens the speed sheet.
      if (!_compact) _tempoStrip(c),
      _controls(c),
      if (ended) _endPanel(c) else ..._inputArea(c),
    ]);
  }

  Widget _transcript(AppColors c) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      itemCount: _log.length,
      itemBuilder: (context, i) {
        final e = _log[i];
        final style = TextStyle(fontFamily: 'CwMono', fontSize: 14, height: 1.4, color: c.logText);
        Widget child;
        if (e.kind == LogEntry.command) {
          child = Text('> ${e.text}', style: style.copyWith(color: c.accent));
        } else if (e.kind == LogEntry.banner) {
          child = Text(e.text, style: style.copyWith(color: c.textFaint, fontSize: 12));
        } else if (e.kind == LogEntry.info) {
          child = Text('— ${e.text} —', style: style.copyWith(color: c.textFaint, fontSize: 12));
        } else if (i == _curEntry && _passage != null) {
          child = _currentAnswer(c, style.copyWith(color: c.textPrimary, fontSize: 15));
        } else {
          child = Text(e.text, style: style);
        }
        return Padding(
            key: i == _curEntry ? _curKey : null,
            padding: const EdgeInsets.only(bottom: 10), child: child);
      },
    );
  }

  Widget _currentAnswer(AppColors c, TextStyle base) {
    final p = _passage!;
    if (_s.show == 2 && !_revealed) {
      return GestureDetector(
        onTap: () => setState(() => _revealed = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_outlined, size: 18, color: c.textMuted),
            const SizedBox(width: 8),
            Text(Strings.t('adv_tap_reveal'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
          ]),
        ),
      );
    }
    final cur = _currentWord;
    final spans = <InlineSpan>[];
    var line = 0;
    for (var i = 0; i < p.words.length; i++) {
      final w = p.words[i];
      if (i > 0) {
        if (w.line != line) {
          spans.add(TextSpan(text: '\n' * (w.line - line)));
        } else {
          spans.add(const TextSpan(text: ' '));
        }
      }
      line = w.line;
      final played = w.inScope && w.cw.isNotEmpty;
      final hidden = played && !_revealed && !_heard.contains(i);
      var st = base;
      if (!w.inScope) st = st.copyWith(color: c.textMuted, fontStyle: FontStyle.italic);
      if (hidden) {
        st = st.copyWith(color: Colors.transparent,
            decoration: TextDecoration.underline,
            decorationColor: i == cur ? c.accent : c.textDisabled,
            decorationThickness: 2);
      } else if (i == cur) {
        st = st.copyWith(backgroundColor: c.accent.withOpacity(0.3));
      }
      spans.add(TextSpan(
        text: w.display,
        style: st,
        recognizer: played && !hidden
            ? (TapGestureRecognizer()..onTap = () => _play(from: i, to: i))
            : null,
      ));
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }

  Widget _tempoStrip(AppColors c) {
    Widget item(String l, String v) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: TextStyle(color: c.textMuted)),
          TextSpan(text: v, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        ]), style: const TextStyle(fontFamily: 'CwMono', fontSize: 12));
    return GestureDetector(
      onTap: _openTempo,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
        // Shrinks instead of overflowing at large font sizes.
        child: LayoutBuilder(builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              item(Strings.t('adv_hear'), '${_s.wpm}'),
              const SizedBox(width: 12),
              item(Strings.t('adv_give'), '${_s.keyWpm}'),
              const SizedBox(width: 12),
              item(Strings.t('adv_strip_char'), '${_s.interChar}'),
              const SizedBox(width: 12),
              item(Strings.t('adv_strip_word'), '${_s.interWord}'),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _controls(AppColors c) {
    Widget small(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(height: 50, child: Center(child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 20, color: onTap == null ? c.textDisabled : c.textPrimary),
                  Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 10,
                      color: onTap == null ? c.textDisabled : c.textMuted)),
                ]),
              ))),
            ),
          ),
        );
    final canPlay = _passage?.hasAudio ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: Material(
            color: canPlay ? c.accent : c.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: canPlay ? _againSentence : null,
              onLongPress: canPlay ? _again : null,
              child: SizedBox(height: 50, child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.replay, color: canPlay ? c.background : c.textDisabled),
                  const SizedBox(width: 8),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(Strings.t('adv_again'),
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 15, fontWeight: FontWeight.bold,
                          color: canPlay ? c.background : c.textDisabled)))),
                ],
              )),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _pausedAt != null
            ? small(Icons.play_arrow, Strings.t('adv_resume'), _resume)
            : small(Icons.pause, Strings.t('adv_pause'), _playing ? _pause : null),
        const SizedBox(width: 6),
        small(_textVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            Strings.t('adv_text'), _passage == null ? null : _toggleText),
        const SizedBox(width: 6),
        small(Icons.undo, Strings.t('adv_undo'), _undo.isEmpty ? null : _undoMove),
      ]),
    );
  }

  List<Widget> _inputArea(AppColors c) {
    final paddle = _s.input == 0;
    final hint = paddle ? Strings.t(const ['adv_key_hint_ar', 'adv_key_hint_k', 'adv_key_hint_btn'][_s.send])
        : Strings.t('adv_keys_hint');
    return [
      Container(
        margin: EdgeInsets.fromLTRB(12, 8, 12, _compact ? 6 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        width: double.infinity,
        decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Text('> ', style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.accent)),
          // The end of the line stays visible while a long command grows.
          Expanded(child: LayoutBuilder(builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: _input, style: TextStyle(color: c.textPrimary)),
                if (_elements.isNotEmpty) TextSpan(text: _elements, style: TextStyle(color: c.warning)),
              ]), maxLines: 1, style: const TextStyle(fontFamily: 'CwMono', fontSize: 16)),
            ),
          ))),
        ]),
      ),
      if (!_compact) Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
      ),
      if (paddle) ..._paddleInput(c) else CwKeyboard(
        active: _keyboardKeys,
        outputCase: 1,
        passLabel: '␣',
        submitLabel: '⏎',
        onKey: (k) => setState(() => _input += k),
        onBackspace: () => setState(() {
          if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        }),
        onPass: () => setState(() {
          if (_input.isNotEmpty && !_input.endsWith(' ')) _input += ' ';
        }),
        onSubmit: _submit,
      ),
    ];
  }

  List<Widget> _paddleInput(AppColors c) {
    Widget btn(IconData icon, String label, VoidCallback? onTap, {Color? color}) => Expanded(
          child: Material(
            color: color ?? c.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox(height: 40, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: color != null ? c.background : c.textMuted),
                const SizedBox(width: 6),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label,
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
                        fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
                        color: color != null ? c.background : c.textMuted)))),
              ])),
            ),
          ),
        );
    final has = _input.trim().isNotEmpty;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(12, _compact ? 0 : 2, 12, 8),
        child: Row(children: [
          btn(Icons.backspace_outlined, Strings.t('adv_del_word'), has ? _deleteWord : null),
          const SizedBox(width: 6),
          btn(Icons.clear, Strings.t('adv_clear_line'), has ? () => setState(() => _input = '') : null),
          const SizedBox(width: 6),
          btn(Icons.keyboard_return, Strings.t('adv_send'), has ? _submit : null,
              color: has ? c.accent : null),
        ]),
      ),
      if (_keyerMode == 4)
        StraightKeyPaddle(
            onDown: () => _setTouch(dit: true),
            onUp: () => _setTouch(dit: false))
      else
        IambicPaddles(
          onDitDown: () => _setTouch(dit: true),
          onDitUp: () => _setTouch(dit: false),
          onDahDown: () => _setTouch(dah: true),
          onDahUp: () => _setTouch(dah: false),
        ),
      SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
    ];
  }

  static final Set<String> _keyboardKeys = {
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''),
    '.', ',', '?', '-',
  };

  Widget _endPanel(AppColors c) {
    final st = _z!.status;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(Strings.t('adv_end_title'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 18, fontWeight: FontWeight.bold,
                color: c.textPrimary)),
        const SizedBox(height: 4),
        Text(Strings.t('adv_end_body').replaceAll('{s}', '${st.score}').replaceAll('{m}', '${st.moves}'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: AppButton(label: Strings.t('adv_load_save'), color: c.accent, onTap: _openSaves)),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: Strings.t('adv_undo_menu'), color: c.info,
              onTap: _undo.isEmpty ? null : _undoMove)),
        ]),
        const SizedBox(height: 8),
        AppButton(label: Strings.t('adv_restart'), color: c.danger, onTap: _restart),
      ]),
    );
  }
}
