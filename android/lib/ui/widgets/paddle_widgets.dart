// Shared touch-paddle widgets: used by CW Keyer and — since the Echo Trainer
// also needs to receive keyed input, whether from touch or a vband adapter —
// the Echo Trainer too (including Koch "Neu lernen" / "Vorhören").
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class IambicPaddles extends StatelessWidget {
  final VoidCallback onDitDown, onDitUp, onDahDown, onDahUp;
  const IambicPaddles({super.key, required this.onDitDown, required this.onDitUp,
      required this.onDahDown, required this.onDahUp});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(children: [
      Expanded(child: PaddleButton(label: 'DIT  ·',
          color: c.accent, onDown: onDitDown, onUp: onDitUp)),
      const SizedBox(width: 12),
      Expanded(child: PaddleButton(label: 'DAH  —',
          color: c.warning, onDown: onDahDown, onUp: onDahUp)),
    ]),
  );
  }
}

// Uses raw Listener (pointer events) instead of GestureDetector's tap
// recognizer — a long hold must never be reinterpreted/canceled, since the
// hold duration itself is what decides dit vs. dah.
class StraightKeyPaddle extends StatefulWidget {
  final VoidCallback onDown, onUp;
  const StraightKeyPaddle({super.key, required this.onDown, required this.onUp});

  @override
  State<StraightKeyPaddle> createState() => _StraightKeyPaddleState();
}

class _StraightKeyPaddleState extends State<StraightKeyPaddle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = c.info;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Listener(
        onPointerDown: (_) { setState(() => _pressed = true);  widget.onDown(); },
        onPointerUp:   (_) { setState(() => _pressed = false); widget.onUp(); },
        onPointerCancel: (_) { setState(() => _pressed = false); widget.onUp(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 30),
          height: 90,
          decoration: BoxDecoration(
            color: _pressed ? color.withOpacity(0.25) : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(_pressed ? 0.8 : 0.3),
                width: _pressed ? 2 : 1),
          ),
          child: Center(child: Text('KEY',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(_pressed ? 1.0 : 0.6)))),
        ),
      ),
    );
  }
}

class PaddleButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onDown, onUp;
  final double height;
  const PaddleButton({super.key, required this.label, required this.color,
      required this.onDown, required this.onUp, this.height = 90});
  @override
  State<PaddleButton> createState() => _PaddleButtonState();
}

class _PaddleButtonState extends State<PaddleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) { setState(() => _pressed = true); widget.onDown(); },
      onPointerUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onPointerCancel: (_) { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 30),
        height: widget.height,
        decoration: BoxDecoration(
          color: _pressed ? widget.color.withOpacity(0.25) : widget.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: widget.color.withOpacity(_pressed ? 0.8 : 0.3),
              width: _pressed ? 2 : 1),
        ),
        child: Center(child: Text(widget.label,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                fontWeight: FontWeight.bold,
                color: widget.color.withOpacity(_pressed ? 1.0 : 0.6)))),
      ),
    );
  }
}
