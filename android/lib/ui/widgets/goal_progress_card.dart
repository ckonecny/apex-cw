// "On the way to ..." card for every active training goal except new
// characters (which has the unlock card): where the lever stands between its
// start and the goal, and how far the readiness window for the next step is.
import 'package:flutter/material.dart';

import '../../content/training_goals.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';
import 'goal_suggestion_card.dart';

class GoalProgressCard extends StatelessWidget {
  final String kind; // 'hear' or 'echo'
  final LeverGoal goal;
  final GoalValues values;
  final List<bool> window; // graded items since the last change
  final double high; // hit rate needed for the next step
  // Tighter spacing (when space is tight).
  final bool compact;
  // New characters: the readiness bar shows the unlock progress instead of the
  // window (value 0..1 and its line), [extra] (practice lists) below it.
  final double? readyValue;
  final String? readyText;
  final Widget? extra;
  const GoalProgressCard({
    super.key,
    required this.kind,
    required this.goal,
    required this.values,
    required this.window,
    required this.high,
    this.compact = false,
    this.readyValue,
    this.readyText,
    this.extra,
  });

  // Share of the way from the value when the goal was set to the goal.
  double get _progress {
    final now = values.valueOf(goal.lever), t = effectiveTarget(goal, values);
    final start = goal.start ?? now;
    final span = (start - t).abs();
    if (span == 0) return 0;
    final done = lowerIsHarder(goal.lever) ? start - now : now - start;
    return (done / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final lever = goal.lever;
    final t = effectiveTarget(goal, values);
    String v(int x) => lever == GoalLever.giveWpm && x == 0
        ? Strings.t('settings_answer_wpm_same')
        : leverValue(lever, x);
    final size = goalWindow(kind);
    final ready = goalReady(window, high);
    final bad = readyValue == null && ready == GoalReady.notYet;
    final label = TextStyle(fontSize: 13, color: c.textMuted);
    Widget bar(double value, Color color) => ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8,
        backgroundColor: c.border,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // New characters: "On the way to: 39 characters", no label.
              lever == GoalLever.newChars
                  ? Strings.t('tg_way_title_chars').replaceFirst('{t}', v(t))
                  : Strings.t('tg_way_title')
                        .replaceFirst('{l}', leverLabel(lever, kind))
                        .replaceFirst('{t}', v(t)),
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
            SizedBox(height: compact ? 8 : 12),
            bar(_progress, c.accent),
            const SizedBox(height: 4),
            Text(
              Strings.t('tg_way_now')
                  .replaceFirst('{v}', v(values.valueOf(lever))),
              style: label,
            ),
            SizedBox(height: compact ? 8 : 14),
            InkWell(
              onTap: readyValue == null
                  ? () => _showDetails(context, size)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(
                    readyValue ?? goalReadyBar(window, size, high),
                    bad ? c.warning : c.accent,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    readyText ?? Strings.t('tg_ready_${ready.name}'),
                    style: label,
                  ),
                ],
              ),
            ),
            if (!compact && extra != null) ...[
              const SizedBox(height: 14),
              extra!,
            ],
          ],
        ),
      ),
    );
  }

  // The numbers behind the readiness line, on tap.
  void _showDetails(BuildContext context, int size) {
    final c = AppColors.of(context);
    final rate = windowRateSoFar(window);
    final unit = Strings.t('tg_win_chars');
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(k, style: TextStyle(fontSize: 14, color: c.textMuted)),
          ),
          const SizedBox(width: 12),
          Text(v, style: TextStyle(fontSize: 14, color: c.textPrimary)),
        ],
      ),
    );
    final missing = (size - window.length).clamp(0, size);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.background,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Strings.t('tg_ready_title'),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              const SizedBox(height: 12),
              row(
                Strings.t('tg_ready_collected'),
                Strings.t('tg_ready_of')
                    .replaceFirst('{c}', '${window.length}')
                    .replaceFirst('{n}', '$size')
                    .replaceFirst('{u}', unit),
              ),
              row(
                Strings.t('tg_ready_rate'),
                rate == null ? '–' : '${(rate * 100).round()} %',
              ),
              row(Strings.t('tg_ready_need'), '${(high * 100).round()} %'),
              if (missing > 0)
                row(Strings.t('tg_ready_missing'), '$missing $unit'),
              const SizedBox(height: 12),
              Text(
                Strings.t('tg_ready_rule')
                    .replaceFirst('{n}', '$size')
                    .replaceFirst('{u}', unit)
                    .replaceFirst('{need}', '${(high * 100).round()}'),
                style: TextStyle(fontSize: 13, color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
