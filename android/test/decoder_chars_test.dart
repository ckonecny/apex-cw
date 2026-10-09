// Decoder Chars (issue #52): the table of the issue, per character set.
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/keyer/decoder_chars.dart';
import 'package:next_cw_trainer/keyer/morse_decoder.dart';

String decode(String pattern, DecoderChars set) {
  final out = <String>[];
  final d = MorseDecoder(onChar: out.add, chars: set);
  for (final s in pattern.split('')) {
    d.add(s == '.' ? '·' : '—');
  }
  d.add(' ');
  return out.join();
}

void main() {
  // pattern → [Standard, ITU, Fr/Es/Pt, Sv/Fi, Da/No]
  const table = {
    '.--.-':  ['*', '*', 'À', 'Å', 'Å'],
    '.-.-':   ['Ä', 'Ä', 'Ä', 'Ä', 'Æ'],
    '---.':   ['Ö', 'Ö', 'Ö', 'Ö', 'Ø'],
    '-.--.':  ['KN', '(', 'KN', 'KN', 'KN'],
    '-.--.-': ['*', ')', '*', '*', '*'],
    '..-..':  ['*', 'É', 'É', '*', '*'],
    '.-..-':  ['*', '*', 'È', '*', '*'],
    '-.-..':  ['*', '*', 'Ç', '*', '*'],
    '--.--':  ['*', '*', 'Ñ', '*', '*'],
    '..--':   ['Ü', 'Ü', 'Ü', 'Ü', 'Ü'],   // the same in every set
  };

  for (final e in table.entries) {
    for (final set in DecoderChars.values) {
      test('${e.key} in ${set.name}', () {
        expect(decode(e.key, set), e.value[set.index]);
      });
    }
  }

  test('Standard is the default', () {
    final d = MorseDecoder(onChar: (_) {});
    expect(d.chars, DecoderChars.standard);
  });
}
