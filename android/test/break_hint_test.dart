import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/break_hint.dart';

void main() {
  final t0 = DateTime(2026, 10, 3, 10);
  DateTime at(int min) => t0.add(Duration(minutes: min));

  // [n] characters (default 8 groups × 5) with the wrong ones at the 1-based
  // positions [wrong].
  List<bool> block(List<int> wrong, {int n = 40}) =>
      [for (var i = 1; i <= n; i++) !wrong.contains(i)];

  // [n] characters, every [step]-th one wrong, starting at [from] (0-based):
  // evenly spread, so no burst.
  List<bool> spread(int n, int step, {int from = 0, int max = 1 << 30}) {
    var left = max;
    return [
      for (var i = 0; i < n; i++)
        !(i >= from && (i - from) % step == 0 && left-- > 0),
    ];
  }

  // The example of issue #48: fatigue creeping in, wrong positions per block.
  const fatigue = <List<int>>[
    [12, 31],
    [7, 19, 33],
    [5, 16, 28, 36],
    [4, 9, 14, 22, 27, 28, 29],
    [3, 6, 8, 11, 15, 16, 24, 25, 26, 33],
    [2, 3, 5, 8, 10, 12, 14, 17, 19, 22, 25, 26, 30],
  ];

  // Feeds [blocks] one minute apart; returns the 1-based block that fired, or 0.
  int feed(BreakWatch w, List<List<bool>> blocks,
      {String sig = 'a', String track = 'hear', int from = 0}) {
    for (var i = 0; i < blocks.length; i++) {
      if (w.add(track, blocks[i], sig, at(from + i))) return i + 1;
    }
    return 0;
  }

  final burst9 = block([1, 2, 3, 5, 6, 8, 10, 12, 14]); // 9 wrong in 20

  test('the issue example: early block 4, normal 5, late 6', () {
    for (final (s, expected) in [
      (BreakSensitivity.early, 4),
      (BreakSensitivity.normal, 5),
      (BreakSensitivity.late, 6),
    ]) {
      expect(feed(BreakWatch(sensitivity: s), [for (final w in fatigue) block(w)]),
          expected, reason: s.name);
    }
  });

  test('one lost group of five does not fire on its own', () {
    for (final s in BreakSensitivity.values) {
      expect(feed(BreakWatch(sensitivity: s), [block([6, 7, 8, 9, 10])]), 0,
          reason: s.name);
    }
  });

  test('a burst fires without a trend; 8 of 20 is not enough (normal)', () {
    expect(feed(BreakWatch(), [burst9]), 1);
    expect(feed(BreakWatch(), [block([1, 2, 3, 5, 6, 8, 10, 12])]), 0);
  });

  test('a burst window may span two blocks', () {
    final w = BreakWatch();
    expect(w.add('hear', block([32, 34, 36, 38, 40]), 'a', at(0)), isFalse);
    // 5 at the end + 4 at the start of the next block = 9 within 20 chars.
    expect(w.add('hear', block([1, 2, 3, 4]), 'a', at(1)), isTrue);
  });

  test('the trend needs twice its length (normal: 120 characters)', () {
    // Every 4th wrong: 25 % errors in the last part, but only 100 characters.
    expect(BreakWatch().add('hear', spread(100, 4, from: 40), 'a', at(0)), isFalse);
  });

  test('trend threshold: 9 more wrong in the last 60 fires, 8 does not', () {
    List<bool> run(int wrongInLast) =>
        [...List.filled(60, true), ...spread(60, 7, max: wrongInLast)];
    expect(BreakWatch().add('hear', run(9), 'a', at(0)), isTrue);
    expect(BreakWatch().add('hear', run(8), 'a', at(0)), isFalse);
  });

  test('a changed signature restarts the run (harder task, not fatigue)', () {
    final w = BreakWatch();
    expect(feed(w, [block([]), block([])], sig: 'a'), 0);
    expect(w.runLength('hear'), 80);
    // Faster: many errors, but only 9 of 20 are needed and these are the
    // first characters under the new signature, so nothing is carried over.
    expect(w.add('hear', block([1, 3, 5, 7, 9, 11, 13, 15]), 'b', at(2)), isFalse);
    expect(w.runLength('hear'), 40);
  });

  test('only once per session', () {
    final w = BreakWatch();
    expect(feed(w, [burst9]), 1);
    expect(feed(w, [burst9, burst9], from: 1), 0);
  });

  test('a long pause starts a new session and a new run', () {
    final w = BreakWatch();
    expect(feed(w, [burst9]), 1);
    expect(feed(w, [burst9], from: 40), 1);
  });

  test('tracks are watched separately', () {
    final w = BreakWatch();
    feed(w, [block([])], track: 'hear');
    expect(w.runLength('echo'), 0);
    expect(w.add('echo', burst9, 'a', at(3)), isTrue);
  });

  test('block size does not matter: same characters, same result', () {
    final all = [
      ...block([4, 9, 14], n: 15),
      ...block([2, 5, 8, 11], n: 15),
      ...block([1, 3, 6, 9, 12], n: 15),
    ];
    final one = BreakWatch().add('hear', all, 'a', at(0));
    final w = BreakWatch();
    var split = false;
    for (var i = 0; i < 3; i++) {
      split = w.add('hear', all.sublist(i * 15, i * 15 + 15), 'a', at(i)) || split;
    }
    expect(split, one);
  });
}
