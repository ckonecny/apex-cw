// Adaptive Copy Mode — listen-and-copy flow: send a block of groups,
// reveal, tap errors, show a result. See docs/ADAPTIVE-COPY.md.
// Two ways to copy (DECISIONS.md "Hören: typing mode"): on paper (the whole
// block plays, errors are tapped afterwards) or typed on CwKeyboard (one
// word per step, graded from the first attempt, errors pre-marked).
//
// Proposals come from the training goals (training_goals.dart) at the end
// of each block: one step towards the active goal, or undoing the last step.
// Nothing is applied without "Apply"; this widget then pushes the value via
// the on*Changed callbacks (wpm/kochLevel/spacing/group length are
// GeneratorScreen's state).
import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/block_history.dart';
import '../content/char_stats.dart';
import '../content/mixup_suggest.dart';
import '../content/mixup_trend.dart';
import '../content/training_profile.dart';
import '../content/charset_content.dart' show profilePracticeChars;
import '../content/cw_content.dart'
    show glyphToken, glyphsToPlayText, isProsignGlyph, keyGlyph, kochActiveChars,
        parsePracticeChars, prosignsToGlyphs;
import '../content/adaptive_copy_engine.dart';
import '../content/training_goals.dart';
import '../content/copy_grading.dart';
import 'widgets/cw_keyboard.dart';
import 'widgets/char_playback_overlay.dart';
import 'widgets/mistake_lesson.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/mixup_boost_chips.dart';
import 'widgets/unlock_outlook_card.dart';
import 'widgets/boost_summary.dart';
import 'widgets/fit_or_compact.dart';
import 'widgets/goal_progress_card.dart';
import 'widgets/goal_suggestion_card.dart';
import '../util/char_color.dart';
import '../util/confirm_tone.dart';
import '../util/interference_profile.dart';
import '../l10n/strings.dart';
import '../util/practice_clock.dart';
import '../util/break_reminder.dart';
import 'widgets/break_hint_card.dart';
import '../content/practice_log.dart' show MilestoneKind;

part 'adaptive_copy_body_views.dart';
part 'adaptive_copy_body_widgets.dart';

enum _Phase { idle, sending, revealed, result }

// Typing mode, per word: input = typing/waiting for the answer, wrong =
// short pause after a wrong attempt before the replay, correct = ✓ shown,
// solution = word shown after the last attempt or a pass.
enum _TypeState { input, wrong, correct, solution, learn }

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
  final int wordLengthMin;
  final int wordLanguage;
  final int abbrevLengthMin;
  final int groupLengthMax;
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
  // Applies an accepted goal step back to the caller's state
  // (GeneratorScreen owns wpm/kochLevel/spacing/group length) — null-safe
  // no-ops if the caller doesn't wire them up.
  final ValueChanged<int>? onWpmChanged;
  final ValueChanged<int>? onKochLevelChanged;
  final void Function(int interCharSpace, int interWordSpace)? onSpacingChanged;
  // Group length goal: one fixed length, min and max set together.
  final ValueChanged<int>? onGroupLengthChanged;
  // Lets the parent hide its setup controls (mode selector, Learn New/
  // Preview/Practice Echo, Classic/Adaptiv toggle) while a block is active,
  // and reset back to idle from its own back button — see
  // AdaptiveCopyController above.
  final ValueChanged<bool>? onActiveChanged;
  // true while the typing keyboard is on screen — the parent hides its WPM
  // slider then, to leave room for the keys.
  final ValueChanged<bool>? onKeyboardChanged;
  // Tempo + spacing card, shown by the body at the bottom of its scrolling
  // start area and above its buttons on the result screen (same order
  // everywhere: card, then buttons). Not while a block runs, on "Gesendet" or
  // on the word marking screen.
  final Widget? controls;
  final AdaptiveCopyController? controller;
  // Profile's practice set: the keyboard's active keys for that charset.
  final String practiceChars;

  // The training goals of Hören, in the user's order: the "On the way to"
  // card shows only while new characters is the active goal.
  final List<LeverGoal> goalOrder;

  const AdaptiveCopyBody({
    super.key,
    this.kochLesson = true,
    this.randomOption = 0,
    this.wordLengthMax = 0,
    this.wordLengthMin = 0,
    this.wordLanguage = 0,
    this.abbrevLengthMin = 0,
    this.groupLengthMax = 0,
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
    this.onGroupLengthChanged,
    this.onActiveChanged,
    this.onKeyboardChanged,
    this.controls,
    this.controller,
    this.goalOrder = const [],
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
  static const _weakCharMaxShown = 5;
  // Koch: same cap as the unlock card's chip list.
  static const _weakCharMaxShownKoch = 10;

  // outputCase: 0=lower, 1=UPPER — display only, matches GeneratorScreen's
  // setting (generator_screen.dart); content/comparisons stay uppercase
  // internally.
  int _outputCase = 0;
  String _displayChar(String ch) {
    final t = glyphToken(ch);
    final s = t == ch ? ch : '<$t>';   // a prosign reads as one unit
    return _outputCase == 1 ? s.toUpperCase() : s.toLowerCase();
  }

  final CharStatsStore _charStats = CharStatsStore();
  AdaptiveCopyEngine? _engine;
  // Thresholds for the unlock outlook on the start screen, before the first
  // block has created the engine.
  AdaptiveCopyThresholds? _startThresholds;

  static AdaptiveCopyThresholds _thresholdsFrom(SharedPreferences p) {
    // Clamped (high to 99): 100% is an unreachable trap, see ADAPTIVE-COPY.md.
    final r = goalRules(p, 'hear');
    return AdaptiveCopyThresholds(
      highThreshold: r.high,
      lowThreshold: r.low,
      unlockOccurrences: r.unlockOccurrences,
    );
  }
  // Guards the "hear it" preview button against overlapping taps while a
  // preview is already playing (see _previewNewChar).
  bool _previewingNewChar = false;
  // Result-screen status line: the EMA the engine is actually reasoning
  // about, captured explicitly (not read back from `widget`, to not depend
  // on parent-rebuild timing).
  BlockTrend? _trend; // Trend über die letzten Blöcke, erst ab 6 Blöcken
  // The goal proposal of the finished block (null = none) and what became
  // of it on the result page.
  GoalSuggestion? _goal;
  GoalCardState _goalState = GoalCardState.open;
  bool _goalReached = false;
  GoalLever? _goalNext;
  // Readiness window of the goal (graded characters) and the settings it
  // belongs to, for the "On the way to" card.
  List<bool> _goalWin = const [];
  String? _goalWinSig;
  // Weak characters (lifetime EMA, not just this block) shown on the result
  // screen, keyed to error rate. Each is tapped on/off to control whether
  // it's included in the boosted draw for the next block — the "eingreifen
  // in die vorgeschlagenen Zeichen" override (docs/ADAPTIVE-COPY.md).
  Map<String, double> _weakChars = {};
  // Recurring mix-ups offered for a boost (#102), minus the pairs the user
  // left out; their characters join the weak ones in the same boosted draw.
  List<MixupTrend> _mixups = [];
  final Set<String> _excludedMixups = {};
  final Set<String> _excludedBoostChars = {};
  // wpm actually pushed to the generator for the in-flight block — set by
  // _startBlock(), independent of widget.wpm so a just-accepted override
  // takes effect immediately rather than waiting for a parent rebuild.
  int _activeWpm = 0;
  int _activeInterChar = 0, _activeInterWord = 0; // spacing of the in-flight block

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

  bool _pausedNow = false;
  bool get _paused => _pausedNow;
  set _paused(bool v) {
    _pausedNow = v;
    _syncPracticeClock();
  }
  Completer<void>? _pauseGate;
  bool _sessionActiveNow = false;
  bool get _sessionActive => _sessionActiveNow;
  set _sessionActive(bool v) {
    _sessionActiveNow = v;
    _syncPracticeClock();
  }

  // A running, unpaused block (not its result pages) counts as practice for the practice clock even
  // without touches (listening on paper).
  void _syncPracticeClock() {
    final run = _sessionActiveNow && !_pausedNow && _phase == _Phase.sending;
    PracticeClock.instance.audioPlaying = run;
    if (run) PracticeClock.instance.touch();
  }
  Completer<void>? _doneCompleter;
  StreamSubscription? _genSub;
  // True for the brief pause right after "Start Block" — gives the user a
  // moment to get ready before the first group actually plays.
  bool _preparing = false;

  // ── Typing mode ──
  bool _typing = false;          // this session copies on the keyboard
  int _typeAttempts = 2;         // ⚙ "attempts per word", 1–3
  bool _learnFromMistake = false; // ⚙ after a wrong answer: replay + dits/dahs, no retry (#50)
  int _learnActive = -1;         // character sounding in the lesson
  Set<int> _learnWrong = {};     // positions wrong in the first attempt
  int _learnElement = 0;         // elements of the lesson heard so far
  bool _typeHaptic = true;
  ConfirmTone _confirmTone = ConfirmTone.classic;      // global, set in Settings → General
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

  // The parent loads kochLevel/sequence/content mode asynchronously, so the
  // first build carries defaults (level 5). The idle weak-char list computed
  // in initState would then stay limited to those first characters.
  @override
  void didUpdateWidget(AdaptiveCopyBody old) {
    super.didUpdateWidget(old);
    if (_phase != _Phase.idle) return;
    if (old.kochLevel == widget.kochLevel &&
        old.kochLesson == widget.kochLesson &&
        old.contentModeIndex == widget.contentModeIndex &&
        old.contentModeOrdinals[old.contentModeIndex] ==
            widget.contentModeOrdinals[widget.contentModeIndex] &&
        listEquals(old.activeKochChars, widget.activeKochChars)) {
      return;
    }
    _refreshBoost();
  }

  // Populates _weakChars from lifetime stats right away, so the idle/start
  // screen's panel (and the boost it drives) is available from the very
  // first block, not only after _finishBlock() has run once.
  // The native boost only works on random character groups (content mode 0,
  // in a Koch lesson or over all characters). Words, abbreviations, mixed
  // (only a third are groups) and the practice-set pool are not boosted, so
  // there neither the weak-characters card nor its chips are shown and the
  // draw is never changed.
  bool get _boostApplies => widget.contentModeOrdinals[widget.contentModeIndex] == 0;

  // The characters a boosted draw can pick from.
  List<String> get _boostCandidates => widget.kochLesson
      ? kochActiveChars(widget.kochLevel, widget.activeKochChars)
      : _charStats.stats.keys.toList();

  // Recurring mix-ups among the drawable characters (#102).
  List<MixupTrend> _mixupsNow() => !_boostApplies
      ? const []
      : suggestedMixups(_charStats.days, DateTime.now(), candidates: _boostCandidates);

  // Refreshes both boost proposals; exclusions of what fell off are dropped.
  void _refreshBoost() {
    _weakChars = _weakCharsNow();
    _mixups = _mixupsNow();
    _excludedBoostChars.removeWhere((ch) => !_weakChars.containsKey(ch));
    _excludedMixups.removeWhere((p) => !_mixups.any((t) => t.pair == p));
  }

  Map<String, double> _weakCharsNow() {
    if (!_boostApplies) return {};
    final chars = _boostCandidates;
    final high = (_engine?.thresholds ?? _startThresholds)?.highThreshold ??
        const AdaptiveCopyThresholds().highThreshold;
    if (widget.kochLesson) {
      // Koch: exactly the chars the "On the way to" card lists under
      // "Accuracy below X %" (acc < high, which is what blocks the unlock),
      // so the card can host the include/exclude chips. The epsilon keeps a
      // char sitting exactly on the threshold (acc == high) out.
      return weakCharsLifetime(_charStats, chars,
          minAttempts: _weakCharMinAttempts,
          threshold: 1 - high + 1e-9,
          maxShown: _weakCharMaxShownKoch);
    }
    return weakCharsLifetime(_charStats, chars,
        minAttempts: _weakCharMinAttempts,
        threshold: weakCharErrorThreshold(high),
        maxShown: _weakCharMaxShown);
  }

  Future<void> _loadInitialWeakChars() async {
    final p = await SharedPreferences.getInstance();
    await _charStats.load(p);
    final goals = await GoalStore.open(TrainingProfile.hear);
    if (!mounted) return;
    setState(() {
      _outputCase = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _startThresholds = _thresholdsFrom(p);
      _goalWin = goals.window;
      _goalWinSig = goals.windowSignature;
      _refreshBoost();
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
    final practiceChars = profilePracticeChars(pf);
    final boostLevel = (pf.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setPracticeChars', practiceChars);
    await _genChannel.invokeMethod('setBoostLevel', boostLevel);
  }

  // Same fallback/range as the ⚙ sheet slider and Geben (echo_trainer_screen):
  // nothing stored (0) means 10.
  int get _blockSize => widget.maxWords == 0 ? 10 : widget.maxWords.clamp(1, 50);

  // The current values as the training goals read them.
  GoalValues get _goalValues => GoalValues(
    koch: widget.kochLesson,
    kochLevel: widget.kochLevel,
    kochTotal: widget.activeKochChars.length,
    interChar: widget.interCharSpace,
    interWord: widget.interWordSpace,
    groups: _playsGroups,
    groupLength: widget.groupLength,
    wpm: widget.wpm,
    typing: _typing,
  );

  // "Apply" on the goal card: the step goes into the normal setting, the
  // same one the −/+ controls change by hand.
  Future<void> _acceptGoal() async {
    final s = _goal;
    if (s == null || _goalState != GoalCardState.open) return;
    final before = _goalValues;
    switch (s.lever) {
      case GoalLever.newChars:
        widget.onKochLevelChanged?.call(s.to);
        PracticeClock.instance.milestone(MilestoneKind.kochHear, s.to);
      case GoalLever.charSpacing:
        widget.onSpacingChanged?.call(
          s.to,
          before.interWord < s.to ? s.to : before.interWord,
        );
      case GoalLever.wordSpacing:
        widget.onSpacingChanged?.call(before.interChar, s.to);
      case GoalLever.groupLength:
        widget.onGroupLengthChanged?.call(s.to);
      case GoalLever.wpm:
        widget.onWpmChanged?.call(s.to);
        PracticeClock.instance.milestone(
          MilestoneKind.wpmHear,
          s.to,
          onlyIfHigher: true,
        );
      case GoalLever.giveWpm:
        break;
    }
    final after = before.withValue(s.lever, s.to);
    final store = await GoalStore.open(TrainingProfile.hear);
    final reached = await store.accept(s, after, DateTime.now());
    final next = reached ? activeGoal(store.order, after)?.lever : null;
    if (!mounted) return;
    setState(() {
      _goalWin = store.window;
      _goalWinSig = store.windowSignature;
      _goalState = GoalCardState.accepted;
      _goalReached = reached;
      _goalNext = next;
    });
  }

  Future<void> _snoozeGoal() async {
    if (_goalState != GoalCardState.open) return;
    final store = await GoalStore.open(TrainingProfile.hear);
    await store.snooze(DateTime.now());
    if (mounted) setState(() => _goalState = GoalCardState.snoozed);
  }

  // Random content (ordinal 0 random chars, 4 practice set) plays groups,
  // everything else words; the counters say which (DECISIONS.md glossary).
  bool get _playsGroups {
    final ordinal = widget.contentModeOrdinals[widget.contentModeIndex];
    return ordinal == 0 || ordinal == 4;
  }

  // Call sign options from the ⚙ sheet (global keys, shared with Send), read
  // when a block starts.
  int _callLengthOpt = 0, _callRegionOpt = 0;
  bool _callCommonOnly = true;

  Future<String> _fetchGroup() async {
    final ordinal = widget.contentModeOrdinals[widget.contentModeIndex];
    final result = await _genChannel.invokeMethod('getNextContent', {
      'mode': ordinal,
      'kochLevel': widget.kochLevel,
      'kochActive': widget.kochLesson && ordinal != 2,
      if (ordinal == 0 || ordinal == 3 || ordinal == 4) 'groupLength': widget.groupLength,
      if (ordinal == 0 || ordinal == 3 || ordinal == 4) 'groupLengthMax': widget.groupLengthMax,
      if (ordinal == 1 || ordinal == 3) 'wordLengthMin': widget.wordLengthMin,
      if (ordinal == 1 || ordinal == 3) 'wordLanguage': widget.wordLanguage,
      if (ordinal != 0 && ordinal != 4) 'abbrevLengthMin': widget.abbrevLengthMin,
      if (ordinal == 0 && !widget.kochLesson) 'randomOption': widget.randomOption,
      if (ordinal == 1 || ordinal == 3) 'wordLengthMax': widget.wordLengthMax,
      // Sent unconditionally for the non-Random modes, same as
      // echo_trainer_screen.dart's kochMode branch — harmless for modes
      // that don't consume it.
      if (ordinal != 0 && ordinal != 4) 'abbrevLengthMax': widget.abbrevLengthMax,
      // Call signs (content "Call signs" and "Mixed" with all characters).
      if (ordinal == 2 || ordinal == 3) ...{
        'callLengthOpt': _callLengthOpt,
        'callRegionOpt': _callRegionOpt,
        'callCommonOnly': _callCommonOnly,
      },
    });
    // Groups are shown and graded per character, so a "<KA>" prosign token
    // is one glyph in the text (cw_content.dart prosignsToGlyphs).
    return prosignsToGlyphs(((result as String?) ?? '').toUpperCase());
  }

  void _onGenEvent(dynamic raw) {
    final ev = raw as Map;
    if (ev['type'] == 'done' && !(_doneCompleter?.isCompleted ?? true)) {
      _doneCompleter!.complete();
    }
    if (ev['type'] == 'paddle') _choose(ev['value'] == 'dit');
    if (ev['type'] == 'elementOn' && _typeState == _TypeState.learn) _advanceLesson();
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
    _activeInterChar = activeInterChar;
    _activeInterWord = activeInterWord;
    BreakReminder.dismiss();
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
    _callLengthOpt = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
    _callRegionOpt = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
    _callCommonOnly = p.getBool('callCommonOnly') ?? true;
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
    // Weak characters plus both characters of the mix-up pairs still ticked;
    // one set, so a character in several places is not boosted any harder.
    final boostChars = {
      ..._weakChars.keys.where((ch) => !_excludedBoostChars.contains(ch)),
      ...mixupBoostChars(
          _mixups.where((t) => !_excludedMixups.contains(t.pair)), _boostCandidates),
    }.toList();
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
      _learnFromMistake = (pf.getInt('typeOnWrong') ?? 0) == 1;
      _confirmTone = ConfirmTone.fromPrefs(p);
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
      await _genChannel.invokeMethod('playOne', glyphsToPlayText(group));
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
        await _genChannel.invokeMethod('playOne', glyphsToPlayText(group));
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
    _syncPracticeClock();
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
      var learned = false;
      final attemptsAllowed = _learnFromMistake ? 1 : _typeAttempts;
      for (var a = 1; a <= attemptsAllowed; a++) {
        if (a > 1) {
          setState(() { _attemptNo = a; _input = ''; _typeState = _TypeState.input; });
        }
        final typed = await _playAndAwaitAnswer(group);
        if (!_sessionActive || !mounted) return;
        setState(() => _typedAttempts[i].add(typed));
        if (a == 1) first = typed ?? '';
        if (typed == null) { // passed: same lesson as after a mistake
          if (_learnFromMistake) {
            learned = true;
            _confirmTone.play(_toneChannel, false);
          }
          break;
        }
        final ok = isTypedRight(group, typed);
        _confirmTone.play(_toneChannel, ok);
        if (ok) {
          outcome = a == 1 ? 0 : 1;
          break;
        }
        if (_learnFromMistake) {
          learned = true;
          break;
        }
        if (a < _typeAttempts) {
          setState(() => _typeState = _TypeState.wrong);
          await Future.delayed(const Duration(milliseconds: 800));
          if (!_sessionActive || !mounted) return;
        }
      }
      final flags = gradeTyped(group, first ?? '');
      if (learned) {
        setState(() {
          _shownWord = group;
          _input = '';
          _learnWrong = {for (var k = 0; k < flags.length; k++) if (!flags[k]) k};
        });
        await _playLesson(group);
        if (!_sessionActive || !mounted) return;
      }
      setState(() {
        _outcomes.add(outcome);
        for (var k = 0; k < flags.length; k++) {
          if (!flags[k]) _wrongPositions.add('$i:$k');
        }
        _shownWord = group;
        _input = '';
        _typeState = outcome == 2 ? _TypeState.solution : _TypeState.correct;
      });
      await Future.delayed(Duration(milliseconds: learned ? 0 : outcome == 2 ? 2000 : 1000));
      if (!_sessionActive || !mounted) return;
      if (outcome != 2) carry = _input;
    }
    if (!_sessionActive || !mounted) return;
    _revealBlock();
  }

  // Learn from the mistake (#50): the word again as sound, its characters
  // as dits/dahs with the letter above; the one sounding is highlighted.
  Future<void> _playLesson(String word) async {
    setState(() { _typeState = _TypeState.learn; _learnActive = -1; _learnElement = 0; });
    // Let the error tone ring out first.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted || !_sessionActive) return;
    final done = Completer<void>();
    _doneCompleter = done;
    await _genChannel.invokeMethod('playOne', glyphsToPlayText(word));
    await done.future;
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) setState(() => _learnActive = -1);
  }

  // One more element sounded: map the running count to a character.
  void _advanceLesson() {
    var n = _learnElement++;
    for (var k = 0; k < _shownWord.length; k++) {
      final len = morsePattern(_shownWord[k]).length;
      if (n < len) {
        if (_learnActive != k) setState(() => _learnActive = k);
        return;
      }
      n -= len;
    }
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
    await _genChannel.invokeMethod('playOne', glyphsToPlayText(word));
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
    setState(() => _input += keyGlyph(k));
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
    // A prosign step is typed with its prosign key; the target's own
    // characters are always typeable.
    return {
      for (final ch in base) ch.toUpperCase(),
      ..._target.split('').map(glyphToken),
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
    // Paper: the word gaps count; typing stops after every word, so they don't.
    _charStats.effWpm =
        effectiveWpm(_activeWpm, _activeInterChar, _activeInterWord, wordGap: !_typing);
    var total = 0, correct = 0;
    final results = <bool>[];
    for (var g = 0; g < _sentGroups.length; g++) {
      final group = _sentGroups[g];
      for (var i = 0; i < group.length; i++) {
        final wrong = _wrongPositions.contains('$g:$i');
        total++;
        if (!wrong) correct++;
        results.add(!wrong);
        _charStats.record(glyphToken(group[i]), !wrong, block: _blockNumber);
      }
      // Typing mode: the first attempt shows what was heard instead (#92).
      // Passed (null) says nothing about what was heard; paper mode neither.
      if (_typing && g < _typedAttempts.length && _typedAttempts[g].isNotEmpty) {
        final typed = _typedAttempts[g].first;
        final pair = typed == null ? null : firstMixup(group, typed);
        if (pair != null && !pair.split('').any(isProsignGlyph)) {
          _charStats.recordMixup(pair);
        }
      }
    }
    await _charStats.save(p);

    _engine ??= AdaptiveCopyEngine(thresholds: _thresholdsFrom(p));
    // Typing mode: only the char gap matters (DECISIONS.md "Hören: typing
    // mode"), so the word gap goal is skipped there.
    final typing = _typing;
    final trend = await const BlockHistory('hear')
        .record(p, total == 0 ? 0 : correct / total);
    if (total > 0) {
      final interf = await InterferenceProfile.load();
      PracticeClock.instance.block('hear', correct / total, interference: interf.enabled);
      // Everything that sets the difficulty of this block (issue #5).
      BreakReminder.onBlock('hear', results,
          '$_activeWpm|$_activeInterChar|$_activeInterWord|${widget.kochLesson ? widget.kochLevel : 0}'
          '|${widget.kochLesson}|${widget.contentModeIndex}|$typing|${interf.difficultySignature}');
    }

    final activeChars = kochActiveChars(widget.kochLevel, widget.activeKochChars)
        .map((ch) => _charStats.stats[ch] ?? CharStat())
        .toList();
    final unlockReady =
        widget.kochLesson &&
        widget.kochLevel < widget.activeKochChars.length &&
        _engine!.shouldUnlockNextChar(activeChars);

    // Training goals: the window of the last 100 characters since the last
    // change decides; only a proposal, applied on "Apply".
    final goals = await GoalStore.open(TrainingProfile.hear);
    final goal = await goals.afterBlock(
      results: results,
      values: _goalValues,
      high: _engine!.thresholds.highThreshold,
      low: _engine!.thresholds.lowThreshold,
      unlockReady: unlockReady,
      now: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _resultCorrect = correct;
      _resultTotal = total;
      _trend = trend;
      _goal = goal;
      _goalWin = goals.window;
      _goalWinSig = goals.windowSignature;
      _goalState = GoalCardState.open;
      _goalReached = false;
      _goalNext = null;
      // Excluding a char only makes sense while it's actually on the list —
      // stale exclusions are dropped (e.g. its EMA recovered since).
      _refreshBoost();
      _phase = _Phase.result;
    });
  }


  void _finish() {
    if (mounted) setState(() => _phase = _Phase.idle);
    widget.onActiveChanged?.call(false);
  }

  void _nextBlock() {
    _blockNumber++;
    _startBlock();
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
