import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/mini_qso_engine.dart';

const _calls = ['OE1ABC', 'DL2XYZ', 'HB9AAA', 'G4BBB', 'OE3CCC', 'DK5DDD', 'F6EEE', 'OE7FFF'];

void main() {
  test('building blocks are sound', () => expect(mqValidate(), isEmpty));

  test('question counts per level', () {
    final e = MiniQsoEngine(rng: Random(1));
    expect(e.newRound(1, _calls).questions.length, 3);
    expect(e.newRound(2, _calls).questions.length, 5);
    expect(e.newRound(3, _calls).questions.length, 2 + mqLevel3Facts);
  });

  test('every question has four different options with the right one inside', () {
    for (var seed = 0; seed < 200; seed++) {
      final e = MiniQsoEngine(rng: Random(seed));
      for (var lv = 1; lv <= mqLevels; lv++) {
        final r = e.newRound(lv, _calls);
        for (final q in r.questions) {
          expect(q.options.length, mqOptionCount);
          expect(q.options.toSet().length, mqOptionCount);
          expect(q.options[q.correct], q.answer);
        }
      }
    }
  });

  test('the right answer is what is played', () {
    for (var seed = 0; seed < 100; seed++) {
      final r = MiniQsoEngine(rng: Random(seed)).newRound(3, _calls);
      final heard = r.turns.map((t) => ' ${t.text} ').join();
      for (final q in r.questions) {
        expect(heard.contains(' ${q.answer} '), isTrue, reason: q.answer);
      }
    }
  });

  test('level 3 does not always ask the same facts', () {
    final sets = {
      for (var seed = 0; seed < 50; seed++)
        MiniQsoEngine(rng: Random(seed)).newRound(3, _calls).questions.skip(2).map((q) => '${q.station}${q.fact.name}').join(',')
    };
    expect(sets.length, greaterThan(5));
  });

  test('level 3 names the stations by callsign after the call questions', () {
    final r = MiniQsoEngine(rng: Random(3)).newRound(3, _calls);
    expect(r.questions.take(2).every((q) => q.byCall == null), isTrue);
    expect(r.questions.skip(2).every((q) => q.byCall != null), isTrue);
  });

  test('the two stations differ in names and places', () {
    String after(String text, String key) => RegExp('$key (\\w+)').firstMatch(text)!.group(1)!;
    for (var seed = 0; seed < 100; seed++) {
      final r = MiniQsoEngine(rng: Random(seed)).newRound(3, _calls);
      expect(after(r.turns[1].text, 'NAME'), isNot(after(r.turns[2].text, 'NAME')));
      expect(after(r.turns[1].text, 'QTH'), isNot(after(r.turns[2].text, 'QTH')));
    }
  });

  test('levels 1 and 2 end after the answer; level 3 is a full exchange', () {
    final e = MiniQsoEngine(rng: Random(2));
    expect(e.newRound(1, _calls).turns.length, 3);
    expect(e.newRound(3, _calls).turns.length, 5);
  });
}
