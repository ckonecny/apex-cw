// Pure-Dart, unit-testable thresholds and the Koch unlock rule shared by
// Hören (Adaptive Copy) and Geben (Echo Trainer). Which setting a block may
// change is decided by the training goals (training_goals.dart), which grade
// a fixed window of the last items instead of the former block EMA
// (DECISIONS.md "Training goals").
import 'char_stats.dart' show CharStat;

class AdaptiveCopyThresholds {
  // Hit rate at or above which a step towards the active goal is offered,
  // and below which undoing the last step is offered. Settings → Adaptive
  // mode, the same for every goal.
  final double highThreshold;
  final double lowThreshold;
  // Minimum attempts a character needs (its last-N-occurrences window,
  // approximated by CharStatsStore's continuous per-char EMA plus this
  // attempts floor) before it's eligible to unlock the next Koch character.
  final int unlockOccurrences;

  const AdaptiveCopyThresholds({
    this.highThreshold = 0.90,
    this.lowThreshold = 0.70,
    this.unlockOccurrences = 20,
  });
}

class AdaptiveCopyEngine {
  final AdaptiveCopyThresholds thresholds;

  AdaptiveCopyEngine({AdaptiveCopyThresholds? thresholds})
    : thresholds = thresholds ?? const AdaptiveCopyThresholds();

  // Per-character unlock decision (Koch level +1): drives the "new
  // characters" goal. A character counts only once it has enough
  // occurrences (its last-N window); an empty or not-yet-attempted active
  // set never unlocks.
  bool shouldUnlockNextChar(Iterable<CharStat> activeChars) {
    if (activeChars.isEmpty) return false;
    return activeChars.every((s) =>
        s.attempts >= thresholds.unlockOccurrences &&
        (1 - s.emaErrorRate) >= thresholds.highThreshold);
  }
}
