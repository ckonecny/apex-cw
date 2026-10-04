import 'package:flutter/material.dart';
import '../../content/charset_content.dart';
import '../../content/cw_content.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/char_color.dart';
import 'app_ui.dart';
import 'setting_rows.dart';

String charSetLabel(CharSet s) => Strings.t(const {
      CharSet.koch: 'charset_koch',
      CharSet.all: 'charset_all',
      CharSet.practice: 'charset_practice',
    }[s]!);

String contentLabel(ContentKind k) => Strings.t(const {
      ContentKind.random: 'mode_random',
      ContentKind.words: 'mode_words',
      ContentKind.abbrevs: 'mode_abbrevs',
      ContentKind.calls: 'mode_callsigns',
      ContentKind.mixed: 'mode_mixed',
    }[k]!);

/// Shared top of Hören and Geben: character set, content, and for the Koch
/// lesson the lesson slider plus the row of unlocked characters.
class CharsetHeader extends StatelessWidget {
  final CharsetChoice choice;
  final ValueChanged<CharsetChoice> onChanged;
  final int kochLevel;
  final List<String> kochSequence;
  final ValueChanged<int> onKochLevelChanged;
  // 0=lower, 1=UPPER — display only.
  final int outputCase;
  // Koch character: tap plays it, long press opens the echo drill (Phase 7e).
  final ValueChanged<String>? onCharTap;
  final ValueChanged<String>? onCharLongPress;
  // Practice Set characters, editable right on the start screen.
  final String practiceChars;
  final ValueChanged<String>? onPracticeCharsChanged;

  const CharsetHeader({
    super.key,
    required this.choice,
    required this.onChanged,
    required this.kochLevel,
    required this.kochSequence,
    required this.onKochLevelChanged,
    this.outputCase = 1,
    this.onCharTap,
    this.onCharLongPress,
    this.practiceChars = '',
    this.onPracticeCharsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final koch = choice.set == CharSet.koch;
    // Scrolls inside a cap instead of overflowing small phones or big fonts
    // (issue #39); the screens below it keep their share of the height.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: SingleChildScrollView(child: _content(context, c, koch)),
    );
  }

  Widget _content(BuildContext context, AppColors c, bool koch) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Chips(
        labels: [for (final s in CharSet.values) charSetLabel(s)],
        selected: choice.set.index,
        onChanged: (i) => onChanged(choice.withSet(CharSet.values[i])),
      ),
      if (allowedContents(choice.set).length > 1)
        _Chips(
          labels: [for (final k in allowedContents(choice.set)) contentLabel(k)],
          selected: allowedContents(choice.set).indexOf(choice.content),
          onChanged: (i) => onChanged(choice.withContent(allowedContents(choice.set)[i])),
        ),
      if (koch) ...[
        Row(children: [
          SizedBox(width: 50, child: Text('KOCH',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted))),
          Expanded(child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.accent, inactiveTrackColor: c.border,
              thumbColor: c.accent, overlayColor: c.accent.withValues(alpha: 0.1), trackHeight: 3,
            ),
            child: Slider(
              value: kochLevel.clamp(2, kochSequence.length).toDouble(),
              min: 2, max: kochSequence.length.toDouble(),
              divisions: kochSequence.length - 2,
              onChanged: (v) => onKochLevelChanged(v.round()),
            ),
          )),
          SizedBox(width: 40, child: Text('$kochLevel', textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.accent))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              // The whole sequence: characters beyond the current lesson are
              // shown inactive (dimmed, no border) but can still be tapped
              // or long-pressed to listen/practice ahead.
              for (final (i, ch) in kochSequence.indexed)
                GestureDetector(
                  onTap: onCharTap == null ? null : () => onCharTap!(ch),
                  onLongPress: onCharLongPress == null ? null : () => onCharLongPress!(ch),
                  child: Opacity(
                    opacity: i < kochLevel ? 1.0 : 0.35,
                    child: Container(
                      width: 30, height: 32, alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < kochLevel ? c.surfaceAlt : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      // Fixed 30×32 tile: ignores the system font size.
                      child: NoTextScale(child: Text(
                          outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase(),
                          style: TextStyle(fontFamily: 'CwMono', fontSize: 15,
                              color: i < kochLevel ? charTypeColor(ch, c) : c.textMuted))),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (onCharTap != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(Strings.t('charset_tap_hint'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 10,
                    color: c.textFaint, fontStyle: FontStyle.italic)),
          ),
      ],
      if (choice.set == CharSet.practice && onPracticeCharsChanged != null)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border)),
          child: CharSetField(
            label: Strings.t('settings_characters'),
            initialValue: practiceChars,
            onChanged: onPracticeCharsChanged!,
            countLabel: Strings.t('settings_unique_chars_detected')
                .replaceFirst('{n}', '${parsePracticeChars(practiceChars).length}'),
            hint: Strings.t('settings_example_chars'),
          ),
        ),
    ]);
  }
}

class _Chips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const _Chips({required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < labels.length; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: i == selected ? c.accent.withValues(alpha: 0.15) : c.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: i == selected ? c.accent : c.border),
              ),
              child: Text(labels[i],
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
                      color: i == selected ? c.accent : c.textMuted)),
            ),
          ),
      ]),
    );
  }
}
