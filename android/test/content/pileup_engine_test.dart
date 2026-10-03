import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/pileup_engine.dart';

void main() {
  late int n;
  String call() => 'DL${n++}AB';
  PileupEngine make([int level = 1]) {
    n = 0;
    return PileupEngine(call, difficulty: pileupDifficulties[level]);
  }

  test('start spawns the initial callers', () {
    final e = make(3)..start(0);
    expect(e.callers.length, 3);
    expect(e.lives, 3);
  });

  test('correct defend scores 100 + 10 x streak, then pauses for an attack', () {
    final e = make()..start(0);
    e.tick(10, typing: false);
    final cur = e.current!;
    expect(e.submit(cur.call.toLowerCase(), 1000), PileupEvent.correct);
    expect(e.score, 110);
    expect(e.streak, 1);
    expect(e.attackMode, true);
    // Attack: wrong first, then right (+50).
    e.tick(1100, typing: false);
    expect(e.attackPrompt, isNotEmpty);
    expect(e.submit('XX', 1200), PileupEvent.tryAgain);
    expect(e.submit(e.attackPrompt, 1300), PileupEvent.attackSent);
    expect(e.score, 160);
    expect(e.attackMode, false);
  });

  test('wrong answer resets the streak and keeps the caller', () {
    final e = make()..start(0);
    e.tick(10, typing: false);
    expect(e.submit('NOPE', 100), PileupEvent.wrong);
    expect(e.streak, 0);
    expect(e.current, isNotNull);
  });

  test('timeout drops the caller, costs 25 (not below 0) and the streak', () {
    final e = make()..start(0);
    e.tick(10, typing: false);
    final to = e.difficulty.callerTimeout;
    final ev = e.tick(10 + to + 1, typing: false);
    expect(ev, contains(PileupEvent.timeout));
    expect(e.dropped, 1);
    expect(e.score, 0);
  });

  test('no timeout while a response is being keyed', () {
    final e = make()..start(0);
    e.tick(10, typing: false);
    final ev = e.tick(10 + e.difficulty.callerTimeout + 5, typing: true);
    expect(ev, isNot(contains(PileupEvent.timeout)));
    expect(e.dropped, 0);
  });

  test('drops cost lives and the game ends at zero lives', () {
    final e = make(2)..start(0); // HARD: 3 drops per life, 20 s
    var t = 0;
    var ended = false;
    for (var i = 0; i < 4000 && !ended; i++) {
      t += 500;
      ended = e.tick(t, typing: false).contains(PileupEvent.over);
    }
    expect(ended, true);
    expect(e.lives, 0);
    expect(e.dropped, greaterThanOrEqualTo(9));
  });

  test('attack pause freezes queue patience', () {
    final e = make(2)..start(0);
    e.tick(10, typing: false);
    final waiting = e.callers.firstWhere((c) => !identical(c, e.current));
    final before = waiting.queuedSince;
    e.submit(e.current!.call, 5000);
    e.tick(5100, typing: false);
    e.submit(e.attackPrompt, 9000);
    expect(waiting.queuedSince, before + 4000);
  });

  test('streak builds up over consecutive defends', () {
    final e = make()..start(0);
    var t = 0;
    for (var i = 0; i < 5; i++) {
      t += 9000;   // long enough for the next caller to arrive
      e.tick(t, typing: false);
      e.submit(e.current!.call, t);
      e.tick(t, typing: false);
      e.submit(e.attackPrompt, t);
    }
    expect(e.streak, 5);
    expect(e.bestStreak, 5);
  });
}
