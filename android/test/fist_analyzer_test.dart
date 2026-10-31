import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/keyer/fist_analyzer.dart';

/// Keys "dit dah dit dah ..." patterns: [press, gap] pairs in ms.
FistAnalyzer keyed(List<(int press, int gap)> seq, {int start = 1000}) {
  final a = FistAnalyzer();
  var t = start;
  for (final (press, gap) in seq) {
    a.add(true, t);
    t += press;
    a.add(false, t);
    t += gap;
  }
  return a;
}

/// "CQ" repeated: -.-. --.-  with the given dit, dah factor and gap factors.
List<(int, int)> cq(int dit,
    {double dah = 3, double elGap = 1, double letter = 3, double word = 7, int reps = 4}) {
  final out = <(int, int)>[];
  int d(double f) => (dit * f).round();
  for (var r = 0; r < reps; r++) {
    for (final w in ['-.-.', '--.-']) {
      for (var i = 0; i < w.length; i++) {
        final last = i == w.length - 1;
        out.add((w[i] == '.' ? dit : d(dah), last ? d(letter) : d(elGap)));
      }
    }
    out[out.length - 1] = (out.last.$1, d(word));
  }
  return out;
}

void main() {
  test('perfect fist: index 100, all deviations 0', () {
    final r = keyed(cq(60)).report();
    expect(r.index, 100);
    expect(r.ditMs, closeTo(60, 0.1));
    expect(r.wpm, closeTo(20, 0.1));
    for (final s in r.stats.values) {
      expect(s.deviation.abs(), lessThan(0.01));
    }
  });

  test('steady but slow fist scores the same as a fast one', () {
    expect(keyed(cq(150)).report().index, 100);
    expect(keyed(cq(40)).report().index, 100);
  });

  test('dah too short shows as negative deviation and lowers the index', () {
    final r = keyed(cq(60, dah: 2.2)).report();
    expect(r.stats[FistElement.dah]!.deviation, lessThan(-0.3));
    expect(r.stats[FistElement.dit]!.deviation.abs(), lessThan(0.01));
    expect(r.index!, lessThan(100));
    expect(r.index!, greaterThan(50));
  });

  test('letter gaps that are too short are found as gaps, not dits/dahs', () {
    final r = keyed(cq(60, letter: 2)).report();
    expect(r.stats[FistElement.letterGap]!.deviation, lessThan(-0.3));
    expect(r.stats[FistElement.dah]!.deviation.abs(), lessThan(0.01));
  });

  test('word gaps that are too long show as positive deviation', () {
    final r = keyed(cq(60, word: 12)).report();
    expect(r.stats[FistElement.wordGap]!.deviation, greaterThan(0.5));
  });

  test('the worse the rhythm, the lower the index', () {
    final good = keyed(cq(60, dah: 2.8)).report().index!;
    final bad = keyed(cq(60, dah: 2.0, letter: 2, elGap: 1.5)).report().index!;
    expect(good, greaterThan(bad));
  });

  test('contact bounce is ignored', () {
    final a = FistAnalyzer();
    var t = 0;
    for (final (press, gap) in cq(60)) {
      a.add(true, t);
      t += 30;
      a.add(false, t); // key opens for 4 ms in the middle of the press
      t += 4;
      a.add(true, t);
      t += press - 34;
      a.add(false, t);
      // ghost press of 5 ms inside the gap
      t += 20;
      a.add(true, t);
      t += 5;
      a.add(false, t);
      t += gap - 25;
    }
    final r = a.report();
    expect(r.index, greaterThan(95));
    expect(r.stats[FistElement.dit]!.ratio, closeTo(1, 0.1));
  });

  test('too little data gives no index', () {
    final r = keyed(cq(60, reps: 1)).report(); // 8 presses + gaps < 20 elements
    expect(r.elements, lessThan(FistAnalyzer.minElements));
    expect(r.index, isNull);
    expect(keyed(const [(60, 60)]).report().stats, isEmpty);
  });

  test('dits only: no dah category', () {
    final r = keyed([for (var i = 0; i < 20; i++) (60, 60)]).report();
    expect(r.stats.containsKey(FistElement.dah), isFalse);
    expect(r.stats[FistElement.dit]!.count, 20);
    expect(r.index, 100);
  });

  test('only the newest elements count', () {
    final a = FistAnalyzer(window: 24);
    var t = 0;
    for (final (press, gap) in [...cq(60, dah: 1.5), ...cq(60, reps: 6)]) {
      a.add(true, t);
      t += press;
      a.add(false, t);
      t += gap;
    }
    expect(a.report().stats[FistElement.dah]!.deviation.abs(), lessThan(0.05));
  });

  group('spread', () {
    test('min and max of the single elements are reported', () {
      final seq = cq(60);
      // one dah too short (140 ms) and one too long (260 ms)
      final i = seq.indexWhere((e) => e.$1 > 100);
      seq[i] = (140, seq[i].$2);
      final j = seq.lastIndexWhere((e) => e.$1 > 100);
      seq[j] = (260, seq[j].$2);
      final d = keyed(seq).report().stats[FistElement.dah]!;
      expect(d.minRatio * 60, closeTo(140, 1));
      expect(d.maxRatio * 60, closeTo(260, 1));
      expect(d.minDeviation, lessThan(0));
      expect(d.maxDeviation, greaterThan(0));
    });
  });

  group('hints', () {
    // Plays [seq] and feeds the hints after every key-up, like the screen.
    FistHints play(List<(int, int)> seq, [FistHints? h]) {
      h ??= FistHints();
      final a = FistAnalyzer();
      var t = 0;
      for (final (press, gap) in seq) {
        a.add(true, t);
        t += press;
        a.add(false, t);
        t += gap;
        h.update(a.report());
      }
      return h;
    }

    test('a good fist gets no remark', () {
      expect(play(cq(60, reps: 8)).shown, isEmpty);
    });

    test('a steady short dah is named', () {
      final h = play(cq(60, dah: 2.0, reps: 8));
      expect(h.shown.map((x) => x.key), ['fist_h_dah_short']);
    });

    test('two worst misses at most, biggest first', () {
      final h = play(cq(60, dah: 2.2, letter: 2.2, word: 12, reps: 10));
      expect(h.shown.length, 2);
      expect(h.shown.first.element, FistElement.wordGap);
    });

    test('single outliers do not make a remark', () {
      final seq = cq(60, reps: 10);
      for (var i = 7; i < seq.length; i += 11) {
        seq[i] = (seq[i].$1 > 100 ? 70 : 200, seq[i].$2); // wild press
      }
      expect(play(seq).shown, isEmpty);
    });

    test('a remark stays while the miss is between the two thresholds', () {
      final h = play(cq(60, dah: 2.0, reps: 8));
      expect(h.shown, isNotEmpty);
      // keeps going with dah 2.4 (-0.32 octave from 3 .. below on, above off)
      play(cq(60, dah: 2.5, reps: 8), h); // new analyzer, hints carried over
      expect(h.shown.map((x) => x.element), contains(FistElement.dah));
    });

    test('a remark goes after the fist is fixed, not at once', () {
      final h = play(cq(60, dah: 2.0, reps: 8));
      final once = FistAnalyzer();
      expect(h.shown, isNotEmpty);
      var t = 0;
      for (final (press, gap) in cq(60, reps: 10)) {
        once.add(true, t);
        t += press;
        once.add(false, t);
        t += gap;
        h.update(once.report());
        if (once.report().index == null) continue;
      }
      expect(h.shown, isEmpty);
    });

    test('clear drops everything', () {
      final h = play(cq(60, dah: 2.0, reps: 8))..clear();
      expect(h.shown, isEmpty);
    });
  });
}
