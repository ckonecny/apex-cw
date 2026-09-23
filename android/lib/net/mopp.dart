// MOPP (Morse Code over Packet Protocol) v1 encoder/decoder.
//
// Encoder is a literal port of cwForTx() in m32_v6.ino (reference/ V9.0),
// decoder mirrors decodePacket()/onWifiReceive() there. One packet = one
// word. Elements are 2-bit pairs: 01 dit, 10 dah, 00 end-of-char, 11
// end-of-word. Header: 2 bit version (01) + 6 bit serial, then 6 bit WPM
// followed by the first element in the last 2 bits of byte 1.

import 'dart:math';
import 'dart:typed_data';
import '../keyer/morse_decoder.dart';

class MoppPacket {
  final int serial;
  final int wpm;
  final List<String> patterns; // one entry per character, e.g. ".-", "-..."
  const MoppPacket(this.serial, this.wpm, this.patterns);

  /// Text using the same table as the keyer decoder; unknown patterns → '*'.
  String get text =>
      patterns.map((p) => MorseDecoder.table[p] ?? '*').join();
}

class MoppEncoder {
  static const _bufSize = 80; // sizeof(cwTxBuffer) in the firmware
  final Uint8List _buf = Uint8List(_bufSize);
  int _pair = 0;
  int _serial = Random().nextInt(256);

  bool get hasPending => _pair != 0;

  void reset() => _pair = 0;

  /// element: 0 = end of char, 1 = dit, 2 = dah, 3 = end of word.
  /// Returns the finished packet on end-of-word, otherwise null.
  Uint8List? element(int element, int wpm) {
    if (_pair == 0) {
      _buf.fillRange(0, _bufSize, 0);
      _serial = (_serial + 1) & 0xFF;
      _buf[0] = (_serial % 64) + 1 * 64;
      _buf[1] |= (wpm * 4) & 0xFF;
      _pair = 7; // 4 pairs in byte 0 + 3 pairs of WPM in byte 1
    } else if (_pair > _bufSize * 4 - 4) {
      if (element == 3) _pair = 0; // overlong word: drop it, don't stay stuck
      return null;
    }

    var temp = element & 3;
    if (temp != 0 && temp != 3) {
      _buf[_pair ~/ 4] |= temp << (2 * (3 - (_pair % 4)));
    }

    if (temp != 3) {
      _pair++;
      return null;
    }
    // End of word replaces the preceding end-of-char.
    _pair--;
    if (_pair % 4 != 0) {
      _buf[_pair ~/ 4] |= temp << (2 * (3 - (_pair % 4)));
    }
    _pair = 0;
    // The firmware sends strlen(cwTxBuffer): up to the first zero byte.
    var len = 0;
    while (len < _bufSize && _buf[len] != 0) {
      len++;
    }
    return Uint8List.fromList(_buf.sublist(0, len));
  }

  /// Encodes plain text (chars from [MorseDecoder.table]) into one packet per
  /// word. Characters without a Morse pattern are skipped.
  List<Uint8List> encodeText(String text, int wpm) {
    final inverse = <String, String>{
      for (final e in MorseDecoder.table.entries)
        if (e.value.length == 1) e.value: e.key,
    };
    final out = <Uint8List>[];
    for (final word in text.toUpperCase().split(RegExp(r'\s+'))) {
      reset();
      var any = false;
      for (final ch in word.split('')) {
        final pat = inverse[ch];
        if (pat == null) continue;
        for (final s in pat.split('')) {
          element(s == '.' ? 1 : 2, wpm);
        }
        element(0, wpm);
        any = true;
      }
      if (!any) continue;
      final p = element(3, wpm);
      if (p != null) out.add(p);
    }
    return out;
  }
}

/// Returns null for packets the firmware would reject (wrong version,
/// WPM outside 5..60, first element 00) or that are too short/empty.
MoppPacket? decodeMopp(Uint8List d) {
  if (d.length < 2) return null;
  if ((d[0] & 0xC0) != 0x40) return null;
  final wpm = d[1] >> 2;
  if (wpm < 5 || wpm > 60) return null;
  if ((d[1] & 3) == 0) return null;

  final patterns = <String>[];
  var cur = '';
  var done = false;
  void feed(int el) {
    switch (el) {
      case 0:
        if (cur.isNotEmpty) patterns.add(cur);
        cur = '';
      case 1:
        cur += '.';
      case 2:
        cur += '-';
      default:
        if (cur.isNotEmpty) patterns.add(cur);
        cur = '';
        done = true;
    }
  }

  feed(d[1] & 3);
  for (var i = 2; i < d.length && !done; i++) {
    for (var j = 0; j < 4 && !done; j++) {
      feed((d[i] >> (2 * (3 - j))) & 3);
    }
  }
  if (cur.isNotEmpty) patterns.add(cur);
  if (patterns.isEmpty) return null;
  return MoppPacket(d[0] & 0x3F, wpm, patterns);
}
