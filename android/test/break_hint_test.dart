import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/break_hint.dart';

void main() {
  final t0 = DateTime(2026, 10, 3, 10);
  DateTime at(int min) => t0.add(Duration(minutes: min));

  // Feeds [rates] one minute apart; returns the index that fired, or -1.
  int feed(BreakWatch w, List<double> rates, {String sig = 'a', String track = 'hear', int from = 0}) {
    for (var i = 0; i < rates.length; i++) {
      if (w.add(track, rates[i], sig, at(from + i))) return i;
    }
    return -1;
  }

  test('fires on a clear drop once six blocks are there', () {
    expect(feed(BreakWatch(), [.95, .95, .95, .8, .7, .7]), 5);
  });

  test('not before six blocks', () {
    expect(feed(BreakWatch(), [.95, .95, .95, .6, .6]), -1);
  });

  test('a small drop does not fire', () {
    expect(feed(BreakWatch(), [.95, .95, .95, .85, .85, .85]), -1);
  });

  test('exactly at the threshold fires', () {
    expect(feed(BreakWatch(), [.9, .9, .9, .75, .75, .75]), 5);
  });

  test('a changed signature restarts the run (harder task, not fatigue)', () {
    final w = BreakWatch();
    expect(feed(w, [.95, .95, .95], sig: 'a'), -1);
    // Faster: rate drops, but under the new signature there are only 3 blocks.
    expect(feed(w, [.6, .6, .6], sig: 'b', from: 3), -1);
    expect(w.runLength('hear'), 3);
  });

  test('a drop only after a change is not counted against the old start', () {
    final w = BreakWatch();
    feed(w, [.95, .95, .95], sig: 'a');
    // 6 blocks under the new signature, flat at the new (lower) level.
    expect(feed(w, [.6, .6, .6, .6, .6, .6], sig: 'b', from: 3), -1);
  });

  test('only once per session', () {
    final w = BreakWatch();
    expect(feed(w, [.95, .95, .95, .7, .7, .7]), 5);
    expect(feed(w, [.5, .5, .5], from: 6), -1);
  });

  test('a long pause starts a new session and a new run', () {
    final w = BreakWatch();
    expect(feed(w, [.95, .95, .95, .7, .7, .7]), 5);
    // 30 minutes later: the hint may show again after a fresh run.
    expect(feed(w, [.95, .95, .95, .7, .7, .7], from: 40), 5);
  });

  test('tracks are watched separately', () {
    final w = BreakWatch();
    feed(w, [.95, .95, .95], track: 'hear');
    expect(feed(w, [.5, .5, .5], track: 'echo', from: 3), -1);
  });
}
