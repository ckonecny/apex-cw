// Pure-Dart suggestion logic for the Echo Trainer's block flow
// (docs/training/P6-echo-vorschlaege.md). Reuses AdaptiveCopyEngine for the
// block EMA / tempo steps and the unlock check; this file only adds the
// Echo-specific rules (first-try rate, Gebe-Tempo, lock while Koch chars are
// still open). Proposals only — nothing here changes any setting.
import 'adaptive_copy_engine.dart';
import 'char_stats.dart';
import 'training_profile.dart';

/// Lowest Gebe-Tempo cap (echoAnswerWpmMax) the UI offers; 0 = same as
/// Hören. Same floor as the listening speed (TrainingProfile.minWpm).
const int kGiveWpmMin = TrainingProfile.minWpm;

/// A stored cap, sanitised: 0 stays "same as Hören", older values below
/// [kGiveWpmMin] are raised to it.
int kGiveWpmCap(int v) => v <= 0 ? 0 : v.clamp(kGiveWpmMin, 60);

class EchoSuggestionInput {
  // One entry per word of the block: true = right on the first attempt
  // (a word right only after a repeat counts as false, decision 3).
  final List<bool> firstTry;
  final int wpm; // Hör-Tempo
  final int answerWpmMax; // Gebe-Tempo cap, 0 = same as Hören
  final int interCharSpace, interWordSpace;
  // Upper bound for widening (spacing at session start).
  final int maxInterCharSpace, maxInterWordSpace;
  // Koch content only; otherwise kochLevel = kochTotal = 0.
  final int kochLevel, kochTotal;
  // Characters the block could have used, for unlock check and weak chars.
  // Empty for word/callsign content.
  final List<String> activeChars;
  final CharStatsStore stats;

  const EchoSuggestionInput({
    required this.firstTry,
    required this.wpm,
    required this.answerWpmMax,
    required this.interCharSpace,
    required this.interWordSpace,
    required this.maxInterCharSpace,
    required this.maxInterWordSpace,
    required this.kochLevel,
    required this.kochTotal,
    required this.activeChars,
    required this.stats,
  });
}

class EchoSuggestions {
  final double blockRate; // first-try rate of this block, 0..1
  final double blockEma;
  final bool unlockNext;
  final int? newInterChar, newInterWord; // tighten or widen (see before)
  final int? newWpm; // Hör-Tempo +1
  final int? newAnswerWpmMax; // Gebe-Tempo +1
  final Map<String, double> weakChars;

  const EchoSuggestions({
    required this.blockRate,
    required this.blockEma,
    required this.unlockNext,
    this.newInterChar,
    this.newInterWord,
    this.newWpm,
    this.newAnswerWpmMax,
    this.weakChars = const {},
  });

  bool get hasAny =>
      unlockNext || newInterChar != null || newWpm != null || newAnswerWpmMax != null;
}

// Feeds one block into `engine` (updates its block EMA) and decides.
EchoSuggestions evaluateEchoBlock(AdaptiveCopyEngine engine, EchoSuggestionInput i) {
  final n = i.firstTry.length;
  final rate = n == 0 ? 0.0 : i.firstTry.where((r) => r).length / n;
  final spacingAtCharSpeed = i.interCharSpace <= 3 && i.interWordSpace <= 7;
  final decision = engine.recordBlock(i.firstTry, spacingAtCharSpeed: spacingAtCharSpeed);

  final koch = i.kochTotal > 0;
  final kochOpen = koch && i.kochLevel < i.kochTotal;
  final unlock = kochOpen &&
      engine.shouldUnlockNextChar(i.activeChars.map((c) => i.stats.stats[c] ?? CharStat()));
  // Tempo may only rise once no Koch chars are open and none was added in
  // this block (decision 2); widening / slowing down is never blocked.
  final mayRise = !unlock && !kochOpen;

  int? ic, iw;
  if (decision.spacingStep == TempoStep.up && mayRise) {
    ic = (i.interCharSpace - 1).clamp(3, i.maxInterCharSpace);
    iw = (i.interWordSpace - 1).clamp(7, i.maxInterWordSpace);
  } else if (decision.spacingStep == TempoStep.down) {
    ic = (i.interCharSpace + 1).clamp(3, i.maxInterCharSpace);
    iw = (i.interWordSpace + 1).clamp(7, i.maxInterWordSpace);
  }
  if (ic == i.interCharSpace && iw == i.interWordSpace) { ic = null; iw = null; }

  final newWpm = (decision.charSpeedStep == TempoStep.up && mayRise) ? i.wpm + 1 : null;

  // Gebe-Tempo: only with an explicit cap below the Hör-Tempo, never
  // automatic (decision 10). Not in the block where a char was added.
  int? newAnswer;
  if (!unlock &&
      rate >= engine.thresholds.highThreshold &&
      i.answerWpmMax > 0 &&
      i.answerWpmMax < i.wpm) {
    newAnswer = i.answerWpmMax + 1;
  }

  final weak = i.activeChars.isEmpty
      ? const <String, double>{}
      : weakCharsLifetime(i.stats, i.activeChars);

  return EchoSuggestions(
    blockRate: rate,
    blockEma: engine.blockEma,
    unlockNext: unlock,
    newInterChar: ic,
    newInterWord: iw,
    newWpm: newWpm,
    newAnswerWpmMax: newAnswer,
    weakChars: weak,
  );
}
