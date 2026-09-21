// Pure-Dart, unit-testable adaptation logic for Adaptive Copy mode. See
// docs/ADAPTIVE-COPY.md ("Decisions: weighting/recency questions", answered
// 2026-09-21) for the design this implements:
//   - EMA-based (not last-block-only, not full trend detection yet).
//   - Blockquote-level tempo/spacing decision and per-character unlock
//     decision are independent and apply simultaneously, never conflicting.
// Takes generic inputs, not an AdaptiveCopyBody-shaped object, so Echo
// Trainer's own "Adaptive Speed" can eventually call into the same tempo
// logic instead of its own parallel implementation.
import 'char_stats.dart' show CharStat;

class AdaptiveCopyThresholds {
  final double highThreshold;
  final double lowThreshold;
  // Smoothing factor for the blockquote-level success-rate EMA. Per-char
  // EMA smoothing is CharStat's own emaErrorRate (char_stats.dart), reused
  // as-is rather than duplicated here.
  final double blockEmaAlpha;
  // Minimum attempts a character needs (its last-N-occurrences window,
  // approximated by CharStatsStore's continuous per-char EMA plus this
  // attempts floor) before it's eligible to unlock the next Koch character.
  final int unlockOccurrences;

  const AdaptiveCopyThresholds({
    this.highThreshold = 0.90,
    this.lowThreshold = 0.70,
    this.blockEmaAlpha = 0.3,
    this.unlockOccurrences = 20,
  });
}

enum TempoStep { up, down, none }

class TempoDecision {
  final TempoStep spacingStep;
  final TempoStep charSpeedStep;
  const TempoDecision(this.spacingStep, this.charSpeedStep);

  @override
  String toString() => 'TempoDecision(spacing: $spacingStep, charSpeed: $charSpeedStep)';
}

// Drives the two adaptation signals for Adaptive Copy mode. Not tied to any
// UI or persistence — the caller (AdaptiveCopyBody) owns loading/saving the
// blockquote EMA and CharStatsStore, and passes results in per block.
class AdaptiveCopyEngine {
  final AdaptiveCopyThresholds thresholds;
  double _blockEma;

  // `initialBlockEma` lets a caller resume a persisted EMA across sessions;
  // defaults to 1.0 (assume success) so the first block doesn't immediately
  // read as a low-threshold miss before any data exists.
  AdaptiveCopyEngine({AdaptiveCopyThresholds? thresholds, double initialBlockEma = 1.0})
      : thresholds = thresholds ?? const AdaptiveCopyThresholds(),
        _blockEma = initialBlockEma;

  double get blockEma => _blockEma;

  // Feeds one block's per-character (char, correct) results. Updates the
  // blockquote-level EMA and returns the tempo/spacing decision for this
  // block. `spacingAtCharSpeed` is true once spacing speed has caught up to
  // char speed — only then does a further "up" also step char speed itself
  // (see docs/ADAPTIVE-COPY.md "Success-rate high/low thresholds").
  TempoDecision recordBlock(List<bool> results, {required bool spacingAtCharSpeed}) {
    if (results.isEmpty) return const TempoDecision(TempoStep.none, TempoStep.none);
    final successRate = results.where((r) => r).length / results.length;
    _blockEma = thresholds.blockEmaAlpha * successRate + (1 - thresholds.blockEmaAlpha) * _blockEma;

    if (_blockEma >= thresholds.highThreshold) {
      return TempoDecision(TempoStep.up, spacingAtCharSpeed ? TempoStep.up : TempoStep.none);
    }
    if (_blockEma < thresholds.lowThreshold) {
      return const TempoDecision(TempoStep.down, TempoStep.none);
    }
    return const TempoDecision(TempoStep.none, TempoStep.none);
  }

  // Per-character unlock decision (Koch level +1), independent of
  // recordBlock's tempo decision — both can fire in the same block. A
  // character counts only once it has enough occurrences (its last-N
  // window); an empty or not-yet-attempted active set never unlocks.
  bool shouldUnlockNextChar(Iterable<CharStat> activeChars) {
    if (activeChars.isEmpty) return false;
    return activeChars.every((s) =>
        s.attempts >= thresholds.unlockOccurrences &&
        (1 - s.emaErrorRate) >= thresholds.highThreshold);
  }
}
