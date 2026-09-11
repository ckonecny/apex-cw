// USB-OTG paddle input via HID keyboard events (vband interface).
//
// Default mapping (kd8rtt vband firmware):
//   Dit → 'ü'   (LogicalKeyboardKey.semicolonAndAlt on DE layout, but we match by keyLabel)
//   Dah → '+'
//
// Configurable at runtime: enter learn mode, press Dit → press Dah → saved.

import 'package:flutter/services.dart';

typedef PaddleCallback = void Function({required bool dit, required bool dah});

class PaddleInput {
  // Current configured key labels
  String ditKeyLabel;
  String dahKeyLabel;

  // Current physical state
  bool _dit = false;
  bool _dah = false;

  // LogicalKey seen on the most-recent KeyDown for each paddle.
  // Used to match KeyUpEvents, which carry no 'character'.
  LogicalKeyboardKey? _ditLogicalKey;
  LogicalKeyboardKey? _dahLogicalKey;

  PaddleCallback? onChanged;

  bool learnMode = false;
  int _learnStep = 0; // 0=wait for dit, 1=wait for dah
  void Function(String msg)? onLearnStatus;

  PaddleInput({
    this.ditKeyLabel = 'ü',
    this.dahKeyLabel = '+',
  });

  // Call this from a Focus/HardwareKeyboard handler in the widget tree.
  // Returns true if the event was consumed.
  bool handleKeyEvent(KeyEvent event) {
    if (learnMode) {
      return _handleLearnEvent(event);
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // character is available on down/repeat — use it to identify the paddle
      final char = event.character;
      if (char == ditKeyLabel) {
        _ditLogicalKey = event.logicalKey;
        if (!_dit) { _dit = true; onChanged?.call(dit: true, dah: _dah); }
        return true;
      }
      if (char == dahKeyLabel) {
        _dahLogicalKey = event.logicalKey;
        if (!_dah) { _dah = true; onChanged?.call(dit: _dit, dah: true); }
        return true;
      }
      // Fallback: match by keyLabel (for keys without character, e.g. non-BMP)
      final label = event.logicalKey.keyLabel;
      if (label == ditKeyLabel) {
        _ditLogicalKey = event.logicalKey;
        if (!_dit) { _dit = true; onChanged?.call(dit: true, dah: _dah); }
        return true;
      }
      if (label == dahKeyLabel) {
        _dahLogicalKey = event.logicalKey;
        if (!_dah) { _dah = true; onChanged?.call(dit: _dit, dah: true); }
        return true;
      }
    } else if (event is KeyUpEvent) {
      // character is null on up — match via stored logicalKey from the down event
      bool consumed = false;
      if (_ditLogicalKey != null && event.logicalKey == _ditLogicalKey) {
        _dit = false; _ditLogicalKey = null;
        onChanged?.call(dit: false, dah: _dah);
        consumed = true;
      }
      if (_dahLogicalKey != null && event.logicalKey == _dahLogicalKey) {
        _dah = false; _dahLogicalKey = null;
        onChanged?.call(dit: _dit, dah: false);
        consumed = true;
      }
      if (consumed) return true;
    }

    return false;
  }

  bool _handleLearnEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final label = _labelOf(event);
    if (label == null) return false;

    if (_learnStep == 0) {
      ditKeyLabel = label;
      _learnStep = 1;
      onLearnStatus?.call('Dit: "$label" — now press Dah');
    } else {
      dahKeyLabel = label;
      _learnStep = 0;
      learnMode = false;
      onLearnStatus?.call('Dah: "$label" — done!');
    }
    return true;
  }

  void startLearn() {
    learnMode = true;
    _learnStep = 0;
    onLearnStatus?.call('Press Dit paddle...');
  }

  String? _labelOf(KeyEvent event) {
    // Prefer the character, fall back to key label
    if (event.character != null && event.character!.isNotEmpty) {
      return event.character;
    }
    return event.logicalKey.keyLabel.isEmpty ? null : event.logicalKey.keyLabel;
  }

  bool get dit => _dit;
  bool get dah => _dah;
}
