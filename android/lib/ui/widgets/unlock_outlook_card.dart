// Weak-character chips and the "On the way to ..." card as in Listen, for the
// Send start/result view (#107). Same look: amber chips, 20/12 px radius,
// accuracy row inside the unlock card.
import 'package:flutter/material.dart';
import '../../content/adaptive_copy_engine.dart';
import '../../content/char_stats.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../content/training_goals.dart';
import 'app_ui.dart';
import 'goal_progress_card.dart';

/// Tappable weak characters: tap = leave one out of the boost (struck
/// through) or take it in again.
class WeakCharChips extends StatelessWidget {
  final Map<String, double> weak; // char -> error rate
  final Set<String> excluded;
  final String Function(String) display;
  final void Function(String) onToggle;
  final double scale;
  final WrapAlignment alignment;
  final bool small;
  const WeakCharChips(
      {super.key,
      required this.weak,
      required this.excluded,
      required this.display,
      required this.onToggle,
      this.scale = 1,
      this.alignment = WrapAlignment.center,
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
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: included ? c.warning.withValues(alpha: 0.15) : c.surfaceAlt,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: included ? c.warning.withValues(alpha: 0.5) : c.border),
            ),
            child: Text('${display(e.key)}  ${(e.value * 100).round()}%',
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
  // A second block in the same card (the recurring mix-ups), below a thin line.
  final Widget? extra;
  const WeakCharsCard({super.key, required this.chips, this.extra});

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
          if (extra != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 12),
            extra!,
          ],
        ])));
  }
}

/// What is still missing before the next Koch character unlocks: the "On the
/// way to" card of the goal "New characters" (bars, repetitions owed).
class UnlockOutlookCard extends StatelessWidget {
  final String next; // display form of the next character
  final List<String> chars; // active Koch characters
  final Map<String, CharStat> stats;
  final AdaptiveCopyThresholds thresholds;
  final String Function(String) display;
  // Tighter spacing, no lists (when space is tight).
  final bool compact;
  // The "New characters" goal; the card has the look of the other goals'.
  final String kind;
  final LeverGoal goal;
  final GoalValues values;
  const UnlockOutlookCard(
      {super.key,
      required this.kind,
      required this.goal,
      required this.values,
      required this.next,
      required this.chars,
      required this.stats,
      required this.thresholds,
      required this.display,
      this.compact = false});

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
      return Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.start, children: [
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
    Widget heading(String t) => SizedBox(width: double.infinity, child: Text(t, style: label));
    return GoalProgressCard(
      kind: kind,
      goal: goal,
      values: values,
      window: const [],
      high: th.highThreshold,
      compact: compact,
      readyValue: progress,
      readyText: Strings.t('tg_way_unlock')
          .replaceFirst('{ch}', next)
          .replaceFirst('{pct}', '${(progress * 100).round()}'),
      extra: owed.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              heading(Strings.t('ac_outlook_attempts')),
              const SizedBox(height: 6),
              SizedBox(
                  width: double.infinity,
                  child: chips([for (final x in owed) '${display(x.key)} ${x.value}'])),
            ]),
    );
  }
}
