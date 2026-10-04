// Prints sample rounds as Markdown: dart run test/content/head_copy_samples_tool.dart > out.md
import 'dart:io';
import 'dart:math';

import 'package:next_cw_trainer/content/head_copy_data.dart';
import 'package:next_cw_trainer/content/head_copy_engine.dart';

void main() {
  final out = StringBuffer('# Head copy: 20 samples from the engine\n');
  var n = 0;
  for (final (content, label) in [(deContent, 'Deutsch'), (enContent, 'English')]) {
    final engine = HeadCopyEngine(content, rng: Random(content.code == 'de' ? 7 : 8));
    for (var i = 0; i < 10; i++) {
      final level = 1 + i % 3;
      final round = engine.newRound(level);
      n++;
      out.writeln('\n## $n. $label, level $level\n');
      for (final s in round.sentences) {
        out.writeln('- Played: ${s.text}  (CW: `${s.cwText}`)');
      }
      for (final q in round.questions) {
        out.writeln('\n**${round.sentences.length > 1 ? 'Satz ${q.sentence + 1}: ' : ''}${q.prompt}**');
        for (var k = 0; k < q.options.length; k++) {
          out.writeln('${k == q.correct ? '- [x]' : '- [ ]'} ${q.options[k]}');
        }
      }
    }
  }
  stdout.write(out);
}
