import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/content/char_stats.dart';

void main() {
  test('old single store becomes the hearing track, echo starts empty', () async {
    SharedPreferences.setMockInitialValues({
      'charStats': '{"k":{"a":10,"e":3,"ema":0.3,"lb":2,"w":5}}',
    });
    final p = await SharedPreferences.getInstance();
    final hear = CharStatsStore(CharStatsStore.hear);
    await hear.load(p);
    final echo = CharStatsStore(CharStatsStore.echo);
    await echo.load(p);
    expect(hear.stats['k']!.attempts, 10);
    expect(echo.stats, isEmpty);
    expect(p.getString('charStats'), isNull);
  });

  test('legacy adaptiveWeights migrate to hearing', () async {
    SharedPreferences.setMockInitialValues({'adaptiveWeights': 'k:7,m:2'});
    final p = await SharedPreferences.getInstance();
    final hear = CharStatsStore(CharStatsStore.hear);
    await hear.load(p);
    expect(hear.weightFor('k'), 7);
    expect(p.getString('adaptiveWeights'), isNull);
  });

  test('tracks are independent, reset affects one track', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final hear = CharStatsStore(CharStatsStore.hear);
    final echo = CharStatsStore(CharStatsStore.echo);
    hear.record('k', false);
    await hear.save(p);
    echo.record('m', false);
    await echo.save(p);
    final h2 = CharStatsStore(CharStatsStore.hear);
    await h2.load(p);
    expect(h2.stats.keys, ['k']);
    await echo.reset(p);
    await h2.load(p);
    expect(h2.stats.keys, ['k']);
    final e2 = CharStatsStore(CharStatsStore.echo);
    await e2.load(p);
    expect(e2.stats, isEmpty);
  });

  group('recordWord (firmware weighting)', () {
    test('wrong char +4, neighbours +2, later chars untouched', () {
      final st = CharStatsStore(CharStatsStore.echo);
      st.recordWord('ABCDE', 'ABXDE');
      expect(st.weightFor('C'), 5);
      expect(st.weightFor('B'), 3);
      expect(st.weightFor('D'), 3);
      expect(st.weightFor('E'), 1);
      expect(st.stats['A']!.attempts, 1);
      expect(st.stats['A']!.errors, 0);
      expect(st.stats['C']!.errors, 1);
      expect(st.stats['D']!.attempts, 0);
      expect(st.stats['E'], isNull);
    });
    test('short answer fails at first missing char', () {
      final st = CharStatsStore(CharStatsStore.echo);
      st.recordWord('ABC', 'AB');
      expect(st.weightFor('C'), 5);
      expect(st.stats['C']!.errors, 1);
    });
    test('correct word lowers each char by 1, floor 1', () {
      final st = CharStatsStore(CharStatsStore.echo);
      st.recordWord('AB', 'AX');
      st.recordWord('AB', 'ab');
      expect(st.weightFor('B'), 4);
      expect(st.weightFor('A'), 2);
      expect(st.stats['A']!.attempts, 2);
    });
  });

  test('history keeps the last 30 results, overall rate and timestamp', () {
    final store = CharStatsStore(CharStatsStore.hear);
    for (var i = 0; i < 40; i++) { store.record('s', i % 10 != 0); }
    final s = store.stats['s']!;
    expect(s.history.length, CharStat.historyLen);
    expect(s.history.endsWith('1'), isTrue);
    expect(s.attempts, 40);
    expect(s.errors, 4);
    expect(s.overallRate, closeTo(0.9, 1e-9));
    expect(s.lastTs, greaterThan(0));
    expect(CharStat().overallRate, isNull);
  });

  test('history and timestamp survive save/load; old data without them loads', () {
    final s = CharStat()..history = '1101'..lastTs = 123;
    final back = CharStat.fromJson(s.toJson());
    expect(back.history, '1101');
    expect(back.lastTs, 123);
    final old = CharStat.fromJson({'a': 5, 'e': 1});
    expect(old.history, '');
    expect(old.lastTs, 0);
  });

  test('correctsToReach counts right answers until the moving rate is back', () {
    final store = CharStatsStore(CharStatsStore.hear);
    store.record('i', false); // ema 0.2 -> hit rate 80 %
    final s = store.stats['i']!;
    final n = s.correctsToReach(0.90)!;
    expect(n, 4); // 0.2 * 0.8^4 = 0.082 <= 0.10, 0.8^3 -> 0.102 > 0.10
    for (var i = 0; i < n; i++) { store.record('i', true); }
    expect(1 - s.emaErrorRate, greaterThanOrEqualTo(0.90));
    expect(CharStat().correctsToReach(0.90), 0);
    expect(store.stats['i']!.correctsToReach(1.0), isNull);
  });

  test('per-day aggregates: overall, tempo and per character; save/load', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final store = CharStatsStore(CharStatsStore.hear);
    store.now = () => DateTime(2026, 10, 1, 9);
    store.wpm = 20;
    store.record('a', true);
    store.record('a', false);
    store.wpm = 22;
    store.record('b', true);
    store.now = () => DateTime(2026, 10, 2, 9);
    store.record('b', true);
    await store.save(p);

    final back = CharStatsStore(CharStatsStore.hear);
    await back.load(p);
    expect(back.days.keys.toList()..sort(), ['2026-10-01', '2026-10-02']);
    final d = back.days['2026-10-01']!;
    expect([d.attempts, d.errors], [3, 1]);
    expect(d.chars['a'], [2, 1]);
    expect(d.wm, 22);
    expect(d.avgWpm, closeTo(62 / 3, 0.001));
    expect(d.rate, closeTo(2 / 3, 0.001));
    // The echo track keeps its own days.
    final echo = CharStatsStore(CharStatsStore.echo);
    await echo.load(p);
    expect(echo.days, isEmpty);
    await back.reset(p);
    final again = CharStatsStore(CharStatsStore.hear);
    await again.load(p);
    expect(again.days, isEmpty);
  });

  test('recordWord books the days too, without wpm when unknown', () {
    final store = CharStatsStore(CharStatsStore.echo);
    store.now = () => DateTime(2026, 10, 1);
    store.recordWord('CAT', 'CXT');
    final d = store.days['2026-10-01']!;
    expect([d.attempts, d.errors], [2, 1]); // C right, A wrong, T not counted
    expect(d.avgWpm, isNull);
  });
}
