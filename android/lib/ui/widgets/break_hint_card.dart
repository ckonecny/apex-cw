import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/break_reminder.dart';

/// Quiet suggestion on the block result page when the hit rate has fallen
/// (issue #5). Never blocks: "Continue" closes it, "Break" leaves the
/// training screen, "Don't show again" switches it off (Settings → General).
class BreakHintCard extends StatelessWidget {
  const BreakHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([BreakReminder.due, BreakReminder.enabled]),
      builder: (context, _) {
        if (!BreakReminder.due.value || !BreakReminder.enabled.value) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.warning.withValues(alpha: 0.12),
            border: Border.all(color: c.warning.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.self_improvement, size: 18, color: c.warning),
              const SizedBox(width: 8),
              Expanded(child: Text(Strings.t('break_hint_title'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary))),
            ]),
            const SizedBox(height: 6),
            Text(Strings.t('break_hint_body'),
                style: TextStyle(fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () {
                  BreakReminder.dismiss();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: Text(Strings.t('break_hint_pause')),
              ),
              TextButton(
                onPressed: BreakReminder.dismiss,
                child: Text(Strings.t('break_hint_continue')),
              ),
              TextButton(
                onPressed: () {
                  BreakReminder.setEnabled(false);
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(Strings.t('break_hint_off_note'))));
                },
                child: Text(Strings.t('break_hint_never'),
                    style: TextStyle(color: c.textFaint)),
              ),
            ]),
          ]),
        );
      },
    );
  }
}
