// Port of Morserino-32 doPaddleIambic() — m32_v6.ino
// States and logic kept intentionally close to the original C++ for easy comparison.

import 'dart:async';

enum KeyerState { idle, dit, dah, keyStart, keyed, interElement }

enum KeyerMode { iambicA, iambicB, ultimatic, nonSqueeze, straightKey }

typedef KeyOutCallback = void Function(bool on);

class IambicKeyer {
  // ── Config ──────────────────────────────────────────────────────────────
  KeyerMode mode;
  int wpm;
  KeyOutCallback onKeyOut;

  // ── Timing ──────────────────────────────────────────────────────────────
  int get _ditMs => (1200 / wpm).round();
  int get _dahMs => _ditMs * 3;
  int get _interElementMs => _ditMs;

  // ── State ────────────────────────────────────────────────────────────────
  KeyerState _state = KeyerState.idle;
  bool _dit = false;      // current dit latch
  bool _dah = false;      // current dah latch
  bool _ditMemory = false;
  bool _dahMemory = false;
  bool _ditLast = false;

  int _keyerTimer = 0;      // deadline in ms since epoch
  bool _keyIsDown = false;

  // Ultimatic tracking
  bool _prevDit = false;
  bool _prevDah = false;
  int _ditOpenedAt = 0;
  int _dahOpenedAt = 0;
  static const int _minBounceMs = 5;

  Timer? _ticker;

  // ── Decoded output (dot/dash stream for display) ─────────────────────────
  final _outputController = StreamController<String>.broadcast();
  Stream<String> get symbolStream => _outputController.stream;

  // ── Latency measurement ──────────────────────────────────────────────────
  int _lastKeyPressMs = 0;
  int lastLatencyMs = 0;

  IambicKeyer({
    this.mode = KeyerMode.iambicA,
    this.wpm = 20,
    required this.onKeyOut,
  });

  // ── Public API ────────────────────────────────────────────────────────────

  void start() {
    _ticker = Timer.periodic(const Duration(milliseconds: 1), (_) => _tick());
  }

  void stop() {
    _ticker?.cancel();
    _setKey(false);
    _state = KeyerState.idle;
  }

  void setInputs({required bool dit, required bool dah}) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (mode == KeyerMode.straightKey) {
      if (dit != _keyIsDown) {
        if (dit) _lastKeyPressMs = now;
        _setKey(dit);
      }
      return;
    }

    // Latch on leading edge
    if (dit && !_prevDit) {
      _dit = true;
      _ditMemory = true;
      _lastKeyPressMs = now;
    }
    if (dah && !_prevDah) {
      _dah = true;
      _dahMemory = true;
      if (_lastKeyPressMs == 0) _lastKeyPressMs = now;
    }

    // Ultimatic: re-closure of a paddle seizes control
    if (mode == KeyerMode.ultimatic) {
      if (!dit && _prevDit) _ditOpenedAt = now;
      if (!dah && _prevDah) _dahOpenedAt = now;
      if (dit && _prevDit && dah && !_prevDah) {
        final gap = now - _ditOpenedAt;
        if (gap > _minBounceMs) { _ditMemory = false; _dit = false; }
      }
      if (dah && _prevDah && dit && !_prevDit) {
        final gap = now - _dahOpenedAt;
        if (gap > _minBounceMs) { _dahMemory = false; _dah = false; }
      }
    }

    // Keep latches live while paddle is held
    if (dit) { _dit = true; _ditMemory = true; }
    if (dah) { _dah = true; _dahMemory = true; }

    _prevDit = dit;
    _prevDah = dah;
  }

  // ── Main keyer tick (called every 1 ms) ──────────────────────────────────

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (_state) {
      case KeyerState.idle:
        if (_dit || _dah) {
          _state = KeyerState.keyStart;
        }
        break;

      case KeyerState.keyStart:
        final sendDit = _decideDit();
        if (_lastKeyPressMs > 0) {
          lastLatencyMs = 0; // will be set when key actually goes on
        }
        _setKey(true);
        if (_lastKeyPressMs > 0) {
          lastLatencyMs = DateTime.now().millisecondsSinceEpoch - _lastKeyPressMs;
          _lastKeyPressMs = 0;
        }
        _keyerTimer = now + (sendDit ? _ditMs : _dahMs);
        _state = sendDit ? KeyerState.dit : KeyerState.dah;
        _outputController.add(sendDit ? '·' : '—');
        break;

      case KeyerState.dit:
        if (now >= _keyerTimer) {
          _setKey(false);
          _clearDitLatch();
          _keyerTimer = now + _interElementMs;
          _state = KeyerState.interElement;
        }
        break;

      case KeyerState.dah:
        if (now >= _keyerTimer) {
          _setKey(false);
          _clearDahLatch();
          _keyerTimer = now + _interElementMs;
          _state = KeyerState.interElement;
        }
        break;

      case KeyerState.interElement:
        if (mode == KeyerMode.iambicB && _dit && _dah) {
          // Curtis B: latch the opposite of what just played
          if (_ditLast) _dahMemory = true;
          else _ditMemory = true;
        }
        if (now >= _keyerTimer) {
          if (_ditMemory || _dahMemory || _dit || _dah) {
            _state = KeyerState.keyStart;
          } else {
            _state = KeyerState.idle;
            _outputController.add(' ');
          }
        }
        break;

      case KeyerState.keyed:
        break;
    }
  }

  bool _decideDit() {
    if (mode == KeyerMode.nonSqueeze) {
      return _ditLast ? !(_dah || _dahMemory) : (_dit || _ditMemory);
    }
    if (mode == KeyerMode.ultimatic) {
      if (_dit && _dah) return !_ditLast;
    }
    if (_dit && _dah) return !_ditLast;
    if (_dit || _ditMemory) return true;
    return false;
  }

  void _clearDitLatch() {
    _ditLast = true;
    _ditMemory = false;
    if (!_prevDit) _dit = false;
  }

  void _clearDahLatch() {
    _ditLast = false;
    _dahMemory = false;
    if (!_prevDah) _dah = false;
  }

  void _setKey(bool on) {
    if (on == _keyIsDown) return;
    _keyIsDown = on;
    onKeyOut(on);
  }

  void dispose() {
    stop();
    _outputController.close();
  }
}
