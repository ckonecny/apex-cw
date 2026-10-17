// Weak-character chips and the "On the way to ..." card as in Listen, for the
// Send start/result view (#107). Same look: amber chips, 20/12 px radius,
// accuracy row inside the unlock card.
import 'package:flutter/material.dart';
import '../../content/adaptive_copy_engine.dart';
import '../../content/char_stats.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';

/// Tappable weak characters: tap = leave one out of the boost (struck
/// through) or take it in again. [showAccuracy] shows 100 % - error rate.
class WeakCharChips extends StatelessWidget {
  final Map<String, double> weak; // char -> error rate
  final Set<String> excluded;
  final String Function(String) display;
  final void Function(String) onToggle;
  final double scale;
  final WrapAlignment alignment;
  final bool showAccuracy;
  final bool small;
  const WeakCharChips(
      {super.key,
      required this.weak,
      required this.excluded,
      required this.display,
      required this.onToggle,
      this.scale = 1,
      this.alignment = WrapAlignment.center,
      this.showAccuracy = false,
      this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = small ? 12.0 : 20.0;
    return Wrap(
      spacing: small ? 6 : 8,
      runSpacing: small ? 6 : 8,
      alignment: alignment,
      children: weak.entries.map((e) {
        final included = !excluded.contains(e.key);
        return InkWell(
          onTap: () => onToggle(e.key),
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            padding: small
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: included ? c.warning.withValues(alpha: 0.15) : c.surfaceAlt,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: included ? c.warning.withValues(alpha: 0.5) : c.border),
            ),
            child: Text('${display(e.key)}  ${((showAccuracy ? 1 - e.value : e.value) * 100).round()}%',
                style: TextStyle(
                    fontFamily: 'CwMono',
                    fontSize: 13 * scale,
                    color: included ? c.warning : c.textMuted,
                    decoration: included ? null : TextDecoration.lineThrough)),
          ),
        );
      }).toList(),
    );
  }
}

/// The card "Weak characters: practice more?" (title + chips).
class WeakCharsCard extends StatelessWidget {
  final WeakCharChips chips;
  const WeakCharsCard({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
        width: double.infinity,
        child: AppCard(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Strings.t('ac_weak_chars'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11 * chips.scale, color: c.textMuted)),
          const SizedBox(height: 8),
          chips,
        ])));
  }
}

/// What is still missing before the next Koch character unlocks (progress
/// bar, repetitions owed, weak characters as accuracy chips).
class UnlockOutlookCard extends StatelessWidget {
  final String next; // display form of the next character
  final List<String> chars; // active Koch characters
  final Map<String, CharStat> stats;
  final AdaptiveCopyThresholds thresholds;
  final String Function(String) display;
  final Map<String, double> weak;
  final Set<String> excluded;
  final void Function(String) onToggle;
  const UnlockOutlookCard(
      {super.key,
      required this.next,
      required this.chars,
      required this.stats,
      required this.thresholds,
      required this.display,
      required this.weak,
      required this.excluded,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final th = thresholds;
    final needAttempts = <String, int>{};
    final lowAcc = <String, int>{};
    var doneAttempts = 0, wantAttempts = 0;
    for (final ch in chars) {
      final st = stats[ch] ?? CharStat();
      final acc = 1 - st.emaErrorRate;
      if (st.attempts < th.unlockOccurrences) {
        doneAttempts += st.attempts;
        wantAttempts += th.unlockOccurrences;
        needAttempts[ch] = th.unlockOccurrences - st.attempts;
      } else if (acc < th.highThreshold) {
        lowAcc[ch] = (acc * 100).round();
      }
    }
    double progress;
    if (wantAttempts > 0) {
      progress = doneAttempts / wantAttempts;
    } else {
      final worst = lowAcc.values.fold<int>(100, (m, v) => v < m ? v : m);
      progress = (worst / 100 / th.highThreshold).clamp(0.0, 1.0);
    }
    const maxChips = 10;
    Widget chips(List<String> items) {
      final shown = items.take(maxChips).toList();
      return Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: c.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Text(t, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
          ),
        if (items.length > maxChips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(Strings.t('ac_outlook_more').replaceFirst('{n}', '${items.length - maxChips}'),
                style: TextStyle(fontSize: 13, color: c.textMuted)),
          ),
      ]);
    }

    final owed = needAttempts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final label = TextStyle(fontSize: 13, color: c.textMuted);
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_outlook_title').replaceFirst('{ch}', next),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.textPrimary)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: c.background,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          if (owed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(Strings.t('ac_outlook_attempts'), style: label),
            const SizedBox(height: 6),
            chips([for (final x in owed) '${display(x.key)} ${x.value}']),
          ],
          if (weak.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                Strings.t('ac_outlook_accuracy_boost')
                    .replaceFirst('{pct}', '${(th.highThreshold * 100).round()}'),
                style: label),
            const SizedBox(height: 6),
            WeakCharChips(
                weak: weak,
                excluded: excluded,
                display: display,
                onToggle: onToggle,
                alignment: WrapAlignment.start,
                showAccuracy: true,
                small: true),
          ],
        ]),
      ),
    );
  }
}
