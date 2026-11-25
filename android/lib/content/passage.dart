// A text split into words for CW playback, shared by the text adventure and
// own texts (#23). The screen always shows the original words; each word
// carries what the CW engine plays for it, so the screen can highlight the
// word being played and replay from a word or a sentence.
//
// What a word plays as (and what ends a sentence) stays with each mode:
// `adventure/cw_text.dart` (game text, ASCII) and `owntexts/text_passage.dart`
// (pasted text: umlauts, accents, prosigns). DECISIONS.md "Passages".

class PassageWord {
  /// As shown, e.g. `"WELCOME` or `Größe,`.
  final String display;
  /// As played, e.g. `WELCOME` or `GROESSE,`; prosigns as `<KA>`; empty =
  /// nothing to play.
  final String cw;
  /// Number of characters the engine reports for [cw] (a prosign counts one).
  final int tokens;
  /// Line index in the text (paragraphs: a gap of more than one line).
  final int line;
  /// Last word of a sentence.
  final bool endsSentence;
  /// Part of the played range (the text adventure's CW scope).
  final bool inScope;
  const PassageWord(this.display, this.cw, this.tokens, this.line, this.endsSentence,
      {this.inScope = true});
}

/// The words of a text, split at blanks and line breaks, with their line index.
List<(String, int)> splitWords(String text) {
  final lines = text.split('\n');
  return [
    for (var l = 0; l < lines.length; l++)
      for (final w in lines[l].split(' '))
        if (w.isNotEmpty) (w, l),
  ];
}

class Passage {
  final List<PassageWord> words;
  /// Indices of the words that are played, in order.
  final List<int> played;
  Passage(this.words)
      : played = [
          for (var i = 0; i < words.length; i++)
            if (words[i].inScope && words[i].cw.isNotEmpty) i
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

  /// First played word of the sentence containing word [i].
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

  /// Start of the last played sentence.
  int lastSentenceStart() => played.isEmpty ? 0 : sentenceStart(played.last);
}
