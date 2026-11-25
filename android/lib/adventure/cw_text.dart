// Game text -> what the CW engine plays (DECISIONS.md "Text adventure").
//
// The screen always shows the game's original text. Only the audio is
// adapted: CwGenerator.kt knows letters, digits and . , ? / - = + @ : —
// everything else is replaced or dropped here, before playOne(). Each shown
// word keeps its index, so the screen can highlight the word being played
// and replay from any word (the shared Passage, content/passage.dart, #23).

import '../content/passage.dart';

export '../content/passage.dart';

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

/// One game answer as a [Passage]; words past the [scope] are shown but not
/// played. The text is taken as the game wrote it (no normalising), so line
/// indices and paragraph gaps stay the game's.
Passage parseAdventureText(String text, {required CwScope scope, String? roomName}) {
  final raw = splitWords(text);
  final ends = [for (final (w, _) in raw) _endsSentence(w)];

  // Last word index (inclusive) that is played.
  var limit = raw.length - 1;
  if (scope != CwScope.all && raw.isNotEmpty) {
    final firstLine =
        text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
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
  final words = <PassageWord>[];
  for (var i = 0; i < raw.length; i++) {
    final (w, line) = raw[i];
    final cw = cwWord(w);
    words.add(PassageWord(w, cw, cw.length, line, ends[i], inScope: i <= limit));
  }
  return Passage(words);
}

bool _endsSentence(String w) {
  final t = w.replaceAll(RegExp(r'''["')\]]+$'''), '');
  return t.endsWith('.') || t.endsWith('!') || t.endsWith('?');
}

/// One shown word as played: upper case, `!` → `.`, `;` → `,`, `&` → AND,
/// anything the CW engine can't play dropped (`' " ( ) [ ] * #` …). One
/// engine character per letter, so a word's token count is its length.
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
