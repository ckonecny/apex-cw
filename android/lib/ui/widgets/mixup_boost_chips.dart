// Tappable mix-up pairs of the practice suggestion (issue #102), shared by
// Listen and Send: a title, one chip per pair, tap = leave the pair out (struck
// through) or take it in again. Same look as the weak-character chips.
import 'package:flutter/material.dart';
import '../../content/mixup_trend.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'mixup_trend_view.dart';

class MixupBoostChips extends StatelessWidget {
  final List<MixupTrend> pairs;
  final Set<String> excluded; // pairs ("K>R") the user left out
  final int outputCase;
  final void Function(String pair) onToggle;
  final double scale;
  const MixupBoostChips(
      {super.key,
      required this.pairs,
      required this.excluded,
      required this.outputCase,
      required this.onToggle,
      this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(Strings.t('mx_boost_title'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11 * scale, color: c.textMuted)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final t in pairs)
          InkWell(
            onTap: () => onToggle(t.pair),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: excluded.contains(t.pair) ? c.surfaceAlt : c.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: excluded.contains(t.pair) ? c.border : c.warning.withValues(alpha: 0.5)),
              ),
              child: Text(
                  '${mixupLabel(t.pair, outputCase)}  '
                  '${mixupArrow(t.direction, c).arrow ?? ''} ${((t.rateRecent ?? 0) * 100).round()}%',
                  style: TextStyle(
                      fontFamily: 'CwMono',
                      fontSize: 13 * scale,
                      color: excluded.contains(t.pair) ? c.textMuted : c.warning,
                      decoration: excluded.contains(t.pair) ? TextDecoration.lineThrough : null)),
            ),
          ),
      ]),
    ]);
  }
}
