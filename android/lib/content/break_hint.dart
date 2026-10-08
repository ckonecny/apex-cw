// Break reminder (issue #5, #48; docs/DECISIONS.md "Break reminder"): suggests
// a pause when errors pile up or the hit rate sinks within a session. Pure
// Dart, no UI/storage.
//
// Works on the sequence of answered characters, not on blocks: block size is
// the user's choice (5 groups of 3 vs 10 groups of 5), so "N blocks" would mean
// very different amounts of practice. Only characters under unchanged
// conditions count: a new Koch character, a higher speed or tighter spacing
// lowers the rate through the harder task, not through fatigue. So the watch
// looks at the trailing run of characters with the same "challenge signature".

/// How early the hint fires (Settings → General).
enum BreakSensitivity {
  early(window: 20, burst: 7, trendLen: 40, trendDropPct: 12),
  normal(window: 20, burst: 9, trendLen: 60, trendDropPct: 15),
  late(window: 20, burst: 11, trendLen: 80, trendDropPct: 20);

  const BreakSensitivity({
    required this.window,
    required this.burst,
    required this.trendLen,
    required this.trendDropPct,
  });

  /// Burst rule: this many wrong characters within any [window] consecutive
  /// ones. Larger than one group, so a single lost group never fires alone.
  final int window;
  final int burst;

  /// Trend rule: the first [trendLen] characters of the run against the last
  /// [trendLen]; the hit rate must have fallen by [trendDropPct] points. Needs
  /// 2 × [trendLen] characters so the two parts never overlap.
  final int trendLen;
  final int trendDropPct;
}

/// A pause this long between two blocks ends the session.
const kBreakSessionGap = Duration(minutes: 10);

class BreakWatch {
  BreakWatch({this.sensitivity = BreakSensitivity.normal,
      this.sessionGap = kBreakSessionGap});

  BreakSensitivity sensitivity;
  final Duration sessionGap;

  // Per track ('hear' | 'echo'): answered characters of the current run
  // (true = wrong), oldest first, and the run's signature.
  final Map<String, List<bool>> _runs = {};
  final Map<String, String> _sigs = {};
  DateTime? _last;
  bool _shown = false;

  /// Adds a finished block: [correct] holds one entry per answered character
  /// in order (true = right); [signature] = everything that sets its
  /// difficulty. True when the hint should be shown now; at most once per
  /// session. Evaluated at the block end (Hören only knows the errors then).
  bool add(String track, List<bool> correct, String signature, DateTime now) {
    final last = _last;
    _last = now;
    if (last != null && now.difference(last) > sessionGap) {
      _runs.clear();
      _sigs.clear();
      _shown = false;
    }
    final run = _runs.putIfAbsent(track, () => []);
    if (_sigs[track] != signature) {
      run.clear();
      _sigs[track] = signature;
    }
    final before = run.length;
    run.addAll(correct.map((c) => !c));
    if (_shown) return false;
    if (_burst(run, before) || _trend(run)) return _shown = true;
    return false;
  }

  bool _burst(List<bool> run, int before) {
    final s = sensitivity;
    if (run.length < s.window) return false;
    // Only windows that end in the new block; earlier ones were checked.
    var wrong = 0;
    for (var i = 0; i < run.length; i++) {
      if (run[i]) wrong++;
      if (i >= s.window && run[i - s.window]) wrong--;
      if (i >= before && i >= s.window - 1 && wrong >= s.burst) return true;
    }
    return false;
  }

  bool _trend(List<bool> run) {
    final s = sensitivity;
    if (run.length < 2 * s.trendLen) return false;
    final first = run.take(s.trendLen).where((w) => w).length;
    final lastN = run.skip(run.length - s.trendLen).where((w) => w).length;
    // (wrong_last − wrong_first) / len >= drop%, in integers.
    return (lastN - first) * 100 >= s.trendDropPct * s.trendLen;
  }

  /// For tests.
  int runLength(String track) => _runs[track]?.length ?? 0;
}
