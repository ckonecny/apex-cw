// Grid engine and scoring of Trailblazer / Fox Hunt (MorseGridEngine.cpp,
// MorseGridScore.cpp).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/grid_engine.dart';
import 'package:next_cw_trainer/content/grid_score.dart';

void main() {
  group('path', () {
    test('runs from the left to the right edge in single orthogonal steps, no repeats', () {
      for (var seed = 0; seed < 200; seed++) {
        final e = GridEngine(Random(seed))..generate(['E', 'T', 'A']);
        expect(e.pathColAt(0), 0);
        expect(e.pathColAt(e.pathLength - 1), gridCols - 1);
        final seen = <int>{};
        for (var i = 0; i < e.pathLength; i++) {
          expect(seen.add(e.pathRowAt(i) * gridCols + e.pathColAt(i)), isTrue);
          if (i > 0) {
            final d = (e.pathColAt(i) - e.pathColAt(i - 1)).abs() +
                (e.pathRowAt(i) - e.pathRowAt(i - 1)).abs();
            expect(d, 1);
          }
        }
      }
    });

    test('every cell comes from the pool', () {
      final e = GridEngine(Random(1))..generate(['K', 'M', '5']);
      for (var r = 0; r < gridRows; r++) {
        for (var c = 0; c < gridCols; c++) {
          expect(['K', 'M', '5'], contains(e.cell(c, r)));
        }
      }
    });

    test('the neighbours of a path cell are distinct with a roomy pool', () {
      for (var seed = 0; seed < 100; seed++) {
        final e = GridEngine(Random(seed))..generate(['M', 'K', 'R', 'S', 'U', 'A', 'P', 'T']);
        for (var p = 0; p < e.pathLength; p++) {
          final c = e.pathColAt(p), r = e.pathRowAt(p);
          final n = [
            if (r > 0) e.cell(c, r - 1),
            if (r < gridRows - 1) e.cell(c, r + 1),
            if (c > 0) e.cell(c - 1, r),
            if (c < gridCols - 1) e.cell(c + 1, r),
          ];
          expect(n.toSet().length, n.length, reason: 'seed $seed path cell $p');
        }
      }
    });
  });

  group('walking', () {
    test('advance follows the path; directionMatchesNext is true for exactly one direction', () {
      final e = GridEngine(Random(3))..generate(['E', 'T', 'A', 'N']);
      while (!e.atEnd) {
        final matches = [for (final d in GridDir.values) if (e.directionMatchesNext(d)) d];
        expect(matches.length, 1);
        final next = e.nextChar;
        expect(next, e.cell(e.pathColAt(e.currentIndex + 1), e.pathRowAt(e.currentIndex + 1)));
        e.advance();
      }
      expect(e.currentIndex, e.pathLength - 1);
      expect(e.directionMatchesNext(GridDir.e), isFalse);
      e.advance();
      expect(e.currentIndex, e.pathLength - 1);
    });
  });

  group('direction legend', () {
    test('uses the canonical letters when learned', () {
      final l = GridEngine.directionLegend(['N', 'S', 'W', 'E', 'T']);
      expect(l.map((d) => d.ltr), ['N', 'S', 'W', 'E']);
      expect(l.any((d) => d.substituted), isFalse);
    });

    test('substitutes unlearned compass letters with the first unused learned letter', () {
      // M, K, 5 are learned; N, S, W, E are not: M, K get assigned, 5 is no letter.
      final l = GridEngine.directionLegend(['M', 'K', '5', 'R']);
      expect(l.map((d) => d.ltr), ['M', 'K', 'R', '?']);
      expect(l.every((d) => d.substituted), isTrue);
    });

    test('a learned canonical letter is not reused as a substitute', () {
      final l = GridEngine.directionLegend(['E', 'M', 'K', 'R']);
      expect(l[3].ltr, 'E');
      expect(l[3].substituted, isFalse);
      expect(l.map((d) => d.ltr).toSet().length, 4);
    });
  });

  group('score', () {
    test('cpm is steps per minute over the penalised time', () {
      expect(gridCpm(60000, 30, 0), 30);
      expect(gridCpm(55000, 30, 1), 30);   // 55 s + 5 s penalty
      expect(gridCpm(0, 30, 0), greaterThan(0));
    });

    test('table keeps the best 7 by cpm, ties rank below older entries', () {
      final t = <GridScore>[];
      for (var i = 1; i <= 8; i++) {
        gridRecord(t, GridScore(i * 10, 1, 0, 40, 5));
      }
      expect(t.length, gridHiN);
      expect(t.first.cpm, 80);
      expect(t.last.cpm, 20);
      expect(gridRecord(t, const GridScore(80, 1, 0, 40, 5)), 1);
      expect(gridRecord(t, const GridScore(5, 1, 0, 40, 5)), -1);
      expect(gridRecord(<GridScore>[], const GridScore(0, 1, 0, 40, 5)), -1);
    });

    test('json round trip, bad data gives an empty table', () {
      final t = [gridScore(60000, 40, 2, 7)];
      final back = gridTableFromJson(gridTableToJson(t));
      expect(back.single.cpm, t.single.cpm);
      expect(back.single.koch, 7);
      expect(gridTableFromJson('nonsense'), isEmpty);
      expect(gridTableFromJson(null), isEmpty);
    });
  });
}
