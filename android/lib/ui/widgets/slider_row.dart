import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Label, slider and value readout in one row (Generator, Keyer, Echo).
/// [display] overrides the numeric readout; [labelWidth]/[valueWidth] let
/// two rows on one screen line up.
class SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String? display;
  final double labelWidth, valueWidth;
  final bool showTicks;
  const SliderRow({super.key, required this.label, required this.value,
      required this.min, required this.max, required this.divisions,
      required this.onChanged, this.display, this.labelWidth = 50,
      this.valueWidth = 40, this.showTicks = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        SizedBox(width: labelWidth, child: Text(label,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                color: c.textMuted))),
        Expanded(child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.accent,
            inactiveTrackColor: c.border,
            thumbColor: c.accent,
            overlayColor: c.accent.withOpacity(0.1),
            trackHeight: 3,
            // No step dots: Flutter draws them only when the track is long
            // enough, so rows of different width looked different.
            tickMarkShape: showTicks ? null : SliderTickMarkShape.noTickMark,
          ),
          child: Slider(value: value, min: min, max: max,
              divisions: divisions, onChanged: onChanged),
        )),
        SizedBox(width: valueWidth, child: Text(
            display ?? value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                color: c.accent))),
      ],
    );
  }
}
