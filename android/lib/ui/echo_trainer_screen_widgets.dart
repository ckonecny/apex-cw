// Small widgets. Split out of echo_trainer_screen.dart; same library.
part of 'echo_trainer_screen.dart';

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusLabel extends StatelessWidget {
  final _State state;
  final bool preparing;
  const _StatusLabel({required this.state, this.preparing = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Nothing to say while idle (the Hören start view has no label either).
    if (state == _State.idle) return const SizedBox.shrink();
    final (text, color) = switch (state) {
      _State.idle      => ('', c.textDisabled),
      _State.playing   => preparing
          ? (Strings.t('get_ready'), c.warning)
          : (Strings.t('echo_status_playing'), c.warning),
      _State.receiving => (Strings.t('echo_status_receiving'), c.info),
      _State.correct   => (Strings.t('echo_status_correct'), c.accent),
      _State.wrong     => (Strings.t('echo_status_wrong'), c.danger),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(fontSize: 14, color: color)),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int correct, total;
  final int? answerWpm;   // shown only when the answer is capped below the prompt tempo
  const _StatsBar({required this.correct, required this.total, this.answerWpm});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pct = (correct * 100 ~/ total);
    final wrong = total - correct;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: c.surfaceAlt,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _chip('✓ $correct', c.accent),
          const SizedBox(width: 12),
          _chip('✗ $wrong', c.danger),
          const SizedBox(width: 12),
          _chip('$pct %',
              pct >= 90 ? c.accent
            : pct >= 70 ? c.warning
                        : c.danger),
          if (answerWpm != null) ...[
            const SizedBox(width: 12),
            _chip('${Strings.t('echo_answer_wpm')} $answerWpm', c.info),
          ],
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Text(t, style: TextStyle(fontSize: 13, color: c)),
  );
}
