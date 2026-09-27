// Adaptive Copy Mode — listen-and-copy flow: send a block of groups,
// reveal, tap errors, show a result. See docs/ADAPTIVE-COPY.md.
// Two ways to copy (DECISIONS.md "Hören: typing mode"): on paper (the whole
// block plays, errors are tapped afterwards) or typed on CwKeyboard (one
// word per step, graded from the first attempt, errors pre-marked).
//
// Tempo/spacing/Koch-level auto-adaptation is driven by AdaptiveCopyEngine
// (adaptive_copy_engine.dart) at the end of each block. The engine only
// computes decisions — this widget owns applying them (via the
// on*Changed callbacks, since wpm/kochLevel/spacing are GeneratorScreen's
// state, shared with the Classic flow) and persisting the blockquote EMA.
import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets/setting_rows.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/block_history.dart';
import '../content/char_stats.dart';
import '../content/training_profile.dart';
import '../content/cw_content.dart' show kochActiveChars, parsePracticeChars;
import '../content/adaptive_copy_engine.dart';
import '../content/copy_grading.dart';
import 'widgets/cw_keyboard.dart';
import 'widgets/char_playback_overlay.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import '../util/char_color.dart';
import '../l10n/strings.dart';

enum _Phase { idle, sending, revealed, result }

// Typing mode, per word: input = typing/waiting for the answer, wrong =
// short pause after a wrong attempt before the replay, correct = ✓ shown,
// solution = word shown after the last attempt or a pass.
enum _TypeState { input, wrong, correct, solution }

// Characters the generator can draw for "all characters" random groups, as
// CwGenerator.kt randomCharsAlphabet (prosigns arrive as their two letters,
// see _fetchGroup()), and its randomOption ranges.
const _randomAlphabet = [
  'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S',
  'T','U','V','W','X','Y','Z','0','1','2','3','4','5','6','7','8','9',
  '.',',',':','-','/','=','?','@','+','AS','KA','KN','SK','VE','BK',
];
(int, int) _randomOptionRange(int option) => switch (option) {
  1 => (0, 25), 2 => (26, 35), 3 => (36, 44), 4 => (44, 50), 5 => (0, 35),
  6 => (26, 44), 7 => (36, 50), 8 => (0, 44), 9 => (26, 50), _ => (0, 50),
};

// Lets the parent (GeneratorScreen) reset an in-progress session back to
// the idle/start phase — e.g. from the app bar back button, which during
// practice should return to the Koch Trainer setup screen rather than
// leaving the screen entirely. Bound in _AdaptiveCopyBodyState.initState().
class AdaptiveCopyController {
  VoidCallback? _resetToIdle;
  void Function(bool typing)? _start;
  void resetToIdle() => _resetToIdle?.call();
  /// typing: false = copy on paper, true = type on the on-screen keyboard.
  void start({bool typing = false}) => _start?.call(typing);
}

class AdaptiveCopyBody extends StatefulWidget {
  // true = Koch lesson; false = all characters / practice set (Phase 7):
  // no unlock, no tempo lock, weak-char boost only for random groups.
  final bool kochLesson;
  final int randomOption;
  final int wordLengthMax;
  // Firmware "Stop<Next>Rep": nach jeder Gruppe warten, Dit = Wiederholen, Dah = Weiter.
  final bool stopEachGroup;
  final int kochLevel;
  final List<String> activeKochChars;
  // Content mode within the Koch-nested selector (Random/Abbrevs/Words/Mixed
  // — see GeneratorScreen._kochModeOrdinals/_kochModeLabels, shared with the
  // Classic flow, not duplicated here).
  final int contentModeIndex;
  final List<int> contentModeOrdinals;
  final List<String> contentModeLabels;
  final int wpm;
  final int groupLength;
  final int maxWords;
  final int abbrevLengthMax;
  final int interCharSpace;
  final int interWordSpace;
  // Applies the adaptive engine's decisions back to the caller's state
  // (GeneratorScreen owns wpm/kochLevel/spacing, shared with the Classic
  // flow) — null-safe no-ops if the caller doesn't wire them up.
  final ValueChanged<int>? onWpmChanged;
  final ValueChanged<int>? onKochLevelChanged;
  final void Function(int interCharSpace, int interWordSpace)? onSpacingChanged;
  // Lets the parent hide its setup controls (mode selector, Learn New/
  // Preview/Practice Echo, Classic/Adaptiv toggle) while a block is active,
  // and reset back to idle from its own back button — see
  // AdaptiveCopyController above.
  final ValueChanged<bool>? onActiveChanged;
  // true while the typing keyboard is on screen — the parent hides its WPM
  // slider then, to leave room for the keys.
  final ValueChanged<bool>? onKeyboardChanged;
  final AdaptiveCopyController? controller;
  // Profile's practice set: the keyboard's active keys for that charset.
  final String practiceChars;

  const AdaptiveCopyBody({
    super.key,
    this.kochLesson = true,
    this.randomOption = 0,
    this.wordLengthMax = 0,
    this.stopEachGroup = false,
    required this.kochLevel,
    required this.activeKochChars,
    required this.contentModeIndex,
    required this.contentModeOrdinals,
    required this.contentModeLabels,
    required this.wpm,
    required this.groupLength,
    required this.maxWords,
    required this.abbrevLengthMax,
    required this.interCharSpace,
    required this.interWordSpace,
    this.onWpmChanged,
    this.onKochLevelChanged,
    this.onSpacingChanged,
    this.onActiveChanged,
    this.onKeyboardChanged,
    this.controller,
    this.practiceChars = '',
  });

  @override
  State<AdaptiveCopyBody> createState() => _AdaptiveCopyBodyState();
}

class _AdaptiveCopyBodyState extends State<AdaptiveCopyBody> {
  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  // Weak-char detection for the "weak characters" display and the
  // boost-next-block proposal: needs enough attempts to be meaningful (not
  // just one unlucky group) and an error rate clearly above noise. Reuses
  // CharStat.emaErrorRate — the same lifetime-persistent per-character store
  // Echo Trainer's "Adapt. Rand." already uses (docs/ADAPTIVE-COPY.md).
  static const _weakCharMinAttempts = 8;
  static const _weakCharThreshold = 0.12;
  static const _weakCharMaxShown = 5;

  // outputCase: 0=lower, 1=UPPER — display only, matches GeneratorScreen's
  // setting (generator_screen.dart); content/comparisons stay uppercase
  // internally.
  int _outputCase = 0;
  String _displayChar(String ch) => _outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();

  final CharStatsStore _charStats = CharStatsStore();
  AdaptiveCopyEngine? _engine;
  // Floor for the spacing "step down" direction — never make spacing wider
  // (slower/easier) than what the screen started with (docs/ADAPTIVE-COPY.md
  // "Success-rate high/low thresholds": "not below the configured start
  // value"). Captured once; independent of later widget.interCharSpace
  // changes driven by our own onSpacingChanged calls.
  late final int _startInterCharSpace = widget.interCharSpace;
  late final int _startInterWordSpace = widget.interWordSpace;
  TempoDecision? _lastDecision;
  bool _unlockedThisBlock = false;
  // Guards the "hear it" preview button against overlapping taps while a
  // preview is already playing (see _previewNewChar).
  bool _previewingNewChar = false;
  // Result-screen status line: the EMA the engine is actually reasoning
  // about, captured explicitly (not read back from `widget`, to not depend
  // on parent-rebuild timing).
  BlockTrend? _trend; // Trend über die letzten Blöcke, erst ab 6 Blöcken
  // Before values for the change notices, only set on a block where that
  // value actually changed.
  int? _wpmBefore;
  int? _interCharBefore, _interWordBefore;
  // Engine's proposed post-block values — not applied yet. The result
  // screen lets the user accept/reject each one (default: accepted, same
  // as the old fully-automatic behavior) and nudge the magnitude before
  // it's applied on "Next Block"/"Finish" (docs/ADAPTIVE-COPY.md, "User
  // override on the result screen" TODO). Null when the engine made no
  // proposal of that kind this block.
  int? _pendingWpm;
  int? _pendingInterChar, _pendingInterWord;
  bool _acceptCharSpeed = true;
  bool _acceptSpacing = true;
  bool _acceptUnlock = true;
  // Weak characters (lifetime EMA, not just this block) shown on the result
  // screen, keyed to error rate. Each is tapped on/off to control whether
  // it's included in the boosted draw for the next block — the "eingreifen
  // in die vorgeschlagenen Zeichen" override (docs/ADAPTIVE-COPY.md).
  Map<String, double> _weakChars = {};
  final Set<String> _excludedBoostChars = {};
  // wpm actually pushed to the generator for the in-flight block — set by
  // _startBlock(), independent of widget.wpm so a just-accepted override
  // takes effect immediately rather than waiting for a parent rebuild.
  int _activeWpm = 0;

  _Phase _phase = _Phase.idle;
  // Stop<Next>Rep: true = Gruppe wiederholen, false = weiter.
  Completer<bool>? _choiceGate;
  bool _awaitingChoice = false;
  int _blockNumber = 1;
  List<String> _sentGroups = [];
  int _currentGroupIndex = 0;
  // "$groupIndex:$charIndex" keys of characters tapped as wrong.
  final Set<String> _wrongPositions = {};
  // Word tapped open for character-level marking on the combined
  // sent/marking screen; null shows the word-tile overview.
  int? _markingWordIndex;
  int _resultCorrect = 0;
  int _resultTotal = 0;

  bool _paused = false;
  Completer<void>? _pauseGate;
  bool _sessionActive = false;
  Completer<void>? _doneCompleter;
  StreamSubscription? _genSub;
  // True for the brief pause right after "Start Block" — gives the user a
  // moment to get ready before the first group actually plays.
  bool _preparing = false;

  // ── Typing mode ──
  bool _typing = false;          // this session copies on the keyboard
  int _typeAttempts = 2;         // ⚙ "attempts per word", 1–3
  bool _typeHaptic = true;
  bool _confirmTone = true;      // global, set in Geben's ⚙ sheet
  _TypeState _typeState = _TypeState.input;
  String _input = '';
  String _target = '';           // word being asked
  String _shownWord = '';        // word shown in the correct/solution state
  bool _playing = false;
  int _attemptNo = 1;
  // Per sent group: every attempt (null = passed), and the outcome
  // (0 = right first time, 1 = right after a retry, 2 = failed/passed).
  List<List<String?>> _typedAttempts = [];
  List<int> _outcomes = [];
  Completer<String?>? _submitGate;
  bool _submitRequested = false; // ⏎ pressed while the word still played
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    widget.controller?._resetToIdle = _resetToIdle;
    widget.controller?._start = (typing) => _startBlock(typing: typing);
    _loadInitialWeakChars();
  }

  // Populates _weakChars from lifetime stats right away, so the idle/start
  // screen's panel (and the boost it drives) is available from the very
  // first block, not only after _finishBlock() has run once.
  // The native boost only works on random groups (Koch lesson or all
  // characters); the practice-set pool and words are not boosted.
  bool get _boostApplies =>
      widget.kochLesson || widget.contentModeOrdinals[widget.contentModeIndex] == 0;

  Map<String, double> _weakCharsNow() {
    if (!_boostApplies) return {};
    final chars = widget.kochLesson
        ? kochActiveChars(widget.kochLevel, widget.activeKochChars)
        : _charStats.stats.keys.toList();
    return weakCharsLifetime(_charStats, chars,
        minAttempts: _weakCharMinAttempts, threshold: _weakCharThreshold, maxShown: _weakCharMaxShown);
  }

  Future<void> _loadInitialWeakChars() async {
    final p = await SharedPreferences.getInstance();
    await _charStats.load(p);
    if (!mounted) return;
    setState(() {
      _outputCase = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _weakChars = _weakCharsNow();
      _excludedBoostChars.removeWhere((ch) => !_weakChars.containsKey(ch));
    });
  }

  @override
  void dispose() {
    _sessionActive = false;
    _checkTimer?.cancel();
    _completeSubmit(null);
    _genSub?.cancel();
    _genChannel.invokeMethod('stop');
    _genChannel.invokeMethod('setPaddleChoice', false);
    // The boost proposal pushes practiceChars/boostLevel to the shared
    // generator singleton (CLAUDE.md rule: nothing re-syncs this
    // automatically). Restore the Settings-persisted values on the way out
    // so leaving Adaptive Copy doesn't silently leave Classic mode (or the
    // Echo Trainer) boosting our leftover weak-char set.
    _restorePracticeCharsAndBoost();
    super.dispose();
  }

  // Bound to widget.controller — lets the parent's back button return to
  // the idle/start phase (and its setup controls) instead of leaving the
  // screen, without tearing down this whole widget.
  void _resetToIdle() {
    _sessionActive = false;
    _checkTimer?.cancel();
    _completeSubmit(null);
    widget.onKeyboardChanged?.call(false);
    _cancelChoice();
    _awaitingChoice = false;
    _genSub?.cancel();
    _genChannel.invokeMethod('stop');
    _genChannel.invokeMethod('setPaddleChoice', false);
    if (_pauseGate != null) {
      _pauseGate!.complete();
      _pauseGate = null;
    }
    if (mounted) setState(() { _phase = _Phase.idle; _paused = false; });
    widget.onActiveChanged?.call(false);
  }

  Future<void> _restorePracticeCharsAndBoost() async {
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    final practiceChars = parsePracticeChars(pf.getString('practiceChars') ?? '');
    final boostLevel = (pf.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setPracticeChars', practiceChars);
    await _genChannel.invokeMethod('setBoostLevel', boostLevel);
  }

  // Same fallback/range as the ⚙ sheet slider and Geben (echo_trainer_screen):
  // nothing stored (0) means 10.
  int get _blockSize => widget.maxWords == 0 ? 10 : widget.maxWords.clamp(1, 50);

  // Resolved target for the *next* block: the pending proposal if accepted,
  // otherwise the unchanged current value. Drives both the status line and
  // what actually gets pushed to the generator in _startBlock().
  int get _effectiveWpm =>
      (_acceptCharSpeed && _pendingWpm != null) ? _pendingWpm! : widget.wpm;
  int get _effectiveInterChar =>
      (_acceptSpacing && _pendingInterChar != null) ? _pendingInterChar! : widget.interCharSpace;
  int get _effectiveInterWord =>
      (_acceptSpacing && _pendingInterWord != null) ? _pendingInterWord! : widget.interWordSpace;

  // Farnsworth text speed implied by char speed + spacing: PARIS at
  // standard timing is 50 dit units/word, 31 of which are the marks
  // themselves (tied to char speed) — swap in the actual inter-char/
  // inter-word counts for the rest to get the real words-per-minute rate.
  int get _effectiveTextWpm {
    final unitsPerWord = 31 + 4 * _effectiveInterChar + _effectiveInterWord;
    return (50 * _effectiveWpm / unitsPerWord).round();
  }

  void _stepPendingWpm(int delta) {
    if (_pendingWpm == null) return;
    setState(() => _pendingWpm = (_pendingWpm! + delta).clamp(widget.wpm, widget.wpm + 5));
  }

  void _stepPendingSpacing(int delta) {
    if (_pendingInterChar == null || _pendingInterWord == null) return;
    setState(() {
      _pendingInterChar = (_pendingInterChar! + delta).clamp(3, _startInterCharSpace);
      // Typing mode: the word gap has no effect there, only the char gap
      // is suggested (DECISIONS.md "Hören: typing mode").
      if (!_typing) {
        _pendingInterWord = (_pendingInterWord! + delta).clamp(7, _startInterWordSpace);
      }
    });
  }

  // Pushes the accepted proposals to the shared state the caller
  // (GeneratorScreen) owns. Called right before leaving the result screen,
  // not inside _finishBlock() — that's the whole point of the override UI.
  void _applyPendingDecision() {
    if (_acceptCharSpeed && _pendingWpm != null && _pendingWpm != widget.wpm) {
      widget.onWpmChanged?.call(_pendingWpm!);
    }
    if (_acceptSpacing && _pendingInterChar != null && _pendingInterWord != null &&
        (_pendingInterChar != widget.interCharSpace || _pendingInterWord != widget.interWordSpace)) {
      widget.onSpacingChanged?.call(_pendingInterChar!, _pendingInterWord!);
    }
    if (_acceptUnlock && _unlockedThisBlock) {
      widget.onKochLevelChanged?.call(widget.kochLevel + 1);
    }
  }

  // Random content (ordinal 0 random chars, 4 practice set) plays groups,
  // everything else words; the counters say which (DECISIONS.md glossary).
  bool get _playsGroups {
    final ordinal = widget.contentModeOrdinals[widget.contentModeIndex];
    return ordinal == 0 || ordinal == 4;
  }

  Future<String> _fetchGroup() async {
    final ordinal = widget.contentModeOrdinals[widget.contentModeIndex];
    final result = await _genChannel.invokeMethod('getNextContent', {
      'mode': ordinal,
      'kochLevel': widget.kochLevel,
      'kochActive': widget.kochLesson && ordinal != 2,
      if (ordinal == 0 || ordinal == 4) 'groupLength': widget.groupLength,
      if (ordinal == 0 && !widget.kochLesson) 'randomOption': widget.randomOption,
      if (ordinal == 1 || ordinal == 3) 'wordLengthMax': widget.wordLengthMax,
      // Sent unconditionally for the non-Random modes, same as
      // echo_trainer_screen.dart's kochMode branch — harmless for modes
      // that don't consume it.
      if (ordinal != 0 && ordinal != 4) 'abbrevLengthMax': widget.abbrevLengthMax,
    });
    // Groups are shown and graded per character, so a "<KA>" prosign token
    // from Random Groups is sent as the plain letters K A here.
    return ((result as String?) ?? '').replaceAll(RegExp('[<>]'), '').toUpperCase();
  }

  void _onGenEvent(dynamic raw) {
    final ev = raw as Map;
    if (ev['type'] == 'done' && !(_doneCompleter?.isCompleted ?? true)) {
      _doneCompleter!.complete();
    }
    if (ev['type'] == 'paddle') _choose(ev['value'] == 'dit');
  }

  Future<void> _waitIfPaused() async {
    if (!_paused) return;
    _pauseGate = Completer<void>();
    await _pauseGate!.future;
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (!_paused) {
      _pauseGate?.complete();
      _pauseGate = null;
    }
  }

  // Plays a just-unlocked character right on the result screen's suggestion
  // row, with the same tile as a tap on a Koch character on the setup page
  // (character + code lighting up, played three times) — user request
  // 2026-09-27: consistent with the Koch overview. Deliberately not routed
  // through CharPracticeScreen: that navigates away from Adaptive Copy, which
  // is exactly what this is meant to avoid.
  Future<void> _previewNewChar(String ch) async {
    if (_previewingNewChar) return;
    setState(() => _previewingNewChar = true);
    // The tile listens on the shared cwGenEvents stream; a second
    // receiveBroadcastStream() on the same channel would steal its events,
    // so drop ours meanwhile. _startBlock() subscribes afresh anyway.
    _genSub?.cancel();
    _genSub = null;
    try {
      await showCharPlayback(context,
          ch: ch, outputCase: _outputCase,
          play: () => playCharThrice(ch, wpm: widget.wpm, interWordSpace: widget.interWordSpace));
    } finally {
      if (mounted) setState(() => _previewingNewChar = false);
    }
  }

  // wpm/interCharSpace/interWordSpace default to the widget's current
  // values; _nextBlock() passes the just-accepted overrides explicitly
  // instead, since calling widget.onWpmChanged/onSpacingChanged and then
  // immediately reading widget.wpm/widget.interCharSpace in the same
  // synchronous call would still see the pre-rebuild values.
  Future<void> _startBlock({int? wpm, int? interCharSpace, int? interWordSpace, bool? typing}) async {
    if (_phase == _Phase.sending) return;
    if (typing != null) _typing = typing;
    _activeWpm = wpm ?? widget.wpm;
    final activeInterChar = interCharSpace ?? widget.interCharSpace;
    final activeInterWord = interWordSpace ?? widget.interWordSpace;
    final wasIdle = _phase == _Phase.idle;
    _sessionActive = true;
    setState(() {
      _phase = _Phase.sending;
      _preparing = true;
      _sentGroups = [];
      _wrongPositions.clear();
      _markingWordIndex = null;
      _currentGroupIndex = 0;
      _paused = false;
      _typedAttempts = [];
      _outcomes = [];
      _input = '';
      _typeState = _TypeState.input;
    });
    if (wasIdle) widget.onActiveChanged?.call(true);
    if (_typing) widget.onKeyboardChanged?.call(true);

    // Brief pause before the first group actually plays, so the user can
    // get ready — mirrors the same "Start" delay in GeneratorScreen._start().
    await Future.delayed(const Duration(seconds: 1));
    if (!_sessionActive || !mounted) return;
    setState(() => _preparing = false);

    final p = await SharedPreferences.getInstance();
    // Sync tempo/spacing/tone before sending — nothing else does this for
    // us (CLAUDE.md rule: shared singleton engine, every screen must push
    // its own config on entry).
    await _genChannel.invokeMethod('setWpm', _activeWpm);
    await _genChannel.invokeMethod('setInterCharSpace', activeInterChar);
    await _genChannel.invokeMethod('setInterWordSpace', activeInterWord);
    // Boost proposal from the previous block's result screen, minus
    // whatever the user tapped out — reuses the same practiceChars/
    // boostLevel mechanism as CW Generator's "Practice Set" + Boost
    // (CwGenerator.kt randomKochChars() already consults both). Merged with
    // the profile's own Practice Set + Boost Practice (decision 2026-09-26,
    // docs/DECISIONS.md): union of both char lists, the higher of the two
    // levels — so the profile's boost still applies, with or without weak
    // chars.
    // Level 1 (Moderate, 3 draw attempts), not 2 (Strong, 8 attempts): user
    // feedback 2026-09-23 — Strong pushed one missed char to ~80% of the
    // very next block, far too extreme a spike; weak chars already stay
    // boosted across several following blocks (lifetime EMA-based, not
    // cleared after one block), so a gentler per-block rate spread over
    // that whole stretch is enough without dominating any single block.
    final boostChars = _weakChars.keys
        .where((ch) => !_excludedBoostChars.contains(ch))
        .toList();
    if (_boostApplies) {
      final pf = await TrainingProfile.open(TrainingProfile.hear);
      final ownChars = parsePracticeChars(pf.getString('practiceChars') ?? '');
      // A level with an empty Practice Set boosts nothing of the user's own —
      // it must not raise the weak chars above Moderate on its own.
      final ownLevel = ownChars.isEmpty ? 0 : (pf.getInt('boostLevel') ?? 0).clamp(0, 2);
      final chars = {...ownChars, ...boostChars}.toList();
      final level = [ownLevel, boostChars.isEmpty ? 0 : 1]
          .reduce((a, b) => a > b ? a : b);
      await _genChannel.invokeMethod('setPracticeChars', chars);
      await _genChannel.invokeMethod('setBoostLevel', level);
    } else {
      // Practice set / words: the profile's own set (rule 2).
      await _restorePracticeCharsAndBoost();
    }
    final pitch = p.getInt('pitch') ?? 600;
    final toneSoftness = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs', (toneSoftness + 1).toDouble());

    _genSub?.cancel();
    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);

    if (_typing) {
      final pf = await TrainingProfile.open(TrainingProfile.hear);
      _typeAttempts = (pf.getInt('typeAttempts') ?? 2).clamp(1, 3);
      _typeHaptic = (pf.getInt('typeHaptic') ?? 1) == 1;
      _confirmTone = p.getBool('confirmTone') ?? true;
      await _runTypingBlock();
      return;
    }

    for (var i = 0; i < _blockSize; i++) {
      if (!_sessionActive) return;
      await _waitIfPaused();
      if (!_sessionActive) return;

      final group = await _fetchGroup();
      if (!_sessionActive || !mounted) return;
      setState(() {
        _sentGroups.add(group);
        _currentGroupIndex = i;
      });

      final completer = Completer<void>();
      _doneCompleter = completer;
      await _genChannel.invokeMethod('playOne', group);
      await completer.future;
      if (!_sessionActive) return;

      while (widget.stopEachGroup) {
        final repeat = await _awaitGroupChoice();
        if (!_sessionActive || !mounted) return;
        if (!repeat) break;
        await _waitIfPaused();
        if (!_sessionActive) return;
        final again = Completer<void>();
        _doneCompleter = again;
        await _genChannel.invokeMethod('playOne', group);
        await again.future;
        if (!_sessionActive) return;
      }

      // playOne() plays with trailingGap=false (see CwGenerator.kt) — same
      // reasoning as the Classic flow's start-marker gap: insert the
      // inter-word gap ourselves between groups.
      final ditMs = (1200 / _activeWpm).round();
      await Future.delayed(Duration(milliseconds: ditMs * activeInterWord));
    }
    if (!_sessionActive || !mounted) return;
    _revealBlock();
  }

  // "Aufdecken": ends sending early and reveals only what's been sent so
  // far — matches the concept doc's "überspringt den Rest".
  Future<void> _revealNow() async {
    if (_phase != _Phase.sending) return;
    _sessionActive = false;
    _cancelChoice();
    _pauseGate?.complete();
    _pauseGate = null;
    await _genChannel.invokeMethod('stop');
    _genSub?.cancel();
    _genSub = null;
    _revealBlock();
  }

  void _revealBlock() {
    if (_typing) widget.onKeyboardChanged?.call(false);
    if (mounted) setState(() => _phase = _Phase.revealed);
  }

  // ── Typing mode flow ──
  // One word per step: play it, wait for the answer (typed during or after
  // the word), check. Wrong → the word is replayed with an empty field, up to
  // _typeAttempts attempts; pass or the last wrong attempt → solution for 2 s.
  // Only the first attempt is graded (as in Geben), per character via
  // gradeTyped(); its errors pre-mark the "Gesendet" page. Timings as Geben.
  Future<void> _runTypingBlock() async {
    var carry = '';
    for (var i = 0; i < _blockSize; i++) {
      if (!_sessionActive) return;
      final group = await _fetchGroup();
      if (!_sessionActive || !mounted) return;
      setState(() {
        _sentGroups.add(group);
        _typedAttempts.add([]);
        _currentGroupIndex = i;
        _attemptNo = 1;
        _typeState = _TypeState.input;
        _input = carry; // keys typed while the previous ✓ was shown
      });
      carry = '';
      String? first;
      var outcome = 2;
      for (var a = 1; a <= _typeAttempts; a++) {
        if (a > 1) {
          setState(() { _attemptNo = a; _input = ''; _typeState = _TypeState.input; });
        }
        final typed = await _playAndAwaitAnswer(group);
        if (!_sessionActive || !mounted) return;
        setState(() => _typedAttempts[i].add(typed));
        if (a == 1) first = typed ?? '';
        if (typed == null) break; // passed
        final ok = typed == group;
        if (_confirmTone) _toneChannel.invokeMethod('playConfirmTone', ok);
        if (ok) {
          outcome = a == 1 ? 0 : 1;
          break;
        }
        if (a < _typeAttempts) {
          setState(() => _typeState = _TypeState.wrong);
          await Future.delayed(const Duration(milliseconds: 800));
          if (!_sessionActive || !mounted) return;
        }
      }
      final flags = gradeTyped(group, first ?? '');
      setState(() {
        _outcomes.add(outcome);
        for (var k = 0; k < flags.length; k++) {
          if (!flags[k]) _wrongPositions.add('$i:$k');
        }
        _shownWord = group;
        _input = '';
        _typeState = outcome == 2 ? _TypeState.solution : _TypeState.correct;
      });
      await Future.delayed(Duration(milliseconds: outcome == 2 ? 2000 : 1000));
      if (!_sessionActive || !mounted) return;
      if (outcome != 2) carry = _input;
    }
    if (!_sessionActive || !mounted) return;
    _revealBlock();
  }

  // Plays the word and resolves with the answer (null = passed). The answer
  // is taken once the word has finished: at once after ⏎, or 0.4 s after
  // the input reached the word's length (⌫ in that time cancels it).
  Future<String?> _playAndAwaitAnswer(String word) async {
    final gate = Completer<String?>();
    _submitGate = gate;
    _submitRequested = false;
    _target = word;
    setState(() => _playing = true);
    final done = Completer<void>();
    _doneCompleter = done;
    await _genChannel.invokeMethod('playOne', word);
    await Future.any([done.future, gate.future]);
    if (mounted) setState(() => _playing = false);
    _maybeScheduleCheck();
    final answer = await gate.future;
    _checkTimer?.cancel();
    if (_submitGate == gate) _submitGate = null;
    return answer;
  }

  void _completeSubmit(String? answer) {
    final g = _submitGate;
    if (g != null && !g.isCompleted) g.complete(answer);
  }

  void _maybeScheduleCheck() {
    _checkTimer?.cancel();
    final gate = _submitGate;
    if (gate == null || gate.isCompleted || _playing || _typeState != _TypeState.input) return;
    if (_submitRequested) {
      gate.complete(_input);
      return;
    }
    if (_target.isNotEmpty && _input.length >= _target.length) {
      _checkTimer = Timer(const Duration(milliseconds: 400), () {
        if (_submitGate == gate && _input.length >= _target.length) _completeSubmit(_input);
      });
    }
  }

  // Keys count while answering, and during the ✓ (they carry over to the
  // next word); not during the pause after a wrong attempt or the solution.
  void _onKey(String k) {
    if (_typeState != _TypeState.input && _typeState != _TypeState.correct) return;
    if (_input.length >= 16) return;
    setState(() => _input += k);
    if (_typeState == _TypeState.input) _maybeScheduleCheck();
  }

  void _onBackspace() {
    if (_typeState != _TypeState.input && _typeState != _TypeState.correct) return;
    _checkTimer?.cancel();
    _submitRequested = false;
    if (_input.isEmpty) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _onSubmit() {
    if (_typeState != _TypeState.input || _submitGate == null) return;
    if (_playing) {
      setState(() => _submitRequested = true);
    } else {
      _checkTimer?.cancel();
      _completeSubmit(_input);
    }
  }

  // Pass, also while the word still plays (stopOne leaves the keyer alone).
  void _onPass() {
    if (_typeState != _TypeState.input || _submitGate == null) return;
    _checkTimer?.cancel();
    if (_playing) _genChannel.invokeMethod('stopOne');
    _completeSubmit(null);
  }

  // Active keyboard keys: the characters the current charset can play.
  Set<String> get _keyboardChars {
    final ordinal = widget.contentModeOrdinals[widget.contentModeIndex];
    Iterable<String> base;
    if (ordinal == 4) {
      base = parsePracticeChars(widget.practiceChars);
    } else if (widget.kochLesson) {
      base = kochActiveChars(widget.kochLevel, widget.activeKochChars);
    } else if (ordinal == 0) {
      final (a, b) = _randomOptionRange(widget.randomOption);
      base = _randomAlphabet.sublist(a, b + 1);
    } else {
      base = _randomAlphabet;
    }
    // Prosigns play as their two letters in Hören (see _fetchGroup()), so
    // they are typed as letters; the target's own chars are always typeable.
    return {
      for (final ch in base) ...ch.toUpperCase().split(''),
      ..._target.split(''),
    };
  }

  // Stop<Next>Rep (firmware autoStop): nach der Gruppe anhalten und auf die
  // Wahl warten. Dit/Knopf = dieselbe Gruppe noch einmal, Dah/Knopf = weiter.
  Future<bool> _awaitGroupChoice() async {
    final gate = Completer<bool>();
    _choiceGate = gate;
    setState(() => _awaitingChoice = true);
    _genChannel.invokeMethod('setPaddleChoice', true);
    final repeat = await gate.future;
    _genChannel.invokeMethod('setPaddleChoice', false);
    if (mounted) setState(() => _awaitingChoice = false);
    return repeat;
  }

  void _choose(bool repeat) {
    final g = _choiceGate;
    _choiceGate = null;
    if (g != null && !g.isCompleted) g.complete(repeat);
  }

  void _cancelChoice() => _choose(false);

  void _toggleWrong(int groupIndex, int charIndex) {
    final key = '$groupIndex:$charIndex';
    setState(() {
      if (!_wrongPositions.remove(key)) _wrongPositions.add(key);
    });
  }

  Future<void> _finishBlock() async {
    final p = await SharedPreferences.getInstance();
    await _charStats.load(p);
    var total = 0, correct = 0;
    final results = <bool>[];
    for (var g = 0; g < _sentGroups.length; g++) {
      final group = _sentGroups[g];
      for (var i = 0; i < group.length; i++) {
        final wrong = _wrongPositions.contains('$g:$i');
        total++;
        if (!wrong) correct++;
        results.add(!wrong);
        _charStats.record(group[i], !wrong, block: _blockNumber);
      }
    }
    await _charStats.save(p);

    // Adaptive engine: blockquote EMA -> spacing/char-speed step, plus an
    // independent per-character unlock decision — both can fire on the same
    // block (docs/ADAPTIVE-COPY.md "Decisions: weighting/recency questions").
    _engine ??= AdaptiveCopyEngine(
      thresholds: AdaptiveCopyThresholds(
        // Clamped to 99 even though Settings now caps the slider there too —
        // guards a value already persisted as 100 before that cap existed
        // (100% is an unreachable trap, see ADAPTIVE-COPY.md).
        highThreshold: ((p.getInt('adaptiveHighThresholdPct') ?? 90).clamp(50, 99)) / 100,
        lowThreshold: (p.getInt('adaptiveLowThresholdPct') ?? 70) / 100,
        blockEmaAlpha: (p.getInt('adaptiveEmaAlphaPct') ?? 30) / 100,
        unlockOccurrences: p.getInt('adaptiveUnlockOccurrences') ?? 20,
      ),
      initialBlockEma: p.getDouble('adaptiveBlockEma') ?? 1.0,
    );
    // Typing mode: only the char gap matters (DECISIONS.md "Hören: typing
    // mode"), so the word gap is neither suggested nor waited for.
    final typing = _typing;
    final spacingAtCharSpeed = widget.interCharSpace <= 3 && (typing || widget.interWordSpace <= 7);
    final decision = _engine!.recordBlock(results, spacingAtCharSpeed: spacingAtCharSpeed);
    final newEma = _engine!.blockEma;
    await p.setDouble('adaptiveBlockEma', newEma);
    final trend = await const BlockHistory('hear')
        .record(p, total == 0 ? 0 : correct / total);

    final activeChars = kochActiveChars(widget.kochLevel, widget.activeKochChars)
        .map((ch) => _charStats.stats[ch] ?? CharStat())
        .toList();
    final unlocked = widget.kochLesson && widget.kochLevel < widget.activeKochChars.length &&
        _engine!.shouldUnlockNextChar(activeChars);

    // Proposals only — not applied here. The result screen shows them as
    // accept/reject/adjust suggestions; _applyPendingDecision() pushes
    // whatever's still accepted once the user leaves the result screen.
    // A new Koch character is enough to absorb on its own — don't also
    // tighten spacing or raise char speed in the same block it unlocks
    // ("in dem moment wo ein neues zeichen hinzukommt wird mir das zu
    // schnell"). Widening/slowing down is unaffected, since that only ever
    // makes the next block easier.
    //
    // Beyond that single block: suppress tighten/speed-up proposals for the
    // whole time the user is still working through Koch lessons (not all
    // sequence characters unlocked yet) — user feedback 2026-09-22: pausing
    // reduction pressure on top of still-being-introduced-to-new-characters
    // felt like a constant nag. The manual spacing +/- control
    // (_buildSpacingControl) is untouched by this — it's independent of the
    // engine's proposals and still lets the user tighten by hand any time.
    // Once the full sequence is unlocked, the (now hysteresis-gated, see
    // AdaptiveCopyThresholds.spacingUpConsecutiveBlocks) tighten/speed-up
    // proposals resume normally.
    final rampingUpKoch = widget.kochLesson && widget.kochLevel < widget.activeKochChars.length;
    int? newInterChar, newInterWord, interCharBefore, interWordBefore;
    if (decision.spacingStep == TempoStep.up && !unlocked && !rampingUpKoch) {
      final ic = (widget.interCharSpace - 1).clamp(3, _startInterCharSpace);
      final iw = typing ? widget.interWordSpace
          : (widget.interWordSpace - 1).clamp(7, _startInterWordSpace);
      // Already at the floor — clamping produced no real change, so don't
      // propose a no-op ("tightened: 3→3") suggestion row.
      if (ic != widget.interCharSpace || iw != widget.interWordSpace) {
        interCharBefore = widget.interCharSpace;
        interWordBefore = widget.interWordSpace;
        newInterChar = ic;
        newInterWord = iw;
      }
    } else if (decision.spacingStep == TempoStep.down) {
      final ic = (widget.interCharSpace + 1).clamp(3, _startInterCharSpace);
      final iw = typing ? widget.interWordSpace
          : (widget.interWordSpace + 1).clamp(7, _startInterWordSpace);
      // Already at the ceiling (this session's starting spacing) — same
      // no-op guard for "widened: 11→11".
      if (ic != widget.interCharSpace || iw != widget.interWordSpace) {
        interCharBefore = widget.interCharSpace;
        interWordBefore = widget.interWordSpace;
        newInterChar = ic;
        newInterWord = iw;
      }
    }
    int? newWpm, wpmBefore;
    if (decision.charSpeedStep == TempoStep.up && !unlocked && !rampingUpKoch) {
      wpmBefore = widget.wpm;
      newWpm = widget.wpm + 1;
    }
    final weakChars = _weakCharsNow();

    if (!mounted) return;
    setState(() {
      _resultCorrect = correct;
      _resultTotal = total;
      _lastDecision = decision;
      _unlockedThisBlock = unlocked;
      _trend = trend;
      _wpmBefore = wpmBefore;
      _interCharBefore = interCharBefore;
      _interWordBefore = interWordBefore;
      _pendingWpm = newWpm;
      _pendingInterChar = newInterChar;
      _pendingInterWord = newInterWord;
      _acceptCharSpeed = true;
      _acceptSpacing = true;
      _acceptUnlock = true;
      _weakChars = weakChars;
      // Excluding a char only makes sense while it's actually on the list —
      // drop stale exclusions for chars that fell off (e.g. its EMA
      // recovered below threshold since the user last excluded it).
      _excludedBoostChars.removeWhere((ch) => !weakChars.containsKey(ch));
      _phase = _Phase.result;
    });
  }

  bool get _hasSuggestions =>
      _pendingWpm != null || _pendingInterChar != null || _unlockedThisBlock;

  void _finish() {
    _applyPendingDecision();
    if (mounted) setState(() => _phase = _Phase.idle);
    widget.onActiveChanged?.call(false);
  }

  void _nextBlock() {
    final wpm = _effectiveWpm;
    final interChar = _effectiveInterChar;
    final interWord = _effectiveInterWord;
    _applyPendingDecision();
    _blockNumber++;
    _startBlock(wpm: wpm, interCharSpace: interChar, interWordSpace: interWord);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.idle => _buildIdle(context),
      _Phase.sending => _typing ? _buildTyping(context) : _buildSending(context),
      _Phase.revealed => _buildRevealed(context),
      _Phase.result => _buildResult(context),
    };
  }

  // Idle/start screen. _weakChars is already populated here (loaded in
  // initState from lifetime stats, not just after a block) so the panel —
  // and the boost it drives on the very first block — is visible right
  // away, not only from the second block onward.
  Widget _buildIdle(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(Strings.t('ac_idle_hint'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                      color: c.textMuted, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              // Same status-line format as the result screen (gen_status_line),
              // minus Trend/EMA — that's only meaningful once a block has been
              // scored, and none has run yet on this start screen.
              Text(Strings.t('gen_status_line')
                      .replaceFirst('{wpm}', '$_effectiveWpm')
                      .replaceFirst('{ewpm}', '$_effectiveTextWpm')
                      .replaceFirst('{ic}', '$_effectiveInterChar')
                      .replaceFirst('{iw}', '$_effectiveInterWord'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
              const SizedBox(height: 24),
              _buildSpacingControl(context, scale: 1.2),
              if (_weakChars.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildWeakCharsSection(context, scale: 1.2),
              ],
            ]),
          ),
        ),
      );
    });
  }

  // Weak-character chips, tappable to include/exclude from the boosted
  // draw — shared between the idle/start screen (boosts the next block
  // about to start) and the result screen (boosts the block after that
  // one), see docs/ADAPTIVE-COPY.md.
  // scale bumps text size for the result screen ("der komplette text beim
  // resultat screen könnte ruhig größer sein") without also growing this
  // section where it's reused on the idle screen.
  Widget _buildWeakCharsSection(BuildContext context, {double scale = 1}) {
    final c = AppColors.of(context);
    return SizedBox(width: double.infinity, child: AppCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(Strings.t('ac_weak_chars'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 11 * scale, color: c.textMuted)),
      const SizedBox(height: 2),
      Text(Strings.t('ac_boost_hint'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 10 * scale,
              color: c.textMuted, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
        children: _weakChars.entries.map((e) {
          final included = !_excludedBoostChars.contains(e.key);
          return InkWell(
            onTap: () => setState(() {
              if (included) {
                _excludedBoostChars.add(e.key);
              } else {
                _excludedBoostChars.remove(e.key);
              }
            }),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: included ? c.warning.withOpacity(0.15) : c.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: included ? c.warning.withOpacity(0.5) : c.border),
              ),
              child: Text('${_displayChar(e.key)}  ${(e.value * 100).round()}%',
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 13 * scale,
                      color: included ? c.warning : c.textMuted,
                      decoration: included ? null : TextDecoration.lineThrough)),
            ),
          );
        }).toList(),
      ),
    ])));
  }

  // Manual spacing control, requested to be visible at every summary and at
  // the start ("bitte bei jeder zusammenfassung und auch zu beginn den
  // block zum anpassen der pausen einblenden") — separate from the engine's
  // own accept/reject spacing suggestion on the result screen: this one
  // always shows and lets the user nudge the pause directly, any time.
  // Bounds match the Settings sliders (interCharSpace/interWordSpace), not
  // _startInterCharSpace/_startInterWordSpace — those only cap how far the
  // *engine* is allowed to auto-widen, not a manual override.
  void _adjustSpacing(int delta) {
    final ic = (widget.interCharSpace + delta).clamp(3, 45);
    final iw = (widget.interWordSpace + delta).clamp(6, 105);
    if (ic == widget.interCharSpace && iw == widget.interWordSpace) return;
    widget.onSpacingChanged?.call(ic, iw);
  }

  Widget _buildSpacingControl(BuildContext context, {double scale = 1}) {
    final c = AppColors.of(context);
    return SizedBox(width: double.infinity, child: AppCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(Strings.t('ac_spacing_control_title'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 11 * scale, color: c.textMuted)),
      const SizedBox(height: 2),
      Text(Strings.t('ac_spacing_control_hint'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 10 * scale,
              color: c.textMuted, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _TapTarget(onTap: () => _adjustSpacing(-1),
            child: Icon(Icons.remove, size: 20, color: c.accent)),
        SizedBox(
          width: 84 * scale,
          child: Text('${widget.interCharSpace}/${widget.interWordSpace}',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 15 * scale,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
        ),
        _TapTarget(onTap: () => _adjustSpacing(1),
            child: Icon(Icons.add, size: 20, color: c.accent)),
      ]),
    ])));
  }

  Widget _buildHeader(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(Strings.t('ac_block_label').replaceFirst('{n}', '$_blockNumber'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                fontWeight: FontWeight.bold, color: c.textMuted)),
        Text('${widget.contentModeLabels[widget.contentModeIndex]}${widget.kochLesson ? ' · KOCH ${widget.kochLevel}' : ''}',
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
      ]),
    );
  }

  Widget _buildSending(BuildContext context) {
    final c = AppColors.of(context);
    return Column(children: [
      _buildHeader(context),
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_preparing ? Strings.t('get_ready') : Strings.t('ac_listening'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _preparing ? c.warning : c.textPrimary)),
            const SizedBox(height: 20),
            Row(mainAxisSize: MainAxisSize.min,
                children: List.generate(_blockSize, (i) {
              final sent = i < _currentGroupIndex ||
                  (i == _currentGroupIndex && _sentGroups.length > i);
              final current = i == _currentGroupIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  current ? Icons.radio_button_checked : Icons.circle,
                  size: current ? 16 : 10,
                  color: sent ? c.accent : c.border,
                ),
              );
            })),
            const SizedBox(height: 12),
            Text(
                Strings.t(_playsGroups ? 'ac_group_of' : 'ac_word_of')
                    .replaceFirst('{n}', '${(_currentGroupIndex + 1).clamp(1, _blockSize)}')
                    .replaceFirst('{total}', '$_blockSize'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
            const SizedBox(height: 6),
            Text('$_activeWpm WPM',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textDisabled)),
            if (_awaitingChoice) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Expanded(child: _SecondaryButton(
                      label: Strings.t('repeat_upper'), onTap: () => _choose(true))),
                  const SizedBox(width: 12),
                  Expanded(child: _PrimaryButton(
                      label: Strings.t('next_upper'), onTap: () => _choose(false))),
                ]),
              ),
              const SizedBox(height: 6),
              Text(Strings.t('ac_paddle_hint'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.textMuted)),
            ],
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: _SecondaryButton(
            label: _paused ? Strings.t('ac_resume') : Strings.t('ac_pause'),
            onTap: _togglePause,
          )),
          const SizedBox(width: 12),
          Expanded(child: _PrimaryButton(
            label: Strings.t('ac_reveal'),
            onTap: _revealNow,
          )),
        ]),
      ),
    ]);
  }

  // Typing mode screen: progress, the answer line, and the keyboard.
  Widget _buildTyping(BuildContext context) {
    final c = AppColors.of(context);
    final i = _currentGroupIndex;
    final mono = TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted);
    final attempts = i < _typedAttempts.length ? _typedAttempts[i] : const <String?>[];
    // The fixed heights below keep the layout from jumping between states;
    // they grow with the system font size so the text still fits.
    final f = textScaleOf(context);

    Widget center;
    if (_preparing) {
      center = Text(Strings.t('get_ready'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 26,
              fontWeight: FontWeight.bold, color: c.warning));
    } else {
      final solution = _typeState == _TypeState.solution;
      final correct = _typeState == _TypeState.correct;
      final wrong = _typeState == _TypeState.wrong;
      // Answer line: the typed text with a cursor; the word itself once
      // it is right (green) or given up (wrong chars of attempt 1 in red).
      Widget answer;
      if (correct || solution) {
        answer = Row(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < _shownWord.length; k++)
            Text(_displayChar(_shownWord[k]), style: TextStyle(fontFamily: 'CwMono',
                fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4,
                color: correct ? c.accent
                    : _wrongPositions.contains('$i:$k') ? c.danger : c.textPrimary)),
          const SizedBox(width: 2),
        ]);
      } else {
        final shown = wrong && attempts.isNotEmpty ? (attempts.last ?? '') : _input;
        answer = Row(mainAxisSize: MainAxisSize.min, children: [
          Text(shown.split('').map(_displayChar).join(),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 36,
                  fontWeight: FontWeight.bold, letterSpacing: 4,
                  color: wrong ? c.danger : c.textPrimary,
                  decoration: wrong ? TextDecoration.lineThrough : null)),
          Container(width: 2, height: 34 * f, color: wrong ? Colors.transparent : c.accent),
        ]);
      }
      String? badge;
      Color badgeColor = c.danger;
      if (correct) {
        badge = Strings.t('echo_status_correct');
        badgeColor = c.accent;
      } else if (solution) {
        badge = Strings.t('ac_type_solution');
      } else if (wrong) {
        badge = Strings.t('echo_status_wrong');
      } else if (_attemptNo > 1) {
        badge = '✗ ${Strings.t('echo_attempt')
            .replaceFirst('{n}', '$_attemptNo').replaceFirst('{max}', '$_typeAttempts')}';
      }
      center = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: List.generate(_blockSize, (k) {
          final done = k < _outcomes.length;
          final color = !done
              ? (k == i ? c.accent : c.border)
              : _outcomes[k] == 0 ? c.accent : _outcomes[k] == 1 ? c.warning : c.danger;
          // Fixed 16x16 cell: the current dot is bigger, and when it turns
          // into a result dot the row must not shrink — everything below
          // would jump (user feedback 2026-09-27).
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(width: 16, height: 16, child: Center(
              child: Icon(k == i && !done ? Icons.radio_button_checked : Icons.circle,
                  size: k == i && !done ? 16 : 10, color: color))),
          );
        })),
        const SizedBox(height: 10),
        Text('${Strings.t(_playsGroups ? 'ac_group_of' : 'ac_word_of')
            .replaceFirst('{n}', '${i + 1}').replaceFirst('{total}', '$_blockSize')} · $_activeWpm WPM',
            style: mono),
        const SizedBox(height: 14),
        SizedBox(height: 28 * f, child: badge == null ? null : Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: badgeColor.withOpacity(0.13),
              borderRadius: BorderRadius.circular(14)),
          child: Text(badge, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: badgeColor)),
        )),
        const SizedBox(height: 6),
        // Earlier attempts of this word, struck through — no hint where the
        // error was. In the solution state: every attempt, numbered.
        // Fixed height in every state, sized for the solution's numbered
        // list (one 18 px line per allowed attempt), so the answer line
        // below stays put when the solution appears.
        SizedBox(height: (_typeAttempts * 18 < 22 ? 22 : _typeAttempts * 18.0) * f,
            child: Align(alignment: Alignment.bottomCenter, child: solution
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                for (var a = 0; a < attempts.length; a++)
                  SizedBox(height: 18 * f, child: Text('${a + 1}.  ${attempts[a] == null ? '— ${Strings.t('ac_type_passed')}'
                      : attempts[a]!.split('').map(_displayChar).join()}', style: mono)),
              ])
            : Text([
                for (final a in attempts.take(wrong ? attempts.length - 1 : attempts.length))
                  (a ?? '').split('').map(_displayChar).join()
              ].join('   '),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textFaint,
                    decoration: TextDecoration.lineThrough, letterSpacing: 2)))),
        const SizedBox(height: 4),
        // Long groups/words shrink to fit instead of overflowing sideways.
        SizedBox(height: 48 * f, child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: answer))),
        Container(width: 200, height: 2, color: correct ? c.accent
            : (wrong || solution) ? c.danger : c.border),
        const SizedBox(height: 10),
        SizedBox(height: 18 * f, child: _playing
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.graphic_eq, size: 16, color: c.accent),
                const SizedBox(width: 6),
                Text(Strings.t(_submitRequested ? 'ac_type_check_after' : 'ac_type_playing'),
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.accent)),
              ])
            : null),
      ]);
    }
    final canType = !_preparing &&
        (_typeState == _TypeState.input || _typeState == _TypeState.correct);
    return Column(children: [
      _buildHeader(context),
      Expanded(child: Center(child: SingleChildScrollView(child: center))),
      CwKeyboard(
        active: _keyboardChars,
        onKey: _onKey,
        onBackspace: _onBackspace,
        onSubmit: _onSubmit,
        onPass: _onPass,
        enabled: canType,
        submitFaded: _playing,
        haptic: _typeHaptic,
        outputCase: _outputCase,
        passLabel: Strings.t('ac_type_pass'),
        submitLabel: '⏎ ${Strings.t('ac_type_check')}',
      ),
    ]);
  }

  // Combines the old separate "sent" and "marking" screens: the word tiles
  // double as the error-marking overview (tap a word to drill into its
  // characters), so there's a single flow instead of two screens plus a
  // "mark errors" hand-off button.
  Widget _buildRevealed(BuildContext context) {
    if (_markingWordIndex != null) {
      return _buildWordMarking(context, _markingWordIndex!);
    }
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_sent_title'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 18,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text(Strings.t(_typing ? 'ac_sent_desc_typed' : 'ac_sent_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          // Centered when the tiles fit; otherwise scrollable, with a
          // visible scrollbar and bottom fade so it's clear there's more.
          // Tiles grow with the font size, but never below two columns.
          final tileWidth = (150 * textScaleOf(context))
              .clamp(0.0, (constraints.maxWidth - 32 - 20) / 2);
          return ScrollHint(
            center: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: List.generate(_sentGroups.length,
                  (i) => _buildRevealedTile(context, i, tileWidth)),
            ),
          );
        }),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _PrimaryButton(
          label: Strings.t('ac_done_errors').replaceFirst('{n}', '${_wrongPositions.length}'),
          onTap: _finishBlock,
        ),
      ),
    ]);
  }

  // One sent group on the "revealed" screen — a fixed-width card so groups
  // wrap into as many columns as fit, instead of a single left-stuck
  // column with the rest of the middle area left empty. Characters are
  // colored by type (letter/digit/other) so mixed-content groups are
  // easier to scan. Tapping the tile opens the per-word marking screen;
  // any characters already marked wrong in it show red right here too.
  Widget _buildRevealedTile(BuildContext context, int i, double width) {
    final c = AppColors.of(context);
    final group = _sentGroups[i];
    final hasError =
        Iterable.generate(group.length).any((k) => _wrongPositions.contains('$i:$k'));
    return InkWell(
      onTap: () => setState(() => _markingWordIndex = i),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasError ? c.danger.withOpacity(0.13) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasError ? c.danger : c.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${i + 1}',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textDisabled)),
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: List.generate(group.length, (k) {
              final wrong = _wrongPositions.contains('$i:$k');
              return Text(_displayChar(group[k]),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: wrong ? c.danger : charTypeColor(group[k], c)));
            }),
          ),
          // Typing mode: what was typed, attempt by attempt.
          if (_typing && i < _typedAttempts.length) ...[
            const SizedBox(height: 2),
            Text([
              for (final a in _typedAttempts[i])
                a == null ? '— ${Strings.t('ac_type_passed')}' : a.split('').map(_displayChar).join()
            ].join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
          ],
        ]),
      ),
    );
  }

  // Per-word drill-down: only this word's characters, large tap targets,
  // so marking errors doesn't mean hunting a small target among every
  // character of every word on screen at once.
  Widget _buildWordMarking(BuildContext context, int wordIndex) {
    final c = AppColors.of(context);
    final group = _sentGroups[wordIndex];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t(_playsGroups ? 'ac_group_title' : 'ac_word_title').replaceFirst('{n}', '${wordIndex + 1}'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 18,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text(Strings.t('ac_mark_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
        ]),
      ),
      Expanded(
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: List.generate(group.length, (i) {
              final wrong = _wrongPositions.contains('$wordIndex:$i');
              return InkWell(
                onTap: () => _toggleWrong(wordIndex, i),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 56, height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: wrong ? c.danger.withOpacity(0.18) : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: wrong ? c.danger : c.border),
                  ),
                  child: Text(_displayChar(group[i]), style: TextStyle(fontFamily: 'CwMono',
                      fontSize: 24, fontWeight: FontWeight.bold,
                      color: wrong ? c.danger : charTypeColor(group[i], c))),
                ),
              );
            }),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _SecondaryButton(
          label: Strings.t('ac_back'),
          onTap: () => setState(() => _markingWordIndex = null),
        ),
      ),
    ]);
  }

  Widget _buildResult(BuildContext context) {
    final c = AppColors.of(context);
    final pct = _resultTotal == 0 ? 100 : (_resultCorrect * 100 ~/ _resultTotal);
    final weak = _weakChars;
    return Column(children: [
      _buildHeader(context),
      Expanded(
        child: ScrollHint(
          center: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$pct %', style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 52,
                fontVariations: const [FontVariation('wght', 600)],
                color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
            Text(Strings.t('ac_correct_of')
                    .replaceFirst('{c}', '$_resultCorrect').replaceFirst('{t}', '$_resultTotal'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textMuted)),
            const SizedBox(height: 10),
            Text(Strings.t('gen_status_line')
                    .replaceFirst('{wpm}', '$_effectiveWpm')
                    .replaceFirst('{ewpm}', '$_effectiveTextWpm')
                    .replaceFirst('{ic}', '$_effectiveInterChar')
                    .replaceFirst('{iw}', '$_effectiveInterWord') +
                    (_trend == null ? '' : ' · ' + Strings.t('trend_line')
                        .replaceFirst('{pct}', '${_trend!.percent}')
                        .replaceFirst('{arrow}', _trend!.arrow)),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
            const SizedBox(height: 20),
            _buildSpacingControl(context, scale: 1.2),
            if (weak.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildWeakCharsSection(context, scale: 1.2),
            ],
            if (_buildUnlockOutlook(context) case final outlook?) ...[
              const SizedBox(height: 20),
              outlook,
            ],
            if (_hasSuggestions) ...[
              const SizedBox(height: 20),
              Text(Strings.t('ac_suggestions_title'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
              const SizedBox(height: 8),
              ..._buildSuggestionRows(context),
            ],
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: _SecondaryButton(label: Strings.t('ac_finish'), onTap: _finish)),
          const SizedBox(width: 12),
          Expanded(child: _PrimaryButton(label: Strings.t('ac_next_block'), onTap: _nextBlock)),
        ]),
      ),
    ]);
  }

  // Motivation: what is still missing before the next Koch character
  // unlocks (mirrors AdaptiveCopyEngine.shouldUnlockNextChar: every active
  // char needs enough attempts AND accuracy >= high threshold).
  Widget? _buildUnlockOutlook(BuildContext context) {
    if (!widget.kochLesson ||
        widget.kochLevel >= widget.activeKochChars.length ||
        _unlockedThisBlock) {
      return null;
    }
    final c = AppColors.of(context);
    final th = _engine!.thresholds;
    final chars = kochActiveChars(widget.kochLevel, widget.activeKochChars);
    if (chars.isEmpty) return null;
    final needAttempts = <String, int>{};
    final lowAcc = <String, int>{};
    var doneAttempts = 0, wantAttempts = 0;
    for (final ch in chars) {
      final st = _charStats.stats[ch] ?? CharStat();
      final acc = 1 - st.emaErrorRate;
      if (st.attempts < th.unlockOccurrences) {
        doneAttempts += st.attempts;
        wantAttempts += th.unlockOccurrences;
        needAttempts[ch] = th.unlockOccurrences - st.attempts;
      } else if (acc < th.highThreshold) {
        lowAcc[ch] = (acc * 100).round();
      }
    }
    // Bar = repetitions still owed, summed over the chars that lack them;
    // if only accuracy is missing, it shows accuracy vs. threshold.
    double progress;
    if (wantAttempts > 0) {
      progress = doneAttempts / wantAttempts;
    } else {
      final worst = lowAcc.values.fold<int>(100, (m, v) => v < m ? v : m);
      progress = (worst / 100 / th.highThreshold).clamp(0.0, 1.0);
    }
    final next = _displayChar(widget.activeKochChars[widget.kochLevel]);
    // One chip per character, so an entry never breaks across lines; most
    // repetitions owed / lowest accuracy first, capped so a bad block
    // doesn't turn the card into a wall.
    const maxChips = 10;
    Widget chips(List<String> items) {
      final shown = items.take(maxChips).toList();
      return Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in shown) Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
          child: Text(t, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
        ),
        if (items.length > maxChips) Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(Strings.t('ac_outlook_more').replaceFirst('{n}', '${items.length - maxChips}'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
        ),
      ]);
    }
    final sections = <(String, List<String>)>[];
    if (needAttempts.isNotEmpty) {
      final e = needAttempts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      sections.add((Strings.t('ac_outlook_attempts'),
          [for (final x in e) '${_displayChar(x.key)} ${x.value}']));
    }
    if (lowAcc.isNotEmpty) {
      final e = lowAcc.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      sections.add((Strings.t('ac_outlook_accuracy')
          .replaceFirst('{pct}', '${(th.highThreshold * 100).round()}'),
          [for (final x in e) '${_displayChar(x.key)} ${x.value} %']));
    }
    final mono = TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted);
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_outlook_title').replaceFirst('{ch}', next),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: c.background,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          for (final (label, items) in sections) ...[
            const SizedBox(height: 10),
            Text(label, style: mono),
            const SizedBox(height: 6),
            chips(items),
          ],
        ]),
      ),
    );
  }

  // Result screen sits in a mainAxisSize.min Center column, so rows here
  // get loose (not stretched) width constraints — size explicitly instead
  // of relying on Expanded, which would need a bounded incoming width.
  List<Widget> _buildSuggestionRows(BuildContext context) {
    final rowWidth = MediaQuery.of(context).size.width - 32;
    final rows = <Widget>[];
    // Unlock goes first and stands out (star icon, bolder styling) — it's a
    // bigger deal than a tempo/spacing nudge, and names the actual character
    // so it's clear what's being proposed, not just that "something" unlocked.
    if (_unlockedThisBlock) {
      final nextChar = widget.kochLevel < widget.activeKochChars.length
          ? widget.activeKochChars[widget.kochLevel]
          : null;
      rows.add(SuggestionRow(
        width: rowWidth,
        accepted: _acceptUnlock,
        onToggle: (v) => setState(() => _acceptUnlock = v),
        label: nextChar == null
            ? Strings.t('ac_char_unlocked')
            : '${Strings.t('ac_char_unlocked')}: "${_displayChar(nextChar)}"',
        highlight: true,
        // Lets the user hear the brand-new character right here, without
        // leaving Adaptive Copy for the separate Learn New Chr screen — user
        // feedback 2026-09-22: they want to stay "im Lern-Flow". Plays
        // in-place over the same channels _startBlock() already uses.
        onPreview: nextChar == null || _previewingNewChar ? null : () => _previewNewChar(nextChar),
      ));
    }
    if (_pendingWpm != null) {
      rows.add(SuggestionRow(
        width: rowWidth,
        accepted: _acceptCharSpeed,
        onToggle: (v) => setState(() => _acceptCharSpeed = v),
        label: '${Strings.t('ac_char_speed_up')}: $_wpmBefore→${_acceptCharSpeed ? _pendingWpm : _wpmBefore}',
        onDecrement: _acceptCharSpeed ? () => _stepPendingWpm(-1) : null,
        onIncrement: _acceptCharSpeed ? () => _stepPendingWpm(1) : null,
      ));
    }
    if (_pendingInterChar != null) {
      final spacingWpm = (_acceptCharSpeed && _pendingWpm != null) ? _pendingWpm! : (_wpmBefore ?? widget.wpm);
      final label = _lastDecision!.spacingStep == TempoStep.up
          ? Strings.t('ac_spacing_up')
          : Strings.t('ac_spacing_down');
      rows.add(SuggestionRow(
        width: rowWidth,
        accepted: _acceptSpacing,
        onToggle: (v) => setState(() => _acceptSpacing = v),
        label: '$label: $_interCharBefore→${_acceptSpacing ? _pendingInterChar : _interCharBefore} '
            '(${ditsToSeconds(_acceptSpacing ? _pendingInterChar! : _interCharBefore!, spacingWpm)})'
            '${_typing ? '' : ' / '
            '$_interWordBefore→${_acceptSpacing ? _pendingInterWord : _interWordBefore} '
            '(${ditsToSeconds(_acceptSpacing ? _pendingInterWord! : _interWordBefore!, spacingWpm)})'}',
        onDecrement: _acceptSpacing ? () => _stepPendingSpacing(-1) : null,
        onIncrement: _acceptSpacing ? () => _stepPendingSpacing(1) : null,
      ));
    }
    return rows;
  }
}

// One adaptive-engine proposal on the result screen: a checkbox to
// accept/reject it, and (when it carries a magnitude) +/- steppers to
// adjust it before it's applied. See docs/ADAPTIVE-COPY.md "User override
// on the result screen".
class SuggestionRow extends StatelessWidget {
  final double width;
  final bool accepted;
  final ValueChanged<bool> onToggle;
  final String label;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  // Set for the Koch-unlock proposal only — a bigger deal than a tempo/
  // spacing nudge, so it gets a star icon and a bolder border instead of
  // blending into the same generic row style as the other two.
  final bool highlight;
  // Unlock row only: plays the new character in place. Null while a preview
  // is already in flight, or when there's no next character to preview.
  final VoidCallback? onPreview;

  const SuggestionRow({
    required this.width,
    required this.accepted,
    required this.onToggle,
    required this.label,
    this.onIncrement,
    this.onDecrement,
    this.highlight = false,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // No row-wide tap target — only the checkbox toggles acceptance.
    // A whole-row InkWell made stray taps near the steppers register as an
    // accidental reject instead, which is worse than requiring a precise
    // checkbox tap.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: accepted ? c.accent.withOpacity(highlight ? 0.2 : 0.12) : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: highlight ? Border.all(
                color: accepted ? c.accent.withOpacity(0.8) : c.border, width: 1.5) : null,
          ),
          child: Row(children: [
            _TapTarget(
              onTap: () => onToggle(!accepted),
              child: Icon(accepted ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 22, color: accepted ? c.accent : c.textMuted),
            ),
            if (highlight)
              Icon(Icons.star, size: 18, color: accepted ? c.accent : c.textMuted),
            if (highlight) const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: highlight ? 15 : 14,
                      fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                      color: accepted ? c.accent : c.textMuted,
                      decoration: accepted ? null : TextDecoration.lineThrough)),
            ),
            if (onPreview != null)
              _TapTarget(onTap: onPreview!, child: Icon(Icons.volume_up, size: 20, color: c.accent)),
            if (onDecrement != null)
              _TapTarget(onTap: onDecrement!, child: Icon(Icons.remove, size: 20, color: c.accent)),
            if (onIncrement != null)
              _TapTarget(onTap: onIncrement!, child: Icon(Icons.add, size: 20, color: c.accent)),
          ]),
        ),
      ),
    );
  }
}

// 44x44 minimum touch target (Material guideline) around a small icon —
// the plain Icon-in-Padding steppers this replaced were easy to miss and
// the miss-tap fell through to the row behind them.
class _TapTarget extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TapTarget({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(width: 44, height: 44, child: Center(child: child)),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      AppButton(label: label, onTap: onTap, color: AppColors.of(context).info);
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => AppButton(
      label: label, onTap: onTap, color: AppColors.of(context).info, primary: false);
}
