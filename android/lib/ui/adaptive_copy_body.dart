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
import '../util/interference_profile.dart';
import '../l10n/strings.dart';

part 'adaptive_copy_body_views.dart';
part 'adaptive_copy_body_widgets.dart';

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
  // setState for the view extension in adaptive_copy_body_views.dart.
  void _update(VoidCallback fn) => setState(fn);

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
    InterferenceProfile.releaseAmbient(this);
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
    // Leaving from the result screen (back button) counts as accepting the
    // proposals shown there — otherwise a Koch unlock earned in the last
    // block would be lost unless another block was started.
    if (_phase == _Phase.result) _applyPendingDecision();
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
    InterferenceProfile.releaseAmbient(this);
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
    // The noise stands for the whole block, until the result is revealed.
    InterferenceProfile.requestAmbient(this);
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
    InterferenceProfile.releaseAmbient(this);
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
    _charStats.wpm = _activeWpm;
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
}
