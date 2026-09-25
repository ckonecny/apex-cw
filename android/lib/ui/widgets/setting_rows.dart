import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';

class SettingsDivider extends StatelessWidget {
  const SettingsDivider();
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Divider(color: c.border, height: 1);
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String text;
  const SettingsSectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Text(text,
      style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
          color: c.textMuted, letterSpacing: 1.2));
  }
}

class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
    decoration: BoxDecoration(color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border)),
    child: Column(children: children),
  );
  }
}

class LabeledSlider extends StatelessWidget {
  final String label, display;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const LabeledSlider({required this.label, required this.value, required this.min,
      required this.max, required this.divisions, required this.display,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
            color: c.textPrimary)),
        const Spacer(),
        Text(display, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
            color: c.accent)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: c.accent,
          inactiveTrackColor: c.border,
          thumbColor: c.accent,
          overlayColor: c.accent.withOpacity(0.1),
          trackHeight: 3,
        ),
        child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ),
    ]),
  );
  }
}

// Two-thumb variant of LabeledSlider for a low/high pair that must never
// cross (e.g. Adaptive Mode's success thresholds) — one control instead of
// two independent sliders that could be set inconsistently.
class LabeledRangeSlider extends StatelessWidget {
  final String label, display;
  final RangeValues values;
  final double min, max;
  final int divisions;
  final ValueChanged<RangeValues> onChanged;
  const LabeledRangeSlider({required this.label, required this.values, required this.min,
      required this.max, required this.divisions, required this.display,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
            color: c.textPrimary)),
        const Spacer(),
        Text(display, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
            color: c.accent)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: c.accent,
          inactiveTrackColor: c.border,
          thumbColor: c.accent,
          overlayColor: c.accent.withOpacity(0.1),
          trackHeight: 3,
        ),
        child: RangeSlider(values: values, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ),
    ]),
  );
  }
}

class ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textPrimary)),
      const Spacer(),
      Switch(
        value: value,
        onChanged: onChanged,
        activeColor: c.accent,
        inactiveTrackColor: c.border,
        // Default Material off-thumb is near-white — glares against the dark
        // background/border, looking like an accidentally-highlighted control.
        inactiveThumbColor: c.textMuted,
        // Material 3 also draws a separate track outline around the off
        // state, defaulting to a light neutral that inactiveTrackColor above
        // doesn't touch — same glare, needs its own override.
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? c.accent : c.border),
      ),
    ]),
  );
  }
}

class CharSetField extends StatelessWidget {
  final String label, initialValue, countLabel;
  final String? hint;
  final ValueChanged<String> onChanged;
  const CharSetField({required this.label, required this.initialValue,
      required this.onChanged, required this.countLabel, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textPrimary)),
      const SizedBox(height: 8),
      TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
            color: c.accent),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.background,
          hintText: hint ?? Strings.t('settings_char_hint_default'),
          hintStyle: TextStyle(fontFamily: 'CwMono', color: c.textDisabled),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.accent)),
        ),
      ),
      const SizedBox(height: 6),
      Text(countLabel, style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
          color: c.textFaint)),
    ]),
  );
  }
}

class SegmentRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const SegmentRow({required this.label, required this.options,
      required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
          color: c.textPrimary)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        // Wrap onto multiple rows once options no longer fit comfortably in one.
        final perRow = options.length <= 3 ? options.length : 3;
        final gap = 6.0;
        final itemWidth = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap, runSpacing: gap,
          children: List.generate(options.length, (i) {
            final active = i == selected;
            return SizedBox(width: itemWidth, child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? c.accent.withOpacity(0.15) : c.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: active ? c.accent : c.border),
                ),
                child: Text(options[i], textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                        color: active ? c.accent : c.textMuted)),
              ),
            ));
          }),
        );
      }),
    ]),
  );
  }
}


/// Length of [dits] dit lengths at [wpm] (PARIS: dit = 1.2 / wpm s), e.g. "0.4 s".
String ditsToSeconds(int dits, int wpm) => '${(dits * 1.2 / wpm).toStringAsFixed(1)} s';
