// Shared look of the app (start-page style): flat cards, solid buttons,
// Space Grotesk titles. Screens use these instead of restyling locally.
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

const _titleVariations = [FontVariation('wght', 600)];

/// Upper bound for the system font size, applied app-wide in main.dart
/// (DECISIONS.md "System font size: capped at 1.3").
const kMaxTextScale = 1.3;

/// Current effective text scale factor (after the cap), measured at body
/// text size. For fixed-height boxes that hold text: `h * textScaleOf(ctx)`
/// keeps the box constant across states (nothing jumps) while the text in
/// it still fits at larger system font sizes.
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;

/// For fixed-geometry elements (keyboard keys, character tiles) whose
/// text is already sized for the box: ignores the system font size.
class NoTextScale extends StatelessWidget {
  final Widget child;
  const NoTextScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(child: child);
}

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
    // One line, shrunk to fit rather than clipped or wrapped: half-width
    // buttons ("Nächster Block") run out of room at larger font sizes.
    final label0 = Text(label, maxLines: 1, softWrap: false,
        style: const TextStyle(fontFamily: 'CwMono', fontSize: 15, fontWeight: FontWeight.bold));
    final Widget text = FittedBox(fit: BoxFit.scaleDown, child: icon == null
        ? label0
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            label0,
          ]));
    const padding = EdgeInsets.symmetric(horizontal: 12);
    return SizedBox(height: height, child: primary
        ? ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withOpacity(0.18), foregroundColor: color,
              elevation: 0, shape: shape, padding: padding),
            onPressed: onTap, child: text)
        : ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surface, foregroundColor: c.textMuted,
              elevation: 0, shape: shape, padding: padding),
            onPressed: onTap, child: text));
  }
}

/// Vertical scroll view that shows when there is more: an always-visible
/// scrollbar and a soft fade at the bottom edge while content continues
/// below — otherwise a long list (or a large system font) cuts off
/// silently and nobody knows to scroll. With [center], content shorter
/// than the viewport is centered vertically.
class ScrollHint extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool center;
  const ScrollHint({super.key, required this.child,
      this.padding = EdgeInsets.zero, this.center = false});

  @override
  State<ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<ScrollHint> {
  final _controller = ScrollController();
  bool _more = false;

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final more = _controller.position.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Content size can change without a scroll (new rows, font size), so
    // re-check after every layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    final bg = AppColors.of(context).background;
    return LayoutBuilder(builder: (context, box) {
      Widget content = widget.child;
      if (widget.center) {
        content = ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: (box.maxHeight - widget.padding.vertical).clamp(0, double.infinity)),
          child: Center(child: content),
        );
      }
      return Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _update();
            return false;
          },
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _controller,
              padding: widget.padding,
              child: content,
            ),
          ),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0, height: 32,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _more ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [bg.withOpacity(0), bg],
                ),
              )),
            ),
          ),
        ),
      ]);
    });
  }
}
