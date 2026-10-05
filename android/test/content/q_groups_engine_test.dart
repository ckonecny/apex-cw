import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/q_groups_data.dart';
import 'package:next_cw_trainer/content/q_groups_engine.dart';

void main() {
  QgRound round(int seed, int level, int count, String lang) =>
      QGroupsEngine(rng: Random(seed)).newRound(level, count, lang);

  test('every question has four distinct options with the right one marked', () {
    for (var seed = 0; seed < 200; seed++) {
      for (final lang in const ['de', 'en']) {
        for (var level = 1; level <= qgLevels; level++) {
          for (final q in round(seed, level, 10, lang).questions) {
            expect(q.options.length, qgOptionCount);
            expect(q.options.toSet().length, qgOptionCount);
            final g = q.group.text(lang);
            expect(q.answer, q.isQuestion ? g.question : g.statement);
          }
        }
      }
    }
  });

  test('wrong options never come from the cluster of the right one, nor from a higher level', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= qgLevels; level++) {
        for (final q in round(seed, level, 10, 'en').questions) {
          expect(q.group.level <= level, isTrue);
          for (final o in q.options) {
            if (o == q.answer) continue;
            final owners = qGroups.where((g) {
              final t = g.en;
              return (q.isQuestion ? t.question : t.statement) == o;
            });
            expect(owners, isNotEmpty);
            for (final g in owners) {
              expect(g.cluster, isNot(q.group.cluster), reason: '${q.group.code} vs ${g.code}');
              expect(g.level <= level, isTrue);
            }
          }
        }
      }
    }
  });

  test('groups without a question form are never asked as a question', () {
    for (var seed = 0; seed < 300; seed++) {
      for (final q in round(seed, 3, 10, 'de').questions) {
        if (q.isQuestion) expect(q.group.de.question, isNotNull, reason: q.group.code);
      }
    }
  });

  test('a round of 8 at level 1 uses every group once; none twice in a row', () {
    final codes = round(1, 1, 8, 'de').questions.map((q) => q.group.code).toList();
    expect(codes.toSet().length, 8);
    for (var seed = 0; seed < 100; seed++) {
      final c = round(seed, 1, 10, 'de').questions.map((q) => q.group.code).toList();
      for (var i = 1; i < c.length; i++) {
        expect(c[i], isNot(c[i - 1]));
      }
    }
  });

  test('level 1 plays the bare group, higher levels may add a value; questions stay bare', () {
    for (var seed = 0; seed < 100; seed++) {
      for (final q in round(seed, 1, 8, 'de').questions) {
        expect(q.cwText, q.isQuestion ? '${q.group.code}?' : q.group.code);
      }
    }
    var withTail = false;
    for (var seed = 0; seed < 100; seed++) {
      for (final q in round(seed, 3, 10, 'de').questions) {
        if (q.isQuestion) {
          expect(q.cwText, '${q.group.code}?');
        } else if (q.cwText != q.group.code) {
          expect(qgTails[q.group.code], isNotNull);
          withTail = true;
        }
      }
    }
    expect(withTail, isTrue);
  });

  test('tails exist only for known groups and are plain ASCII', () {
    for (final e in qgTails.entries) {
      expect(qGroups.any((g) => g.code == e.key), isTrue);
      for (final t in e.value) {
        expect(RegExp(r'^[A-Z0-9 ]+$').hasMatch(t), isTrue, reason: t);
      }
    }
  });
}
