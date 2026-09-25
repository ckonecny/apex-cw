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
}
