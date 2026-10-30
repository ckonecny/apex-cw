import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/adaptive_copy_engine.dart';
import 'package:next_cw_trainer/content/char_stats.dart';

void main() {
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
