// Break reminder (issue #5, docs/DECISIONS.md "Break reminder"): suggests a
// pause when the hit rate falls within a session. Pure Dart, no UI/storage.
//
// Only blocks under unchanged conditions count: a new Koch character, a higher
// speed or tighter spacing lowers the rate through the harder task, not through
// fatigue. So the watch looks at the trailing run of blocks with the same
// "challenge signature" and compares its start with its end.

/// Blocks at the start / end of the run that are averaged.
const kBreakWindow = 3;

/// Hit rate must have fallen by this much (0..1) between start and end.
const kBreakDrop = 0.15;

/// A pause this long between two blocks ends the session.
const kBreakSessionGap = Duration(minutes: 10);

class BreakWatch {
  BreakWatch({this.window = kBreakWindow, this.drop = kBreakDrop,
      this.sessionGap = kBreakSessionGap});

  final int window;
  final double drop;
  final Duration sessionGap;

  // Per track ('hear' | 'echo'): rate and signature of the blocks of the
  // current run, oldest first.
  final Map<String, List<(double, String)>> _runs = {};
  DateTime? _last;
  bool _shown = false;

  /// Adds a finished block ([rate] 0..1, [signature] = everything that sets
  /// its difficulty). True when the hint should be shown now; at most once per
  /// session.
  bool add(String track, double rate, String signature, DateTime now) {
    final last = _last;
    _last = now;
    if (last != null && now.difference(last) > sessionGap) {
      _runs.clear();
      _shown = false;
    }
    final run = _runs.putIfAbsent(track, () => []);
    if (run.isNotEmpty && run.last.$2 != signature) run.clear();
    run.add((rate.clamp(0.0, 1.0), signature));
    if (_shown || run.length < 2 * window) return false;
    double avg(Iterable<(double, String)> l) =>
        l.fold(0.0, (a, b) => a + b.$1) / l.length;
    final start = avg(run.take(window));
    final end = avg(run.skip(run.length - window));
    if (start - end < drop) return false;
    return _shown = true;
  }

  /// For tests.
  int runLength(String track) => _runs[track]?.length ?? 0;
}
