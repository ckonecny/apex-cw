// Own texts (issue #8): a pasted text split into words, with what the CW
// engine plays for each. The screen always shows the original text; only the
// audio is flattened to what Morse has (DECISIONS.md "Own texts").
//
// Deliberately separate from the text adventure's Passage (issue #23 tracks
// merging the two later).

/// Longest text accepted, in characters.
const maxTextChars = 20000;

class TextWord {
  /// As shown, e.g. `Größe,`.
  final String display;
  /// As played, e.g. `GROESSE,`; prosigns as `<KA>`; empty = nothing to play.
  final String cw;
  /// Number of characters the engine reports for [cw] (a prosign counts one).
  final int tokens;
  /// Line (paragraph) index.
  final int line;
  final bool endsSentence;
  const TextWord(this.display, this.cw, this.tokens, this.line, this.endsSentence);
}

class TextPassage {
  final List<TextWord> words;
  /// Indices of the words that are played, in order.
  final List<int> played;
  TextPassage._(this.words) : played = [
        for (var i = 0; i < words.length; i++)
          if (words[i].cw.isNotEmpty) i
      ];

  bool get hasAudio => played.isNotEmpty;

  /// Text for CwGenerator.playOne, played words [from] to [to] (inclusive,
  /// default to the end); a paragraph break becomes a double word gap. Also
  /// returns the played word indices, to map the engine's char events back.
  (String, List<int>) audioFrom(int from, [int? to]) {
    final sb = StringBuffer();
    final order = <int>[];
    int? lastLine;
    for (final i in played) {
      if (i < from) continue;
      if (to != null && i > to) break;
      final w = words[i];
      if (sb.isNotEmpty) {
        sb.write(' ');
        if (lastLine != null && w.line - lastLine > 1) sb.write(' ');
      }
      sb.write(w.cw);
      order.add(i);
      lastLine = w.line;
    }
    return (sb.toString(), order);
  }

  /// First played word at or after [i]; the last one if there is none.
  int playableFrom(int i) {
    for (final j in played) {
      if (j >= i) return j;
    }
    return played.isEmpty ? 0 : played.last;
  }

  /// Last played word before [i], or null.
  int? playableBefore(int i) {
    int? r;
    for (final j in played) {
      if (j >= i) break;
      r = j;
    }
    return r;
  }

  /// First word of the sentence containing word [i].
  int sentenceStart(int i) {
    var start = played.isEmpty ? 0 : played.first;
    for (final j in played) {
      if (j >= i) break;
      if (words[j].endsSentence) start = j + 1;
    }
    return playableFrom(start);
  }

  /// Last word of the sentence containing word [i].
  int sentenceEnd(int i) {
    for (final j in played) {
      if (j >= i && words[j].endsSentence) return j;
    }
    return played.isEmpty ? i : played.last;
  }

  /// First word of the sentence after the one containing [i], or null.
  int? nextSentenceStart(int i) {
    final e = sentenceEnd(i);
    for (final j in played) {
      if (j > e) return j;
    }
    return null;
  }

  static TextPassage parse(String text) {
    final lines = _normalise(text).split('\n');
    final words = <TextWord>[];
    for (var l = 0; l < lines.length; l++) {
      for (final w in lines[l].split(' ')) {
        if (w.isEmpty) continue;
        final (cw, tokens) = flattenWord(w);
        words.add(TextWord(w, cw, tokens, l, _endsSentence(w)));
      }
    }
    return TextPassage._(words);
  }

  /// Unified line breaks and blanks; at most one empty line in a row.
  static String _normalise(String text) {
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    t = t.replaceAll(RegExp(r'[\t ​]'), ' ');
    t = t.split('\n').map((l) => l.trim()).join('\n');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  static bool _endsSentence(String w) {
    final t = w.replaceAll(RegExp('["\')\\]»“”’]+\$'), '');
    return t.endsWith('.') || t.endsWith('!') || t.endsWith('?') || t.endsWith('…');
  }
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
