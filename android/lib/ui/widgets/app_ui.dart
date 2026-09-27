// Shared look of the app (start-page style): flat cards, solid buttons,
// Space Grotesk titles. Screens use these instead of restyling locally.
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

const _titleVariations = [FontVariation('wght', 600)];

/// App bar title in the modern title font.
Widget appBarTitle(AppColors c, String text) => Text(text,
    style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 20,
        color: c.textPrimary, fontVariations: _titleVariations));

/// Flat surface card, no border.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  const AppCard({super.key, required this.child,
      this.padding = const EdgeInsets.all(14),
      this.margin = EdgeInsets.zero, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: borderColor == null ? null : Border.all(color: borderColor!, width: 0.8),
      ),
      child: child,
    );
  }
}

/// Small letter-spaced caption above a card or value.
class AppCaption extends StatelessWidget {
  final String text;
  const AppCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(fontFamily: 'CwMono', fontSize: 11, letterSpacing: 1,
          color: AppColors.of(context).textMuted));
}

/// Softly tinted button in the given accent color (secondary: neutral card).
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool primary;
  final double height;
  final IconData? icon;
  const AppButton({super.key, required this.label, required this.onTap,
      required this.color, this.primary = true, this.height = 52, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final Widget text = icon == null
        ? Text(label, style: const TextStyle(fontFamily: 'CwMono',
            fontSize: 15, fontWeight: FontWeight.bold))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontFamily: 'CwMono',
                fontSize: 15, fontWeight: FontWeight.bold)),
          ]);
    return SizedBox(height: height, child: primary
        ? ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withOpacity(0.18), foregroundColor: color,
              elevation: 0, shape: shape),
            onPressed: onTap, child: text)
        : ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surface, foregroundColor: c.textMuted,
              elevation: 0, shape: shape),
            onPressed: onTap, child: text));
  }
}
