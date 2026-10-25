// Koch character order and content helpers (mirrors CwGenerator.kt).
//
// Koch Sequence: the M32/LCWO/CW Academy/LICW orders below come from the
// firmware's own strings (MorsePreferences.h: morserinoKochChars/lcwoKochChars/
// cwacKochChars/licwAllKochChars), tokenised by [_kochTokens] — prosigns are
// marked with upper-case letters there. M32 is the firmware's order as is
// (51 steps). LCWO, CW Academy and LICW are cut back to the original
// course: the firmware appends its own tail (`- SK + AS KN VE BK @ :` etc.)
// that none of those courses teaches (docs/DECISIONS.md). A lesson step is
// one token, so a prosign is a two-letter entry ('KA', rule 3 in CLAUDE.md)
// in a list of single characters.

// Firmware marker letter -> prosign (m32_v6.ino CWchars: S=<as>, A=<ka>,
// N=<kn>, K=<sk>, E=<ve>, B=<bk>).
const _prosignMarker = {
  'S': 'AS', 'A': 'KA', 'N': 'KN', 'K': 'SK', 'E': 'VE', 'B': 'BK',
};

List<String> _kochTokens(String fw) => [
  for (final c in fw.split(''))
    _prosignMarker[c] ?? c.toUpperCase(),
];

/// True for a lesson token that is a prosign ('KA', ...), not one character.
bool isProsignToken(String t) => t.length > 1;

/// How a lesson token goes to the native generator: prosigns bracketed
/// (`<KA>`), because a bare letter pair would play as two letters.
String kochPlayText(String t) => t.length > 1 ? '<${t.toUpperCase()}>' : t.toUpperCase();

final kochSeqM32 = _kochTokens('mkrsuaptlowi.njef0yv,g5/q9zh38b?427c1d6x-=K+SNAEB@:');
// lcwo.net: 40 lessons, 41 characters (lesson 1 is K M); letters, digits and
// . , ? = / only.
final kochSeqLcwo = _kochTokens('kmuresnaptlwi.jz=foy,vg5/q92h38b?47c1d60x');
// CW Academy beginner curriculum, sessions 1-10: + is <AR>, = is <BT>.
final kochSeqCwAcademy = _kochTokens('teanois14rhdl25ucmw36?fy,pgq79/bv+kj80=xzBK.');

// The 44 LICW characters (BC1 + BC2; MorsePreferences.h's licwAllKochChars
// without the firmware's own tail), the basis for the carousel rotation below.
// + is <AR>, = is <BT>.
const _licwAllKochChars = 'reatinpgslcdhofuwbkmy59,qxv73?+K=16.zj/28B40';

// LICW Carousel "Entry Point" (posCarouselStart, 0-13): ports
// Koch::setupLICWkochChars() exactly — start<6 rotates an 18-char "BC1"
// window, start>=6 rotates the full 44-char "BC2" window, by character index
// over the string with its prosign markers (so the BC2 window carries <sk>
// and <bk>, like the firmware's).
List<String> licwCarouselChars(int start) {
  final all = _kochTokens(_licwAllKochChars);
  final s = start.clamp(0, 13);
  final out = <String>[];
  if (s < 6) {
    final segLen = 18 - 3 * s;
    out.addAll(all.sublist(3 * s, 3 * s + segLen));
    if (s > 0) out.addAll(all.sublist(0, 3 * s));
  } else {
    out.addAll(all.sublist(0, 18));
    final segLen = 44 - 3 * s;
    out.addAll(all.sublist(3 * s, 3 * s + segLen));
    if (s > 6) out.addAll(all.sublist(18, 18 + (3 * s - 18)));
  }
  return out;
}

// seq: 0=M32, 1=LCWO, 2=CW Academy, 3=LICW, 4=Custom (matches M32 "Koch Sequence")
// licwCarouselStart: "LICW Carousel" entry point (0-13), only meaningful for seq=3.
List<String> kochSequenceChars(int seq, String customChars, {int licwCarouselStart = 0}) {
  switch (seq) {
    case 1: return kochSeqLcwo;
    case 2: return kochSeqCwAcademy;
    case 3: return licwCarouselChars(licwCarouselStart);
    case 4:
      final out = parseCharTokens(customChars);
      return out.isEmpty ? kochSeqM32 : out;
    default: return kochSeqM32;
  }
}

// Backward-compatible default (M32 native order) for call sites that don't
// yet carry a Koch Sequence preference of their own.
final kochChars = kochSeqM32;

// Returns the active character set for a given Koch level (2-based).
List<String> kochActiveChars(int level, [List<String>? sequence]) {
  final seq = sequence ?? kochChars;
  return seq.take(level.clamp(2, seq.length)).toList();
}

// Parses a user-entered character string (Custom Koch chars, Practice Set)
// into an ordered, de-duplicated token list. A prosign is typed in angle
// brackets, `<KA>` (CLAUDE.md rule 3); anything else is one character per
// token, upper-cased. Whitespace is ignored.
/// Every prosign the app knows, in the order shown (Prosign set, keyboard,
/// chart, tree). AR and BT are the same signals as `+` and `=` (the decoder
/// reports those as `+`/`=`); HH is the error sign (the decoder's `<err>`).
const kProsignTokens = ['AS', 'KA', 'KN', 'SK', 'VE', 'BK', 'AR', 'BT', 'HH', 'SOS'];

/// Dit/dah code of each prosign (CwGenerator.kt morseTable).
const kProsignCodes = {
  'AS': '.-...', 'KA': '-.-.-', 'KN': '-.--.', 'SK': '...-.-', 'VE': '...-.',
  'BK': '-...-.-', 'AR': '.-.-.', 'BT': '-...-', 'HH': '........',
  'SOS': '...---...',
};

final _prosignAlt = kProsignTokens.join('|');
final _prosignInput = RegExp('<($_prosignAlt)>', caseSensitive: false);

List<String> parseCharTokens(String input) {
  final seen = <String>{};
  final out = <String>[];
  var i = 0;
  while (i < input.length) {
    final m = _prosignInput.matchAsPrefix(input, i);
    final String t;
    if (m != null) {
      t = m.group(1)!.toUpperCase();
      i = m.end;
    } else {
      t = input[i].toUpperCase();
      i++;
    }
    if (t.trim().isEmpty || t == '<' || t == '>') continue;   // half-typed <KA
    if (seen.add(t)) out.add(t);
  }
  return out;
}

/// Inverse of [parseCharTokens]: prosign tokens bracketed again.
String joinCharTokens(Iterable<String> tokens) =>
    tokens.map((t) => t.length > 1 ? '<$t>' : t).join();

// Practice Set: same rule as Koch's Custom Chars (order doesn't matter here,
// but duplicates would just skew nothing usefully).
List<String> parsePracticeChars(String input) => parseCharTokens(input);

// Hören's typing flow works per character (alignment, grading, cursor,
// backspace). So that a prosign stays ONE unit there, a group carries it as a
// single private-use code point; these map between that form, the token
// ('KA') and the text the generator plays ('<KA>').
const _prosignGlyph = {
  'AS': '\uE000', 'KA': '\uE001', 'KN': '\uE002',
  'SK': '\uE003', 'VE': '\uE004', 'BK': '\uE005',
  'AR': '\uE006', 'BT': '\uE007', 'HH': '\uE008', 'SOS': '\uE009',
};
final _glyphToken = {for (final e in _prosignGlyph.entries) e.value: e.key};

/// `AB<KA>C` -> `AB\uE001C`.
String prosignsToGlyphs(String s) =>
    s.replaceAllMapped(_prosignInput,
        (m) => _prosignGlyph[m.group(1)!.toUpperCase()]!);

/// `AB\uE001C` -> `AB<KA>C`, the text for the generator.
String glyphsToPlayText(String s) => s.split('').map((c) {
      final t = _glyphToken[c];
      return t == null ? c : '<$t>';
    }).join();

/// The lesson token of one character of a glyph string ('KA' for a prosign
/// glyph, otherwise the character itself).
String glyphToken(String ch) => _glyphToken[ch] ?? ch;

/// The glyph for a keyboard key: 'KA' -> prosign glyph, 'A' -> 'A'.
String keyGlyph(String k) => _prosignGlyph[k.toUpperCase()] ?? k;

bool isProsignGlyph(String ch) => _glyphToken.containsKey(ch);
