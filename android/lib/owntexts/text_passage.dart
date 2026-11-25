// Own texts (issue #8): a pasted text split into words, with what the CW
// engine plays for each. The screen always shows the original text; only the
// audio is flattened to what Morse has (DECISIONS.md "Own texts").
//
// Split and navigated by the shared Passage (content/passage.dart, #23);
// only the word mapping and sentence ends are own-text specific.

import '../content/passage.dart';

export '../content/passage.dart';

/// Longest text accepted, in characters.
const maxTextChars = 20000;

/// A pasted text as a [Passage]: line breaks and blanks unified first, at
/// most one empty line in a row.
Passage parseOwnText(String text) => Passage([
      for (final (w, line) in splitWords(_normalise(text)))
        if (flattenWord(w) case (final cw, final tokens))
          PassageWord(w, cw, tokens, line, _endsSentence(w)),
    ]);

String _normalise(String text) {
  var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = t.replaceAll(RegExp(r'[\t ​]'), ' ');
  t = t.split('\n').map((l) => l.trim()).join('\n');
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

bool _endsSentence(String w) {
  final t = w.replaceAll(RegExp('["\')\\]»“”’]+\$'), '');
  return t.endsWith('.') || t.endsWith('!') || t.endsWith('?') || t.endsWith('…');
}

const _prosigns = {'AR', 'SK', 'KN', 'KA', 'BT', 'AS', 'VE', 'BK', 'HH'};
const _prosignAlias = {'CT': 'KA'};
final _prosignToken = RegExp(r'[<\[]([A-Za-z]{2})[>\]]');

/// What the engine can play (CwGenerator.kt morseTable).
const _playable = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,?/-=+@:';

/// Characters Morse has no sign for, and their closest plain version.
const _flatten = {
  'Ä': 'AE', 'Ö': 'OE', 'Ü': 'UE', 'ẞ': 'SS', 'ß': 'SS', 'Æ': 'AE', 'Œ': 'OE',
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Å': 'A', 'Ā': 'A', 'Ą': 'A',
  'Ç': 'C', 'Ć': 'C', 'Č': 'C', 'Ď': 'D', 'Đ': 'D',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ē': 'E', 'Ę': 'E', 'Ě': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'İ': 'I',
  'Ł': 'L', 'Ĺ': 'L', 'Ľ': 'L', 'Ñ': 'N', 'Ń': 'N', 'Ň': 'N',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ø': 'O', 'Ő': 'O',
  'Ř': 'R', 'Ś': 'S', 'Š': 'S', 'Ş': 'S', 'Ť': 'T',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ů': 'U', 'Ű': 'U',
  'Ý': 'Y', 'Ÿ': 'Y', 'Ź': 'Z', 'Ż': 'Z', 'Ž': 'Z',
  '!': '.', ';': ',', '&': 'AND', '…': '.',
  '–': '-', '—': '-', '‑': '-', '−': '-',
};

/// One shown word as played, and the number of characters the engine will
/// report for it. Upper case; Ä→AE, Ö→OE, Ü→UE, ß→SS, accents dropped,
/// `!`→`.`, `;`→`,`, `&`→AND, dashes→`-` (a dash standing alone is dropped); prosigns written `<KA>` or `[KA]`
/// are kept; anything else Morse can't play is dropped.
(String, int) flattenWord(String word) {
  // A dash standing alone between spaces is punctuation, not a hyphen.
  if (RegExp(r'^[-–—‑−]+$').hasMatch(word)) return ('', 0);
  final sb = StringBuffer();
  var tokens = 0;
  void plain(String s) {
    for (final r in s.toUpperCase().runes) {
      final ch = String.fromCharCode(r);
      final mapped = _flatten[ch] ?? ch;
      for (final m in mapped.split('')) {
        if (_playable.contains(m)) {
          sb.write(m);
          tokens++;
        }
      }
    }
  }

  var last = 0;
  for (final m in _prosignToken.allMatches(word)) {
    var name = m.group(1)!.toUpperCase();
    name = _prosignAlias[name] ?? name;
    if (!_prosigns.contains(name)) continue;
    plain(word.substring(last, m.start));
    sb.write('<$name>');
    tokens++;
    last = m.end;
  }
  plain(word.substring(last));
  return (sb.toString(), tokens);
}
