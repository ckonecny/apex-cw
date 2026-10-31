import 'package:flutter/material.dart';

import '../../content/training_goals.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';

/// Name of a lever; Geben calls its plain tempo "listening speed".
String leverLabel(GoalLever l, String kind) => Strings.t(
  l == GoalLever.wpm && kind == 'echo'
      ? 'tg_lever_wpm_echo'
      : 'tg_lever_${l.name}',
);

/// A lever value with its unit ("5 Dits", "20 WPM"); new characters 0 = all.
String leverValue(GoalLever l, int v) => switch (l) {
  GoalLever.newChars =>
    v == 0 ? Strings.t('opt_all') : '$v ${Strings.t('tg_unit_chars')}',
  GoalLever.charSpacing ||
  GoalLever.wordSpacing => '$v ${Strings.t('tg_unit_dits')}',
  GoalLever.groupLength => '$v ${Strings.t('tg_unit_chars')}',
  GoalLever.wpm || GoalLever.giveWpm => '$v WPM',
};

enum GoalCardState { open, accepted, snoozed }

/// The goal proposal on a result page (Hören and Geben): one step towards the
/// active goal, or undoing the last step, with "Apply" / "Not now". Nothing
/// changes without the tap (DECISIONS.md "Training goals").
class GoalSuggestionCard extends StatelessWidget {
  final GoalSuggestion suggestion;
  final String kind; // 'hear' or 'echo'
  final GoalCardState state;
  final VoidCallback onAccept, onLater;

  /// New characters: the character that comes next, and a play button.
  final String? newChar;
  final VoidCallback? onPreview;

  /// After "Apply": the goal it reached, and the goal that comes next.
  final bool reached;
  final GoalLever? nextGoal;

  const GoalSuggestionCard({
    super.key,
    required this.suggestion,
    required this.kind,
    required this.state,
    required this.onAccept,
    required this.onLater,
    this.newChar,
    this.onPreview,
    this.reached = false,
    this.nextGoal,
  });

  String _value(int v) => suggestion.lever == GoalLever.giveWpm && v == 0
      ? Strings.t('settings_answer_wpm_same')
      : leverValue(suggestion.lever, v);

  // "5 → 4 Dits": the unit only once, behind the new value.
  String get _change {
    final s = suggestion;
    if (s.lever == GoalLever.newChars) {
      return newChar == null ? '+1' : '+ "$newChar"';
    }
    final unit = _value(s.to).replaceFirst('${s.to}', '').trim();
    return '${s.from} → ${s.to}${unit.isEmpty ? '' : ' $unit'}';
  }

  String get _why {
    final s = suggestion;
    if (s.rate == null) return Strings.t('tg_why_unlock');
    return Strings.t('tg_why')
        .replaceFirst('{n}', '${goalWindow(kind)}')
        .replaceFirst('{u}', Strings.t('tg_win_chars'))
        .replaceFirst('{pct}', '${(s.rate! * 100).round()}');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = suggestion;
    final label = leverLabel(s.lever, kind);
    final muted = TextStyle(fontSize: 12, color: c.textMuted);
    final List<Widget> body;
    if (state == GoalCardState.accepted) {
      body = [
        Row(
          children: [
            Icon(Icons.check_circle, size: 20, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Strings.t('tg_accepted')
                    .replaceFirst('{l}', label)
                    .replaceFirst(
                      '{v}',
                      s.lever == GoalLever.newChars ? _change : _value(s.to),
                    ),
                style: TextStyle(fontSize: 14, color: c.accent),
              ),
            ),
          ],
        ),
        if (reached) ...[
          const SizedBox(height: 8),
          Text(
            '⚑ ${Strings.t('tg_goal_reached').replaceFirst('{l}', label)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          Text(
            nextGoal == null
                ? Strings.t('tg_all_reached')
                : Strings.t('tg_next_goal')
                      .replaceFirst('{l}', leverLabel(nextGoal!, kind)),
            style: muted,
          ),
        ],
      ];
    } else if (state == GoalCardState.snoozed) {
      body = [Text(Strings.t('tg_snoozed'), style: muted)];
    } else {
      final steps = s.stepsLeft == 0
          ? Strings.t('tg_steps_last')
          : s.stepsLeft == 1
          ? Strings.t('tg_steps_left1')
          : Strings.t('tg_steps_left').replaceFirst('{n}', '${s.stepsLeft}');
      body = [
        Text(
          s.back
              ? Strings.t('tg_back_head')
              : Strings.t('tg_sugg_head')
                    .replaceFirst('{p}', '${s.position}')
                    .replaceFirst('{n}', '${s.count}'),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1,
            color: s.back ? c.warning : c.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (s.back) ...[
              Icon(Icons.undo, size: 20, color: c.warning),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.back)
                    Text(
                      Strings.t('tg_back_title'),
                      style: TextStyle(fontSize: 14, color: c.textPrimary),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: s.back ? 13 : 15,
                      color: c.textPrimary,
                      fontWeight: s.back ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  Text(
                    _change,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: s.back ? c.warning : c.accent,
                    ),
                  ),
                  if (!s.back && s.target != null)
                    Text(
                      '${Strings.t('tg_sugg_target').replaceFirst('{t}', _value(s.target!))} · $steps',
                      style: muted,
                    ),
                  Text(_why, style: muted),
                ],
              ),
            ),
            if (onPreview != null)
              IconButton(
                icon: Icon(Icons.volume_up, color: c.accent),
                onPressed: onPreview,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: Strings.t('tg_accept'),
                onTap: onAccept,
                color: s.back ? c.warning : c.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(
                label: Strings.t('tg_later'),
                onTap: onLater,
                color: c.textMuted,
                primary: false,
              ),
            ),
          ],
        ),
      ];
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: state == GoalCardState.open
              ? (s.back ? c.warning : c.accent).withValues(alpha: 0.7)
              : c.border,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: body,
      ),
    );
  }
}
