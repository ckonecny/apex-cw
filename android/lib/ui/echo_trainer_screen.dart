import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'widgets/setting_rows.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../keyer/morse_decoder.dart';
import '../content/cw_content.dart';
import '../content/block_history.dart';
import '../content/char_stats.dart';
import '../content/adaptive_copy_engine.dart';
import '../content/echo_suggestions.dart';
import 'adaptive_copy_body.dart' show SuggestionRow;
import 'char_stats_screen.dart';
import '../content/training_profile.dart';
import '../content/charset_content.dart';
import 'widgets/charset_header.dart';
import 'widgets/char_actions_sheet.dart';

import 'widgets/paddle_widgets.dart';
import 'widgets/pinch_zoom_text.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import '../util/keep_screen_on.dart';
import '../l10n/strings.dart';
import 'widgets/training_settings_sheet.dart';

enum _State { idle, playing, receiving, correct, wrong }

/// Outcome of one word in block mode (docs/training/P5-echo-bloecke.md):
/// first try right, right after a repeat, or given up (revealed).
enum WordOutcome { first, afterRepeat, failed }

class WordResult {
  final String target;
  final String firstAttempt;
  final int attempts;
  final WordOutcome outcome;
  /// Index of the first wrong character of the first attempt, or -1.
  final int firstWrongIndex;
  const WordResult(this.target, this.firstAttempt, this.attempts, this.outcome,
      this.firstWrongIndex);
}

class EchoTrainerScreen extends StatefulWidget {
  // When set, locks onto this single character instead of picking a random
  // target: the same char repeats every round (M32 Koch Trainer "Learn New
  // Chr" / "Preview Char" — both funnel into the Echo Trainer engine drilling
  // one fixed character; see Koch::getNewChar()/getKochChar()). No start/end
  // markers and no Max # of Words in this mode, matching KOCH_LEARN/PREVIEW.
  final String? fixedTarget;
  final String? title;
  const EchoTrainerScreen({super.key, this.fixedTarget, this.title});

  @override
  State<EchoTrainerScreen> createState() => _EchoTrainerScreenState();
}

class _EchoTrainerScreenState extends State<EchoTrainerScreen> {
  static const _genChannel    = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents     = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _keyerChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream  = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _toneChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  static const _dispCodeOnly    = 1;  // Sound only
  static const _dispDispOnly    = 2;  // Display only (no audio)
  // 3 = Sound & Display: the default, needs no special handling

  _State _state    = _State.idle;
  int    _wpm      = 20;
  int    _kochLevel = 5;
  // Character set + content (docs/training/P7), stored in the Geben profile.
  CharsetChoice _choice = const CharsetChoice(CharSet.koch, ContentKind.random);
  bool get _koch => _choice.set == CharSet.koch;
  // "Adapt. Rand." (KOCH_ADAPTIVE): weighted-random character draw — wrong
  // answers raise a character's weight (drawn more often), right answers
  // lower it, within [1,20]. Backed by CharStatsStore's own
  // echo track (separate from hearing, docs/training/P4-zeichenstatistik.md).
  final CharStatsStore _charStats = CharStatsStore(CharStatsStore.echo);
  int    _kochSeq         = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
  int    _licwCarouselStart = 0;
  List<String> get _activeKochChars =>
      kochSequenceChars(_kochSeq, _customKochChars, licwCarouselStart: _licwCarouselStart);
  int  _abbrevLengthMax = 0;
  int  _wordLengthMax = 0;
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
  // Block flow (P5): per-word results of the current block.
  final List<WordResult> _blockResults = [];
  final List<String> _blockPairs = [];
  BlockTrend? _trend; // erst ab 6 Blöcken
  String _firstAttempt = '';
  bool _showResult = false;
  int get _blockSize => _maxWords == 0 ? 10 : _maxWords.clamp(1, 50);
  // The single-character drill (fixedTarget) runs endless, without blocks.
  bool get _blockActive => widget.fixedTarget == null;

  // Touch paddle: 0=Iambic A, 1=Iambic B, 2=Ultimatic, 3=Non-Squeeze, 4=Straight
  int _keyerMode = 0;
  bool _touchDit = false;
  bool _touchDah = false;
  // "CurtisB DitT%"/"CurtisB DahT%" — only meaningful in Iambic B/Ultimatic;
  // shared with the CW Keyer screen, synced to the native keyer at session
  // start (see _startSession()) since this screen's own keyer instance is
  // otherwise left at whatever a different screen last configured it to.
  int _curtisBDitTiming = 75;
  int _curtisBDahTiming = 45;
  int _acs = 0;   // M32 "AutoChar Spc" — shared with the CW Keyer screen, same sync-at-session-start reasoning

  // Echo settings (from SharedPreferences)
  int  _echoThinkTime = 8;   // seconds
  int  _echoRepeats   = 3;   // M32 "Echo Repeats": 0..6, or 7 = "Forever"
  int  _echoDisplay   = _dispCodeOnly;  // matches M32 "Echo Prompt": sound/display/both
  bool _confirmTone   = true;
  // "Gebe-Tempo" (M32 "Echo Speed Max"): cap on the tempo the ANSWER is
  // expected at; 0 = same as the prompt. Answer tempo = min(prompt, cap).
  int  _answerWpmMax  = 0;
  // Pushed to the shared generator singleton on every prompt (CLAUDE.md rule 2).
  int  _interCharSpace = 28;
  int  _interWordSpace = 40;
  // Widening cap for block suggestions: spacing as loaded/set in the sheet.
  int  _capInterChar = 28, _capInterWord = 40;
  EchoSuggestions? _suggestions;
  // Proposals shown on the result page. Accepting has no effect yet (6d).
  int? _pendWpm, _pendAnswer, _pendIC, _pendIW;
  bool _accUnlock = true, _accWpm = true, _accSpacing = true, _accAnswer = false;
  final Set<String> _excludedBoost = {};
  bool _previewing = false;
  // Weak chars boosted in the block after the result page (accepted chips).
  List<String> _boostChars = [];
  List<String> _practiceChars = const [];
  int  _boostLevel = 0;
  int  _pitch         = 600;  // base sidetone pitch (M32 "Tone Pitch")
  // "Tone Shift" (M32 posEchoToneShift): 0=off, 1=up 1 half-tone, 2=down 1
  // half-tone — shifts the OPERATOR's own echoed-answer sidetone away from
  // the target word's playback pitch (m32_v6.ino KEY_START/MorseDecoder::ON_()),
  // so the two are audibly distinguishable. Applied in _beginReceive(), not to
  // the target word playback itself.
  int  _toneShift     = 1;
  int  _toneSoftness  = 4;   // M32 "Tone Softness" (0..8 -> 1..9 ms attack/release)

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

  int _currentWpm = 20;

  // What the practice view shows for the current word (same idea as the
  // Hören block view: one word at a time, no scrolling transcript).
  bool _targetVisible = false;   // the prompt was revealed (Echo Prompt != Sound)
  bool _revealVisible = false;   // given up: the word is shown after the last try
  // True while a start/end marker is being played via playOne() — the 'done'
  // event it produces must not be mistaken for the target word finishing.
  bool _awaitingSignal = false;
  bool _preparing = false;   // the 2 s wait before the first word
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

  // Echo Think T., as in the firmware after its 2026-09-15 fix (origin/master
  // f98a409, docs/DECISIONS.md): only a grace period for STARTING the answer.
  // Deadline from the end of the prompt: 1400 ms + inter-char + inter-word/3
  // (at the prompt speed) + think time. Once the answer has begun, it is
  // evaluated at the word gap, without think time.
  int get _startDeadlineMs {
    final dit = 1200 / _currentWpm;
    return (1400 + _interCharSpace * dit + _interWordSpace * dit / 3).round() +
        _echoThinkTime * 1000;
  }

  // Safety net only: the keyer normally reports the word gap by itself.
  int get _answerSafetyMs => max(3000, (20 * 1200 / _answerWpm).round());

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _decoder = MorseDecoder(onChar: _onDecodedChar);
    _loadPrefs();
  }

  // Per-training settings (docs/training/P3). The sheet only saves; reloading
  // picks the values up. Prompt/answer config is pushed at every session and
  // word start (_applyPromptConfig/_applyAnswerConfig), so nothing else to do.
  Future<void> _openSettingsSheet() async {
    await showTrainingSettingsSheet(context,
        profile: TrainingProfile.echo,
        sections: [
          // Koch sequence is global; only shown with the Koch lesson.
          if (_koch) TrainingSection.kochSequence,
          TrainingSection.content,
          TrainingSection.spacing,
          TrainingSection.wordSelection,
          TrainingSection.echoFlow,
        ]);
    if (mounted) await _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.echo);
    if (mounted) setState(() {
      _wpm            = pf.getInt('wpm')            ?? 20;
      _kochLevel      = pf.getInt('kochLevel')      ?? 5;
      _echoThinkTime  = p.getInt('echoThinkTime')  ?? 8;
      _echoRepeats    = (p.getInt('echoRepeats')   ?? 3).clamp(0, 7);
      _echoDisplay    = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _confirmTone    = p.getBool('confirmTone')   ?? true;
      _answerWpmMax   = (p.getInt('echoAnswerWpmMax') ?? 0).clamp(0, 50);
      _interCharSpace = (pf.getInt('interCharSpace') ?? 28).clamp(3, 45);
      _interWordSpace = (pf.getInt('interWordSpace') ?? 40).clamp(6, 105);
      _capInterChar = _interCharSpace;
      _capInterWord = _interWordSpace;
      _practiceChars  = parsePracticeChars(pf.getString('practiceChars') ?? '');
      _boostLevel     = (pf.getInt('boostLevel') ?? 0).clamp(0, 2);
      _choice         = CharsetChoice.load(pf);
      _keyerMode      = p.getInt('keyerMode')      ?? 0;
      _curtisBDitTiming = (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100);
      _curtisBDahTiming = (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100);
      _acs              = (p.getInt('acs') ?? 0).clamp(0, 3);
      _pitch           = p.getInt('pitch') ?? 600;
      _toneShift       = (p.getInt('toneShift') ?? 1).clamp(0, 2);
      _toneSoftness    = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = (p.getString('customKochChars') ?? '').isNotEmpty
          ? p.getString('customKochChars')!
          : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _abbrevLengthMax = (pf.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _wordLengthMax   = (pf.getInt('wordLengthMax') ?? 0).clamp(0, 8);
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      _outputCase      = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _groupLength     = pf.getInt('groupLength')    ?? 5;
      _randomOption    = (pf.getInt('randomOption')  ?? 0).clamp(0, 9);
      _maxWords        = pf.getInt('maxWords')        ?? 0;
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
      _currentWpm     = _wpm;
    });
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
    await _charStats.load(p);
    if (mounted) setState(() {});
  }

  Future<void> _savePrefs() async {
    final pf = await TrainingProfile.open(TrainingProfile.echo);
    await pf.setInt('wpm',       _wpm);
    await pf.setInt('kochLevel', _kochLevel);
    await _choice.save(pf);
  }

  // Weighted-random single character from the active Koch set — weight
  // defaults to 1 (never drawn yet / already mastered back down to baseline).
  String _pickAdaptiveChar() {
    final active = kochActiveChars(_kochLevel, _activeKochChars);
    final weights = active
        .map((c) => _charStats.weightFor(c) * (_boostChars.contains(c) ? 2 : 1))
        .toList();
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

  // Block flow: every echo content feeds the Geben track, once per word
  // after the first attempt (docs/training/P6-echo-vorschlaege.md).
  Future<void> _applyBlockFeedback(String target, String received) async {
    final pair = _charStats.recordWord(target, received);
    if (pair != null) _blockPairs.add(pair);
    final p = await SharedPreferences.getInstance();
    await _charStats.save(p);
  }

  // Block end: feed the first-try results to the adaptive engine and keep
  // the proposals for the result page (docs/training/P6). Nothing is applied.
  Future<void> _computeSuggestions() async {
    _boostChars = [];   // a boost lasts one block
    final p = await SharedPreferences.getInstance();
    _echoEngine ??= AdaptiveCopyEngine(
      thresholds: AdaptiveCopyThresholds(
        highThreshold: ((p.getInt('adaptiveHighThresholdPct') ?? 90).clamp(50, 99)) / 100,
        lowThreshold: (p.getInt('adaptiveLowThresholdPct') ?? 70) / 100,
        blockEmaAlpha: (p.getInt('adaptiveEmaAlphaPct') ?? 30) / 100,
        unlockOccurrences: p.getInt('adaptiveUnlockOccurrences') ?? 20,
      ),
      initialBlockEma: p.getDouble('echoBlockEma') ?? 1.0,
    );
    await _charStats.load(p);
    // Char-based content only: unlock check and weak chars need a char set.
    final charContent = _koch && _choice.content == ContentKind.random;
    final s = evaluateEchoBlock(
      _echoEngine!,
      EchoSuggestionInput(
        firstTry: _blockResults.map((r) => r.outcome == WordOutcome.first).toList(),
        wpm: _wpm,
        answerWpmMax: _answerWpmMax,
        interCharSpace: _interCharSpace,
        interWordSpace: _interWordSpace,
        maxInterCharSpace: max(_capInterChar, _interCharSpace),
        maxInterWordSpace: max(_capInterWord, _interWordSpace),
        kochLevel: _koch ? _kochLevel : 0,
        kochTotal: _koch ? _activeKochChars.length : 0,
        activeChars: charContent ? kochActiveChars(_kochLevel, _activeKochChars) : const [],
        stats: _charStats,
      ),
    );
    await p.setDouble('echoBlockEma', s.blockEma);
    final n = _blockResults.length;
    _trend = await const BlockHistory('echo').record(
        p, n == 0 ? 0 : _blockResults.where((r) => r.outcome == WordOutcome.first).length / n);
    _suggestions = s;
    _pendWpm = s.newWpm;
    _pendAnswer = s.newAnswerWpmMax;
    _pendIC = s.newInterChar;
    _pendIW = s.newInterWord;
    _accUnlock = _accWpm = _accSpacing = true;
    _accAnswer = false;
    _excludedBoost.clear();
  }

  AdaptiveCopyEngine? _echoEngine;

  // Result page -> next block: writes what is still ticked into the profile
  // / prefs and sets the boost set (docs/training/P6, step 6d). Native
  // values are pushed by _applyPromptConfig/_applyAnswerConfig at start.
  Future<void> _applyAccepted({required bool boost}) async {
    final s = _suggestions;
    if (s == null) return;
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.echo);
    if (s.unlockNext && _accUnlock && _kochLevel < _activeKochChars.length) _kochLevel++;
    if (_pendWpm != null && _accWpm) _wpm = _pendWpm!;
    if (_pendIC != null && _pendIW != null && _accSpacing) {
      _interCharSpace = _pendIC!;
      _interWordSpace = _pendIW!;
      await pf.setInt('interCharSpace', _interCharSpace);
      await pf.setInt('interWordSpace', _interWordSpace);
    }
    if (_pendAnswer != null && _accAnswer) {
      _answerWpmMax = _pendAnswer!;
      await p.setInt('echoAnswerWpmMax', _answerWpmMax);
    }
    _currentWpm = _wpm;
    await _savePrefs();
    _boostChars = boost
        ? s.weakChars.keys.where((ch) => !_excludedBoost.contains(ch)).toList()
        : [];
    _suggestions = null;
    _pendWpm = _pendAnswer = _pendIC = _pendIW = null;
  }

  // Plays the proposed new Koch char twice, in place (like Adaptive Copy).
  Future<void> _previewChar(String ch) async {
    if (_previewing) return;
    setState(() => _previewing = true);
    final hadSub = _genSub != null;
    _genSub ??= _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    try {
      await _toneChannel.invokeMethod('setFreq', _pitch).catchError((_) {});
      for (var i = 0; i < 2; i++) {
        await _playSignal(ch);
        if (i == 0) await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      if (!hadSub) { _genSub?.cancel(); _genSub = null; }
      if (mounted) setState(() => _previewing = false);
    }
  }

  // Manual tempo changes (idle slider / result page). They override the
  // matching suggestion of the finished block.
  Future<void> _setHearWpm(int v) async {
    setState(() {
      _wpm = v.clamp(5, 60);
      _currentWpm = _wpm;
      _pendWpm = null;
    });
    await _savePrefs();
  }

  Future<void> _setGiveWpm(int v) async {
    setState(() {
      _answerWpmMax = v.clamp(0, 60);
      _pendAnswer = null;
    });
    final p = await SharedPreferences.getInstance();
    await p.setInt('echoAnswerWpmMax', _answerWpmMax);
  }

  // Give speed 0 means "same as hearing"; stepping up to the hearing speed
  // goes back to that, stepping down from it starts at hearing speed - 1.
  void _stepGiveWpm(int d) {
    final eff = _answerWpmMax == 0 ? _wpm : min(_answerWpmMax, _wpm);
    final n = (eff + d).clamp(5, _wpm);
    _setGiveWpm(n >= _wpm ? 0 : n);
  }

  Widget _tempoStepper(AppColors c, String label, String value,
      VoidCallback onMinus, VoidCallback onPlus) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
      IconButton(
          icon: const Icon(Icons.remove_circle_outline), color: c.accent,
          visualDensity: VisualDensity.compact, onPressed: onMinus),
      SizedBox(width: 62, child: Text(value, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.accent))),
      IconButton(
          icon: const Icon(Icons.add_circle_outline), color: c.accent,
          visualDensity: VisualDensity.compact, onPressed: onPlus),
    ]);
  }

  Widget _buildTempoControls(AppColors c) {
    return Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
      _tempoStepper(c, Strings.t('block_hear'), '$_wpm WPM',
          () => _setHearWpm(_wpm - 1), () => _setHearWpm(_wpm + 1)),
      _tempoStepper(c, Strings.t('block_give'),
          _answerWpmMax == 0 ? Strings.t('settings_answer_wpm_same') : '$_answerWpmMax WPM',
          () => _stepGiveWpm(-1), () => _stepGiveWpm(1)),
    ]);
  }

  void _stepSpacing(int d) => setState(() {
        _pendIC = (_pendIC! + d).clamp(3, max(_capInterChar, _interCharSpace));
        _pendIW = (_pendIW! + d).clamp(7, max(_capInterWord, _interWordSpace));
      });

  List<Widget> _buildSuggestionRows(AppColors c, double width, String Function(String) cs) {
    final s = _suggestions;
    if (s == null) return const [];
    final rows = <Widget>[];
    if (s.unlockNext && _kochLevel < _activeKochChars.length) {
      final next = _activeKochChars[_kochLevel];
      rows.add(SuggestionRow(
        width: width,
        accepted: _accUnlock,
        onToggle: (v) => setState(() => _accUnlock = v),
        label: '${Strings.t('ac_char_unlocked')}: "${cs(next)}"',
        highlight: true,
        onPreview: _previewing ? null : () => _previewChar(next),
      ));
    }
    if (_pendWpm != null) {
      rows.add(SuggestionRow(
        width: width,
        accepted: _accWpm,
        onToggle: (v) => setState(() => _accWpm = v),
        label: '${Strings.t('echo_hear_speed_up')}: $_wpm→${_accWpm ? _pendWpm : _wpm}',
        onDecrement: _accWpm ? () => setState(() => _pendWpm = max(_wpm, _pendWpm! - 1)) : null,
        onIncrement: _accWpm ? () => setState(() => _pendWpm = min(_wpm + 5, _pendWpm! + 1)) : null,
      ));
    }
    if (_pendIC != null && _pendIW != null) {
      final tighter = _pendIC! < _interCharSpace;
      rows.add(SuggestionRow(
        width: width,
        accepted: _accSpacing,
        onToggle: (v) => setState(() => _accSpacing = v),
        label: '${Strings.t(tighter ? 'ac_spacing_up' : 'ac_spacing_down')}: '
            '$_interCharSpace→${_accSpacing ? _pendIC : _interCharSpace} '
            '(${ditsToSeconds(_accSpacing ? _pendIC! : _interCharSpace, _wpm)}) / '
            '$_interWordSpace→${_accSpacing ? _pendIW : _interWordSpace} '
            '(${ditsToSeconds(_accSpacing ? _pendIW! : _interWordSpace, _wpm)})',
        onDecrement: _accSpacing ? () => _stepSpacing(-1) : null,
        onIncrement: _accSpacing ? () => _stepSpacing(1) : null,
      ));
    }
    if (_pendAnswer != null) {
      rows.add(SuggestionRow(
        width: width,
        accepted: _accAnswer,
        onToggle: (v) => setState(() => _accAnswer = v),
        label: '${Strings.t('echo_give_speed_up')}: $_answerWpmMax→${_accAnswer ? _pendAnswer : _answerWpmMax}',
        onDecrement: _accAnswer ? () => setState(() => _pendAnswer = max(_answerWpmMax, _pendAnswer! - 1)) : null,
        onIncrement: _accAnswer ? () => setState(() => _pendAnswer = min(_wpm, _pendAnswer! + 1)) : null,
      ));
    }
    if (s.weakChars.isNotEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(children: [
          Text(Strings.t('ac_weak_chars'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
          Text(Strings.t('ac_boost_hint'), textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.textMuted,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final e in s.weakChars.entries)
              InkWell(
                onTap: () => setState(() {
                  if (!_excludedBoost.remove(e.key)) _excludedBoost.add(e.key);
                }),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _excludedBoost.contains(e.key) ? c.surfaceAlt : c.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _excludedBoost.contains(e.key) ? c.border : c.danger.withOpacity(0.4)),
                  ),
                  child: Text('${cs(e.key)}  ${(e.value * 100).round()}%',
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
                          color: _excludedBoost.contains(e.key) ? c.textMuted : c.danger)),
                ),
              ),
          ]),
        ]),
      ));
    }
    if (rows.isNotEmpty) {
      rows.insert(0, Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(Strings.t('ac_suggestions_title'), textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
      ));
      rows.add(const Divider());
    }
    return rows;
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _silenceTimer?.cancel();
    _genSub?.cancel();
    _symbolSub?.cancel();
    _genChannel.invokeMethod('stop');
    _keyerChannel.invokeMethod('stop');
    super.dispose();
  }

  int get _answerWpm =>
      _answerWpmMax > 0 ? min(_currentWpm, _answerWpmMax) : _currentWpm;

  /// Everything the shared generator/tone need for playing the prompt.
  Future<void> _applyPromptConfig() async {
    await _genChannel.invokeMethod('setWpm', _currentWpm).catchError((_) {});
    await _genChannel.invokeMethod('setInterCharSpace', _interCharSpace).catchError((_) {});
    await _genChannel.invokeMethod('setInterWordSpace', _interWordSpace).catchError((_) {});
    final practice = {..._practiceChars, ..._boostChars}.toList();
    await _genChannel.invokeMethod('setPracticeChars', practice).catchError((_) {});
    await _genChannel.invokeMethod('setBoostLevel',
        _boostChars.isEmpty ? _boostLevel : max(_boostLevel, 1)).catchError((_) {});
    await _toneChannel.invokeMethod('setFreq', _pitch).catchError((_) {});   // base pitch
  }

  /// Keyer tempo for the answer (Echo Speed Max) and the shifted answer pitch.
  Future<void> _applyAnswerConfig() async {
    await _keyerChannel.invokeMethod('setWpm', _answerWpm).catchError((_) {});
  }

  // ── Session control ────────────────────────────────────────────────────────

  Future<void> _startSession() async {
    if (_state != _State.idle) return;   // guard against a double-tap racing two sessions
    _correct = 0; _total = 0; _wordCounter = 0;
    _blockResults.clear();
    _blockPairs.clear();
    _showResult = false;
    _target = ''; _attempt = ''; _firstAttempt = '';
    _targetVisible = false; _revealVisible = false; _repeats = 0;
    _currentWpm = _wpm;
    _sessionActive = true;

    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    // Keep the scrolling log across Start presses — like the real device
    // (and matching the CW Generator screen), a new session just continues
    // underneath what was already practiced; it only clears on leaving and
    // re-entering this screen (a fresh State instance).
    setState(() => _state = _State.playing);

    // Sync the shared native keyer's mode/CurtisB timing before it's used to
    // receive the echoed answer — otherwise it's left at whatever a DIFFERENT
    // screen (or nothing, on a fresh app session) last configured it to, same
    // class of bug as the CW Generator's stale-wpm marker fix.
    await _keyerChannel.invokeMethod('setMode', _keyerMode).catchError((_) {});
    await _keyerChannel.invokeMethod('setCurtisBTiming',
        {'dit': _curtisBDitTiming, 'dah': _curtisBDahTiming}).catchError((_) {});
    await _keyerChannel.invokeMethod('setAcs', _acs).catchError((_) {});
    // Echo trainer keeps its own word-end rule; don't inherit the keyer's.
    await _keyerChannel.invokeMethod('setInterWordSpace', 7).catchError((_) {});
    // Base sidetone pitch for the target word; _beginReceive() shifts it for
    // the operator's own echoed answer (Tone Shift).
    await _toneChannel.invokeMethod('setEnvelopeMs', (_toneSoftness + 1).toDouble()).catchError((_) {});

    // Like the Hören block: wait 2 s before the first word so there is time to
    // get ready (replaces the firmware's "vvv<ka>" start marker).
    if (widget.fixedTarget == null) {
      await _applyPromptConfig();
      setState(() => _preparing = true);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() => _preparing = false);
      if (!_sessionActive) return;
    }

    await _playWord(fresh: true);
  }

  void _stopSession() {
    _sessionActive = false;
    _preparing = false;
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

    if (mounted) setState(() {
      _targetVisible = false;
      _revealVisible = false;
      _state = _State.playing;
    });

    // Echo Prompt = Display only: no audio at all, just show the target briefly
    // (mirrors the real device's "silentEcho": genTimer skips almost instantly).
    if (_echoDisplay == _dispDispOnly) {
      if (mounted) setState(() => _targetVisible = true);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_state == _State.playing && mounted) _beginReceive();
      });
      return;
    }

    _revealOnDone = _echoDisplay != _dispCodeOnly;
    await _applyPromptConfig();   // base pitch — see _beginReceive() for the shifted one
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
      if (_revealOnDone) setState(() => _targetVisible = true);
      _beginReceive();
    }
  }

  void _beginReceive() {
    // Tone Shift (M32 "Tone Shift"): shift the operator's own echoed-answer
    // sidetone up/down one half-tone from the target word's playback pitch,
    // so the two are audibly distinguishable — matches MorseDecoder::ON_()/
    // m32_v6.ino's KEY_START, both gated on morseState==echoTrainer there.
    final shifted = switch (_toneShift) {
      1 => (_pitch * 18 / 17).round(),
      2 => (_pitch * 17 / 18).round(),
      _ => _pitch,
    };
    _toneChannel.invokeMethod('setFreq', shifted);
    _applyAnswerConfig();
    _keyerChannel.invokeMethod('start');
    setState(() => _state = _State.receiving);
    // Start the timeout immediately — otherwise it only ever gets (re)armed
    // reactively by an incoming symbol, so giving no echo at all waits forever.
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: _startDeadlineMs), _evaluate);
    _symbolSub = _symbolStream.receiveBroadcastStream().listen((sym) {
      _decoder.add(sym as String);
      // The answer has begun: think time no longer applies. Evaluate at the
      // word gap; the timer is just a fallback.
      if (sym == '  ' && _attempt.trim().isNotEmpty) {
        _evaluate();
      } else {
        _silenceTimer?.cancel();
        _silenceTimer = Timer(Duration(milliseconds: _answerSafetyMs), _evaluate);
      }
    });
  }

  void _onDecodedChar(String ch) {
    if (_state != _State.receiving) return;
    if (ch == ' ') return;  // ignore word-gap spaces mid-attempt
    _attempt += ch;
    setState(() {});
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
    if (_repeats == 1) _firstAttempt = _attempt.trim();
    if (_blockActive && _repeats == 1) _applyBlockFeedback(_target, _attempt);

    setState(() => _state = ok ? _State.correct : _State.wrong);
    if (_confirmTone) _toneChannel.invokeMethod('playConfirmTone', ok);

    if (ok) {
      _recordWord(_repeats == 1 ? WordOutcome.first : WordOutcome.afterRepeat);
      _correct++;
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
      _recordWord(WordOutcome.failed);
      // Reveal the word, then move on — matches the REPEAT_WORD "goto
      // randomGenerate" branch's displayGeneratedMorse(INVERSE_REGULAR, ...).
      setState(() => _revealVisible = true);
      Timer(const Duration(milliseconds: 2000), () {
        if (mounted && _sessionActive) _advance();
      });
    } else {
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _sessionActive) _playWord(fresh: false);
      });
    }
  }

  void _recordWord(WordOutcome outcome) {
    if (widget.fixedTarget != null) return;
    final t = _target.toUpperCase(), a = _firstAttempt.toUpperCase();
    var wrong = -1;
    if (a != t) {
      wrong = 0;
      while (wrong < t.length && wrong < a.length && t[wrong] == a[wrong]) wrong++;
    }
    _blockResults.add(WordResult(_target, _firstAttempt, _repeats, outcome, wrong));
  }

  // Moves on to the next word, or ends the session if Max # of Words has
  // been reached — matches fetchNewWord()'s posMaxSequence handling.
  Future<void> _advance() async {
    if (widget.fixedTarget == null) {
      _wordCounter++;
      if (_wordCounter >= _blockSize) {
        await _computeSuggestions();
        if (mounted) setState(() {
          _state = _State.idle;
          _showResult = true;
        });
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

    final e = _choice.engine;
    // Koch + random: weighted draw by weak chars (former "Adapt. Rand."),
    // a GROUP like getRandomChars(posRandomLength, ...) in m32_v6.ino.
    if (_koch && _choice.content == ContentKind.random) return _pickAdaptiveGroup();
    // Everything else is generated Kotlin-side from the shared content pools.
    final result = await _genChannel.invokeMethod('getNextContent', {
      'mode': e.mode,
      'kochLevel': _kochLevel,
      'kochActive': e.kochActive,
      'groupLength': _groupLength,
      if (e.usesRandomOption) 'randomOption': _randomOption,
      'wordLengthMax': _wordLengthMax,
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
    // Rebuild this whole screen the instant the language changes — see the
    // matching comment in settings_screen.dart's build().
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => PopScope(
      // While a block runs, back returns to the idle view instead of leaving
      // (same as the Hören block view). The single-char drill just leaves.
      canPop: _state == _State.idle || widget.fixedTarget != null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _stopSession();
      },
      child: Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, widget.title ?? Strings.t('block_give')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (_state == _State.idle && widget.fixedTarget == null)
            IconButton(
              icon: Icon(Icons.bar_chart_outlined, color: c.textMuted),
              tooltip: Strings.t('char_stats_title_echo'),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CharStatsScreen(track: CharStatsStore.echo))),
            ),
          if (_state == _State.idle)
            IconButton(
              icon: Icon(Icons.settings, color: c.textMuted),
              tooltip: Strings.t('settings_title'),
              onPressed: _openSettingsSheet,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Character set + content (hidden while running or when locked
          // to a fixed target) ─────────────────────────────────────────────
          if (widget.fixedTarget == null && _state == _State.idle && !_showResult)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: CharsetHeader(
                choice: _choice,
                onChanged: (v) { setState(() => _choice = v); _savePrefs(); },
                kochLevel: _kochLevel,
                kochSequence: _activeKochChars,
                onKochLevelChanged: (v) { setState(() => _kochLevel = v); _savePrefs(); },
                outputCase: _outputCase,
                practiceChars: _practiceChars.join(),
                onPracticeCharsChanged: (v) async {
                  _practiceChars = parsePracticeChars(v);
                  final pf = await TrainingProfile.open(TrainingProfile.echo);
                  await pf.setString('practiceChars', v);
                },
                onCharTap: (ch) => showCharActionsSheet(context,
                    ch: ch, outputCase: _outputCase,
                    onListen: () async {
                      await _toneChannel.invokeMethod('setFreq', _pitch).catchError((_) {});
                      await playCharThrice(ch, wpm: _wpm, interWordSpace: _interWordSpace);
                    },
                    onEcho: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EchoTrainerScreen(
                      fixedTarget: ch,
                      title: Strings.t('char_echo_title').replaceFirst('{ch}', ch.toUpperCase()),
                    )))),
              ),
            ),

          if (_showResult) Expanded(child: _buildBlockResult(c)) else ...[
          if (_blockActive && _sessionActive) _buildBlockProgress(c),
          // ── One word at a time: idle hint or practice view ──────────────
          Expanded(child: _state == _State.idle
              ? _buildIdle(c)
              : PinchZoomFontSize(
                  prefsKey: 'echoLogFontSize',
                  initialSize: 40,
                  minSize: 20,
                  maxSize: 72,
                  builder: (context, fontSize) => _buildPracticeView(c, fontSize),
                )),

          // ── Stats bar ────────────────────────────────────────────────────
          if (_total > 0) _StatsBar(correct: _correct, total: _total,
              answerWpm: (_answerWpmMax > 0 && _answerWpm < _currentWpm) ? _answerWpm : null),

          // ── Status label ─────────────────────────────────────────────────
          _StatusLabel(state: _state, preparing: _preparing),

          // ── Sliders ──────────────────────────────────────────────────────
          if (_state == _State.idle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _SliderRow(label: Strings.t('block_hear'), value: _wpm.toDouble(),
                  min: 5, max: 60, divisions: 55,
                  onChanged: (v) { setState(() => _wpm = v.round()); _savePrefs(); }),
              _SliderRow(label: Strings.t('block_give'), value: _answerWpmMax.toDouble(),
                  min: 0, max: 60, divisions: 60,
                  display: _answerWpmMax == 0
                      ? Strings.t('settings_answer_wpm_same') : '$_answerWpmMax',
                  onChanged: (v) => _setGiveWpm(v < 5 ? 0 : v.round())),
            ]),
          ),

          ],
          if (!_showResult) ...[
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
              child: AppButton(
                height: 56,
                label: (_state == _State.idle) ? '▶  START' : '■  STOP',
                color: (_state != _State.idle) ? c.warning : c.accent,
                onTap: (_state == _State.idle) ? _startSession : _stopSession,
              ),
            ),
          ),
          ],
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildBlockProgress(AppColors c) {
    final n = (_blockResults.length + 1).clamp(1, _blockSize);
    final dots = List.generate(_blockSize, (i) {
      if (i >= _blockResults.length) return '·';
      return switch (_blockResults[i].outcome) {
        WordOutcome.first => '●',
        WordOutcome.afterRepeat => '◐',
        WordOutcome.failed => '○',
      };
    }).join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        Text(Strings.t('block_word_of').replaceFirst('{n}', '$n').replaceFirst('{t}', '$_blockSize'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textMuted)),
        const SizedBox(height: 2),
        Text(dots, style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
      ]),
    );
  }

  Widget _buildBlockResult(AppColors c) {
    final first = _blockResults.where((r) => r.outcome == WordOutcome.first).length;
    final again = _blockResults.where((r) => r.outcome == WordOutcome.afterRepeat).length;
    final failed = _blockResults.where((r) => r.outcome == WordOutcome.failed).length;
    final total = _blockResults.length;
    final pct = total == 0 ? 0 : first * 100 ~/ total;
    final status = [
      '${Strings.t('block_hear')} $_wpm WPM',
      if (_answerWpmMax > 0 && _answerWpm < _wpm) '${Strings.t('block_give')} $_answerWpm WPM',
      if (_koch) '${Strings.t('block_lesson')} $_kochLevel',
      if (_trend != null)
        Strings.t('trend_line')
            .replaceFirst('{pct}', '${_trend!.percent}')
            .replaceFirst('{arrow}', _trend!.arrow),
    ].join(' · ');
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$pct %',
              style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 52,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('● ${Strings.t('block_right')} $first',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.accent)),
            Text('◐ ${Strings.t('block_after')} $again',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.warning)),
            Text('○ ${Strings.t('block_wrong')} $failed',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.danger)),
          ]),
        ]),
        const SizedBox(height: 6),
        Text(status, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
        if (_blockPairs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '${Strings.t('pairs_block')}: ${_blockPairs.map((x) => cs(x.replaceFirst('>', ' → '))).join(', ')}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.warning)),
          ),
        _buildTempoControls(c),
        const SizedBox(height: 4),
        Expanded(child: PinchZoomFontSize(
          prefsKey: 'echoResultFontSize',
          initialSize: 20,
          minSize: 12,
          maxSize: 40,
          builder: (context, fontSize) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView(children: [
              ..._buildSuggestionRows(c, MediaQuery.of(context).size.width - 56, cs),
              for (final r in _blockResults)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(switch (r.outcome) {
                      WordOutcome.first => '● ',
                      WordOutcome.afterRepeat => '◐ ',
                      WordOutcome.failed => '○ ',
                    }, style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize,
                        color: switch (r.outcome) {
                          WordOutcome.first => c.accent,
                          WordOutcome.afterRepeat => c.warning,
                          WordOutcome.failed => c.danger,
                        })),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cs(r.target), style: TextStyle(fontFamily: 'CwMono',
                          fontSize: fontSize, fontWeight: FontWeight.bold, color: c.textPrimary)),
                      if (r.outcome != WordOutcome.first || r.firstWrongIndex >= 0)
                        RichText(text: TextSpan(children: [
                          for (var i = 0; i < r.firstAttempt.length; i++)
                            TextSpan(text: cs(r.firstAttempt[i]), style: TextStyle(
                                fontFamily: 'CwMono', fontSize: fontSize * 0.85,
                                color: i == r.firstWrongIndex ? c.danger : c.textMuted,
                                fontWeight: i == r.firstWrongIndex ? FontWeight.bold : FontWeight.normal)),
                          if (r.firstWrongIndex >= r.firstAttempt.length)
                            TextSpan(text: r.firstAttempt.isEmpty ? '–' : '_', style: TextStyle(
                                fontFamily: 'CwMono', fontSize: fontSize * 0.85,
                                color: c.danger, fontWeight: FontWeight.bold)),
                        ])),
                    ])),
                  ]),
                ),
            ]),
          ),
        )),
        const SizedBox(height: 12),
        AppButton(
          height: 56,
          label: Strings.t('block_next'),
          color: c.accent,
          onTap: () async {
            await _applyAccepted(boost: true);
            if (mounted) setState(() {});
            await _startSession();
          },
        ),
        const SizedBox(height: 8),
        AppButton(
          height: 56,
          primary: false,
          label: Strings.t('block_end'),
          color: c.accent,
          onTap: () async {
            await _applyAccepted(boost: false);
            if (mounted) setState(() => _showResult = false);
          },
        ),
      ]),
    );
  }

  // Idle: hint and the current tempo/spacing, like the Hören block view.
  Widget _buildIdle(AppColors c) {
    final ewpm = (50 * _wpm / (31 + 4 * _interCharSpace + _interWordSpace)).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Strings.t('echo_idle_hint'), textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                  color: c.textMuted, fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          Text(Strings.t('gen_status_line')
                  .replaceFirst('{wpm}', '$_wpm')
                  .replaceFirst('{ewpm}', '$ewpm')
                  .replaceFirst('{ic}', '$_interCharSpace')
                  .replaceFirst('{iw}', '$_interWordSpace'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
        ]),
      ),
    );
  }

  // Running: the current word centred — the prompt (if shown), what the
  // operator keyed so far, and the verdict. Same one-thing-at-a-time layout
  // as the Hören block view instead of a scrolling transcript.
  Widget _buildPracticeView(AppColors c, double fontSize) {
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    final showTarget = _targetVisible || _revealVisible;
    final verdict = switch (_state) {
      _State.correct => ('OK', c.accent),
      _State.wrong => ('ERR', c.danger),
      _ => ('', c.textPrimary),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Retry indicator: only for a word that did not pass on the first try.
          Text(_repeats > 1 && _state != _State.idle
                  ? Strings.t('echo_attempt')
                      .replaceFirst('{n}', '$_repeats')
                      .replaceFirst('{max}', _echoRepeats == 7 ? '∞' : '${_echoRepeats + 1}')
                  : ' ',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                  fontWeight: FontWeight.bold, color: c.warning)),
          const SizedBox(height: 8),
          Text(showTarget ? cs(_target) : ' ', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize,
                  fontWeight: FontWeight.bold, height: 1.3,
                  color: _revealVisible ? c.warning : c.accent)),
          const SizedBox(height: 12),
          Text(_attempt.isEmpty ? ' ' : cs(_attempt), textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize * 0.8,
                  height: 1.3, color: c.textPrimary)),
          const SizedBox(height: 12),
          Text(verdict.$1.isEmpty ? ' ' : verdict.$1,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize * 0.6,
                  fontWeight: FontWeight.bold, color: verdict.$2)),
        ]),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusLabel extends StatelessWidget {
  final _State state;
  final bool preparing;
  const _StatusLabel({required this.state, this.preparing = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (text, color) = switch (state) {
      _State.idle      => (Strings.t('echo_status_idle'), c.textDisabled),
      _State.playing   => preparing
          ? (Strings.t('get_ready'), c.warning)
          : (Strings.t('echo_status_playing'), c.warning),
      _State.receiving => (Strings.t('echo_status_receiving'), c.info),
      _State.correct   => (Strings.t('echo_status_correct'), c.accent),
      _State.wrong     => (Strings.t('echo_status_wrong'), c.danger),
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
  final int? answerWpm;   // shown only when the answer is capped below the prompt tempo
  const _StatsBar({required this.correct, required this.total, this.answerWpm});

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
          if (answerWpm != null) ...[
            const SizedBox(width: 12),
            _chip('${Strings.t('echo_answer_wpm')} $answerWpm', c.info),
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

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String? display;
  const _SliderRow({required this.label, required this.value, required this.min,
      required this.max, required this.divisions, required this.onChanged,
      this.display});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
    children: [
      SizedBox(width: 56, child: Text(label,
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
      SizedBox(width: display == null ? 40 : 84, child: Text(display ?? value.round().toString(),
          textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
              color: c.accent))),
    ],
  );
  }
}
