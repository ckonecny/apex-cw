import 'package:flutter/material.dart';
import '../../content/effective_wpm.dart';
import '../../content/training_profile.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'setting_rows.dart';

/// Speed and pauses in one block, the same everywhere in the app (Verstehen
/// setup screens, Hören): a "Tempo" slider showing the effective speed in
/// brackets right behind the WPM, then one −/+ row for the character spacing
/// and one for the word spacing. Put it into a [SettingsCard].
///
/// [leading] is an extra row above the tempo (Geben: the give-speed slider);
/// [speedLabel] replaces "Tempo" where there are two speeds ("Hören"). The
/// spacing rows always belong to the speed directly above them.
///
/// [typing] (Hören on the on-screen keyboard): the app waits after every word,
/// so only the character spacing is shown and counts for "eff." (see
/// [effectiveWpm]). [compact] uses denser sliders and rows, for screens where
/// height is short; the "Dits · s" sub line stays, so the block looks the same
/// everywhere. [showUndo] switches off the
/// "Changed … Undo" snackbar of the slider (it would cover buttons below).
class TempoSpacingSection extends StatelessWidget {
  final int wpm, interChar, interWord;
  final bool typing, compact, showUndo;
  final Widget? leading;
  final String? speedLabel;
  final ValueChanged<int> onWpm;
  final void Function(int interChar, int interWord) onSpacing;

  const TempoSpacingSection({
    super.key,
    required this.wpm,
    required this.interChar,
    required this.interWord,
    required this.onWpm,
    required this.onSpacing,
    this.typing = false,
    this.compact = false,
    this.showUndo = true,
    this.leading,
    this.speedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final eff = effectiveWpm(wpm, interChar, interWord, typing: typing);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (leading != null) ...[leading!, const SettingsDivider()],
      LabeledSlider(
        label: speedLabel ?? Strings.t('hc_speed'),
        display: '$wpm WPM (eff. $eff)',
        value: wpm.toDouble(),
        min: TrainingProfile.minWpm.toDouble(),
        max: 60,
        divisions: 60 - TrainingProfile.minWpm,
        showUndo: showUndo,
        dense: compact,
        onChanged: (v) => onWpm(v.round()),
      ),
      const SettingsDivider(),
      Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 0 : 4, 8, compact ? 0 : 4),
        child: Column(children: [
          _StepRow(
            label: Strings.t('settings_char_spacing'),
            value: '$interChar',
            sub: 'Dits · ${ditsToSeconds(interChar, wpm)}',
            compact: compact,
            onMinus: interChar > 3 ? () => onSpacing(interChar - 1, interWord) : null,
            // The word gap never drops below the char gap.
            onPlus: interChar < 45
                ? () => onSpacing(interChar + 1, interWord < interChar + 1 ? interChar + 1 : interWord)
                : null,
          ),
          if (!typing)
            _StepRow(
              label: Strings.t('settings_word_spacing'),
              value: '$interWord',
              sub: 'Dits · ${ditsToSeconds(interWord, wpm)}',
              compact: compact,
              onMinus: interWord > 6 && interWord > interChar
                  ? () => onSpacing(interChar, interWord - 1)
                  : null,
              onPlus: interWord < 105 ? () => onSpacing(interChar, interWord + 1) : null,
            ),
        ]),
      ),
    ]);
  }
}

class _StepRow extends StatelessWidget {
  final String label, value;
  final String? sub;
  final bool compact;
  final VoidCallback? onMinus, onPlus;
  const _StepRow({
    required this.label,
    required this.value,
    required this.sub,
    required this.compact,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final density = compact ? VisualDensity.compact : VisualDensity.standard;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, color: c.textPrimary)),
          if (sub != null) Text(sub!, style: TextStyle(fontSize: 11, color: c.textFaint)),
        ]),
      ),
      IconButton(
          visualDensity: density,
          icon: const Icon(Icons.remove_circle_outline),
          color: c.accent,
          onPressed: onMinus),
      SizedBox(
          width: 50,
          child: Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.accent))),
      IconButton(
          visualDensity: density,
          icon: const Icon(Icons.add_circle_outline),
          color: c.accent,
          onPressed: onPlus),
    ]);
  }
}
