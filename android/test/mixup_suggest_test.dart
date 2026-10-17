import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/char_stats.dart';
import 'package:next_cw_trainer/content/mixup_suggest.dart';

void main() {
  final now = DateTime(2026, 10, 15);
  String key(int daysAgo) => dayKey(now.subtract(Duration(days: daysAgo)));

  DayStat day(Map<String, int> att, [Map<String, int> pairs = const {}]) {
    final d = DayStat();
    att.forEach((ch, n) => d.chars[ch] = [n, 0]);
    d.attempts = d.chars.values.fold(0, (a, v) => a + v[0]);
    d.pairs.addAll(pairs);
    return d;
  }

  List<String> pairs(Map<String, DayStat> days, {Iterable<String>? candidates, int max = 3}) =>
      suggestedMixups(days, now, candidates: candidates, maxPairs: max)
          .map((t) => t.pair)
          .toList();

  group('suggestedMixups', () {
    test('frequent pair is suggested even without data before it', () {
      final days = {key(2): day({'K': 40}, {'K>R': 4})}; // 10 %
      expect(pairs(days), ['K>R']);
    });

    test('below 10 % and not rising: not suggested', () {
      final days = {key(2): day({'K': 40}, {'K>R': 3})}; // 7.5 %
      expect(pairs(days), isEmpty);
    });

    test('too few mix-ups: not suggested', () {
      final days = {key(2): day({'K': 20}, {'K>R': 2})}; // 10 % but only 2
      expect(pairs(days), isEmpty);
    });

    test('rising pair is suggested below 10 %', () {
      final days = {
        key(2): day({'K': 50}, {'K>R': 4}), // 8 %
        key(20): day({'K': 50}, {'K>R': 2}), // 4 %
      };
      expect(pairs(days), ['K>R']);
    });

    test('new pair (none before) is suggested', () {
      final days = {
        key(2): day({'K': 50}, {'K>R': 3}),
        key(20): day({'K': 50}),
      };
      expect(pairs(days), ['K>R']);
    });

    test('falling pair is not suggested even when still frequent', () {
      final days = {
        key(2): day({'K': 50}, {'K>R': 6}), // 12 %
        key(20): day({'K': 50}, {'K>R': 12}), // 24 %
      };
      expect(pairs(days), isEmpty);
    });

    test('vanished pair is not suggested', () {
      final days = {
        key(2): day({'K': 50}),
        key(20): day({'K': 50}, {'K>R': 8}),
      };
      expect(pairs(days), isEmpty);
    });

    test('left-out character and identical pair are skipped', () {
      final days = {key(2): day({'K': 40, 'M': 40}, {'M>–': 8, 'K>K': 8})};
      expect(pairs(days), isEmpty);
    });

    test('only pairs whose played character can be drawn (case-insensitive)', () {
      final days = {key(2): day({'K': 40, 'Q': 40}, {'K>R': 5, 'Q>G': 6})};
      expect(pairs(days, candidates: ['k', 'r']), ['K>R']);
    });

    test('worst first, at most maxPairs', () {
      final days = {
        key(2): day({'K': 40, 'F': 40, 'B': 40, 'S': 40},
            {'K>R': 4, 'F>L': 8, 'B>D': 6, 'S>H': 5})
      };
      expect(pairs(days), ['F>L', 'B>D', 'S>H']);
      expect(pairs(days, max: 1), ['F>L']);
    });
  });

  group('mixupBoostChars', () {
    final days = {
      key(2): day({'K': 40, 'F': 40}, {'K>R': 5, 'K>M': 5, 'F>L': 6})
    };
    final trends = suggestedMixups(days, now);

    test('both characters of each pair, in the spelling of the candidates', () {
      expect(mixupBoostChars(trends, ['k', 'r', 'm', 'f', 'l', 'q']),
          {'k', 'r', 'm', 'f', 'l'});
    });

    test('a character in several pairs appears once', () {
      final set = mixupBoostChars(trends, ['k', 'r', 'm']);
      expect(set.where((c) => c == 'k').length, 1);
    });

    test('characters outside the candidates are left out', () {
      expect(mixupBoostChars(trends, ['k', 'f']), {'k', 'f'});
    });
  });
}
