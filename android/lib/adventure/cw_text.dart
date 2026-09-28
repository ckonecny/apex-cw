// Game text -> what the CW engine plays (DECISIONS.md "Text adventure").
//
// The screen always shows the game's original text. Only the audio is
// adapted: CwGenerator.kt knows letters, digits and . , ? / - = + @ : —
// everything else is replaced or dropped here, before playOne(). Each shown
// word keeps its index, so the screen can highlight the word being played
// and replay from any word.

/// How much of an answer is played ("CW-Umfang").
enum CwScope {
  /// Everything.
  all,
  /// Up to the end of the first sentence (a leading room name included).
  firstSentence,
  /// Room name only when the answer describes a room, otherwise the first
  /// sentence.
  roomOrMessage,
}

class PassageWord {
  /// As shown, e.g. `"WELCOME` or `door.`
  final String display;
  /// As played, e.g. `WELCOME` or `DOOR.`; empty = nothing to play.
  final String cw;
  /// Line index in the passage (for layout).
  final int line;
  /// Part of the played range for the chosen [CwScope].
  final bool inScope;
  /// Last word of a sentence (for "repeat the last sentence").
  final bool endsSentence;
  const PassageWord(this.display, this.cw, this.line, this.inScope, this.endsSentence);
}

/// One game answer, split into words.
class Passage {
  final List<PassageWord> words;
  /// Number of lines (blank lines included, so paragraphs stay visible).
  final int lineCount;
  Passage._(this.words, this.lineCount);

  /// Indices of the words that are played, in order.
  List<int> get playedIndices => [
        for (var i = 0; i < words.length; i++)
          if (words[i].inScope && words[i].cw.isNotEmpty) i
      ];

  bool get hasAudio => playedIndices.isNotEmpty;

  /// Text for CwGenerator.playOne, words [from] to [to] (inclusive; default
  /// to the end). Paragraph breaks become a double word gap. Returns the
  /// played word indices in the same order, so onChar events can be mapped
  /// back to words.
  (String, List<int>) audioFrom(int from, [int? to]) {
    final sb = StringBuffer();
    final order = <int>[];
    int? lastLine;
    for (final i in playedIndices) {
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

  /// First word of the sentence containing word [i] (among played words).
  int sentenceStart(int i) {
    final played = playedIndices;
    var start = played.isEmpty ? 0 : played.first;
    for (final j in played) {
      if (j >= i) break;
      if (words[j].endsSentence) start = j + 1;
    }
    return start;
  }

  /// Last word of the sentence containing word [i] (among played words).
  int sentenceEnd(int i) {
    final played = playedIndices;
    for (final j in played) {
      if (j >= i && words[j].endsSentence) return j;
    }
    return played.isEmpty ? i : played.last;
  }

  /// Start of the last played sentence.
  int lastSentenceStart() {
    final played = playedIndices;
    if (played.isEmpty) return 0;
    return sentenceStart(played.last);
  }

  static Passage parse(String text, {required CwScope scope, String? roomName}) {
    final lines = text.split('\n');
    final raw = <(String, int)>[];
    for (var l = 0; l < lines.length; l++) {
      for (final w in lines[l].split(' ')) {
        if (w.isNotEmpty) raw.add((w, l));
      }
    }
    final ends = [for (final (w, _) in raw) _endsSentence(w)];

    // Last word index (inclusive) that is played.
    var limit = raw.length - 1;
    if (scope != CwScope.all && raw.isNotEmpty) {
      final firstLine = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
      final isRoom = roomName != null && roomName.isNotEmpty && firstLine == roomName;
      if (scope == CwScope.roomOrMessage && isRoom) {
        limit = raw.lastIndexWhere((e) => e.$2 == raw.first.$2);
      } else {
        // A room name line has no full stop; the sentence after it counts.
        final start = isRoom ? raw.lastIndexWhere((e) => e.$2 == raw.first.$2) + 1 : 0;
        final end = ends.indexWhere((e) => e, start);
        limit = end < 0 ? raw.length - 1 : end;
      }
    }
    return Passage._([
      for (var i = 0; i < raw.length; i++)
        PassageWord(raw[i].$1, cwWord(raw[i].$1), raw[i].$2, i <= limit, ends[i]),
    ], lines.length);
  }

  static bool _endsSentence(String w) {
    final t = w.replaceAll(RegExp(r'''["')\]]+$'''), '');
    return t.endsWith('.') || t.endsWith('!') || t.endsWith('?');
  }
}

/// One shown word as played: upper case, `!` → `.`, `;` → `,`, `&` → AND,
/// anything the CW engine can't play dropped (`' " ( ) [ ] * #` …).
String cwWord(String word) {
  final sb = StringBuffer();
  for (final ch in word.toUpperCase().split('')) {
    switch (ch) {
      case '!':
        sb.write('.');
      case ';':
        sb.write(',');
      case '&':
        sb.write('AND');
      default:
        if (_playable.contains(ch)) sb.write(ch);
    }
  }
  return sb.toString();
}

const _playable = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,?/-=+@:';
