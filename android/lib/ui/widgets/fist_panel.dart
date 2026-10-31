import 'package:flutter/material.dart';
import '../../keyer/fist_analyzer.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';

/// Straight-key timing panel (#164): index plus one bar per element kind,
/// left = too short, right = too long, centre = ideal.
class FistPanel extends StatelessWidget {
  const FistPanel(
      {super.key, required this.report, required this.hints, required this.onReset});

  final FistReport report;
  final List<FistHint> hints;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final index = report.index;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                index == null
                    ? Strings.t('fist_title')
                    : '${Strings.t('fist_title')}  $index / 100',
                style: TextStyle(
                    color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: Icon(Icons.restart_alt, color: c.textMuted),
              tooltip: Strings.t('fist_reset'),
              visualDensity: VisualDensity.compact,
              onPressed: onReset,
            ),
          ]),
          if (index == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 6),
              child: Text(Strings.t('fist_index_pending'),
                  style: TextStyle(color: c.textMuted, fontSize: 13)),
            )
          else ...[
            // All rows stay: one without an element in the window (e.g. no word
            // gap lately) shows an empty track, it must not jump in and out.
            FistBars(report: report),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: hints.isEmpty
                  ? Text(Strings.t('fist_h_ok'),
                      style: TextStyle(color: c.accent, fontSize: 13))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final h in hints)
                        Text(Strings.t(h.key),
                            style: TextStyle(color: c.warning, fontSize: 13)),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Text(
                  Strings.t('fist_rhythm_note')
                      .replaceAll('{wpm}', report.wpm.round().toString()),
                  style: TextStyle(color: c.textFaint, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The five bars (dit, dah, three gaps), shared by the CW Keyer panel and the
/// Geben result sheet.
class FistBars extends StatelessWidget {
  const FistBars({super.key, required this.report});

  final FistReport report;

  static const _rows = [
    (FistElement.dit, 'fist_dit'),
    (FistElement.dah, 'fist_dah'),
    (FistElement.elementGap, 'fist_gap_el'),
    (FistElement.letterGap, 'fist_gap_letter'),
    (FistElement.wordGap, 'fist_gap_word'),
  ];

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (kind, key) in _rows)
          _BarRow(label: Strings.t(key), stat: report.stats[kind]),
      ]);
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.stat});

  final String label;
  final FistStat? stat;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final st = stat;
    final pct = st == null ? 0 : ((st.ratio / st.ideal - 1) * 100).round();
    final good = st != null && st.deviation.abs() <= 0.14; // about ±10 %
    final colour = st == null ? c.textFaint : (good ? c.accent : c.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textMuted, fontSize: 13)),
        ),
        Expanded(
          flex: 5,
          child: SizedBox(
            height: 18,
            child: CustomPaint(
              painter: _BarPainter(
                // ±1 octave (half to double) spans the whole bar
                position: st?.deviation.clamp(-1.0, 1.0),
                low: st?.minDeviation.clamp(-1.0, 1.0),
                high: st?.maxDeviation.clamp(-1.0, 1.0),
                track: c.surfaceAlt,
                zone: c.accent.withValues(alpha: 0.25),
                marker: colour,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(st == null ? '–' : '${pct > 0 ? '+' : ''}$pct %',
              textAlign: TextAlign.end,
              style: TextStyle(color: colour, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(
      {required this.position,
      required this.low,
      required this.high,
      required this.track,
      required this.zone,
      required this.marker});

  /// Null: no element of this kind in the window, only the empty track.
  final double? position;

  /// Shortest / longest single element of the window (peak marks).
  final double? low, high;
  final Color track, zone, marker;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final y = size.height / 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, y - 3, size.width, 6), const Radius.circular(3)),
        Paint()..color = track);
    final z = size.width * 0.07; // ±10 % ≈ ±0.14 octave
    canvas.drawRect(Rect.fromLTWH(mid - z, y - 7, 2 * z, 14), Paint()..color = zone);
    final pos = position, lo = low, hi = high;
    if (pos == null || lo == null || hi == null) return;
    double at(double v) => mid + v * (mid - 6);
    // Spread: faint span from the shortest to the longest element, with a
    // mark at each end that stays while the window still holds the element.
    final spread = Paint()
      ..color = marker.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(at(lo), y), Offset(at(hi), y), spread);
    for (final v in [lo, hi]) {
      canvas.drawLine(Offset(at(v), y - 6), Offset(at(v), y + 6), spread..strokeWidth = 2);
    }
    final x = at(pos);
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = marker);
    canvas.drawLine(Offset(mid, y - 8), Offset(mid, y + 8),
        Paint()
          ..color = marker.withValues(alpha: 0.5)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.position != position || o.low != low || o.high != high || o.marker != marker || o.track != track;
}
