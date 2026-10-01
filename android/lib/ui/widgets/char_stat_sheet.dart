// Detail sheet for one character of the statistics screen (tap on a row):
// overall vs. moving rate, the last results as a strip, when it was last
// practised, its draw weight, what is still missing for the unlock (Listen)
// and the mix-ups (Send). The moving rate is what the unlock rule uses, so
// both are shown side by side (user 2026-09-30, docs/STATUS.md).
import 'package:flutter/material.dart';
import '../../content/char_stats.dart';
import '../../content/progress_series.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/char_color.dart';
import 'progress_charts.dart';

// Difference in percentage points below which "current" counts as equal to
// "overall" (same band as the block trend, block_history.dart).
const _flatBand = 3.0;

Future<void> showCharStatSheet(
  BuildContext context, {
  required String ch,
  required CharStat stat,
  required bool isHear,
  required bool ready,
  required int unlockOccurrences,
  required double highThreshold,
  required int outputCase,
  required Map<String, int> pairs,
  required Map<String, DayStat> days,
  required Future<void> Function() onListen,
}) {
  final c = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CharStatSheet(
      ch: ch, stat: stat, isHear: isHear, ready: ready,
      unlockOccurrences: unlockOccurrences, highThreshold: highThreshold,
      outputCase: outputCase, pairs: pairs, days: days, onListen: onListen,
    ),
  );
}

class _CharStatSheet extends StatelessWidget {
  final String ch;
  final CharStat stat;
  final bool isHear, ready;
  final int unlockOccurrences, outputCase;
  final double highThreshold;
  final Map<String, int> pairs;
  final Map<String, DayStat> days;
  final Future<void> Function() onListen;
  const _CharStatSheet({
    required this.ch, required this.stat, required this.isHear, required this.ready,
    required this.unlockOccurrences, required this.highThreshold,
    required this.outputCase, required this.pairs, required this.days,
    required this.onListen,
  });

  static String _pct(double v) => (v * 100).toStringAsFixed(1);

  String? _lastPractised() {
    if (stat.lastTs <= 0) return null;
    final now = DateTime.now();
    final then = DateTime.fromMillisecondsSinceEpoch(stat.lastTs);
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(then.year, then.month, then.day)).inDays;
    if (days <= 0) return Strings.t('cs_today');
    if (days == 1) return Strings.t('cs_yesterday');
    return Strings.t('cs_days_ago').replaceFirst('{n}', '$days');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final display = outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();
    final chColor = charTypeColor(ch, c);
    final current = 1 - stat.emaErrorRate;
    final overall = stat.overallRate;
    final mono = TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary);
    final faint = TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textFaint);

    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 4),
            child,
          ]),
        );

    // Trend: current vs. overall, only once there is something to compare.
    String? trend;
    var trendArrow = '';
    Color trendColor = c.textMuted;
    if (overall != null && stat.attempts >= 5) {
      final diff = (current - overall) * 100;
      if (diff >= _flatBand) {
        trend = Strings.t('cs_trend_up'); trendArrow = '▲'; trendColor = c.accent;
      } else if (diff <= -_flatBand) {
        trend = Strings.t('cs_trend_down'); trendArrow = '▼'; trendColor = c.warning;
      } else {
        trend = Strings.t('cs_trend_same'); trendArrow = '►';
      }
    }

    final unlockLines = <String>[];
    if (!ready) {
      if (stat.attempts < unlockOccurrences) {
        unlockLines.add(Strings.t('cs_unlock_attempts')
            .replaceFirst('{k}', '${unlockOccurrences - stat.attempts}'));
      }
      if (current < highThreshold) {
        final n = stat.correctsToReach(highThreshold);
        if (n != null) {
          unlockLines.add(Strings.t('cs_unlock_rate')
              .replaceFirst('{c}', '$n')
              .replaceFirst('{t}', '${(highThreshold * 100).round()}'));
        }
      }
    }

    final mix = pairs.entries
        .where((e) => e.key.startsWith('${ch.toUpperCase()}>'))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final last = _lastPractised();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(display,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                      fontWeight: FontWeight.bold, color: chColor)),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onListen,
              icon: const Icon(Icons.volume_up, size: 18),
              label: Text(Strings.t('cs_listen')),
            ),
          ]),
          const SizedBox(height: 16),
          section(Strings.t('cs_overall'),
              Text(
                  overall == null
                      ? '–'
                      : Strings.t('cs_overall_value')
                          .replaceFirst('{p}', _pct(overall))
                          .replaceFirst('{e}', '${stat.errors}')
                          .replaceFirst('{n}', '${stat.attempts}'),
                  style: mono)),
          section(Strings.t('cs_current'),
              Text.rich(TextSpan(style: mono, children: [
                TextSpan(text: '${_pct(current)} %',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        color: current >= highThreshold ? c.accent : c.textPrimary)),
                if (trend != null)
                  TextSpan(text: '   $trendArrow $trend',
                      style: TextStyle(color: trendColor)),
              ]))),
          section(
              Strings.t('cs_strip').replaceFirst('{n}', '${stat.history.length}'),
              stat.history.isEmpty
                  ? Text(Strings.t('cs_strip_empty'), style: faint)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 3, runSpacing: 3, children: [
                        for (final r in stat.history.split(''))
                          Container(
                            width: 9, height: 16,
                            decoration: BoxDecoration(
                              color: r == '1' ? c.accent : c.danger,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text(Strings.t('cs_strip_legend'), style: faint),
                    ])),
          section(Strings.t('pr_curve_title'),
              _CharCurve(ch: ch, days: days, highThreshold: highThreshold)),
          if (last != null) section(Strings.t('cs_last'), Text(last, style: mono)),
          section(Strings.t('cs_weight'),
              Text(Strings.t('cs_weight_value').replaceFirst('{w}', '${stat.weight}'),
                  style: mono)),
          section(
                Strings.t('cs_unlock'),
                ready
                    ? Text(Strings.t('cs_unlock_ready'),
                        style: mono.copyWith(color: c.accent))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final l in unlockLines) Text(l, style: mono)])),
          section(
              Strings.t('cs_mixups'),
              isHear
                  ? Text(Strings.t('cs_mixups_hear'), style: faint)
                  : mix.isEmpty
                      ? Text(Strings.t('cs_mixups_none'), style: faint)
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final e in mix.take(5))
                            Text(
                                '$display → ${(outputCase == 1 ? e.key.split('>')[1] : e.key.split('>')[1].toLowerCase())}   ${e.value}×',
                                style: mono.copyWith(color: c.warning)),
                        ])),
        ]),
      ),
    );
  }
}

// Weekly hit rate / attempts of one character over the last 12 weeks, from the
// per-day aggregates (same buckets as the progress view).
class _CharCurve extends StatefulWidget {
  final String ch;
  final Map<String, DayStat> days;
  final double highThreshold;
  const _CharCurve({required this.ch, required this.days, required this.highThreshold});

  @override
  State<_CharCurve> createState() => _CharCurveState();
}

class _CharCurveState extends State<_CharCurve> {
  bool _hits = true;

  static TextStyle _label(AppColors c, bool on) =>
      TextStyle(fontFamily: 'CwMono', fontSize: 13, color: on ? c.accent : c.textMuted);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final faint = TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textFaint);
    final s = buildSeries(widget.days, ProgressRange.weeks12, DateTime.now());
    final attempts = [for (final b in s.buckets) b.charAttempts(widget.ch)];
    if (attempts.every((a) => a == 0)) {
      return Text(Strings.t('pr_curve_empty'), style: faint);
    }
    final first = bucketLabel(s.buckets.first.start, s.granularity);
    final last = bucketLabel(s.buckets.last.start, s.granularity);
    final rates = [
      for (final b in s.buckets) b.charRate(widget.ch) == null ? null : b.charRate(widget.ch)! * 100
    ];
    final present = rates.whereType<double>();
    final lo = ((present.reduce((a, b) => a < b ? a : b) / 10).floor() * 10).clamp(0, 90).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      chipsThemed(
        context,
        Wrap(spacing: 8, children: [
          ChoiceChip(
              label: Text(Strings.t('pr_curve_hits')),
              selected: _hits,
              labelStyle: _label(c, _hits),
              onSelected: (_) => setState(() => _hits = true)),
          ChoiceChip(
              label: Text(Strings.t('pr_curve_attempts')),
              selected: !_hits,
              labelStyle: _label(c, !_hits),
              onSelected: (_) => setState(() => _hits = false)),
        ]),
      ),
      const SizedBox(height: 8),
      if (_hits)
        ProgressLineChart(
          values: rates,
          yMin: lo,
          yMax: 100,
          yLabel: (v) => '${v.round()} %',
          firstLabel: first,
          lastLabel: last,
          color: c.accent,
          threshold: widget.highThreshold * 100,
        )
      else
        ProgressBars(
          values: [for (final a in attempts) a.toDouble()],
          max: attempts.reduce((a, b) => a > b ? a : b).toDouble(),
          color: c.info,
          firstLabel: first,
          lastLabel: last,
        ),
      const SizedBox(height: 4),
      Text(
          _hits
              ? Strings.t('pr_curve_note').replaceFirst('{t}', '${(widget.highThreshold * 100).round()}')
              : Strings.t('pr_curve_note_attempts'),
          style: faint),
    ]);
  }
}
