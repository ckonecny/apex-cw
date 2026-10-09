import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'char_playback_overlay.dart' show morsePattern;

/// "Learn from the mistake" view (issue #50): the word that was missed, each
/// character as dits and dahs with the plain character above it. [active] is
/// the index of the character that sounds right now (-1 = none), so sound,
/// pattern and letter are linked. Wraps to several lines for long words.
class MistakeLesson extends StatelessWidget {
  final String word;
  final int active;
  /// Positions that were wrong in the first attempt: shown in red.
  final Set<int> wrong;
  final String Function(String) display;
  const MistakeLesson({super.key, required this.word, required this.active,
      this.wrong = const {}, required this.display});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 12,
      children: [
        for (var k = 0; k < word.length; k++)
          // The sounding character gets a tinted background, so it stays
          // visible even when its colour is the red of a mistake.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
                color: k == active ? c.accent.withValues(alpha: 0.18) : null,
                borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(display(word[k]), style: TextStyle(fontFamily: 'CwMono',
                fontSize: 30, fontWeight: FontWeight.bold,
                color: wrong.contains(k) ? c.danger : k == active ? c.accent : c.textPrimary)),
            const SizedBox(height: 4),
            // Drawn instead of typeset: a bold dot and a bold bar are far
            // easier to see than the thin "·" and "—" glyphs.
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in morsePattern(word[k]).split(''))
                Container(
                  width: e == '.' ? 10 : 26,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: wrong.contains(k) ? c.danger : k == active ? c.accent : c.textPrimary,
                    borderRadius: BorderRadius.circular(5)),
                ),
            ]),
          ])),
      ],
    );
  }
}
