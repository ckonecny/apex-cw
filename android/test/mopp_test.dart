import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/net/mopp.dart';

void main() {
  test('PARIS @16 WPM matches the protocol document example', () {
    final enc = MoppEncoder();
    final pkts = enc.encodeText('PARIS', 16);
    expect(pkts.length, 1);
    final p = pkts.first;
    // Serial is random: compare everything but the low 6 bits of byte 0.
    expect(p[0] & 0xC0, 0x40);
    expect(p.sublist(1), [0x41, 0xA4, 0x61, 0x91, 0x45, 0x70]);
  });

  test('decode reverses encode', () {
    final enc = MoppEncoder();
    for (final t in ['PARIS', 'E', 'T', 'CQ', 'DE', '73', ':HI', 'A1B2C3']) {
      final p = decodeMopp(enc.encodeText(t, 22).first)!;
      expect(p.text, t, reason: t);
      expect(p.wpm, 22);
    }
  });

  test('keyed element stream matches text encoder', () {
    final a = MoppEncoder(), b = MoppEncoder();
    // "AB" as the keyer emits it: elements, char gap after each char, then word gap.
    for (final e in [1, 2, 0, 2, 1, 1, 1, 0]) {
      expect(a.element(e, 20), isNull);
    }
    final keyed = a.element(3, 20)!;
    final typed = b.encodeText('AB', 20).first;
    expect(keyed.sublist(1), typed.sublist(1));
  });

  test('word ending on a byte boundary still decodes', () {
    final enc = MoppEncoder();
    for (final t in ['S', 'EE', 'IS', 'EEE', 'TTTT', 'OK']) {
      final p = decodeMopp(enc.encodeText(t, 20).first)!;
      expect(p.text, t, reason: t);
    }
  });

  test('rejects what the firmware rejects', () {
    expect(decodeMopp(Uint8List.fromList([0x00, 0x51])), isNull); // version
    expect(decodeMopp(Uint8List.fromList([0x41, 0x11])), isNull); // wpm 4
    expect(decodeMopp(Uint8List.fromList([0x41, 0x50])), isNull); // 1st el 00
    expect(decodeMopp(Uint8List(0)), isNull);
  });
}
