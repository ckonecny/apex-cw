// Mix-up trends (issue #101): the overview tab of the character statistics
// (per track, grouped by direction) and the pieces the character detail view
// reuses (arrow per pair, weekly curve of one pair). The numbers come from
// content/mixup_trend.dart; this file only draws them.
import 'package:flutter/material.dart';
import '../../content/char_stats.dart';
import '../../content/mixup_trend.dart';
import '../../content/progress_series.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'progress_charts.dart';

/// Arrow and colour of a direction; null arrow = no statement.
({String? arrow, Color color}) mixupArrow(MixupDirection d, AppColors c) => switch (d) {
      MixupDirection.up => (arrow: '▲', color: c.warning),
      MixupDirection.fresh => (arrow: '▲', color: c.warning),
      MixupDirection.down => (arrow: '▼', color: c.accent),
      MixupDirection.gone => (arrow: '✓', color: c.accent),
      MixupDirection.same => (arrow: '►', color: c.textMuted),
      MixupDirection.tooFew => (arrow: null, color: c.textFaint),
    };

String _pct(double r) => (r * 100).round().toString();

/// "12 %" plus "before 6 %" for one trend: the headline and the detail line.
({String head, String? detail}) mixupRateText(MixupTrend t) {
  switch (t.direction) {
    case MixupDirection.gone:
      return (
        head: Strings.t('mx_gone_label'),
        detail: Strings.t('mx_gone_detail').replaceFirst('{a}', '${t.countPrior}')
      );
    case MixupDirection.fresh:
      return (
        head: '${_pct(t.rateRecent ?? 0)} %',
        detail: Strings.t('mx_before_none')
      );
    case MixupDirection.tooFew:
      return (head: '${t.countRecent + t.countPrior}×', detail: null);
    default:
      return (
        head: '${_pct(t.rateRecent ?? 0)} %',
        detail: Strings.t('mx_before').replaceFirst('{p}', _pct(t.ratePrior ?? 0))
      );
  }
}

String _show(String ch, int outputCase) =>
    outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();

/// "K → R" in the app's output case ('–' stays).
String mixupLabel(String pair, int outputCase) =>
    '${_show(pair.split('>').first, outputCase)} → ${_show(pair.split('>').last, outputCase)}';

/// Weekly mix-up rates of [pair] over the last 12 weeks (null = too few
/// attempts at the played character that week).
List<double?> pairWeekly(ProgressSeries s, String pair, {int minAttempts = 5}) =>
    [for (final b in s.buckets) b.pairRate(pair, minAttempts: minAttempts)];

class MixupTrendView extends StatefulWidget {
  final Map<String, DayStat> days;
  final int outputCase;
  final void Function(String ch) onChar;
  const MixupTrendView(
      {super.key, required this.days, required this.outputCase, required this.onChar});

  @override
  State<MixupTrendView> createState() => _MixupTrendViewState();
}

class _MixupTrendViewState extends State<MixupTrendView> {
  int _window = 14;
  bool? _showFew; // null = default (open when nothing else is shown)

  String _date(DateTime d) =>
      Strings.lang.value == 0 ? '${d.day}.${d.month}.' : '${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final faint = TextStyle(fontSize: 12, color: c.textFaint);
    final now = DateTime.now();
    final start = mixupTrendStart(widget.days, now, windowDays: _window);
    final trends = mixupTrends(widget.days, now, windowDays: _window);
    final series = buildSeries(widget.days, ProgressRange.weeks12, now);
    final few = trends.where((t) => t.direction == MixupDirection.tooFew).toList();
    final compared = trends.where((t) => t.direction != MixupDirection.tooFew).toList();
    final showFew = _showFew ?? compared.isEmpty;

    Widget group(String key, MixupDirection d, Color color) {
      final rows = compared.where((t) => t.direction == d).toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
              '${mixupArrow(d, c).arrow ?? ''} ${Strings.t(key).toUpperCase()}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ),
        _card(c, [for (final t in rows) _row(c, t, series)]),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(Strings.t('mx_title').toUpperCase(),
          style: TextStyle(fontSize: 12, color: c.textMuted)),
      const SizedBox(height: 6),
      chipsThemed(
        context,
        Wrap(spacing: 8, children: [
          for (final w in const [14, 30])
            ChoiceChip(
                label: Text(Strings.t('mx_win').replaceFirst('{n}', '$w')),
                selected: _window == w,
                labelStyle: TextStyle(
                    fontSize: 13, color: _window == w ? c.accent : c.textMuted),
                onSelected: (_) => setState(() => _window = w)),
        ]),
      ),
      if (start == null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(Strings.t('mx_none'), style: faint),
        )
      else ...[
        if (compared.isEmpty && now.isBefore(start.from))
          _emptyCard(c, start),
        group('mx_g_up', MixupDirection.up, c.warning),
        group('mx_g_fresh', MixupDirection.fresh, c.warning),
        group('mx_g_down', MixupDirection.down, c.accent),
        group('mx_g_gone', MixupDirection.gone, c.accent),
        group('mx_g_same', MixupDirection.same, c.textMuted),
        if (few.isNotEmpty) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: () => setState(() => _showFew = !showFew),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                      compared.isEmpty
                          ? Strings.t('mx_recorded')
                          : Strings.t('mx_g_few').replaceFirst('{n}', '${few.length}'),
                      style: TextStyle(fontSize: 13, color: c.textMuted)),
                ),
                Icon(showFew ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: c.textMuted),
              ]),
            ),
          ),
          if (showFew) _card(c, [for (final t in few) _row(c, t, series)]),
        ],
        const SizedBox(height: 14),
        Text(Strings.t('mx_note'), style: faint),
      ],
    ]);
  }

  Widget _card(AppColors c, List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.borderAlt),
        ),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.border),
            rows[i],
          ],
        ]),
      );

  Widget _emptyCard(AppColors c, ({DateTime from, int elapsed, int needed}) s) {
    final first = s.from.subtract(Duration(days: s.needed));
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderAlt),
      ),
      child: Column(children: [
        Icon(Icons.show_chart, size: 32, color: c.textMuted),
        const SizedBox(height: 8),
        Text(Strings.t('mx_empty_title').replaceFirst('{d}', _date(s.from)),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.textPrimary)),
        const SizedBox(height: 4),
        Text(
            Strings.t('mx_empty_progress')
                .replaceFirst('{e}', '${s.elapsed}')
                .replaceFirst('{n}', '${s.needed}'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.accent)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: s.elapsed / s.needed, minHeight: 6,
              backgroundColor: c.border, color: c.accent),
        ),
        const SizedBox(height: 10),
        Text(
            Strings.t('mx_empty_body')
                .replaceFirst('{s}', _date(first))
                .replaceFirst('{w}', '$_window'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.textMuted)),
      ]),
    );
  }

  Widget _row(AppColors c, MixupTrend t, ProgressSeries series) {
    final a = mixupArrow(t.direction, c);
    final txt = mixupRateText(t);
    final spark = pairWeekly(series, t.pair, minAttempts: 3);
    final few = t.direction == MixupDirection.tooFew;
    return InkWell(
      onTap: () => widget.onChar(t.played),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 64,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(mixupLabel(t.pair, widget.outputCase),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                      fontWeight: FontWeight.bold, color: c.textPrimary)),
            ),
          ),
          SizedBox(
            width: 20,
            child: Text(a.arrow ?? '', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: a.color)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(txt.head,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                      color: t.direction == MixupDirection.gone ? c.accent : c.textPrimary)),
              if (few)
                Text(
                    Strings.t('mx_few_detail')
                        .replaceFirst('{n}', '${t.countRecent + t.countPrior}')
                        .replaceFirst('{w}', '${_window * 2}'),
                    style: TextStyle(fontSize: 11, color: c.textFaint))
              else if (txt.detail != null)
                Text(txt.detail!, style: TextStyle(fontSize: 11, color: c.textFaint)),
            ]),
          ),
          if (!few) ...[
            const SizedBox(width: 6),
            SizedBox(
                width: 52, height: 26,
                child: CustomPaint(painter: _SparkPainter(spark, a.color))),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text('${t.countRecent}×', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: c.textMuted)),
            ),
          ],
        ]),
      ),
    );
  }
}

// Last weeks of one pair as a tiny line; weeks without a value break the line.
class _SparkPainter extends CustomPainter {
  final List<double?> values; // oldest first
  final Color color;
  _SparkPainter(List<double?> all, this.color)
      : values = all.length > 6 ? all.sublist(all.length - 6) : all;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>();
    if (present.isEmpty) return;
    final maxV = present.reduce((a, b) => a > b ? a : b);
    final hi = maxV <= 0 ? 1.0 : maxV;
    final n = values.length;
    double x(int i) => n == 1 ? size.width / 2 : 3 + (size.width - 6) * i / (n - 1);
    double y(double v) => size.height - 3 - (size.height - 6) * (v / hi);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    int? last;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(x(i), y(v));
      } else {
        path.lineTo(x(i), y(v));
      }
      last = i;
    }
    if (path != null) canvas.drawPath(path, line);
    if (last != null) {
      canvas.drawCircle(Offset(x(last), y(values[last]!)), 2.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// Weekly curve of one mix-up pair over the last 12 weeks, with chips to pick
/// the pair (character detail view).
class MixupPairCurve extends StatefulWidget {
  final Map<String, DayStat> days;
  final List<String> pairs; // "K>R", most frequent first
  final int outputCase;
  const MixupPairCurve(
      {super.key, required this.days, required this.pairs, required this.outputCase});

  @override
  State<MixupPairCurve> createState() => _MixupPairCurveState();
}

class _MixupPairCurveState extends State<MixupPairCurve> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final faint = TextStyle(fontSize: 12, color: c.textFaint);
    final s = buildSeries(widget.days, ProgressRange.weeks12, DateTime.now());
    final pair = widget.pairs[_sel.clamp(0, widget.pairs.length - 1)];
    final rates = [
      for (final r in pairWeekly(s, pair)) r == null ? null : r * 100
    ];
    final label = mixupLabel(pair, widget.outputCase);
    final ch = pair.split('>').first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Strings.t('mx_chart_title').replaceFirst('{p}', label),
          style: TextStyle(fontSize: 12, color: c.textMuted)),
      const SizedBox(height: 4),
      if (widget.pairs.length > 1)
        chipsThemed(
          context,
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (var i = 0; i < widget.pairs.length; i++)
              ChoiceChip(
                  label: Text(mixupLabel(widget.pairs[i], widget.outputCase)),
                  selected: i == _sel,
                  labelStyle: TextStyle(
                      fontSize: 13, color: i == _sel ? c.accent : c.textMuted),
                  onSelected: (_) => setState(() => _sel = i)),
          ]),
        ),
      const SizedBox(height: 8),
      if (rates.every((r) => r == null))
        Text(Strings.t('pr_curve_empty'), style: faint)
      else ...[
        ProgressLineChart(
          values: rates,
          yMin: 0,
          yMax: _top(rates),
          yLabel: (v) => '${v.round()} %',
          firstLabel: bucketLabel(s.buckets.first.start, s.granularity),
          lastLabel: bucketLabel(s.buckets.last.start, s.granularity),
          color: c.warning,
          detail: (i) {
            final b = s.buckets[i];
            final r = rates[i];
            final title = bucketTitle(b.start, s.granularity);
            if (r == null) return Strings.t('pr_point_none').replaceFirst('{d}', title);
            return Strings.t('mx_point')
                .replaceFirst('{d}', title)
                .replaceFirst('{r}', r.toStringAsFixed(1))
                .replaceFirst('{k}', '${b.pairs[pair] ?? 0}')
                .replaceFirst('{n}', '${attemptsOfChar(b.chars, ch)}');
          },
        ),
        const SizedBox(height: 4),
        Text(
            Strings.t('mx_chart_note')
                .replaceFirst('{p}', label)
                .replaceFirst('{c}', _show(ch, widget.outputCase)),
            style: faint),
      ],
    ]);
  }

  // Top of the y axis: next multiple of 5 above the highest value, at least 10.
  static double _top(List<double?> v) {
    final m = v.whereType<double>().fold(0.0, (a, b) => a > b ? a : b);
    return (((m * 1.1) / 5).ceil() * 5).clamp(10, 100).toDouble();
  }
}
