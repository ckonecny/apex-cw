import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/keyer/cw_audio_decoder.dart';
import 'package:next_cw_trainer/keyer/morse_decoder.dart';

const _codes = {
  'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
  'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
  'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
  'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
  'Y': '-.--', 'Z': '--..', '0': '-----', '1': '.----', '2': '..---',
  '3': '...--', '4': '....-', '5': '.....', '6': '-....', '7': '--...',
  '8': '---..', '9': '----.', '?': '..--..', '/': '-..-.', '=': '-...-',
};

/// PCM16 of [text] at [wpm] (PARIS timing), tone [freq], plus white noise.
Int16List synth(String text, {int wpm = 20, double freq = 698, int rate = 16000,
    double amp = 0.3, double noise = 0.0, double pitchErr = 0}) {
  final dit = 1.2 / wpm;
  final out = <int>[];
  final rnd = math.Random(1);
  var phase = 0.0;
  void seg(double secs, bool on) {
    final len = (secs * rate).round();
    for (var i = 0; i < len; i++) {
      phase += 2 * math.pi * (freq + pitchErr) / rate;
      var v = on ? amp * math.sin(phase) : 0.0;
      v += noise * (rnd.nextDouble() * 2 - 1);
      out.add((v.clamp(-1.0, 1.0) * 32767).round());
    }
  }
  seg(0.3, false);
  final words = text.split(' ');
  for (var w = 0; w < words.length; w++) {
    final word = words[w];
    for (var c = 0; c < word.length; c++) {
      final code = _codes[word[c]]!;
      for (var e = 0; e < code.length; e++) {
        seg(code[e] == '.' ? dit : 3 * dit, true);
        if (e < code.length - 1) seg(dit, false);
      }
      if (c < word.length - 1) seg(3 * dit, false);
    }
    seg(w < words.length - 1 ? 7 * dit : 20 * dit, false);
  }
  return Int16List.fromList(out);
}

String decode(Int16List pcm, {bool narrow = false, double freq = 698,
    double floor = 0.01, List<int>? wpms}) {
  final buf = StringBuffer();
  final dec = MicCwDecoder(
    GoertzelDetector(sampleRate: 16000, targetFreq: freq, narrow: narrow,
        limitLow: floor),
    AudioCwDecoder(onSymbol: buf.write, onWpm: wpms?.add),
  );
  // Feed in 20 ms chunks like the microphone stream.
  for (var i = 0; i < pcm.length; i += 320) {
    dec.addSamples(Int16List.sublistView(pcm, i, math.min(i + 320, pcm.length)));
  }
  return buf.toString().trim();
}

void main() {
  const text = 'CQ CQ DE OE1CKO K';
  const expected = 'cq cq de oe1cko k';

  // The decoder starts at 15 WPM and adapts; the first characters may be
  // lost while it settles, as on the device — compare from the second word.
  String tail(String s) => s.substring(s.indexOf(' ') + 1);

  test('clean signal, 20 WPM, wide', () {
    expect(tail(decode(synth(text))), tail(expected));
  });

  test('clean signal, 20 WPM, narrow', () {
    expect(tail(decode(synth(text), narrow: true)), tail(expected));
  });

  test('adapts to 30 WPM and reports the speed', () {
    final wpms = <int>[];
    final out = decode(synth('$text $text', wpm: 30), wpms: wpms);
    expect(out.endsWith(expected), isTrue, reason: out);
    expect(wpms.last, inInclusiveRange(27, 33));
  });

  test('12 WPM', () {
    expect(tail(decode(synth(text, wpm: 12))), tail(expected));
  });

  // As on the device, the automatic limit follows constant noise down to
  // the floor, so the floor (sensitivity) has to sit above the noise.
  test('noise, narrow filter, floor above the noise', () {
    final out = decode(synth(text, noise: 0.3, amp: 0.2), narrow: true,
        floor: 0.08);
    expect(tail(out), tail(expected));
  });

  test('tone below the floor is not decoded', () {
    expect(decode(synth(text, amp: 0.02), floor: 0.05), isEmpty);
  });

  test('adjustable target frequency', () {
    expect(tail(decode(synth(text, freq: 550), freq: 550, narrow: true)),
        tail(expected));
  });

  test('prosigns and error sign come from the firmware tree', () {
    final syms = <String>[];
    final d = AudioCwDecoder(onSymbol: syms.add);
    var t = 0;
    // 20 WPM after settling: dit 60 ms (the decoder's start value).
    void key(String code) {
      for (final e in code.split('')) {
        d.decode(true, t);
        for (var i = 0; i < (e == '.' ? 60 : 180); i += 2) { t += 2; d.decode(true, t); }
        for (var i = 0; i < 60; i += 2) { t += 2; d.decode(false, t); }
      }
      for (var i = 0; i < 400; i += 2) { t += 2; d.decode(false, t); }
    }
    key('-.-.-');      // <ka>
    key('........');   // <err>
    expect(syms.where((s) => s != ' ').toList(), ['<ka>', '<err>']);
  });

  test('every pattern of the keyer decoder decodes the same through the firmware tree', () {
    // Two decoders live in the app (keyed symbols: morse_decoder.dart; audio:
    // the firmware tree). For the same pattern they must give the same character.
    String norm(String x) => x.replaceAll(RegExp('[<>]'), '').toUpperCase();
    final mismatches = <String>[];
    MorseDecoder.table.forEach((pattern, expected) {
      final syms = <String>[];
      final d = AudioCwDecoder(onSymbol: syms.add);
      var t = 0;
      for (final e in pattern.split('')) {
        d.decode(true, t);
        for (var i = 0; i < (e == '.' ? 60 : 180); i += 2) { t += 2; d.decode(true, t); }
        for (var i = 0; i < 60; i += 2) { t += 2; d.decode(false, t); }
      }
      for (var i = 0; i < 400; i += 2) { t += 2; d.decode(false, t); }
      final got = syms.where((x) => x != ' ').map(norm).join();
      if (got != norm(expected)) mismatches.add('$pattern: tree $got, keyer $expected');
    });
    // Known, deliberate: the firmware tree reads .-.-. as "+" and -...- as "="
    // like the keyer table, so nothing is expected here.
    expect(mismatches, isEmpty);
  });

  test('random noise, clipping and odd chunk sizes neither crash nor flood', () {
    final rnd = math.Random(7);
    for (final rate in [8000, 16000, 44100, 48000]) {
      final det = GoertzelDetector(sampleRate: rate, narrow: rate % 2 == 0);
      final out = StringBuffer();
      final dec = MicCwDecoder(det, AudioCwDecoder(onSymbol: out.write));
      final n = rate * 5;
      final pcm = Int16List(n);
      for (var i = 0; i < n; i++) {
        // full-scale random samples, with stretches of DC offset and silence
        pcm[i] = (i ~/ 4000) % 3 == 0
            ? 32767
            : (i ~/ 4000) % 3 == 1
                ? 0
                : rnd.nextInt(65536) - 32768;
      }
      var i = 0;
      while (i < n) {
        final len = 1 + rnd.nextInt(700);          // odd, unaligned chunk sizes
        dec.addSamples(Int16List.sublistView(pcm, i, math.min(i + len, n)));
        i += len;
      }
      dec.addSamples(Int16List(0));
      expect(det.level.isFinite, isTrue);
      expect(det.limit.isFinite, isTrue);
      // at most one symbol per two blocks of 1.4 ms: an upper bound that catches a runaway loop
      expect(out.length, lessThan(rate * 5 / det.n));
    }
  });

  test('sample rates other than 16 kHz decode the same text', () {
    for (final rate in [8000, 11025, 22050, 44100, 48000]) {
      final pcm = synth(text, rate: rate);
      final buf = StringBuffer();
      final dec = MicCwDecoder(
        GoertzelDetector(sampleRate: rate),
        AudioCwDecoder(onSymbol: buf.write),
      );
      for (var i = 0; i < pcm.length; i += 320) {
        dec.addSamples(Int16List.sublistView(pcm, i, math.min(i + 320, pcm.length)));
      }
      expect(tail(buf.toString().trim()), tail(expected), reason: 'rate $rate');
    }
  });
}
