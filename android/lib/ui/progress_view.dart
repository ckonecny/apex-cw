// "Verlauf" tab of the Hören/Geben statistics (issue #16): hit rate and speed
// over time, days practised, and a heatmap of all characters. Everything is
// derived from CharStatsStore.days via buildSeries (content/progress_series.dart).
import 'package:flutter/material.dart';
import '../content/char_stats.dart';
import '../content/practice_log.dart' show PracticeDay;
import '../content/progress_series.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'widgets/progress_charts.dart';

class ProgressView extends StatefulWidget {
  final Map<String, DayStat> days;
  final List<String> order; // heatmap row order (Koch sequence)
  final int outputCase;
  final void Function(String ch) onChar;
  /// Practice log days (all trainings), for the practice time.
  final Map<String, PracticeDay> practice;
  /// 'hear' or 'echo': whose practice time is shown beside the total.
  final String track;
  const ProgressView({
    super.key,
    required this.days,
    required this.order,
    required this.outputCase,
    required this.onChar,
    this.practice = const {},
    this.track = 'hear',
  });

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  ProgressRange _range = ProgressRange.weeks12;
  bool _weakestFirst = false;

  static const _cellH = 24.0, _labelW = 30.0, _headH = 18.0;
  // Narrowest a heatmap column may get when all buckets are squeezed into the
  // card width (issue #26); below that the grid scrolls, starting at the newest.
  static const _minCellW = 28.0;
  final _headScroll = ScrollController();
  final _bodyScroll = ScrollController();
  // Scroll the heatmap to its newest week again after the first layout and
  // whenever the range changes.
  bool _jumpToNewest = true;

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(() {
      if (_headScroll.hasClients && _headScroll.offset != _bodyScroll.offset) {
        _headScroll.jumpTo(_bodyScroll.offset.clamp(0, _headScroll.position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    _headScroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  static TextStyle _chipLabel(AppColors c, bool on) =>
      TextStyle(fontFamily: 'CwMono', fontSize: 13, color: on ? c.accent : c.textMuted);

  static String _time(int seconds, ProgressRange r) =>
      seconds == 0 ? '–' : formatDuration(seconds, days: r == ProgressRange.all);

  String _display(String ch) => widget.outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();

  Widget _card(AppColors c, String title, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.borderAlt),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _kpi(AppColors c, String value, String label, {String? arrow, Color? arrowColor}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.borderAlt),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(
                style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                    fontWeight: FontWeight.bold, color: c.textPrimary),
                children: [
                  TextSpan(text: value),
                  if (arrow != null)
                    TextSpan(text: ' $arrow', style: TextStyle(color: arrowColor, fontSize: 13)),
                ])),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final now = DateTime.now();
    final s = buildSeries(widget.days, _range, now, practice: widget.practice, track: widget.track);
    final g = s.granularity;
    final unit = unitName(g);
    final mono12 = TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textFaint);

    final chips = chipsThemed(context, Wrap(spacing: 8, runSpacing: 4, children: [
      for (final r in ProgressRange.values)
        ChoiceChip(
          label: Text(Strings.t(const {
            ProgressRange.weeks4: 'pr_range_4',
            ProgressRange.weeks12: 'pr_range_12',
            ProgressRange.all: 'pr_range_all',
          }[r]!)),
          selected: _range == r,
          labelStyle: _chipLabel(c, _range == r),
          onSelected: (_) => setState(() {
            _range = r;
            _jumpToNewest = true;
          }),
        ),
    ]));

    if (!s.hasData) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        chips,
        const SizedBox(height: 16),
        Text(Strings.t('pr_empty'), style: mono12),
      ]);
    }

    final latest = s.latest!;
    final trend = s.rateTrend;
    final arrow = trend == null ? null : trend > 0 ? '▲' : trend < 0 ? '▼' : '►';
    final arrowColor = trend == null ? null : trend > 0 ? c.accent : trend < 0 ? c.warning : c.textMuted;

    final labels = [for (final b in s.buckets) bucketLabel(b.start, g)];
    final rates = [for (final b in s.buckets) b.rate == null ? null : b.rate! * 100];
    final present = rates.whereType<double>();
    final rateMin = ((present.reduce((a, b) => a < b ? a : b) / 10).floor() * 10)
        .clamp(0, 90).toDouble();

    final wpms = [for (final b in s.buckets) b.avgWpm];
    final wpmPresent = wpms.whereType<double>().toList();

    // Practice time exists from the first day of the practice log on.
    final sinceKey = widget.practice.keys.map(DateTime.tryParse).whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final since = sinceKey == null ? null : DateTime.utc(sinceKey.year, sinceKey.month, sinceKey.day);

    final spanKey = const {
      ProgressRange.weeks4: 'pr_span_4',
      ProgressRange.weeks12: 'pr_span_12',
      ProgressRange.all: 'pr_span_all',
    }[_range]!;

    return ListView(padding: const EdgeInsets.all(20), children: [
      chips,
      const SizedBox(height: 12),
      Row(children: [
        _kpi(c, '${(latest.rate! * 100).round()} %', Strings.t('pr_kpi_rate'),
            arrow: arrow, arrowColor: arrowColor),
        const SizedBox(width: 8),
        _kpi(c, latest.avgWpm == null ? '–' : latest.avgWpm!.toStringAsFixed(1),
            Strings.t('pr_kpi_wpm')),
        const SizedBox(width: 8),
        _kpi(c, '${s.daysPracticed}/${s.daysTotal}', Strings.t('pr_kpi_days')),
      ]),
      const SizedBox(height: 8),
      Text(Strings.t('pr_time_head').replaceFirst('{r}', Strings.t(spanKey)), style: mono12),
      const SizedBox(height: 4),
      Row(children: [
        _kpi(c, _time(s.seconds, _range), Strings.t(widget.track == 'echo' ? 'block_give' : 'block_hear')),
        const SizedBox(width: 8),
        _kpi(c, _time(s.totalSeconds, _range), Strings.t('pr_time_total')),
      ]),
      if (s.unsplitDays > 0) ...[
        const SizedBox(height: 4),
        Text(Strings.t('pr_time_unsplit').replaceFirst('{n}', '${s.unsplitDays}'), style: mono12),
      ],
      if (since != null && since.isAfter(s.buckets.first.start)) ...[
        const SizedBox(height: 4),
        Text(Strings.t('pr_time_since').replaceFirst('{d}', bucketLabel(since, Granularity.day)),
            style: mono12),
      ],
      const SizedBox(height: 4),
      Text(Strings.t('pr_note_${g.name}'), style: mono12),
      const SizedBox(height: 12),
      _card(
          c,
          Strings.t('pr_rate_title').replaceFirst('{u}', unit),
          ProgressLineChart(
            values: rates,
            yMin: rateMin,
            yMax: 100,
            yLabel: (v) => '${v.round()} %',
            firstLabel: labels.first,
            lastLabel: labels.last,
            color: c.accent,
            detail: (i) => bucketDetail(s.buckets[i].start, g, s.buckets[i].attempts, s.buckets[i].rate),
          )),
      if (wpmPresent.isNotEmpty)
        _card(
            c,
            Strings.t('pr_wpm_title').replaceFirst('{u}', unit),
            () {
              final lo = wpmPresent.reduce((a, b) => a < b ? a : b).floorToDouble() - 1;
              final hi = wpmPresent.reduce((a, b) => a > b ? a : b).ceilToDouble() + 1;
              return ProgressLineChart(
                values: wpms,
                yMin: lo,
                yMax: hi < lo + 2 ? lo + 2 : hi,
                yLabel: (v) => v.round().toString(),
                firstLabel: labels.first,
                lastLabel: labels.last,
                color: c.info,
                height: 90,
              );
            }()),
      _card(
          c,
          g == Granularity.day
              ? Strings.t('pr_days_title')
              : Strings.t('pr_days_per').replaceFirst('{u}', unit),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProgressBars(
              values: [for (final b in s.buckets) b.daysPracticed.toDouble()],
              max: g == Granularity.day ? 1 : g == Granularity.week ? 7 : 31,
              color: c.accent,
              firstLabel: labels.first,
              lastLabel: labels.last,
              height: g == Granularity.day ? 18 : 56,
              detail: (i) {
                final b = s.buckets[i];
                final title = bucketTitle(b.start, g);
                final time = b.totalSeconds == 0
                    ? ''
                    : ' · ${Strings.t('pr_days_time').replaceFirst('{tr}', Strings.t(widget.track == 'echo' ? 'block_give' : 'block_hear')).replaceFirst('{t}', formatDuration(b.seconds)).replaceFirst('{a}', formatDuration(b.totalSeconds))}';
                if (b.daysPracticed == 0) {
                  return Strings.t('pr_days_detail_none').replaceFirst('{d}', title) + time;
                }
                return Strings.t(g == Granularity.day ? 'pr_days_detail_day' : 'pr_days_detail')
                        .replaceFirst('{d}', title)
                        .replaceFirst('{n}', '${b.daysPracticed}') +
                    time;
              },
            ),
            const SizedBox(height: 6),
            Text(
                Strings.t('pr_days_sum')
                    .replaceFirst('{r}', Strings.t(spanKey))
                    .replaceFirst('{d}', '${s.daysPracticed}')
                    .replaceFirst('{t}', '${s.daysTotal}'),
                style: mono12),
          ])),
      _buildHeatmap(c, now),
    ]);
  }

  Widget _buildHeatmap(AppColors c, DateTime now) {
    final hs = buildSeries(widget.days, _range, now, weekly: true);
    final rows = heatmapRows(hs, widget.order, weakestFirst: _weakestFirst);
    if (rows.isEmpty) return const SizedBox.shrink();
    final mono12 = TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textFaint);
    final mono10 = TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.textFaint);
    final month = hs.granularity == Granularity.month;
    // As tall as the screen allows (all rows if they fit), then the rows scroll.
    final bodyH = (rows.length * _cellH)
        .clamp(0.0, MediaQuery.sizeOf(context).height * 0.62)
        .toDouble();

    // Squeeze all columns into the card if they stay at least _minCellW wide,
    // otherwise keep _minCellW and scroll (to the newest week, see below).
    // Few columns (4 weeks, young "All") are stretched to the full width.
    // Card padding 12 + 12 and list padding 20 + 20 surround the grid.
    final avail = MediaQuery.sizeOf(context).width - 64 - _labelW;
    final n = hs.buckets.length;
    final cellW = avail / n < _minCellW ? _minCellW : avail / n;
    if (_jumpToNewest) {
      _jumpToNewest = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_bodyScroll.hasClients) {
          _bodyScroll.jumpTo(_bodyScroll.position.maxScrollExtent);
        }
      });
    }

    Widget cell(String ch, ProgressBucket b) {
      final r = b.charRate(ch, minAttempts: kHeatMinAttempts);
      return Container(
        width: cellW - 2,
        height: _cellH - 2,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: r == null ? c.surface : rateColor(c, r),
          borderRadius: BorderRadius.circular(3),
          border: r == null ? Border.all(color: c.border) : null,
        ),
      );
    }

    return _card(
      c,
      Strings.t(month ? 'pr_heat_month' : 'pr_heat_week'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        chipsThemed(
          context,
          Wrap(spacing: 8, children: [
            FilterChip(
              label: Text(Strings.t('pr_heat_sort')),
              selected: _weakestFirst,
              labelStyle: _chipLabel(c, _weakestFirst),
              onSelected: (v) => setState(() => _weakestFirst = v),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        // Header: scrolls with the body horizontally, never vertically.
        Row(children: [
          const SizedBox(width: _labelW, height: _headH),
          Expanded(
            child: SizedBox(
              height: _headH,
              child: SingleChildScrollView(
                controller: _headScroll,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (final b in hs.buckets)
                    SizedBox(
                        width: cellW,
                        child: Center(
                            child: Text(bucketLabel(b.start, hs.granularity), style: mono10))),
                ]),
              ),
            ),
          ),
        ]),
        // Body: characters stay on the left, cells scroll sideways.
        SizedBox(
          height: bodyH,
          child: SingleChildScrollView(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                for (final ch in rows)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onChar(ch),
                    child: SizedBox(
                      width: _labelW,
                      height: _cellH,
                      child: Center(
                          child: Text(_display(ch),
                              style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
                                  fontWeight: FontWeight.bold, color: c.textPrimary))),
                    ),
                  ),
              ]),
              Expanded(
                child: SingleChildScrollView(
                  controller: _bodyScroll,
                  scrollDirection: Axis.horizontal,
                  child: Column(children: [
                    for (final ch in rows)
                      GestureDetector(
                        onTap: () => widget.onChar(ch),
                        child: Row(children: [for (final b in hs.buckets) cell(ch, b)]),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('60 %', style: mono10),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: [
                  rateColor(c, 0.6), rateColor(c, 0.75), rateColor(c, 0.9),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('90 %', style: mono10),
        ]),
        const SizedBox(height: 4),
        Text(Strings.t('pr_heat_note').replaceFirst('{n}', '$kHeatMinAttempts'), style: mono12),
      ]),
    );
  }
}
