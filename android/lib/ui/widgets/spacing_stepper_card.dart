import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';

/// Manual spacing control of the Hören screen ("Abstand Zeichen/Wort  − 28/40 +"),
/// sitting below the WPM slider because both are about speed. − and + move the
/// inter-character and inter-word gap together by 1 dit each. Takes effect
/// immediately and independent of the adaptive suggestions.
///
/// Bounds match the ⚙ sliders (3–45 / 6–105), not the adaptive cap.
///
/// [charOnly] (typing mode): the word gap has no effect there (DECISIONS.md
/// "Hören: typing mode"), so only the char gap is shown and changed; the stored
/// word gap stays untouched, but never drops below the char gap (as in ⚙).
class SpacingStepperCard extends StatelessWidget {
  final int interCharSpace;
  final int interWordSpace;
  final bool charOnly;
  final void Function(int interCharSpace, int interWordSpace) onChanged;

  const SpacingStepperCard({
    super.key,
    required this.interCharSpace,
    required this.interWordSpace,
    required this.onChanged,
    this.charOnly = false,
  });

  void _step(int delta) {
    final ic = (interCharSpace + delta).clamp(3, 45);
    final iw = charOnly
        ? (interWordSpace < ic ? ic.clamp(6, 105) : interWordSpace)
        : (interWordSpace + delta).clamp(6, 105);
    if (ic == interCharSpace && iw == interWordSpace) return;
    onChanged(ic, iw);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Row(children: [
          Expanded(
            child: Text(
              Strings.t(charOnly
                  ? 'ac_spacing_control_title_char'
                  : 'ac_spacing_control_title'),
              style: TextStyle(fontSize: 13, color: c.textMuted),
            ),
          ),
          _StepButton(
              icon: Icons.remove, color: c.accent, onTap: () => _step(-1)),
          SizedBox(
            width: 72,
            child: Text(
              charOnly ? '$interCharSpace' : '$interCharSpace/$interWordSpace',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: c.accent),
            ),
          ),
          _StepButton(icon: Icons.add, color: c.accent, onTap: () => _step(1)),
        ]),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StepButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
          width: 44, height: 44, child: Center(child: Icon(icon, size: 20, color: color))),
    );
  }
}
