// Aggregates the per-day statistics (CharStatsStore.days) into the series the
// progress view draws (issue #16, docs/DECISIONS.md "Progress view over time").
// Pure Dart: range → buckets (day / week / month), KPIs, per-character cells.
import 'char_stats.dart';
import 'practice_log.dart' show PracticeDay;

enum ProgressRange { weeks4, weeks12, all }

enum Granularity { day, week, month }

// Percentage points below which two rates count as equal (same band as the
// block trend, block_history.dart).
const _flatBand = 3.0;

// "All" switches from weeks to months beyond this span.
const _weeksBeforeMonths = 26;

/// A heatmap cell needs at least this many attempts to get a colour.
const kHeatMinAttempts = 5;

class ProgressBucket {
  final DateTime start; // UTC date, first day of the bucket
  int attempts = 0;
  int errors = 0;
  int ws = 0; // wpm sum over all attempts, see DayStat
  int wpmAttempts = 0; // attempts that carry a wpm
  int daysPracticed = 0;
  int seconds = 0; // active practice time of the track ('hear' / 'echo'), practice log
  int totalSeconds = 0; // all trainings together
  int unsplitDays = 0; // days with time but no split per mode (from before it existed)
  final Map<String, List<int>> chars = {};

  ProgressBucket(this.start);

  double? get rate => attempts == 0 ? null : (attempts - errors) / attempts;
  double? get avgWpm => wpmAttempts == 0 ? null : ws / wpmAttempts;

  /// Hit rate of one character; null below [minAttempts] (min. 1).
  double? charRate(String ch, {int minAttempts = 1}) {
    final c = chars[ch];
    if (c == null || c[0] < minAttempts || c[0] == 0) return null;
    return (c[0] - c[1]) / c[0];
  }

  int charAttempts(String ch) => chars[ch]?[0] ?? 0;
}

class ProgressSeries {
  final Granularity granularity;
  final List<ProgressBucket> buckets; // oldest first, empty ones included
  final int daysTotal; // days from the start of the range to today
  final int daysPracticed;

  /// Active practice time of the whole range: of the track, and of all trainings.
  int get seconds => buckets.fold(0, (a, b) => a + b.seconds);
  int get totalSeconds => buckets.fold(0, (a, b) => a + b.totalSeconds);
  int get unsplitDays => buckets.fold(0, (a, b) => a + b.unsplitDays);

  const ProgressSeries(this.granularity, this.buckets, this.daysTotal, this.daysPracticed);

  bool get hasData => buckets.any((b) => b.attempts > 0);

  /// Newest bucket with practice, and the one with practice before it.
  ProgressBucket? get latest => _nth(0);
  ProgressBucket? get previous => _nth(1);

  ProgressBucket? _nth(int n) {
    for (var i = buckets.length - 1; i >= 0; i--) {
      if (buckets[i].attempts > 0 && n-- == 0) return buckets[i];
    }
    return null;
  }

  /// 1 better, -1 worse, 0 equal, null = nothing to compare.
  int? get rateTrend {
    final a = latest?.rate, b = previous?.rate;
    if (a == null || b == null) return null;
    final d = (a - b) * 100;
    return d >= _flatBand ? 1 : d <= -_flatBand ? -1 : 0;
  }

  /// Every character with attempts in any bucket.
  Set<String> get chars => {for (final b in buckets) ...b.chars.keys};
}

DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

/// Builds the series for [range] up to [now]. With [weekly] a day-based range
/// (4 weeks) is cut into 7-day blocks instead — the heatmap needs enough
/// attempts per cell.
ProgressSeries buildSeries(Map<String, DayStat> days, ProgressRange range, DateTime now,
    {bool weekly = false,
    Map<String, PracticeDay> practice = const {},
    String track = 'hear'}) {
  final today = _date(now);
  final entries = <DateTime, DayStat>{};
  days.forEach((k, v) {
    final d = DateTime.tryParse(k);
    if (d != null) entries[_date(d)] = v;
  });

  late DateTime start;
  late DateTime countFrom; // first day of the "x of y days" count
  late Granularity gran;
  switch (range) {
    case ProgressRange.weeks4:
      start = countFrom = today.subtract(const Duration(days: 27));
      gran = weekly ? Granularity.week : Granularity.day;
    case ProgressRange.weeks12:
      start = _mondayOf(today).subtract(const Duration(days: 77));
      countFrom = start;
      gran = Granularity.week;
    case ProgressRange.all:
      DateTime? first;
      for (final d in entries.keys) {
        if (first == null || d.isBefore(first)) first = d;
      }
      first ??= today;
      countFrom = first;
      final weeks = today.difference(first).inDays ~/ 7 + 1;
      if (weeks > _weeksBeforeMonths) {
        gran = Granularity.month;
        start = DateTime.utc(first.year, first.month);
      } else {
        gran = Granularity.week;
        start = _mondayOf(first);
      }
  }

  int index(DateTime d) {
    final diff = d.difference(start).inDays;
    return switch (gran) {
      Granularity.day => diff,
      Granularity.week => diff ~/ 7,
      Granularity.month => (d.year * 12 + d.month) - (start.year * 12 + start.month),
    };
  }

  final count = index(today) + 1;
  DateTime bucketStart(int i) => switch (gran) {
        Granularity.day => start.add(Duration(days: i)),
        Granularity.week => start.add(Duration(days: i * 7)),
        Granularity.month => DateTime.utc(start.year, start.month + i),
      };
  final buckets = [for (var i = 0; i < count; i++) ProgressBucket(bucketStart(i))];

  var practiced = 0;
  entries.forEach((d, s) {
    if (d.isBefore(start) || d.isAfter(today) || s.attempts == 0) return;
    final b = buckets[index(d)];
    b.attempts += s.attempts;
    b.errors += s.errors;
    b.ws += s.ws;
    if (s.ws > 0) b.wpmAttempts += s.attempts;
    b.daysPracticed++;
    practiced++;
    s.chars.forEach((ch, v) {
      final c = b.chars.putIfAbsent(ch, () => [0, 0]);
      c[0] += v[0];
      c[1] += v[1];
    });
  });
  // Time comes from the practice log (the daily goal's clock): the track's own
  // and all trainings; days roll over at 04:00 — its key is read as a plain date.
  practice.forEach((k, v) {
    final d = DateTime.tryParse(k);
    if (d == null || v.seconds == 0) return;
    final day = _date(d);
    if (day.isBefore(start) || day.isAfter(today)) return;
    final b = buckets[index(day)];
    b.totalSeconds += v.seconds;
    if (v.modes.isEmpty) {
      b.unsplitDays++;
    } else {
      b.seconds += v.modes[track] ?? 0;
    }
  });
  return ProgressSeries(gran, buckets, today.difference(countFrom).inDays + 1, practiced);
}

/// Order for the heatmap rows: [order] first (e.g. the Koch sequence), then
/// any other character, alphabetically. With [weakestFirst] by the hit rate of
/// the newest bucket that has one (characters without data last).
List<String> heatmapRows(ProgressSeries s, List<String> order, {bool weakestFirst = false}) {
  final present = s.chars;
  final rows = [
    for (final c in order)
      if (present.contains(c)) c,
    ...(present.where((c) => !order.contains(c)).toList()..sort()),
  ];
  if (!weakestFirst) return rows;
  double? last(String c) {
    for (var i = s.buckets.length - 1; i >= 0; i--) {
      final r = s.buckets[i].charRate(c, minAttempts: kHeatMinAttempts);
      if (r != null) return r;
    }
    return null;
  }

  final keyed = {for (final c in rows) c: last(c)};
  return [...rows]..sort((a, b) {
      final x = keyed[a], y = keyed[b];
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
}

/// "42 min", "3 h 25 min"; with [days] from 24 h on "2 d 3 h 25 min".
String formatDuration(int seconds, {bool days = false}) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60, rest = m % 60;
  if (days && h >= 24) return '${h ~/ 24} d ${h % 24} h $rest min';
  return '$h h $rest min';
}
