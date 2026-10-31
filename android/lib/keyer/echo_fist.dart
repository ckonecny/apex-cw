import 'dart:math' as math;

import '../content/cw_content.dart';
import 'fist_analyzer.dart';
import 'morse_decoder.dart';

/// Timing index of a Geben block with a straight key on an adapter (#166).
///
/// The target is known, so each keyed press and gap gets the element it was
/// meant to be (dit, dah, gap inside a character, between characters, between
/// words). A word whose number of presses differs from the target's is a real
/// error (missing or extra element) and stays out; the same number of presses
/// with a dah keyed as short as a dit is a timing error and counts, as
/// "dah too short". The numbers are the same as in the CW Keyer panel
/// ([FistReport]), measured against the player's own dit.
class EchoFistBlock {
  static final _codes = {
    for (final e in MorseDecoder.table.entries) e.value: e.key,
    ...kProsignCodes,
  };

  /// Words that went into the report / were left out as real errors.
  int words = 0, skipped = 0;

  final List<(FistElement, double)> _marks = [];

  void clear() {
    words = 0;
    skipped = 0;
    _marks.clear();
  }

  /// Dit/dah code per character of [target] (`<KA>` = prosign, spaces kept
  /// as null), or null if a character has no code.
  static List<String?>? pattern(String target) {
    final out = <String?>[];
    var i = 0;
    while (i < target.length) {
      final m = RegExp(r'^<([A-Z]+)>', caseSensitive: false).firstMatch(target.substring(i));
      final String tok;
      if (m != null) {
        tok = m.group(1)!.toUpperCase();
        i += m.end;
      } else {
        tok = target[i].toUpperCase();
        i++;
      }
      if (tok == ' ') {
        out.add(null);
        continue;
      }
      final code = _codes[tok];
      if (code == null) return null;
      out.add(code);
    }
    return out;
  }

  /// Adds the first attempt of one word: [presses] as (start, end) in ms.
  /// Returns false if the word was left out.
  bool addWord(String target, List<(int, int)> presses) {
    final pat = pattern(target);
    final kinds = <FistElement>[]; // intended kind of each press
    final gapKinds = <FistElement>[]; // ... and of each gap after a press
    if (pat != null) {
      for (var i = 0; i < pat.length; i++) {
        final code = pat[i];
        if (code == null) continue;
        for (var j = 0; j < code.length; j++) {
          kinds.add(code[j] == '.' ? FistElement.dit : FistElement.dah);
          if (j < code.length - 1) {
            gapKinds.add(FistElement.elementGap);
          } else if (i < pat.length - 1) {
            final spaced = pat[i + 1] == null;
            gapKinds.add(spaced ? FistElement.wordGap : FistElement.letterGap);
          }
        }
      }
    }
    if (pat == null || kinds.isEmpty || presses.length != kinds.length) {
      skipped++;
      return false;
    }
    words++;
    for (var i = 0; i < presses.length; i++) {
      _marks.add((kinds[i], (presses[i].$2 - presses[i].$1).toDouble()));
      if (i < presses.length - 1) {
        _marks.add((gapKinds[i], (presses[i + 1].$1 - presses[i].$2).toDouble()));
      }
    }
    return true;
  }

  FistReport report() {
    List<double> of(FistElement k) =>
        [for (final m in _marks) if (m.$1 == k) m.$2];
    final dits = of(FistElement.dit);
    final dahs = of(FistElement.dah);
    final unit = dits.isNotEmpty
        ? _median(dits)
        : dahs.isNotEmpty
            ? _median(dahs) / 3
            : 0.0;
    if (unit <= 0 || _marks.isEmpty) {
      return FistReport(
          ditMs: 0, wpm: 0, index: null, stats: const {}, elements: _marks.length);
    }
    const ideal = {
      FistElement.dit: 1.0,
      FistElement.dah: 3.0,
      FistElement.elementGap: 1.0,
      FistElement.letterGap: 3.0,
      FistElement.wordGap: 7.0,
    };
    final stats = <FistElement, FistStat>{};
    var sum = 0.0;
    for (final k in FistElement.values) {
      final v = of(k);
      if (v.isEmpty) continue;
      stats[k] = FistStat(k, v.length, _median(v) / unit, ideal[k]!,
          minRatio: v.reduce(math.min) / unit, maxRatio: v.reduce(math.max) / unit);
      for (final x in v) {
        sum += (math.log(x / unit / ideal[k]!) / math.ln2).abs();
      }
    }
    final miss = sum / _marks.length;
    return FistReport(
        ditMs: unit,
        wpm: 1200 / unit,
        index: _marks.length < FistAnalyzer.minElements
            ? null
            : (100 * (1 - miss / 0.5)).clamp(0, 100).round(),
        stats: stats,
        elements: _marks.length);
  }

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }
}
