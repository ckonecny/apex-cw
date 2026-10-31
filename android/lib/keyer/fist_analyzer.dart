import 'dart:math' as math;

/// How one kind of element (dit, dah, gaps) compares with the ideal.
class FistStat {
  const FistStat(this.name, this.count, this.ratio, this.ideal,
      {required this.minRatio, required this.maxRatio});

  final FistElement name;
  final int count;

  /// Median length in dit units (dit 1, dah 3, gaps 1 / 3 / 7).
  final double ratio;
  final double ideal;

  /// Shortest and longest single element of the window, in dit units — the
  /// spread (peak marks next to the median).
  final double minRatio, maxRatio;

  /// Signed deviation in octaves: 0 = perfect, negative = too short,
  /// positive = too long. A tenth of an octave is about 7 %.
  double get deviation => count == 0 ? 0 : _oct(ratio);
  double get minDeviation => count == 0 ? 0 : _oct(minRatio);
  double get maxDeviation => count == 0 ? 0 : _oct(maxRatio);
  double _oct(double r) => math.log(r / ideal) / math.ln2;
}

enum FistElement { dit, dah, elementGap, letterGap, wordGap }

class FistReport {
  const FistReport({
    required this.ditMs,
    required this.wpm,
    required this.index,
    required this.stats,
    required this.elements,
  });

  /// Median dit length in ms (the player's own unit).
  final double ditMs;

  /// Speed implied by [ditMs] (PARIS: 1200 / dit).
  final double wpm;

  /// 0–100, 100 = every element exactly on the ideal. Null until there are
  /// enough elements for a number that means something.
  final int? index;
  final Map<FistElement, FistStat> stats;

  /// Number of elements (keyed and gaps) the report is based on.
  final int elements;
}

/// Judges the rhythm of a straight-key fist from key edges.
///
/// Everything is measured against the player's *own* dit, so a steady but
/// slow fist scores well; the speed is reported separately. Press and gap
/// lengths are classified (dit/dah, element/letter/word gap) and compared
/// with the ideal ratios 1 : 3 and 1 : 3 : 7. Pure Dart, no engine access —
/// the edges come from the `cw_straight_edges` channel (KeyEvent.eventTime).
class FistAnalyzer {
  FistAnalyzer({this.window = 48});

  /// Newest presses (and the gaps between them) that count.
  final int window;

  /// Presses shorter than this, and gaps shorter than this between two
  /// presses, are contact bounce of the adapter, not keying (measured:
  /// 5–19 ms ghost presses; a dit at 40 WPM is 30 ms).
  static const bounceMs = 20;

  /// Elements needed before an index is shown.
  static const minElements = 20;

  final List<(int start, int end)> _presses = [];
  int? _downAt;

  void clear() {
    _presses.clear();
    _downAt = null;
  }

  /// One key edge; [timeMs] is the system's event time (any monotonic base).
  void add(bool down, int timeMs) {
    if (down) {
      _downAt = timeMs;
      return;
    }
    final start = _downAt;
    _downAt = null;
    if (start == null) return;
    if (_presses.isNotEmpty && start - _presses.last.$2 < bounceMs) {
      // Bounce inside one press: the key opened for a moment only.
      _presses[_presses.length - 1] = (_presses.last.$1, timeMs);
    } else if (timeMs - start >= bounceMs) {
      _presses.add((start, timeMs));
    }
    if (_presses.length > window + 1) {
      _presses.removeRange(0, _presses.length - window - 1);
    }
  }

  FistReport report() {
    final presses = _presses.length > window
        ? _presses.sublist(_presses.length - window)
        : _presses;
    final gaps = <double>[
      for (var i = 1; i < presses.length; i++)
        (presses[i].$1 - presses[i - 1].$2).toDouble(),
    ];
    final lengths = [for (final p in presses) (p.$2 - p.$1).toDouble()];
    final elements = lengths.length + gaps.length;
    if (lengths.length < 4) {
      return FistReport(
          ditMs: 0, wpm: 0, index: null, stats: const {}, elements: elements);
    }

    // Dit unit: lower cluster of the press lengths (2-means). Without a dah
    // among them (centres closer than 1 : 1.8) every press is a dit.
    final sorted = [...lengths]..sort();
    var lo = sorted.first, hi = sorted.last;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      final a = sorted.where((x) => x <= mid).toList();
      final b = sorted.where((x) => x > mid).toList();
      if (a.isEmpty || b.isEmpty) break;
      lo = _mean(a);
      hi = _mean(b);
    }
    final hasDah = hi / lo >= 1.8;
    final split = hasDah ? (lo + hi) / 2 : double.infinity;
    final dits = sorted.where((x) => x <= split).toList();
    final dit = _median(dits);

    final byKind = <FistElement, List<double>>{
      for (final k in FistElement.values) k: <double>[],
    };
    for (final l in lengths) {
      byKind[l <= split ? FistElement.dit : FistElement.dah]!.add(l);
    }
    for (final g in gaps) {
      final r = g / dit;
      final kind = r < 2
          ? FistElement.elementGap
          : r < 5
              ? FistElement.letterGap
              : FistElement.wordGap;
      byKind[kind]!.add(g);
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
      final v = byKind[k]!;
      if (v.isEmpty) continue;
      stats[k] = FistStat(k, v.length, _median(v) / dit, ideal[k]!,
          minRatio: v.reduce(math.min) / dit, maxRatio: v.reduce(math.max) / dit);
      for (final x in v) {
        sum += (math.log(x / dit / ideal[k]!) / math.ln2).abs();
      }
    }
    // Mean miss in octaves: 0 -> 100, half an octave (~41 %) and worse -> 0.
    final meanMiss = sum / elements;
    final index = elements < minElements
        ? null
        : (100 * (1 - meanMiss / 0.5)).clamp(0, 100).round();
    return FistReport(
        ditMs: dit,
        wpm: 1200 / dit,
        index: index,
        stats: stats,
        elements: elements);
  }

  static double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }
}

/// One plain-language remark about the fist.
class FistHint {
  const FistHint(this.element, this.tooLong);
  final FistElement element;
  final bool tooLong;

  /// Strings key, e.g. `fist_h_dah_short`.
  String get key => 'fist_h_${element.name}_${tooLong ? 'long' : 'short'}';
}

/// Turns the reports into at most two steady remarks. Steadiness comes from
/// three things: the report's medians (one outlier hardly moves them), a
/// hysteresis (a remark appears at about 20 % off and goes only below about
/// 13 %) and a dwell (a change must hold for [dwell] updates in a row).
class FistHints {
  static const on = 0.26; // octaves, ~20 %
  static const off = 0.18; // octaves, ~13 %
  static const dwell = 4;
  static const maxShown = 2;

  // Dit is the unit everything is measured in, so it never gets a remark.
  static const _minCount = {
    FistElement.dah: 5,
    FistElement.elementGap: 5,
    FistElement.letterGap: 4,
    FistElement.wordGap: 3,
  };

  final Map<FistElement, int> _active = {}; // -1 short, +1 long
  final Map<FistElement, (int dir, int n)> _pending = {};
  final Map<FistElement, double> _dev = {};

  void clear() {
    _active.clear();
    _pending.clear();
    _dev.clear();
  }

  /// Call once per new report (every key-up).
  void update(FistReport r) {
    if (r.index == null) return;
    for (final k in _minCount.keys) {
      final s = r.stats[k];
      if (s == null || s.count < _minCount[k]!) continue;
      final dev = s.deviation;
      final cur = _active[k] ?? 0;
      int target;
      if (cur == 0) {
        target = dev >= on ? 1 : (dev <= -on ? -1 : 0);
      } else if (dev * cur >= off) {
        target = cur;
      } else {
        target = dev * cur <= -on ? -cur : 0;
      }
      if (target == cur) {
        _pending.remove(k);
      } else {
        final p = _pending[k];
        final n = (p != null && p.$1 == target) ? p.$2 + 1 : 1;
        if (n >= dwell) {
          _active[k] = target;
          _pending.remove(k);
        } else {
          _pending[k] = (target, n);
        }
      }
      if ((_active[k] ?? 0) != 0) _dev[k] = dev;
    }
    _active.removeWhere((_, v) => v == 0);
  }

  /// The remarks to show, biggest miss first.
  List<FistHint> get shown {
    final ks = _active.keys.toList()
      ..sort((a, b) => (_dev[b] ?? 0).abs().compareTo((_dev[a] ?? 0).abs()));
    return [for (final k in ks.take(maxShown)) FistHint(k, _active[k]! > 0)];
  }
}
