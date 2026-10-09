import 'dart:math' as math;
import 'dart:typed_data';

import 'decoder_chars.dart';

// CW decoder from audio — port of the firmware's goertzel.cpp (tone
// detection) and the Decoder class of MorseDecoder.cpp (timing state machine,
// adaptive dit/dah averages, decoding tree). Pure Dart and driven by sample
// time, not the wall clock, so it runs identically on live microphone data
// and on synthesized audio in tests.
//
// Deviations from the firmware (see docs/DECISIONS.md, 2026-09-25):
// - Sample rate is whatever the phone delivers (16 kHz) instead of 11905 Hz;
//   the block length keeps the firmware's bandwidths (Wide ~700 Hz, Narrow
//   ~175 Hz, i.e. ~1.4 / ~5.7 ms blocks).
// - The target frequency is adjustable (firmware: fixed 698 Hz, the input
//   being tuned to it); the Goertzel uses the exact frequency instead of the
//   nearest integer bin, so any setting is centred.
// - Magnitudes are normalized to full scale (0..1 amplitude); the fixed
//   ADC-scale floor (magnitudelimit_low) becomes the user's sensitivity.

/// goertzel.cpp: block-wise Goertzel filter with the firmware's automatic
/// magnitude limit.
class GoertzelDetector {
  final int sampleRate;
  final double targetFreq;
  final bool narrow;

  /// Normalized amplitude floor (firmware `magnitudelimit_low`).
  double limitLow;

  late final int n;
  late final double _coeff;
  double _limit;
  double _q1 = 0, _q2 = 0;
  int _count = 0;

  /// Last block's normalized magnitude and the current adaptive limit, for a
  /// level meter.
  double level = 0;
  double get limit => _limit;

  GoertzelDetector({
    required this.sampleRate,
    this.targetFreq = 698,
    this.narrow = false,
    this.limitLow = 0.01,
  }) : _limit = limitLow {
    // Firmware: 17 samples (Wide) / 68 (Narrow) at 11905 Hz → bandwidth
    // 700 / 175 Hz. Keep the bandwidth at our sample rate.
    n = (sampleRate / (narrow ? 175.0 : 700.0)).round();
    final omega = 2.0 * math.pi * targetFreq / sampleRate;
    _coeff = 2.0 * math.cos(omega);
  }

  double get blockMs => n * 1000.0 / sampleRate;

  /// Feeds PCM16 samples; [onBlock] is called with the detected tone state
  /// once per completed block (the firmware's `checkInput()` result).
  void add(Int16List samples, void Function(bool tone) onBlock) {
    for (final s in samples) {
      final q0 = _coeff * _q1 - _q2 + s;
      _q2 = _q1;
      _q1 = q0;
      if (++_count == n) {
        onBlock(_finishBlock());
        _count = 0;
      }
    }
  }

  bool _finishBlock() {
    final magSq = _q1 * _q1 + _q2 * _q2 - _q1 * _q2 * _coeff;
    _q1 = _q2 = 0;
    // Normalize: a full-scale sine gives magnitude n/2 * 32768.
    final magnitude = math.sqrt(math.max(0.0, magSq)) * 2 / n / 32768;
    level = magnitude;

    // "here we will try to set the magnitude limit automatic"
    if (magnitude > limitLow) {
      _limit = _limit * 0.95 + (magnitude - _limit) / 4;   // moving average filter
    }
    if (_limit < limitLow) _limit = limitLow;

    return magnitude > _limit * 0.6;                       // just to have some space up
  }
}

/// MorseDecoder.h CWtree: the dichotomic decoding tree, index → (symbol,
/// dit branch, dah branch). Symbols as the firmware displays them.
const List<(String, int, int)> _cwTree = [
  ('', 1, 2),          // 0
  ('e', 3, 4),         // 1
  ('t', 5, 6),         // 2
  ('i', 7, 8),         // 3
  ('a', 9, 10),        // 4
  ('n', 11, 12),       // 5
  ('m', 13, 14),       // 6
  ('s', 15, 16),       // 7
  ('u', 17, 18),       // 8
  ('r', 19, 20),       // 9
  ('w', 21, 22),       // 10
  ('d', 23, 24),       // 11
  ('k', 25, 26),       // 12
  ('g', 27, 28),       // 13
  ('o', 29, 30),       // 14
  ('h', 31, 32),       // 15
  ('v', 33, 34),       // 16
  ('f', 63, 63),       // 17
  ('ü', 35, 36),       // 18 german ue
  ('l', 37, 38),       // 19
  ('ä', 39, 63),       // 20 german ae
  ('p', 63, 40),       // 21
  ('j', 63, 41),       // 22
  ('b', 42, 43),       // 23
  ('x', 44, 63),       // 24
  ('c', 63, 45),       // 25
  ('y', 46, 63),       // 26
  ('z', 47, 48),       // 27
  ('q', 63, 63),       // 28
  ('ö', 49, 63),       // 29 german oe
  ('<ch>', 50, 51),    // 30 german "ch"
  ('5', 64, 63),       // 31
  ('4', 63, 63),       // 32
  ('<ve>', 63, 52),    // 33
  ('3', 63, 63),       // 34
  ('*', 53, 63),       // 35
  ('2', 63, 63),       // 36
  ('<as>', 63, 63),    // 37
  ('*', 54, 63),       // 38
  ('+', 63, 55),       // 39
  ('*', 56, 63),       // 40
  ('1', 57, 63),       // 41
  ('6', 63, 58),       // 42
  ('=', 67, 63),       // 43
  ('/', 63, 63),       // 44
  ('<ka>', 59, 60),    // 45
  ('<kn>', 63, 63),    // 46
  ('7', 63, 63),       // 47
  ('*', 63, 61),       // 48
  ('8', 62, 63),       // 49
  ('9', 63, 63),       // 50
  ('0', 63, 63),       // 51
  ('<sk>', 63, 63),    // 52
  ('?', 63, 63),       // 53
  ('"', 63, 63),       // 54
  ('.', 63, 63),       // 55
  ('@', 63, 63),       // 56
  ("'", 63, 63),       // 57
  ('-', 63, 63),       // 58
  (';', 63, 63),       // 59
  ('!', 63, 63),       // 60
  (',', 63, 63),       // 61
  (':', 63, 63),       // 62
  ('*', 63, 63),       // 63 default for all unidentified characters
  ('*', 65, 63),       // 64
  ('<err>', 66, 63),   // 65
  ('<err>', 66, 63),   // 66 error - backspace
  ('*', 63, 68),       // 67
  ('<bk>', 63, 63),    // 68
];

enum _DecState { low, high, interElement, interChar }

/// MorseDecoder.cpp `Decoder` (the audio instance): noise blanker, timing
/// state machine and the adaptive dit/dah averages. Call [decode] once per
/// Goertzel block with its tone state and the block's end time in ms — the
/// firmware calls `decode()` once per loop, each reading one block.
class AudioCwDecoder {
  /// A decoded symbol: a tree symbol ('e', `<ka>`, '*', …) or ' ' at the end
  /// of a word.
  final void Function(String symbol) onSymbol;

  /// Tone on/off after the noise blanker (firmware `keyOut` / drawInputStatus).
  final void Function(bool on)? onTone;

  /// Decoded speed changed.
  final void Function(int wpm)? onWpm;

  /// National letters / ITU brackets (issue #52), changeable while listening.
  DecoderChars chars = DecoderChars.standard;

  AudioCwDecoder({required this.onSymbol, this.onTone, this.onWpm});

  bool _filteredState = false, _filteredStateBefore = false;
  bool _realstateBefore = false;
  _DecState _state = _DecState.low;
  int _nbtime = 1;
  int _startTimeHigh = 0, _lastStartTime = 0, _startTimeLow = 0;
  int _ditAvg = 60, _dahAvg = 180;
  int _wpm = 15;
  int _treeptr = 0;
  String _pattern = '';   // dits/dahs of the current character, for [chars]

  int get wpm => _wpm;

  void reset() {
    _filteredState = _filteredStateBefore = _realstateBefore = false;
    _lastStartTime = 0;
    _state = _DecState.low;
    _ditAvg = 60;
    _dahAvg = 180;
    _wpm = 15;
    _nbtime = 1;
    _treeptr = 0;
    _pattern = '';
  }

  // checkInput(): noise blanker; true when the filtered state changed.
  bool _checkInput(bool realstate, int now) {
    if (realstate != _realstateBefore) _lastStartTime = now;
    if (now - _lastStartTime > _nbtime) {
      if (realstate != _filteredState) _filteredState = realstate;
    }
    _realstateBefore = realstate;
    if (_filteredState == _filteredStateBefore) return false;
    _filteredStateBefore = _filteredState;
    return true;
  }

  void decode(bool realstate, int now) {
    switch (_state) {
      case _DecState.interElement:
        if (_checkInput(realstate, now)) {
          _on(now);
          _state = _DecState.high;
        } else {
          final lowDuration = now - _startTimeLow;
          var lacktime = 2.2;   // at high speeds a little more pause before a new letter
          if (_wpm > 35) {
            lacktime = 2.4;
          } else if (_wpm > 30) {
            lacktime = 2.3;
          }
          if (lowDuration > lacktime * _ditAvg) {
            onSymbol(_retrieveSymbol());
            final wpm = (_wpm + 7200 ~/ (_dahAvg + 3 * _ditAvg)) ~/ 2;
            if (_wpm != wpm) {
              _wpm = wpm;
              onWpm?.call(wpm);
            }
            _state = _DecState.interChar;
          }
        }
        break;
      case _DecState.interChar:
        if (_checkInput(realstate, now)) {
          _on(now);
          _state = _DecState.high;
        } else {
          final lowDuration = now - _startTimeLow;
          var lacktime = 5.0;   // at high speeds a little more pause before a new word
          if (_wpm > 35) {
            lacktime = 6;
          } else if (_wpm > 30) {
            lacktime = 5.5;
          }
          if (lowDuration > lacktime * _ditAvg) {
            onSymbol(_retrieveSymbol());   // end of word
            _state = _DecState.low;
          }
        }
        break;
      case _DecState.low:
        if (_checkInput(realstate, now)) {
          _on(now);
          _state = _DecState.high;
        }
        break;
      case _DecState.high:
        if (_checkInput(realstate, now)) {
          _off(now);
          _state = _DecState.interElement;
        }
        break;
    }
  }

  // ON_(): rising flank.
  void _on(int now) {
    final lowDuration = now - _startTimeLow;
    _startTimeHigh = now;
    onTone?.call(true);
    if (lowDuration < _ditAvg * 2.4) _recalculateDit(lowDuration);   // inter-element pause: adjust speed
  }

  // OFF_(): falling flank.
  void _off(int now) {
    // C: ditAvg * sqrt(dahAvg / ditAvg) — the ratio is an integer division.
    final threshold = (_ditAvg * math.sqrt(_dahAvg ~/ _ditAvg)).toInt();
    final highDuration = now - _startTimeHigh;
    _startTimeLow = now;
    if (highDuration > _ditAvg * 0.5 && highDuration < _dahAvg * 2.5) {   // filter out VERY short and VERY long highs
      if (highDuration < threshold) {
        _treeptr = _cwTree[_treeptr].$2;
        _pattern += '.';
        _recalculateDit(highDuration);
      } else {
        _treeptr = _cwTree[_treeptr].$3;
        _pattern += '-';
        _recalculateDah(highDuration);
      }
    }
    onTone?.call(false);
  }

  void _recalculateDit(int duration) {
    _ditAvg = (4 * _ditAvg + duration) ~/ 5;
    _nbtime = (_ditAvg ~/ 5).clamp(7, 20);
  }

  void _recalculateDah(int duration) {
    if (duration > 2 * _dahAvg) {                 // very rapid decrease in speed!
      _dahAvg = (_dahAvg + 2 * duration) ~/ 3;    // adjust faster, ditAvg as well
      _ditAvg = _ditAvg ~/ 2 + _dahAvg ~/ 6;
    } else {
      _dahAvg = (3 * _ditAvg + _dahAvg + duration) ~/ 3;
    }
  }

  String _retrieveSymbol() {
    if (_treeptr == 0) return ' ';
    final s = decoderCharsSymbol(_pattern, chars) ?? _cwTree[_treeptr].$1;
    _treeptr = 0;
    _pattern = '';
    return s;
  }
}

/// Goertzel + decoder, fed with raw PCM16 microphone chunks.
class MicCwDecoder {
  final GoertzelDetector detector;
  final AudioCwDecoder decoder;
  int _samples = 0;

  MicCwDecoder(this.detector, this.decoder);

  void addSamples(Int16List pcm) {
    final rate = detector.sampleRate;
    final n = detector.n;
    detector.add(pcm, (tone) {
      _samples += n;
      decoder.decode(tone, _samples * 1000 ~/ rate);
    });
  }
}
