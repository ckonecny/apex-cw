// MorseDecoder: unknown patterns, <err> and the firmware's extra characters
// (issue #37).
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/keyer/morse_decoder.dart';

String decode(String pattern, {String? unknown}) {
  final out = <String>[];
  final d = unknown == null
      ? MorseDecoder(onChar: out.add)
      : MorseDecoder(onChar: out.add, unknown: unknown);
  for (final s in pattern.split('')) {
    d.add(s == '.' ? '·' : '—');
  }
  d.add(' ');
  return out.join();
}

void main() {
  test('invalid pattern shows * like the firmware, the real ? stays ?', () {
    expect(decode('-----.'), '*');
    expect(decode('--.--'), '*');
    expect(decode('......'), '*');
    expect(decode('..--..'), '?');
  });

  test('seven or more dits are <err>', () {
    expect(decode('.......'), MorseDecoder.err);
    expect(decode('........'), MorseDecoder.err);
  });

  test("firmware's German characters and extra punctuation decode", () {
    expect(decode('.-.-'), 'Ä');
    expect(decode('---.'), 'Ö');
    expect(decode('..--'), 'Ü');
    expect(decode('----'), 'CH');
    expect(decode('-.-.-.'), ';');
    expect(decode('-.-.--'), '!');
    expect(decode('.-..-.'), '"');
    expect(decode('.----.'), "'");
  });
}
