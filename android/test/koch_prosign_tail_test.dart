import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/cw_content.dart';

void main() {
  test('M32, LCWO and CW Academy sequences carry the six prosigns (#72)', () {
    for (final seq in [kochSeqM32, kochSeqLcwo, kochSeqCwAcademy]) {
      expect(seq.length, 51);
      expect(seq.where(isProsignToken).toSet(),
          {'SK', 'AS', 'KN', 'KA', 'VE', 'BK'});
      expect(seq.where((t) => !isProsignToken(t)).length, 45);
    }
  });

  test('prosigns sit where the firmware puts them', () {
    expect(kochSeqM32.sublist(40),
        ['-', '=', 'SK', '+', 'AS', 'KN', 'KA', 'VE', 'BK', '@', ':']);
    expect(kochSeqLcwo.sublist(41),
        ['-', 'SK', '+', 'KA', 'AS', 'KN', 'VE', 'BK', '@', ':']);
    expect(kochSeqCwAcademy.sublist(40),
        ['Z', 'BK', 'SK', '.', '-', 'KA', 'AS', 'KN', 'VE', '@', ':']);
  });

  test('LICW carousel keeps the prosigns inside its window', () {
    final bc1 = licwCarouselChars(0);
    expect(bc1.where(isProsignToken), isEmpty);
    final bc2 = licwCarouselChars(6);
    expect(bc2.where(isProsignToken).toSet(), {'SK', 'BK'});
    expect(bc2.sublist(bc2.length - 3), ['-', '@', ':']);
  });

  test('a prosign goes to the generator bracketed', () {
    expect(kochPlayText('KA'), '<KA>');
    expect(kochPlayText('k'), 'K');
  });

  test('prosigns in Custom/Practice input are typed in angle brackets (#72)', () {
    expect(parseCharTokens('es<KA>n<sk>t'), ['E', 'S', 'KA', 'N', 'SK', 'T']);
    expect(parseCharTokens('KA'), ['K', 'A']);
    expect(parseCharTokens('<KA><KA>e<KA'), ['KA', 'E', 'K', 'A']);
    expect(joinCharTokens(parseCharTokens('a<ve>b')), 'A<VE>B');
    expect(kochSequenceChars(4, 'e<BK>t'), ['E', 'BK', 'T']);
  });

  test('a prosign in a Listen group is one glyph and plays bracketed', () {
    final g = prosignsToGlyphs('AB<KA>C');
    expect(g.length, 4);
    expect(isProsignGlyph(g[2]), isTrue);
    expect(glyphToken(g[2]), 'KA');
    expect(glyphsToPlayText(g), 'AB<KA>C');
    expect(keyGlyph('KA'), g[2]);
    expect(keyGlyph('A'), 'A');
  });
}
