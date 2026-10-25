import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/charset_content.dart';
import 'package:next_cw_trainer/content/cw_content.dart';
import 'package:next_cw_trainer/ui/widgets/char_playback_overlay.dart' show morsePattern;

void main() {
  test('all ten prosigns have a code and a glyph that round-trips', () {
    expect(kProsignTokens.length, 10);
    expect(kProsignCodes.keys.toSet(), kProsignTokens.toSet());
    for (final t in kProsignTokens) {
      final g = keyGlyph(t);
      expect(g.length, 1, reason: t);
      expect(isProsignGlyph(g), isTrue, reason: t);
      expect(glyphToken(g), t);
      expect(glyphsToPlayText(prosignsToGlyphs('A<$t>B')), 'A<$t>B');
      expect(morsePattern(t), kProsignCodes[t]);
    }
  });

  test('AR and BT are the codes of + and =', () {
    expect(kProsignCodes['AR'], '.-.-.');
    expect(kProsignCodes['BT'], '-...-');
    expect(morsePattern('+'), kProsignCodes['AR']);
    expect(morsePattern('='), kProsignCodes['BT']);
  });

  test('Practice set and Custom input take the new prosigns in brackets', () {
    expect(parseCharTokens('<ar><sos>e<hh>'), ['AR', 'SOS', 'E', 'HH']);
    expect(parseCharTokens('SOS'), ['S', 'O']);
    expect(joinCharTokens(['AR', 'SOS', 'E']), '<AR><SOS>E');
  });

  test('Prosign set sits between All characters and Practice set', () {
    expect(charSetOrder,
        [CharSet.koch, CharSet.all, CharSet.prosigns, CharSet.practice]);
    // Stored indexes of the older sets stay as they were.
    expect(CharSet.koch.index, 0);
    expect(CharSet.all.index, 1);
    expect(CharSet.practice.index, 2);
    expect(CharSet.prosigns.index, 3);
  });

  test('Prosign set plays through the practice-set mode, random only', () {
    final e = engineSelection(CharSet.prosigns, ContentKind.words);
    expect(e.mode, 4);
    expect(e.kochActive, isFalse);
    expect(allowedContents(CharSet.prosigns), [ContentKind.random]);
  });

  test('the engine draws from the prosigns, not the saved practice set', () {
    expect(effectivePracticeChars(CharSet.prosigns, 'abc'), kProsignTokens);
    expect(effectivePracticeChars(CharSet.practice, 'a<KA>'), ['A', 'KA']);
    // Keyed answers: no HH (the erase sign) and no SOS (no keyer code).
    final keyed = prosignSetTokens(keyed: true);
    expect(keyed, ['AS', 'KA', 'KN', 'SK', 'VE', 'BK', 'AR', 'BT']);
  });
}
