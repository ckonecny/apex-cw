// Small widgets of the adaptive copy trainer. Split out of
// adaptive_copy_body.dart; same library.
part of 'adaptive_copy_body.dart';

// One adaptive-engine proposal on the result screen: a checkbox to
// accept/reject it, and (when it carries a magnitude) +/- steppers to
// adjust it before it's applied. See docs/ADAPTIVE-COPY.md "User override
// on the result screen".
class SuggestionRow extends StatelessWidget {
  final double width;
  final bool accepted;
  final ValueChanged<bool> onToggle;
  final String label;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  // Set for the Koch-unlock proposal only — a bigger deal than a tempo/
  // spacing nudge, so it gets a star icon and a bolder border instead of
  // blending into the same generic row style as the other two.
  final bool highlight;
  // Unlock row only: plays the new character in place. Null while a preview
  // is already in flight, or when there's no next character to preview.
  final VoidCallback? onPreview;

  const SuggestionRow({
    required this.width,
    required this.accepted,
    required this.onToggle,
    required this.label,
    this.onIncrement,
    this.onDecrement,
    this.highlight = false,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // No row-wide tap target — only the checkbox toggles acceptance.
    // A whole-row InkWell made stray taps near the steppers register as an
    // accidental reject instead, which is worse than requiring a precise
    // checkbox tap.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: accepted ? c.accent.withOpacity(highlight ? 0.2 : 0.12) : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: highlight ? Border.all(
                color: accepted ? c.accent.withOpacity(0.8) : c.border, width: 1.5) : null,
          ),
          child: Row(children: [
            _TapTarget(
              onTap: () => onToggle(!accepted),
              child: Icon(accepted ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 22, color: accepted ? c.accent : c.textMuted),
            ),
            if (highlight)
              Icon(Icons.star, size: 18, color: accepted ? c.accent : c.textMuted),
            if (highlight) const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: highlight ? 15 : 14,
                      fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                      color: accepted ? c.accent : c.textMuted,
                      decoration: accepted ? null : TextDecoration.lineThrough)),
            ),
            if (onPreview != null)
              _TapTarget(onTap: onPreview!, child: Icon(Icons.volume_up, size: 20, color: c.accent)),
            if (onDecrement != null)
              _TapTarget(onTap: onDecrement!, child: Icon(Icons.remove, size: 20, color: c.accent)),
            if (onIncrement != null)
              _TapTarget(onTap: onIncrement!, child: Icon(Icons.add, size: 20, color: c.accent)),
          ]),
        ),
      ),
    );
  }
}

// 44x44 minimum touch target (Material guideline) around a small icon —
// the plain Icon-in-Padding steppers this replaced were easy to miss and
// the miss-tap fell through to the row behind them.
class _TapTarget extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TapTarget({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(width: 44, height: 44, child: Center(child: child)),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      AppButton(label: label, onTap: onTap, color: AppColors.of(context).info);
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => AppButton(
      label: label, onTap: onTap, color: AppColors.of(context).info, primary: false);
}
