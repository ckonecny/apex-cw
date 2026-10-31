import 'package:flutter/material.dart';
import '../../content/effective_wpm.dart';
import '../../content/training_goals.dart';
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
/// [showWordGap] false (Geben: the answer pause lives in the ⚙ sheet): no
/// word-gap row, and "eff." counts the gap at the normal 7 dits.
///
/// [showSpacing] false (Q-groups: a group is heard as one melody, never
/// character by character): only the tempo slider, plain "WPM" without "eff.".
///
/// [typing] (Hören on the on-screen keyboard): the app waits after every word,
/// so only the character spacing is shown and counts for "eff." (see
/// [effectiveWpm]). [compact] uses denser sliders and rows, for screens where
/// height is short; on screens lower than 700 dp it also drops the "Dits · s"
/// sub line, otherwise the sub line stays so the block looks the same
/// everywhere. [showUndo] switches off the
/// "Changed … Undo" snackbar of the slider (it would cover buttons below).
///
/// [goals] adds a small "goal …" hint to the values that have a training
/// goal (DECISIONS.md "Training goals"); the goals only read these values.
/// One −/+ step of the character spacing, as on the row below: 3..45 dits,
/// and the word gap is raised with it so it never drops below. Also used by
/// the audio trainer's lock-screen buttons (#152).
(int, int) stepCharSpacing(int interChar, int interWord, int delta) {
  final ic = (interChar + delta).clamp(3, 45);
  return (ic, interWord < ic ? ic : interWord);
}

class TempoSpacingSection extends StatelessWidget {
  final int wpm, interChar, interWord;
  final bool typing, compact, showUndo, showWordGap, showSpacing;
  final Widget? leading;
  final String? speedLabel;
  final ValueChanged<int> onWpm;
  final void Function(int interChar, int interWord) onSpacing;

  final Map<GoalLever, int> goals;

  const TempoSpacingSection({
    super.key,
    required this.wpm,
    required this.interChar,
    required this.interWord,
    required this.onWpm,
    required this.onSpacing,
    this.typing = false,
    this.showWordGap = true,
    this.showSpacing = true,
    this.compact = false,
    this.showUndo = true,
    this.leading,
    this.speedLabel,
    this.goals = const {},
  });


  String _hint(GoalLever l) => goals[l] == null
      ? ''
      : ' · ${Strings.t('tg_hint').replaceFirst('{t}', '${goals[l]}')}';

  void _step(int delta) {
    final (ic, iw) = stepCharSpacing(interChar, interWord, delta);
    onSpacing(ic, iw);
  }

  @override
  Widget build(BuildContext context) {
    final eff = effectiveWpm(wpm, interChar, interWord, typing: typing || !showWordGap);
    // Compact + short screen: the sub line goes first when height is tight.
    final showSub = !compact || MediaQuery.sizeOf(context).height >= 700;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (leading != null) ...[leading!, const SettingsDivider()],
      LabeledSlider(
          label: (speedLabel ?? Strings.t('hc_speed')) + _hint(GoalLever.wpm),
        display: showSpacing ? '$wpm WPM (eff. $eff)' : '$wpm WPM',
        value: wpm.toDouble(),
        min: TrainingProfile.minWpm.toDouble(),
        max: 60,
        divisions: 60 - TrainingProfile.minWpm,
        showUndo: showUndo,
        dense: compact,
        onChanged: (v) => onWpm(v.round()),
      ),
      if (showSpacing) ...[
      const SettingsDivider(),
      Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 0 : 4, 8, compact ? 0 : 4),
        child: Column(children: [
          _StepRow(
            label: Strings.t('settings_char_spacing'),
            value: '$interChar',
                  sub: showSub
                      ? 'Dits · ${ditsToSeconds(interChar, wpm)}${_hint(GoalLever.charSpacing)}'
                      : null,
            compact: compact,
            onMinus: interChar > 3 ? () => _step(-1) : null,
            onPlus: interChar < 45 ? () => _step(1) : null,
          ),
          if (!typing && showWordGap)
            _StepRow(
              label: Strings.t('settings_word_spacing'),
              value: '$interWord',
                    sub: showSub
                        ? 'Dits · ${ditsToSeconds(interWord, wpm)}${_hint(GoalLever.wordSpacing)}'
                        : null,
              compact: compact,
              onMinus: interWord > 6 && interWord > interChar
                  ? () => onSpacing(interChar, interWord - 1)
                  : null,
              onPlus: interWord < 105 ? () => onSpacing(interChar, interWord + 1) : null,
            ),
        ]),
      ),
      ],
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
