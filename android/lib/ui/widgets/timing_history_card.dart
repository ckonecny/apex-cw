// "Timing" card in the Geben progress view (#167): the index (or one median
// ratio) of every block keyed on a straight key with an adapter, over time.
import 'package:flutter/material.dart';
import '../../content/timing_history.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'progress_charts.dart';

class TimingHistoryCard extends StatefulWidget {
  const TimingHistoryCard({super.key, required this.records});

  /// Oldest first.
  final List<TimingRecord> records;

  /// Most recent blocks shown in the chart.
  static const shown = 60;

  /// Index that counts as a clean fist (dashed line).
  static const goodIndex = 90;

  /// Lower edges of the speed bands (WPM).
  static const bands = [0, 10, 15, 20, 25];

  @override
  State<TimingHistoryCard> createState() => _TimingHistoryCardState();
}

class _TimingHistoryCardState extends State<TimingHistoryCard> {
  TimingMeasure _measure = TimingMeasure.rhythm;
  int? _band; // index into bands, null = all speeds

  static int bandOf(double wpm) {
    var b = 0;
    for (var i = 0; i < TimingHistoryCard.bands.length; i++) {
      if (wpm >= TimingHistoryCard.bands[i]) b = i;
    }
    return b;
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

  String _bandLabel(int i) {
    final bands = TimingHistoryCard.bands;
    return i + 1 < bands.length
        ? Strings.t('tm_band')
            .replaceFirst('{a}', '${bands[i]}')
            .replaceFirst('{b}', '${bands[i + 1]}')
        : Strings.t('tm_band_top').replaceFirst('{a}', '${bands[i]}');
  }

  String _measureLabel(TimingMeasure m) => Strings.t(switch (m) {
        TimingMeasure.rhythm => 'tm_index',
        TimingMeasure.dah => 'tm_dah',
        TimingMeasure.elementGap => 'tm_egap',
        TimingMeasure.letterGap => 'tm_lgap',
        TimingMeasure.wordGap => 'tm_wgap',
      });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mono12 = TextStyle(fontSize: 12, color: c.textFaint);
    final present = {for (final r in widget.records) bandOf(r.wpm)}.toList()..sort();
    final band = _band != null && present.contains(_band) ? _band : null;
    var recs = [
      for (final r in widget.records)
        if (band == null || bandOf(r.wpm) == band) r,
    ];
    if (recs.length > TimingHistoryCard.shown) {
      recs = recs.sublist(recs.length - TimingHistoryCard.shown);
    }
    final m = _measure;
    final values = [for (final r in recs) r.valueOf(m)];
    final data = values.whereType<double>().toList();

    Widget chart;
    if (data.isEmpty) {
      chart = Text(Strings.t('tm_none'), style: mono12);
    } else {
      final ideal = m.ideal;
      double lo, hi;
      if (ideal == null) {
        lo = ((data.reduce((a, b) => a < b ? a : b) / 10).floor() * 10)
            .clamp(0, 80)
            .toDouble();
        hi = 100;
      } else {
        final all = [...data, ideal];
        lo = (all.reduce((a, b) => a < b ? a : b) * 2).floor() / 2 - 0.5;
        hi = (all.reduce((a, b) => a > b ? a : b) * 2).ceil() / 2 + 0.5;
        if (lo < 0) lo = 0;
      }
      chart = ProgressLineChart(
        values: values,
        yMin: lo,
        yMax: hi,
        threshold: ideal ?? TimingHistoryCard.goodIndex.toDouble(),
        yLabel: (v) => ideal == null ? '${v.round()}' : v.toStringAsFixed(1),
        firstLabel: _date(recs.first.at),
        lastLabel: _date(recs.last.at),
        color: c.accent,
        height: 110,
        detail: (i) {
          final r = recs[i];
          final v = values[i];
          return Strings.t('tm_detail')
              .replaceFirst('{d}', _date(r.at))
              .replaceFirst(
                  '{v}',
                  v == null
                      ? '–'
                      : ideal == null
                          ? '${v.round()} / 100'
                          : '${v.toStringAsFixed(1)} (${Strings.t('tm_ideal')} ${ideal.round()})')
              .replaceFirst('{w}', r.wpm.toStringAsFixed(0))
              .replaceFirst('{n}', '${r.elements}');
        },
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderAlt),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Strings.t('tm_title'), style: TextStyle(fontSize: 12, color: c.textMuted)),
        const SizedBox(height: 8),
        chipsThemed(
          context,
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final x in TimingMeasure.values)
              ChoiceChip(
                label: Text(_measureLabel(x)),
                selected: _measure == x,
                labelStyle: TextStyle(
                    fontSize: 13, color: _measure == x ? c.accent : c.textMuted),
                onSelected: (_) => setState(() => _measure = x),
              ),
          ]),
        ),
        if (present.length > 1) ...[
          const SizedBox(height: 4),
          chipsThemed(
            context,
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(
                label: Text(Strings.t('tm_all_speeds')),
                selected: band == null,
                labelStyle: TextStyle(
                    fontSize: 13, color: band == null ? c.accent : c.textMuted),
                onSelected: (_) => setState(() => _band = null),
              ),
              for (final b in present)
                ChoiceChip(
                  label: Text(_bandLabel(b)),
                  selected: band == b,
                  labelStyle: TextStyle(
                      fontSize: 13, color: band == b ? c.accent : c.textMuted),
                  onSelected: (_) => setState(() => _band = b),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        chart,
        const SizedBox(height: 6),
        Text(Strings.t('tm_note'), style: mono12),
      ]),
    );
  }
}
