import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/char_stats.dart';
import 'package:next_cw_trainer/content/mixup_trend.dart';
import 'package:next_cw_trainer/content/progress_series.dart';

void main() {
  final now = DateTime(2026, 10, 15);
  String key(int daysAgo) => dayKey(now.subtract(Duration(days: daysAgo)));

  // One day: attempts at K (or at [char]), more attempts per character in
  // [att], and the mix-ups of the day.
  DayStat day({
    int k = 0,
    Map<String, int> pairs = const {},
    String char = 'K',
    Map<String, int> att = const {},
  }) {
    final d = DayStat();
    if (k > 0) d.chars[char] = [k, 0];
    att.forEach((ch, n) => d.chars[ch] = [n, 0]);
    d.attempts = d.chars.values.fold(0, (a, v) => a + v[0]);
    d.pairs.addAll(pairs);
    return d;
  }

  group('classifyMixup', () {
    MixupDirection c(int cr, int cp, int ar, int ap) => classifyMixup(
        countRecent: cr, countPrior: cp, attemptsRecent: ar, attemptsPrior: ap);

    test('rate doubles: up', () => expect(c(6, 3, 50, 50), MixupDirection.up));
    test('rate halves: down', () => expect(c(3, 6, 50, 50), MixupDirection.down));
    test('small change: same', () => expect(c(4, 4, 50, 50), MixupDirection.same));
    test('1 % to 2 % is noise (under 2 points): same',
        () => expect(c(2, 1, 100, 100), MixupDirection.same));
    test('more practice, same rate: same, not up',
        () => expect(c(10, 5, 100, 50), MixupDirection.same));
    test('absent before: new', () => expect(c(4, 0, 50, 50), MixupDirection.fresh));
    test('absent now: gone', () => expect(c(0, 4, 50, 50), MixupDirection.gone));
    test('too few attempts in a window',
        () => expect(c(6, 3, 10, 50), MixupDirection.tooFew));
    test('too few mix-ups overall',
        () => expect(c(1, 1, 50, 50), MixupDirection.tooFew));
  });

  group('mixupTrends', () {
    test('compares recent window with the one before, rates not counts', () {
      final days = {
        // recent 14 days: 40 attempts at K, 8× K>R (20 %)
        key(1): day(k: 20, pairs: {'K>R': 4}),
        key(5): day(k: 20, pairs: {'K>R': 4}),
        // prior window: 80 attempts at K, 8× K>R (10 %)
        key(16): day(k: 40, pairs: {'K>R': 4}),
        key(20): day(k: 40, pairs: {'K>R': 4}),
      };
      final t = mixupTrends(days, now).single;
      expect(t.pair, 'K>R');
      expect(t.rateRecent, closeTo(0.2, 1e-9));
      expect(t.ratePrior, closeTo(0.1, 1e-9));
      expect(t.direction, MixupDirection.up);
    });

    test('same counts but twice the practice reads as less frequent', () {
      final days = {
        key(2): day(k: 100, pairs: {'K>R': 6}),
        key(18): day(k: 40, pairs: {'K>R': 6}),
      };
      expect(mixupTrends(days, now).single.direction, MixupDirection.down);
    });

    test('window edges: day 14 ago is prior, day 13 ago is recent', () {
      final days = {
        key(13): day(k: 20, pairs: {'K>R': 3}),
        key(14): day(k: 20, pairs: {'K>R': 3}),
      };
      final t = mixupTrends(days, now).single;
      expect(t.countRecent, 3);
      expect(t.countPrior, 3);
      expect(mixupTrends(days, now, windowDays: 30).single.countPrior, 0);
    });

    test('older than two windows is ignored', () {
      final days = {key(40): day(k: 50, pairs: {'K>R': 9})};
      expect(mixupTrends(days, now), isEmpty);
    });

    test('attempts are counted case-insensitively', () {
      final days = {
        key(1): day(k: 20, char: 'k', pairs: {'K>R': 3}),
        key(16): day(k: 20, char: 'k', pairs: {'K>R': 3}),
      };
      expect(mixupTrends(days, now).single.attemptsRecent, 20);
    });

    test('order: up before same before too few', () {
      final att = {'K': 40, 'B': 40, 'Q': 40};
      final days = {
        key(1): day(att: att, pairs: {'K>R': 8, 'B>D': 3, 'Q>G': 1}),
        key(16): day(att: att, pairs: {'K>R': 2, 'B>D': 3}),
      };
      final t = mixupTrends(days, now);
      expect([for (final x in t) x.pair], ['K>R', 'B>D', 'Q>G']);
      expect([for (final x in t) x.direction],
          [MixupDirection.up, MixupDirection.same, MixupDirection.tooFew]);
    });

    test('left-out mix-up K>– works like any pair', () {
      final days = {
        key(1): day(k: 20, pairs: {'K>–': 4}),
        key(16): day(k: 20, pairs: {'K>–': 1}),
      };
      final t = mixupTrends(days, now).single;
      expect(t.given, '–');
      expect(t.direction, MixupDirection.up);
    });
  });

  group('mixupTrendStart', () {
    test('null while nothing is logged', () {
      expect(mixupTrendStart({key(1): day(k: 5)}, now), isNull);
    });

    test('first logged day plus two windows', () {
      final days = {
        key(3): day(k: 5, pairs: {'K>R': 1}),
        key(1): day(k: 5, pairs: {'K>R': 1}),
      };
      final s = mixupTrendStart(days, now)!;
      expect(s.from, DateTime.utc(2026, 10, 12).add(const Duration(days: 28)));
      expect(s.elapsed, 4);
      expect(s.needed, 28);
    });
  });

  group('ProgressBucket.pairRate', () {
    test('rate per week from pairs and attempts', () {
      final days = {key(1): day(k: 20, pairs: {'K>R': 5})};
      final s = buildSeries(days, ProgressRange.weeks12, now);
      final b = s.buckets.last;
      expect(b.pairRate('K>R'), closeTo(0.25, 1e-9));
      expect(b.pairRate('K>R', minAttempts: 30), isNull);
      expect(s.buckets.first.pairRate('K>R'), isNull);
    });
  });
}
