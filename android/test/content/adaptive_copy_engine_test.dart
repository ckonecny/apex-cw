import 'package:flutter_test/flutter_test.dart';
import 'package:morserino_mobile/content/adaptive_copy_engine.dart';
import 'package:morserino_mobile/content/char_stats.dart';

void main() {
  group('AdaptiveCopyEngine.recordBlock', () {
    test('empty results yield no decision and no EMA change', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.5);
      final decision = engine.recordBlock([], spacingAtCharSpeed: false);
      expect(decision.spacingStep, TempoStep.none);
      expect(decision.charSpeedStep, TempoStep.none);
      expect(engine.blockEma, 0.5);
    });

    test('repeated perfect blocks eventually cross the high threshold', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.5);
      TempoDecision? decision;
      for (var i = 0; i < 10; i++) {
        decision = engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: false);
      }
      expect(engine.blockEma, greaterThanOrEqualTo(0.90));
      expect(decision!.spacingStep, TempoStep.up);
      // spacingAtCharSpeed was false throughout, so char speed never steps.
      expect(decision.charSpeedStep, TempoStep.none);
    });

    test('a single high block does not yet step spacing (hysteresis)', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.95);
      final decision = engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: true);
      expect(decision.spacingStep, TempoStep.none);
      expect(decision.charSpeedStep, TempoStep.none);
    });

    test('spacing at char speed lets a high EMA also step char speed, '
        'once the consecutive-high requirement is met', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.95);
      engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: true);
      final decision = engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: true);
      expect(decision.spacingStep, TempoStep.up);
      expect(decision.charSpeedStep, TempoStep.up);
    });

    test('a dip back below high resets the consecutive-high streak', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.95);
      engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: false); // 1st high
      engine.recordBlock(List.filled(10, false), spacingAtCharSpeed: false); // dip, resets streak
      final decision = engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: false); // 1st high again
      expect(decision.spacingStep, TempoStep.none);
    });

    test('repeated failing blocks cross the low threshold and step down', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.8);
      TempoDecision? decision;
      for (var i = 0; i < 10; i++) {
        decision = engine.recordBlock(List.filled(10, false), spacingAtCharSpeed: false);
      }
      expect(engine.blockEma, lessThan(0.70));
      expect(decision!.spacingStep, TempoStep.down);
      expect(decision.charSpeedStep, TempoStep.none);
    });

    test('mid-range EMA yields no tempo change', () {
      final engine = AdaptiveCopyEngine(initialBlockEma: 0.80);
      final decision = engine.recordBlock(List.filled(10, true), spacingAtCharSpeed: false);
      expect(engine.blockEma, greaterThan(0.70));
      expect(engine.blockEma, lessThan(0.90));
      expect(decision.spacingStep, TempoStep.none);
      expect(decision.charSpeedStep, TempoStep.none);
    });
  });

  group('AdaptiveCopyEngine.shouldUnlockNextChar', () {
    test('empty active set never unlocks', () {
      final engine = AdaptiveCopyEngine();
      expect(engine.shouldUnlockNextChar([]), isFalse);
    });

    test('all chars mastered with enough attempts unlocks', () {
      final engine = AdaptiveCopyEngine();
      final chars = [
        CharStat()..attempts = 25..emaErrorRate = 0.05,
        CharStat()..attempts = 30..emaErrorRate = 0.02,
      ];
      expect(engine.shouldUnlockNextChar(chars), isTrue);
    });

    test('a character below the attempts floor blocks unlock', () {
      final engine = AdaptiveCopyEngine();
      final chars = [
        CharStat()..attempts = 25..emaErrorRate = 0.05,
        CharStat()..attempts = 5..emaErrorRate = 0.0,
      ];
      expect(engine.shouldUnlockNextChar(chars), isFalse);
    });

    test('a character with high error rate blocks unlock', () {
      final engine = AdaptiveCopyEngine();
      final chars = [
        CharStat()..attempts = 25..emaErrorRate = 0.05,
        CharStat()..attempts = 25..emaErrorRate = 0.5,
      ];
      expect(engine.shouldUnlockNextChar(chars), isFalse);
    });

    test('custom thresholds are respected', () {
      final engine = AdaptiveCopyEngine(
          thresholds: const AdaptiveCopyThresholds(highThreshold: 0.80, unlockOccurrences: 10));
      final chars = [CharStat()..attempts = 10..emaErrorRate = 0.15];
      expect(engine.shouldUnlockNextChar(chars), isTrue);
    });
  });
}
