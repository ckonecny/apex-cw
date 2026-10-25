import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/cw_content.dart';

void main() {
  test('M32 carries the six prosigns where the firmware puts them (#72)', () {
    expect(kochSeqM32.length, 51);
    expect(kochSeqM32.where(isProsignToken).toSet(),
        {'SK', 'AS', 'KN', 'KA', 'VE', 'BK'});
    expect(kochSeqM32.sublist(40),
        ['-', '=', 'SK', '+', 'AS', 'KN', 'KA', 'VE', 'BK', '@', ':']);
  });

  test('LCWO is the original course: no prosigns, no extras', () {
    expect(kochSeqLcwo.length, 41);
    expect(kochSeqLcwo.where(isProsignToken), isEmpty);
    expect(kochSeqLcwo.last, 'X');
    expect(kochSeqLcwo.take(5), ['K', 'M', 'U', 'R', 'E']);
  });

  test('CW Academy ends with the curriculum: X Z . BK SK, nothing after', () {
    expect(kochSeqCwAcademy.length, 44);
    expect(kochSeqCwAcademy.where(isProsignToken).toSet(), {'SK', 'BK'});
    expect(kochSeqCwAcademy.sublist(39),
        ['X', 'Z', 'BK', 'SK', '.']);
  });

  test('LICW carousel: BC1 entries are the 18 BC1 characters, BC2 all 44', () {
    final bc1 = licwCarouselChars(0);
    expect(bc1.take(6), ['R', 'E', 'A', 'T', 'I', 'N']);
    expect(bc1.where(isProsignToken), isEmpty);
    for (var s = 0; s <= 13; s++) {
      final c = licwCarouselChars(s);
      final n = s < 6 ? 18 : 44;
      expect(c.length, n, reason: 'entry point $s');
      expect(c.toSet().length, n, reason: 'entry point $s');
    }
    expect(licwCarouselChars(6).where(isProsignToken).toSet(), {'SK', 'BK'});
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
