// Small self-drawn charts for the progress view (no chart package, see
// docs/DECISIONS.md "Progress view over time"): a line with gaps and a bar row.
import 'package:flutter/material.dart';
import '../../content/progress_series.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';

/// "21.9." / "9/21" (German / English) for day and week starts, "9/25" for months.
String bucketLabel(DateTime d, Granularity g) {
  final de = Strings.lang.value == 0;
  if (g == Granularity.month) return '${d.month}/${(d.year % 100).toString().padLeft(2, '0')}';
  return de ? '${d.day}.${d.month}.' : '${d.month}/${d.day}';
}

/// "Woche ab 5.10." / "Week of 10/5" for week buckets, plain label otherwise.
String bucketTitle(DateTime d, Granularity g) => g == Granularity.week
    ? Strings.t('pr_week_of').replaceFirst('{d}', bucketLabel(d, g))
    : bucketLabel(d, g);

/// Tap detail line shared by the charts: "Woche ab 5.10.: 17 Versuche · 88.2 % Treffer".
String bucketDetail(DateTime d, Granularity g, int attempts, double? rate) {
  final title = bucketTitle(d, g);
  if (attempts == 0 || rate == null) {
    return Strings.t('pr_point_none').replaceFirst('{d}', title);
  }
  return Strings.t('pr_point_detail')
      .replaceFirst('{d}', title)
      .replaceFirst('{n}', '$attempts')
      .replaceFirst('{p}', (rate * 100).toStringAsFixed(1));
}

String unitName(Granularity g) =>
    Strings.t(const {
      Granularity.day: 'pr_unit_day',
      Granularity.week: 'pr_unit_week',
      Granularity.month: 'pr_unit_month',
    }[g]!);

/// Heatmap / rate colour: red (≤ 60 %) → amber → accent (≥ 90 %).
Color rateColor(AppColors c, double rate) {
  final t = ((rate - 0.6) / 0.3).clamp(0.0, 1.0);
  return t < 0.5
      ? Color.lerp(c.danger, c.warning, t * 2)!
      : Color.lerp(c.warning, c.accent, (t - 0.5) * 2)!;
}

class ProgressLineChart extends StatefulWidget {
  final List<double?> values; // null = no data in that bucket (gap)
  final double yMin, yMax;
  final String Function(double) yLabel;
  final String firstLabel, lastLabel;
  final Color color;
  final double? threshold; // dashed line, same unit as the values
  final double height;
  /// Text for the tapped point (index into [values]); null = chart is not tappable.
  final String Function(int index)? detail;
  const ProgressLineChart({
    super.key,
    required this.values,
    required this.yMin,
    required this.yMax,
    required this.yLabel,
    required this.firstLabel,
    required this.lastLabel,
    required this.color,
    this.threshold,
    this.height = 110,
    this.detail,
  });

  @override
  State<ProgressLineChart> createState() => _ProgressLineChartState();
}

class _ProgressLineChartState extends State<ProgressLineChart> {
  int? _sel;

  void _pick(double dx, double width) {
    final n = widget.values.length;
    final plotW = width - _LinePainter._left - _LinePainter._right;
    final i = n == 1 ? 0 : ((dx - _LinePainter._left) / (plotW / (n - 1))).round().clamp(0, n - 1);
    setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final w = widget;
    final sel = _sel != null && _sel! < w.values.length ? _sel : null;
    final chart = SizedBox(
      height: w.height,
      width: double.infinity,
      child: CustomPaint(painter: _LinePainter(w, c, sel)),
    );
    if (w.detail == null) return chart;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
          child: chart,
        ),
      ),
      const SizedBox(height: 4),
      _detailText(c, sel == null ? Strings.t('pr_tap_point') : w.detail!(sel), sel != null),
    ]);
  }
}

Widget _detailText(AppColors c, String text, bool active) => Text(text,
    style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: active ? c.textPrimary : c.textFaint));

class _LinePainter extends CustomPainter {
  final ProgressLineChart w;
  final AppColors c;
  final int? sel;
  _LinePainter(this.w, this.c, this.sel);

  static const _left = 38.0, _bottom = 16.0, _top = 6.0, _right = 8.0;

  void _text(Canvas canvas, String s, Offset at, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.textFaint)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? at.dx - tp.width : center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);
    double y(double v) =>
        plot.bottom - ((v - w.yMin) / (w.yMax - w.yMin)).clamp(0.0, 1.0) * plot.height;
    final grid = Paint()..color = c.border..strokeWidth = 0.5;
    for (var i = 0; i <= 2; i++) {
      final v = w.yMin + (w.yMax - w.yMin) * i / 2;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, w.yLabel(v), Offset(plot.left - 4, y(v)), alignRight: true);
    }
    final n = w.values.length;
    double x(int i) => n == 1 ? plot.center.dx : plot.left + i * plot.width / (n - 1);

    final t = w.threshold;
    if (t != null && t > w.yMin && t < w.yMax) {
      final p = Paint()..color = c.textMuted..strokeWidth = 1;
      for (var dx = plot.left; dx < plot.right; dx += 8) {
        canvas.drawLine(Offset(dx, y(t)), Offset((dx + 4).clamp(0, plot.right), y(t)), p);
      }
    }

    final line = Paint()
      ..color = w.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    int? lastIdx;
    for (var i = 0; i < n; i++) {
      final v = w.values[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      final pt = Offset(x(i), y(v));
      if (path == null) {
        path = Path()..moveTo(pt.dx, pt.dy);
        canvas.drawCircle(pt, 2, Paint()..color = w.color); // lone points stay visible
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
      lastIdx = i;
    }
    if (path != null) canvas.drawPath(path, line);
    if (lastIdx != null) {
      canvas.drawCircle(Offset(x(lastIdx), y(w.values[lastIdx]!)), 4, Paint()..color = w.color);
    }
    final si = sel;
    if (si != null) {
      final mark = Paint()..color = c.textMuted..strokeWidth = 1;
      canvas.drawLine(Offset(x(si), plot.top), Offset(x(si), plot.bottom), mark);
      final v = w.values[si];
      if (v != null) {
        canvas.drawCircle(Offset(x(si), y(v)), 6,
            Paint()..color = c.textPrimary..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
    }
    _text(canvas, w.firstLabel, Offset(plot.left, size.height - 6));
    _text(canvas, w.lastLabel, Offset(plot.right, size.height - 6), alignRight: true);
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

/// One bar per bucket, height = value / max.
class ProgressBars extends StatefulWidget {
  final List<double> values;
  final double max;
  final Color color;
  final String firstLabel, lastLabel;
  final double height;
  /// Text for the tapped bar (index into [values]); null = bars are not tappable.
  final String Function(int index)? detail;
  const ProgressBars({
    super.key,
    required this.values,
    required this.max,
    required this.color,
    required this.firstLabel,
    required this.lastLabel,
    this.height = 56,
    this.detail,
  });

  @override
  State<ProgressBars> createState() => _ProgressBarsState();
}

class _ProgressBarsState extends State<ProgressBars> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final w = widget;
    final faint = TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.textFaint);
    final sel = _sel != null && _sel! < w.values.length ? _sel : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: w.height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < w.values.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: w.detail == null ? null : () => setState(() => _sel = i),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: w.values[i] <= 0 ? 2 : (w.values[i] / w.max).clamp(0.04, 1.0) * w.height,
                      decoration: BoxDecoration(
                        color: w.values[i] <= 0 ? c.border : w.color,
                        borderRadius: BorderRadius.circular(2),
                        border: i == sel ? Border.all(color: c.textPrimary, width: 1.5) : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(w.firstLabel, style: faint), Text(w.lastLabel, style: faint)]),
      if (w.detail != null) ...[
        const SizedBox(height: 4),
        _detailText(c, sel == null ? Strings.t('pr_tap_bar') : w.detail!(sel), sel != null),
      ],
    ]);
  }
}

/// Chips in the app's colours (the default Material scheme would paint them blue).
Widget chipsThemed(BuildContext context, Widget child) {
  final c = AppColors.of(context);
  return Theme(
    data: Theme.of(context).copyWith(
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceAlt,
        selectedColor: c.accent.withValues(alpha: 0.18),
        side: BorderSide(color: c.borderAlt),
        labelStyle: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted),
        secondaryLabelStyle: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.accent),
        checkmarkColor: c.accent,
      ),
    ),
    child: child,
  );
}
