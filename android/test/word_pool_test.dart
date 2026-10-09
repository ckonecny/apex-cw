import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/word_pool.dart';

void main() {
  for (final lang in ['en', 'de']) {
    final pool = WordPool(WordPool.parse(File('assets/words/$lang.txt').readAsStringSync()));

    test('$lang list: only a-z, sane length, no duplicates', () {
      expect(pool.words, isNotEmpty);
      expect(pool.words.every((w) => RegExp(r'^[a-z]{2,12}$').hasMatch(w)), isTrue);
      expect(pool.words.toSet().length, pool.words.length);
    });

    test('$lang list: length filter and Koch characters narrow the pool', () {
      final all = pool.count();
      expect(all, pool.words.length);
      expect(pool.count(minLen: 4), lessThan(all));
      expect(pool.count(maxLen: 3), lessThan(all));
      expect(pool.count(minLen: 4, maxLen: 3), 0);
      final early = pool.count(allowedChars: 'mkrsuaptlowi'.split('').toSet());
      expect(early, greaterThan(50));
      expect(early, lessThan(all));
      expect(pool.count(allowedChars: <String>{}), 0);
    });
  }

  test('roughly rounds to an order of magnitude', () {
    expect(WordPool.roughly(7), 7);
    expect(WordPool.roughly(43), 45);
    expect(WordPool.roughly(194), 190);
    expect(WordPool.roughly(1467), 1500);
  });
}
