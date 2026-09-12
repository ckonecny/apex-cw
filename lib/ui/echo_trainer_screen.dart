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

// Log span roles — mirrors the distinct FONT_ATTRIBs the real device uses in
// this same scrolling log (m32_v6.ino: frameWordForDisplay/BOLD for the
// vvv<ka>/+ markers, OK_RESULT/ERR_RESULT for the verdict, INVERSE_REGULAR
// for a given-up word's reveal, REGULAR/keyed for the operator's own keying).
enum _Role { marker, target, attempt, ok, err, reveal }

class _LogSpan {
  String text;
  final _Role role;
  _LogSpan(this.text, this.role);
}

class EchoTrainerScreen extends StatefulWidget {
  // When set, locks onto this single character instead of picking a random
  // target: the same char repeats every round (M32 Koch Trainer "Learn New
  // Chr" / "Preview Char" — both funnel into the Echo Trainer engine drilling
  // one fixed character; see Koch::getNewChar()/getKochChar()). No start/end
  // markers and no Max # of Words in this mode, matching KOCH_LEARN/PREVIEW.
  final String? fixedTarget;
  final String? title;
  // Koch Trainer's own Echo Trainer branch (MorseMenu.cpp: "Koch Trainer >
  // Echo Trainer" — Random/CW Abbrevs/English Words/Mixed/Adapt. Rand.):
  // a separate, Koch-filtered content mode selector from the standalone
  // top-level Echo Trainer's own (Random/Words/Calls/Mixed/PracticeSet/Abbrevs).
  final bool kochMode;
  const EchoTrainerScreen({super.key, this.fixedTarget, this.title, this.kochMode = false});

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
  // Koch Trainer's own Echo submenu (widget.kochMode only): position ->
  // CwGenerator.Mode ordinal, matching MorseMenu.cpp's "Koch Trainer > Echo
  // Trainer" list (Random/CW Abbrevs/English Words/Mixed/Adapt. Rand. — no
  // Call Signs, no File Player). Random(0) and Adapt. Rand.(4) are handled
  // locally in Dart (see _fetchTarget()), so their ordinals here are unused.
  static const _kochModeOrdinals = [0, 5, 1, 3, 0];
  static const _kochModeLabels = ['Zufall', 'Abkürzungen', 'Wörter', 'Gemischt', 'Adapt. Rand.'];
  int    _kochModeIndex = 0;
  // "Adapt. Rand." (KOCH_ADAPTIVE): weighted-random character draw — wrong
  // answers raise a character's weight (drawn more often), right answers
  // lower it, within [1,20]. A simplified, in-app stand-in for the firmware's
  // persisted Koch::adaptiveProbabilities[]/fireCharSeen() system: same idea
  // (struggle with a char, see it more), without the full NVS-backed
  // per-attempt bookkeeping.
  Map<String, int> _adaptiveWeight = {};
  int    _kochSeq         = 0;
  String _customKochChars = '';
  int    _licwCarouselStart = 0;
  List<String> get _activeKochChars =>
      kochSequenceChars(_kochSeq, _customKochChars, licwCarouselStart: _licwCarouselStart);
  int  _abbrevLengthMax = 0;
  int  _callLengthOpt   = 0;
  int  _callRegionOpt   = 0;
  bool _callCommonOnly  = true;
  int  _outputCase      = 0;   // 0=lower, 1=UPPER — display only
  // "Random"/"Zufall" and "Adapt. Rand." echo a GROUP of characters, not a
  // single one — matches fetchNewWord()'s RANDOMS/KOCH_ADAPTIVE cases in
  // m32_v6.ino, both getRandomChars(posRandomLength, ...): the same shared
  // "Gruppen-Länge"/"Random Groups" prefs the CW Generator uses.
  int  _groupLength  = 5;
  int  _randomOption = 0;
  // "Max # of Words" (posMaxSequence) — shared with the CW Generator; 0 = unlimited.
  int  _maxWords = 0;

  // Touch paddle: 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight
  int _keyerMode = 0;
  bool _touchDit = false;
  bool _touchDah = false;

  // Echo settings (from SharedPreferences)
  int  _echoThinkTime = 8;   // seconds
  int  _echoRepeats   = 3;   // M32 "Echo Repeats": 0..6, or 7 = "Forever"
  int  _echoDisplay   = _dispCodeOnly;  // matches M32 "Echo Prompt": sound/display/both
  bool _confirmTone   = false;
  bool _adaptiveSpeed = false;
  int  _echoSpeedMax  = 35;

  String _target  = '';
  String _attempt = '';

  int _correct = 0;
  int _total   = 0;
  // "repeats" in m32_v6.ino: how many times the CURRENT word has been
  // presented (first play counts as 1) — compared against Echo Repeats to
  // decide whether to replay it again or give up and reveal it.
  int _repeats = 0;
  // "wordCounter" in m32_v6.ino: words presented this session, for Max # of Words.
  int _wordCounter = 0;
  bool _sessionActive = false;   // guards against a stale target fetch after Stop

  // Adaptive speed tracking
  int _currentWpm = 20;

  // Scrolling transcript — matches the CW Generator's log concept exactly
  // (m32_v6.ino has no separate "big flashcard" UI for Echo Trainer either;
  // target/attempt/verdict/reveal all interleave into one continuous scroll).
  final List<_LogSpan> _log = [];
  final ScrollController _logScroll = ScrollController();
  bool _stickToBottom = true;
  // True while a start/end marker is being played via playOne() — the 'done'
  // event it produces must not be mistaken for the target word finishing.
  bool _awaitingSignal = false;
  Completer<void>? _signalDone;
  // Set right before a target word's playOne() call so the 'done' handler
  // knows whether to reveal it (Echo Prompt != Sound only).
  bool _revealOnDone = false;

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
    _logScroll.addListener(() {
      if (!_logScroll.hasClients) return;
      _stickToBottom = _logScroll.position.pixels >= _logScroll.position.maxScrollExtent - 4;
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _wpm            = p.getInt('wpm')            ?? 20;
      _kochLevel      = p.getInt('kochLevel')      ?? 5;
      _echoThinkTime  = p.getInt('echoThinkTime')  ?? 8;
      _echoRepeats    = (p.getInt('echoRepeats')   ?? 3).clamp(0, 7);
      _echoDisplay    = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _confirmTone    = p.getBool('confirmTone')   ?? false;
      _adaptiveSpeed  = p.getBool('adaptiveSpeed') ?? false;
      _echoSpeedMax   = p.getInt('echoSpeedMax')   ?? 35;
      _modeIndex      = (p.getInt('echoModeIndex') ?? 0).clamp(0, 5);
      _kochModeIndex  = (p.getInt('kochEchoModeIndex') ?? 0).clamp(0, _kochModeLabels.length - 1);
      _keyerMode      = p.getInt('keyerMode')      ?? 0;
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = p.getString('customKochChars') ?? '';
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _abbrevLengthMax = (p.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      _outputCase      = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _groupLength     = p.getInt('groupLength')    ?? 5;
      _randomOption    = (p.getInt('randomOption')  ?? 0).clamp(0, 9);
      _maxWords        = p.getInt('maxWords')        ?? 0;
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
      _currentWpm     = _wpm;
    });
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
    _loadAdaptiveWeights();
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm',       _wpm);
    await p.setInt('kochLevel', _kochLevel);
    await p.setInt('echoModeIndex', _modeIndex);
    await p.setInt('kochEchoModeIndex', _kochModeIndex);
  }

  Future<void> _loadAdaptiveWeights() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('adaptiveWeights') ?? '';
    final map = <String, int>{};
    for (final part in raw.split(',')) {
      final kv = part.split(':');
      if (kv.length == 2) {
        final w = int.tryParse(kv[1]);
        if (w != null) map[kv[0]] = w;
      }
    }
    if (mounted) setState(() => _adaptiveWeight = map);
  }

  Future<void> _saveAdaptiveWeights() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('adaptiveWeights', _adaptiveWeight.entries.map((e) => '${e.key}:${e.value}').join(','));
  }

  // Weighted-random single character from the active Koch set — weight
  // defaults to 1 (never drawn yet / already mastered back down to baseline).
  String _pickAdaptiveChar() {
    final active = kochActiveChars(_kochLevel, _activeKochChars);
    final weights = active.map((c) => _adaptiveWeight[c] ?? 1).toList();
    final total = weights.fold<int>(0, (a, b) => a + b);
    var r = _random.nextInt(total);
    for (var i = 0; i < active.length; i++) {
      if (r < weights[i]) return active[i];
      r -= weights[i];
    }
    return active.last;
  }

  // "Adapt. Rand." echoes a GROUP, same as Random — matches
  // getRandomChars(posRandomLength, OPT_KOCH_ADAPTIVE) in m32_v6.ino.
  String _pickAdaptiveGroup() =>
      List.generate(_groupLength.clamp(2, 8), (_) => _pickAdaptiveChar()).join();

  void _applyAdaptiveFeedback(String target, bool correct) {
    if (!widget.kochMode || _kochModeIndex != 4) return;
    for (final ch in target.split('')) {
      final w = _adaptiveWeight[ch] ?? 1;
      _adaptiveWeight[ch] = (correct ? w - 1 : w + 2).clamp(1, 20);
    }
    _saveAdaptiveWeights();
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _silenceTimer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stop');
    _keyerChannel.invokeMethod('stop');
    _logScroll.dispose();
    super.dispose();
  }

  // ── Log ──────────────────────────────────────────────────────────────────

  void _appendLog(String text, _Role role) {
    if (text.isEmpty) return;
    if (_log.isNotEmpty && _log.last.role == role) {
      _log.last.text += text;
    } else {
      _log.add(_LogSpan(text, role));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stickToBottom || !_logScroll.hasClients) return;
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  // ── Session control ────────────────────────────────────────────────────────

  Future<void> _startSession() async {
    if (_state != _State.idle) return;   // guard against a double-tap racing two sessions
    _correct = 0; _total = 0; _wordCounter = 0;
    _currentWpm = _wpm;
    _sessionActive = true;

    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    // Keep the scrolling log across Start presses — like the real device
    // (and matching the CW Generator screen), a new session just continues
    // underneath what was already practiced; it only clears on leaving and
    // re-entering this screen (a fresh State instance).
    setState(() => _state = _State.playing);

    // Starting signal, sent at the start of every fresh session — same
    // "vvv<ka>" marker as the CW Generator (m32_v6.ino: clearText = "vvvA";
    // frameWordForDisplay = true), skipped for Learn New Chr/Preview Char
    // (KOCH_LEARN/KOCH_PREVIEW set startFirst = false).
    if (widget.fixedTarget == null) {
      await _playSignal('VVVKA');
      if (!mounted || !_sessionActive) return;
      setState(() {
        if (_log.isNotEmpty) _appendLog('\n', _Role.marker);
        _appendLog('vvv<ka>', _Role.marker);
      });
    }

    await _playWord(fresh: true);
  }

  void _stopSession() {
    _sessionActive = false;
    _silenceTimer?.cancel();
    _genSub?.cancel();   _genSub   = null;
    _symbolSub?.cancel(); _symbolSub = null;
    if (_awaitingSignal) {
      _awaitingSignal = false;
      _signalDone?.complete();
    }
    _genChannel.invokeMethod('stop');
    _keyerChannel.invokeMethod('stop');
    if (mounted) setState(() => _state = _State.idle);
  }

  /// Plays a marker string (start "VVVKA" / end "+") via the native playOne()
  /// and waits for its genuine completion.
  Future<void> _playSignal(String morse) async {
    final completer = Completer<void>();
    _signalDone = completer;
    _awaitingSignal = true;
    await _genChannel.invokeMethod('playOne', morse);
    await completer.future;
    _awaitingSignal = false;
  }

  /// End signal, sent when "Max # of Words" is reached — matches the CW
  /// Generator's "+" (=<ar>) marker, not sent on manual Stop.
  Future<void> _playEndSignal() async {
    await _playSignal('+');
    if (mounted) setState(() {
      if (_log.isNotEmpty) _appendLog(' ', _Role.marker);
      _appendLog('+', _Role.marker);
    });
  }

  // Fetches (unless repeating the same word) and plays the next target,
  // matching fetchNewWord()'s SEND_WORD/REPEAT_WORD handling in m32_v6.ino.
  Future<void> _playWord({required bool fresh}) async {
    _symbolSub?.cancel(); _symbolSub = null;
    _silenceTimer?.cancel();
    _decoder.reset();

    if (fresh) {
      _repeats = 0;
      final fetched = await _fetchTarget();
      if (!mounted || !_sessionActive) return;
      _target = fetched;
    }
    _repeats++;
    _attempt = '';

    // Every word (fresh or a repeat) starts its own line, whatever the
    // previous verdict was — keeps each round scannable at a glance.
    if (mounted) setState(() {
      if (_log.isNotEmpty) _appendLog('\n', _Role.attempt);
    });
    if (mounted) setState(() => _state = _State.playing);

    // Echo Prompt = Display only: no audio at all, just show the target briefly
    // (mirrors the real device's "silentEcho": genTimer skips almost instantly).
    if (_echoDisplay == _dispDispOnly) {
      if (mounted) setState(() {
        _appendLog(_target, _Role.target);
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_state == _State.playing && mounted) _beginReceive();
      });
      return;
    }

    _revealOnDone = _echoDisplay != _dispCodeOnly;
    await _genChannel.invokeMethod('setWpm', _currentWpm).catchError((_) {});
    await _genChannel.invokeMethod('playOne', _target);
  }

  void _onGenEvent(dynamic raw) {
    final ev = raw as Map;
    final type = ev['type'] as String;
    if (_awaitingSignal) {
      // Belongs to a start/end marker's playOne(), not the target word.
      if (type == 'done') _signalDone?.complete();
      return;
    }
    if (!mounted) return;
    if (type == 'done' && _state == _State.playing) {
      if (_revealOnDone) {
        setState(() => _appendLog(_target, _Role.target));
      }
      _beginReceive();
    }
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
    _attempt += ch;
    setState(() => _appendLog(ch, _Role.attempt));
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
        if (mounted && _sessionActive) _playWord(fresh: false);
      });
      return;
    }

    _total++;

    final ok = _attempt.trim().toUpperCase() == _target.toUpperCase();
    _applyAdaptiveFeedback(_target, ok);

    setState(() {
      _state = ok ? _State.correct : _State.wrong;
      if (_log.isNotEmpty) _appendLog(' ', ok ? _Role.ok : _Role.err);
      _appendLog(ok ? 'OK' : 'ERR', ok ? _Role.ok : _Role.err);
    });
    if (_confirmTone) _toneChannel.invokeMethod('playConfirmTone', ok);

    if (ok) {
      _correct++;
      // Adaptive speed: every 10 correct, bump by 1 WPM up to max
      if (_adaptiveSpeed && _correct % 10 == 0) {
        _currentWpm = (_currentWpm + 1).clamp(_wpm, _echoSpeedMax);
      }
      Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _sessionActive) _advance();
      });
      return;
    }

    // "Echo Repeats": 7 = Forever (always replay), else replay while the
    // word has been presented _echoRepeats times or fewer so far — matches
    // REPEAT_WORD's `repeats <= posEchoRepeats.value` check in m32_v6.ino.
    final alwaysRepeat = _echoRepeats == 7;
    final exhausted = widget.fixedTarget == null && !alwaysRepeat && _repeats > _echoRepeats;
    if (exhausted) {
      // Reveal the word, then move on — matches the REPEAT_WORD "goto
      // randomGenerate" branch's displayGeneratedMorse(INVERSE_REGULAR, ...).
      // The separating space stays ERR-styled (regular, not inverse) —
      // only the revealed word itself gets the inverse block, same as the
      // firmware's own trailing displayGeneratedMorse(REGULAR, " ").
      setState(() {
        if (_log.isNotEmpty) _appendLog(' ', _Role.err);
        _appendLog(_target, _Role.reveal);
      });
      Timer(const Duration(milliseconds: 2000), () {
        if (mounted && _sessionActive) _advance();
      });
    } else {
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _sessionActive) _playWord(fresh: false);
      });
    }
  }

  // Moves on to the next word, or ends the session if Max # of Words has
  // been reached — matches fetchNewWord()'s posMaxSequence handling.
  Future<void> _advance() async {
    if (widget.fixedTarget == null) {
      _wordCounter++;
      if (_maxWords > 0 && _wordCounter >= _maxWords) {
        await _playEndSignal();
        if (mounted) setState(() => _state = _State.idle);
        _sessionActive = false;
        _genSub?.cancel(); _genSub = null;
        _keyerChannel.invokeMethod('stop');
        return;
      }
    }
    await _playWord(fresh: true);
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

    if (widget.kochMode) {
      switch (_kochModeIndex) {
        case 0: // Zufall — a GROUP of active Koch characters, matching
                // getRandomChars(posRandomLength, ...)'s kochActive branch
                // (koch.getRandomChar(maxLength)) in m32_v6.ino, not one char.
          final result = await _genChannel.invokeMethod('getNextContent', {
            'mode': 0,   // CwGenerator.Mode.RANDOM_CHARS
            'kochLevel': _kochLevel,
            'kochActive': true,
            'groupLength': _groupLength,
          });
          return (result as String?) ?? '';
        case 4: // Adapt. Rand. — also a group (getRandomChars(..., OPT_KOCH_ADAPTIVE))
          return _pickAdaptiveGroup();
        default: // Abkürzungen/Wörter/Gemischt — Koch-filtered (kochActive: true)
          final result = await _genChannel.invokeMethod('getNextContent', {
            'mode': _kochModeOrdinals[_kochModeIndex],
            'kochLevel': _kochLevel,
            'kochActive': true,
            'abbrevLengthMax': _abbrevLengthMax,
          });
          return (result as String?) ?? '';
      }
    }

    if (_modeIndex == 0) {
      // Random — a GROUP of characters from the "Random Groups" pool, same
      // shared prefs and Kotlin path as the CW Generator's Random Chars mode
      // (getRandomChars(posRandomLength, posRandomOption) in m32_v6.ino).
      final result = await _genChannel.invokeMethod('getNextContent', {
        'mode': 0,   // CwGenerator.Mode.RANDOM_CHARS
        'kochLevel': _kochLevel,
        'kochActive': false,
        'groupLength': _groupLength,
        'randomOption': _randomOption,
      });
      return (result as String?) ?? '';
    }
    // Words/Callsigns/Mixed/Practice Set/Abbrevs: generated Kotlin-side from the
    // same content pools as the CW Generator (mode ordinals 1..5 line up directly).
    final result = await _genChannel.invokeMethod('getNextContent', {
      'mode': _modeIndex,
      'kochLevel': _kochLevel,
      'kochActive': false,
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
            widget.kochMode
                ? _EchoModeSelector(
                    labels: _kochModeLabels,
                    selected: _kochModeIndex,
                    enabled: _state == _State.idle,
                    onChanged: (i) { setState(() => _kochModeIndex = i); _savePrefs(); },
                  )
                : _EchoModeSelector(
                    selected: _modeIndex,
                    enabled: _state == _State.idle,
                    onChanged: (i) { setState(() => _modeIndex = i); _savePrefs(); },
                  ),
            if (widget.kochMode)
              _KochCharsRow(level: _kochLevel, sequence: _activeKochChars),
          ],

          // ── Scrolling transcript (target/attempt/verdict/markers) ───────
          Expanded(child: PinchZoomFontSize(
            prefsKey: 'echoLogFontSize',
            initialSize: 26,
            minSize: 14,
            maxSize: 48,
            builder: (context, fontSize) => Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: _buildLog(fontSize),
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
              if (widget.fixedTarget == null && widget.kochMode)
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

  Widget _buildLog(double fontSize) {
    final c = AppColors.of(context);
    if (_log.isEmpty) {
      return Align(alignment: Alignment.bottomLeft, child: Text('▶ START drücken',
          style: TextStyle(fontFamily: 'CwMono', fontSize: 20,
              color: c.textDisabled, fontStyle: FontStyle.italic)));
    }
    return Scrollbar(
      controller: _logScroll,
      child: SingleChildScrollView(
        controller: _logScroll,
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(children: _log.map((span) {
            final text = _outputCase == 1 ? span.text.toUpperCase() : span.text.toLowerCase();
            // "reveal" (the word given up on) is shown INVERSE — background/
            // foreground swapped — matching the real device's
            // displayGeneratedMorse(INVERSE_REGULAR, ...) for that word.
            final (color, background, weight) = switch (span.role) {
              _Role.marker  => (c.warning, null, FontWeight.bold),
              _Role.target  => (c.accent, null, FontWeight.bold),
              _Role.attempt => (c.textPrimary, null, FontWeight.normal),
              _Role.ok      => (c.accent, null, FontWeight.bold),
              _Role.err     => (c.danger, null, FontWeight.bold),
              _Role.reveal  => (c.background, c.warning, FontWeight.bold),
            };
            return TextSpan(text: text, style: TextStyle(
                fontFamily: 'CwMono', fontSize: fontSize, height: 1.5,
                color: color, backgroundColor: background, fontWeight: weight));
          }).toList()),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
  static const _defaultLabels = ['Zufall', 'Wörter', 'Rufzeichen', 'Gemischt', 'Practice Set', 'Abkürzungen'];
  final List<String> labels;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _EchoModeSelector({required this.selected, required this.enabled, required this.onChanged,
      this.labels = _defaultLabels});

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
          children: List.generate(labels.length, (i) {
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
                child: Text(labels[i], textAlign: TextAlign.center,
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
