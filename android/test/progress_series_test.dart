import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/char_stats.dart';
import 'package:next_cw_trainer/content/progress_series.dart';

DayStat day(int a, int e, {int wpm = 20, Map<String, List<int>>? chars}) {
  final d = DayStat()
    ..attempts = a
    ..errors = e
    ..ws = a * wpm
    ..wm = wpm;
  if (chars != null) d.chars.addAll(chars);
  return d;
}

void main() {
  final now = DateTime(2026, 10, 1); // a Thursday

  test('4 weeks: 28 day buckets, practice days counted', () {
    final s = buildSeries({
      '2026-10-01': day(10, 1),
      '2026-09-30': day(10, 3),
      '2026-08-01': day(10, 0), // outside
    }, ProgressRange.weeks4, now);
    expect(s.granularity, Granularity.day);
    expect(s.buckets.length, 28);
    expect(s.daysTotal, 28);
    expect(s.daysPracticed, 2);
    expect(s.latest!.rate, closeTo(0.9, 1e-9));
    expect(s.previous!.rate, closeTo(0.7, 1e-9));
    expect(s.rateTrend, 1);
  });

  test('12 weeks: weekly, rate and wpm weighted by attempts', () {
    final s = buildSeries({
      '2026-09-28': day(10, 0, wpm: 20), // Monday of this week
      '2026-10-01': day(30, 6, wpm: 24),
    }, ProgressRange.weeks12, now);
    expect(s.granularity, Granularity.week);
    expect(s.buckets.length, 12);
    expect(s.buckets.last.start, DateTime.utc(2026, 9, 28));
    expect(s.latest!.rate, closeTo(34 / 40, 1e-9));
    expect(s.latest!.avgWpm, closeTo((200 + 720) / 40, 1e-9));
    expect(s.latest!.daysPracticed, 2);
    expect(s.daysTotal, 11 * 7 + 4); // from the Monday 11 weeks back to Thursday
  });

  test('All: weeks first, months beyond 26 weeks, days counted from the first', () {
    final w = buildSeries({'2026-09-01': day(5, 1)}, ProgressRange.all, now);
    expect(w.granularity, Granularity.week);
    expect(w.daysTotal, 31);
    final m = buildSeries({'2025-12-15': day(5, 1), '2026-10-01': day(5, 0)},
        ProgressRange.all, now);
    expect(m.granularity, Granularity.month);
    expect(m.buckets.length, 11); // Dec 2025 .. Oct 2026
    expect(m.buckets.first.start, DateTime.utc(2025, 12));
    expect(m.daysPracticed, 2);
    expect(buildSeries({}, ProgressRange.all, now).hasData, isFalse);
  });

  test('wpm average ignores attempts without wpm; trend band is 3 points', () {
    final s = buildSeries({
      '2026-10-01': day(10, 1, wpm: 0),
      '2026-09-30': day(10, 1, wpm: 0),
    }, ProgressRange.weeks4, now);
    expect(s.latest!.avgWpm, isNull);
    expect(s.rateTrend, 0);
  });

  test('heatmap: cells need enough attempts; rows ordered, weakest first', () {
    final s = buildSeries({
      '2026-10-01': day(20, 5, chars: {
        'k': [10, 1], 'm': [10, 4], 'x': [3, 0],
      }),
    }, ProgressRange.weeks4, now, weekly: true);
    expect(s.granularity, Granularity.week);
    expect(s.buckets.length, 4);
    final b = s.latest!;
    expect(b.charRate('k', minAttempts: kHeatMinAttempts), closeTo(0.9, 1e-9));
    expect(b.charRate('x', minAttempts: kHeatMinAttempts), isNull);
    expect(b.charRate('x'), 1.0);
    expect(heatmapRows(s, ['m', 'k']), ['m', 'k', 'x']);
    expect(heatmapRows(s, ['m', 'k'], weakestFirst: true), ['m', 'k', 'x']);
    expect(heatmapRows(s, ['k', 'm'], weakestFirst: true), ['m', 'k', 'x']);
  });
}
