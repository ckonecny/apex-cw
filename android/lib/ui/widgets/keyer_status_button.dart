// App bar symbol for an external key (#116): dim while no adapter is
// detected, accent colour once one is. A tap opens the keyer settings.
// While it is shown (and [sound] is true) the keyer runs with the general
// Send settings, so dit and dah can be heard and the key tried out.
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/key_adapter_state.dart';
import '../../util/keyer_try.dart';
import '../settings_screen.dart';

class KeyerStatusButton extends StatefulWidget {
  /// False while the screen needs the keyer for itself or must stay quiet
  /// (a running block, a screen that keys on its own).
  final bool sound;

  /// Speed in WPM when the screen has its own Send speed control; follows it
  /// live. Null = the general Send setting.
  final int? wpm;
  const KeyerStatusButton({super.key, this.sound = true, this.wpm});

  @override
  State<KeyerStatusButton> createState() => _KeyerStatusButtonState();
}

class _KeyerStatusButtonState extends State<KeyerStatusButton> {
  Animation<double>? _covered;
  bool _on = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another route (settings, statistics, a sheet) on top silences the key.
    final a = ModalRoute.of(context)?.secondaryAnimation;
    if (a != _covered) {
      _covered?.removeStatusListener(_onCover);
      _covered = a;
      _covered?.addStatusListener(_onCover);
    }
    _sync();
  }

  @override
  void didUpdateWidget(KeyerStatusButton old) {
    super.didUpdateWidget(old);
    _sync();
    if (_on && widget.wpm != null && widget.wpm != old.wpm) KeyerTry.setWpm(widget.wpm!);
  }

  void _onCover(AnimationStatus _) => _sync();

  void _sync() {
    final covered = _covered != null && _covered!.status != AnimationStatus.dismissed;
    final want = widget.sound && !covered;
    if (want == _on) return;
    _on = want;
    want ? KeyerTry.start(wpm: widget.wpm) : KeyerTry.stop();
  }

  @override
  void dispose() {
    _covered?.removeStatusListener(_onCover);
    if (_on) KeyerTry.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: KeyAdapterState.detected,
      builder: (context, detected, _) => IconButton(
        icon: CustomPaint(
          size: const Size(26, 26),
          painter: StraightKeyPainter(detected ? c.accent : c.textFaint),
        ),
        tooltip: Strings.t(detected ? 'keyer_btn_detected' : 'keyer_btn_none'),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen(scrollToKeyer: true))),
      ),
    );
  }
}

/// A straight key in side view: base, post, lever and knob (drawn on a 48 grid).
class StraightKeyPainter extends CustomPainter {
  final Color color;
  StraightKeyPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 36, 38, 6), const Radius.circular(1.5)), stroke);
    canvas.drawRect(const Rect.fromLTWH(20, 29, 8, 7), stroke);
    canvas.drawLine(const Offset(9, 27), const Offset(41, 23), stroke);
    canvas.drawCircle(const Offset(10, 19), 5, stroke);
  }

  @override
  bool shouldRepaint(StraightKeyPainter old) => old.color != color;
}

/// Small straight key, the Send counterpart of Listen's "playing" symbol.
class StraightKeyIcon extends StatelessWidget {
  final double size;
  final Color color;
  const StraightKeyIcon({super.key, this.size = 16, required this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: StraightKeyPainter(color));
}
