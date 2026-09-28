import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/adventure/cw_text.dart';

void main() {
  const room = 'West of House\n'
      'You are standing in an open field west of a white house, with a boarded front door.\n'
      'There is a small mailbox here.';

  test('audio replaces only what the CW engine cannot play', () {
    expect(cwWord("don't"), 'DONT');
    expect(cwWord('"WELCOME'), 'WELCOME');
    expect(cwWord('ZORK!'), 'ZORK.');
    expect(cwWord('B;'), 'B,');
    expect(cwWord('(Taken)'), 'TAKEN');
    expect(cwWord('***'), '');
    expect(cwWord('&'), 'AND');
    expect(cwWord('FCD#3'), 'FCD3');
    expect(cwWord('a/b-c=d+e@f:g?'), 'A/B-C=D+E@F:G?');
  });

  test('display keeps the original words', () {
    final p = Passage.parse('"WELCOME TO ZORK!', scope: CwScope.all);
    expect(p.words.map((w) => w.display), ['"WELCOME', 'TO', 'ZORK!']);
    expect(p.audioFrom(0).$1, 'WELCOME TO ZORK.');
  });

  test('scope all plays everything, paragraphs get a double gap', () {
    final p = Passage.parse('One two.\n\nThree.', scope: CwScope.all);
    expect(p.audioFrom(0).$1, 'ONE TWO.  THREE.');
    expect(p.audioFrom(0).$2, [0, 1, 2]);
  });

  test('first sentence includes the room name line', () {
    final p = Passage.parse(room, scope: CwScope.firstSentence, roomName: 'West of House');
    final (text, _) = p.audioFrom(0);
    expect(text, 'WEST OF HOUSE YOU ARE STANDING IN AN OPEN FIELD WEST OF A WHITE HOUSE, '
        'WITH A BOARDED FRONT DOOR.');
    expect(p.words.last.inScope, isFalse);
  });

  test('room-or-message: a room plays only its name, a message its first sentence', () {
    final r = Passage.parse(room, scope: CwScope.roomOrMessage, roomName: 'West of House');
    expect(r.audioFrom(0).$1, 'WEST OF HOUSE');
    final m = Passage.parse('Opening the small mailbox reveals a leaflet. Nice.',
        scope: CwScope.roomOrMessage, roomName: 'West of House');
    expect(m.audioFrom(0).$1, 'OPENING THE SMALL MAILBOX REVEALS A LEAFLET.');
  });

  test('replay from a word and from the last sentence', () {
    final p = Passage.parse('A b. C d. E f.', scope: CwScope.all);
    expect(p.audioFrom(2).$1, 'C D. E F.');
    expect(p.lastSentenceStart(), 4);
    expect(p.sentenceStart(3), 2);
    expect(p.sentenceStart(0), 0);
  });

  test('words without anything playable are skipped in the audio', () {
    final p = Passage.parse('*** You have died ***', scope: CwScope.all);
    expect(p.audioFrom(0).$1, 'YOU HAVE DIED');
    expect(p.audioFrom(0).$2, [1, 2, 3]);
  });
}
