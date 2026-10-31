// Long-term timing statistic (#167): one small record per Geben block keyed on
// a straight key with an adapter. Touch input is never recorded (its jitter is
// not comparable), so adapter records are the only ones here.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../keyer/fist_analyzer.dart';

/// What the progress chart can show: the index or one median ratio.
enum TimingMeasure { rhythm, dah, elementGap, letterGap, wordGap }

extension TimingMeasureInfo on TimingMeasure {
  /// Ideal of the ratio measures (dit units); null for the index.
  double? get ideal => switch (this) {
        TimingMeasure.rhythm => null,
        TimingMeasure.dah => 3,
        TimingMeasure.elementGap => 1,
        TimingMeasure.letterGap => 3,
        TimingMeasure.wordGap => 7,
      };

  FistElement? get element => switch (this) {
        TimingMeasure.rhythm => null,
        TimingMeasure.dah => FistElement.dah,
        TimingMeasure.elementGap => FistElement.elementGap,
        TimingMeasure.letterGap => FistElement.letterGap,
        TimingMeasure.wordGap => FistElement.wordGap,
      };
}

class TimingRecord {
  const TimingRecord({
    required this.at,
    required this.wpm,
    required this.index,
    required this.elements,
    required this.ratios,
  });

  final DateTime at;

  /// Speed the player keyed at (from their own dit).
  final double wpm;
  final int index;
  final int elements;

  /// Median length per kind in dit units (kinds without data are missing).
  final Map<FistElement, double> ratios;

  /// The value of [m] for the chart; null if this block had none.
  double? valueOf(TimingMeasure m) =>
      m == TimingMeasure.rhythm ? index.toDouble() : ratios[m.element];

  Map<String, Object> toJson() => {
        't': at.millisecondsSinceEpoch,
        'w': double.parse(wpm.toStringAsFixed(1)),
        'i': index,
        'n': elements,
        for (final e in ratios.entries)
          e.key.name: double.parse(e.value.toStringAsFixed(2)),
      };

  static TimingRecord? fromJson(Object? o) {
    if (o is! Map) return null;
    final t = o['t'], w = o['w'], i = o['i'], n = o['n'];
    if (t is! int || w is! num || i is! int || n is! int) return null;
    final ratios = <FistElement, double>{};
    for (final k in const [
      FistElement.dah,
      FistElement.elementGap,
      FistElement.letterGap,
      FistElement.wordGap,
    ]) {
      final v = o[k.name];
      if (v is num) ratios[k] = v.toDouble();
    }
    return TimingRecord(
        at: DateTime.fromMillisecondsSinceEpoch(t),
        wpm: w.toDouble(),
        index: i,
        elements: n,
        ratios: ratios);
  }

  /// Null while the report has no index (too few elements).
  static TimingRecord? fromReport(FistReport r, DateTime at) {
    final index = r.index;
    if (index == null) return null;
    return TimingRecord(
      at: at,
      wpm: r.wpm,
      index: index,
      elements: r.elements,
      ratios: {
        for (final e in r.stats.entries)
          if (e.key != FistElement.dit) e.key: e.value.ratio,
      },
    );
  }
}

class TimingHistory {
  const TimingHistory();

  static const _key = 'timingHistory';
  static const keep = 300;

  List<TimingRecord> load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final o in jsonDecode(raw) as List)
          ?TimingRecord.fromJson(o),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Appends the block's record (if the report has an index).
  Future<void> record(SharedPreferences p, FistReport r, DateTime at) async {
    final rec = TimingRecord.fromReport(r, at);
    if (rec == null) return;
    final all = [...load(p), rec];
    final kept = all.length > keep ? all.sublist(all.length - keep) : all;
    await p.setString(_key, jsonEncode([for (final x in kept) x.toJson()]));
  }
}
