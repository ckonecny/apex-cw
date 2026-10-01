import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/owntexts/text_passage.dart';

void main() {
  test('flattens umlauts, accents, punctuation for the audio only', () {
    expect(flattenWord('Größe,').$1, 'GROESSE,');
    expect(flattenWord('Über').$1, 'UEBER');
    expect(flattenWord('café').$1, 'CAFE');
    expect(flattenWord('Hallo!').$1, 'HALLO.');
    expect(flattenWord('„Ja“').$1, 'JA');
    expect(flattenWord('a–b').$1, 'A-B');
    expect(flattenWord('—').$1, '');
  });

  test('prosigns in brackets are kept and count as one character', () {
    final (cw, tokens) = flattenWord('<ka>');
    expect(cw, '<KA>');
    expect(tokens, 1);
    expect(flattenWord('[sk]').$1, '<SK>');
    expect(flattenWord('<ct>').$1, '<KA>');
    // Not a prosign: the letters are played as they are.
    expect(flattenWord('<xx>').$1, 'XX');
    expect(flattenWord('73<sk>').$2, 3);
  });

  test('splits words, sentences and paragraphs', () {
    final p = TextPassage.parse('Hello world. How are you?\n\n\n\nFine, thanks! — ok');
    expect(p.words.map((w) => w.display).toList(),
        ['Hello', 'world.', 'How', 'are', 'you?', 'Fine,', 'thanks!', '—', 'ok']);
    expect(p.words[5].line - p.words[4].line, 2); // one blank line kept
    expect(p.played.contains(7), isFalse); // the dash is not played
    expect(p.sentenceStart(3), 0 + 2);
    expect(p.sentenceEnd(3), 4);
    expect(p.sentenceStart(0), 0);
    expect(p.nextSentenceStart(0), 2);
    expect(p.nextSentenceStart(5), 8);
    final (text, order) = p.audioFrom(4, 6);
    expect(text, 'YOU?  FINE, THANKS.');
    expect(order, [4, 5, 6]);
  });
}
