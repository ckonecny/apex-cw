// Trends of mix-ups over time (issue #101, docs/DECISIONS.md "Mix-up trends").
// Pure Dart on the per-day stats (CharStatsStore.days, one track): for every
// pair "K>R" the rate "times K was heard/sent as R ÷ attempts at K" in the
// recent window is compared with the window before it. Rates, not counts:
// more practice must not look like more confusion.
import 'char_stats.dart';

enum MixupDirection {
  up, // more frequent
  fresh, // new: none in the window before
  down, // less frequent
  gone, // none any more
  same,
  tooFew, // not enough data for a statement
}

class MixupTrend {
  final String pair; // "K>R", '–' = left out
  final int countRecent, countPrior, attemptsRecent, attemptsPrior;
  final MixupDirection direction;
  const MixupTrend(this.pair, this.countRecent, this.countPrior, this.attemptsRecent,
      this.attemptsPrior, this.direction);

  String get played => pair.split('>').first;
  String get given => pair.split('>').last;

  double? get rateRecent => attemptsRecent == 0 ? null : countRecent / attemptsRecent;
  double? get ratePrior => attemptsPrior == 0 ? null : countPrior / attemptsPrior;
}

/// Attempts at [ch] in a day's character map, case-insensitive (Listen stores
/// the case as played, Send upper-case; mix-up pairs are always upper-case).
int attemptsOfChar(Map<String, List<int>> chars, String ch) {
  final u = ch.toUpperCase();
  var n = 0;
  chars.forEach((k, v) {
    if (k.toUpperCase() == u) n += v[0];
  });
  return n;
}

DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Direction of one pair from its two windows; the thresholds are in
/// [mixupTrends]. Kept apart so the rule can be tested alone.
MixupDirection classifyMixup({
  required int countRecent,
  required int countPrior,
  required int attemptsRecent,
  required int attemptsPrior,
  int minAttempts = 15,
  int minMixups = 3,
}) {
  final recentOk = attemptsRecent >= minAttempts;
  final priorOk = attemptsPrior >= minAttempts;
  if (!recentOk || !priorOk) return MixupDirection.tooFew;
  if (countRecent + countPrior < minMixups) return MixupDirection.tooFew;
  if (countPrior == 0) return MixupDirection.fresh;
  if (countRecent == 0) return MixupDirection.gone;
  final r = countRecent / attemptsRecent, p = countPrior / attemptsPrior;
  final diffPp = (r - p) * 100;
  // A change counts only if it is both visible in points and large relative
  // to the old rate — 1 % → 2 % is noise, 6 % → 12 % is not.
  if (diffPp >= 2 && r >= p * 1.3) return MixupDirection.up;
  if (diffPp <= -2 && r <= p * 0.7) return MixupDirection.down;
  return MixupDirection.same;
}

// Display order: what needs attention first.
const _order = [
  MixupDirection.up,
  MixupDirection.fresh,
  MixupDirection.down,
  MixupDirection.gone,
  MixupDirection.same,
  MixupDirection.tooFew,
];

/// Trends of all pairs seen in the last two windows, most relevant first:
/// grouped by direction (up, new, down, gone, same, too few), within a group
/// by the recent rate, highest first. Recent window = last [windowDays] days
/// including today, prior = the [windowDays] before it.
List<MixupTrend> mixupTrends(Map<String, DayStat> days, DateTime now,
    {int windowDays = 14, int minAttempts = 15, int minMixups = 3}) {
  final today = _date(now);
  final recentStart = today.subtract(Duration(days: windowDays - 1));
  final priorStart = today.subtract(Duration(days: 2 * windowDays - 1));
  final cntR = <String, int>{}, cntP = <String, int>{};
  final attR = <String, int>{}, attP = <String, int>{}; // per upper-case char
  days.forEach((k, s) {
    final parsed = DateTime.tryParse(k);
    if (parsed == null) return;
    final d = _date(parsed);
    if (d.isBefore(priorStart) || d.isAfter(today)) return;
    final recent = !d.isBefore(recentStart);
    final cnt = recent ? cntR : cntP, att = recent ? attR : attP;
    s.pairs.forEach((p, n) => cnt[p] = (cnt[p] ?? 0) + n);
    s.chars.forEach((ch, v) {
      final u = ch.toUpperCase();
      att[u] = (att[u] ?? 0) + v[0];
    });
  });
  final out = <MixupTrend>[];
  for (final p in {...cntR.keys, ...cntP.keys}) {
    final ch = p.split('>').first;
    final aR = attR[ch] ?? 0, aP = attP[ch] ?? 0;
    final cR = cntR[p] ?? 0, cP = cntP[p] ?? 0;
    out.add(MixupTrend(
        p, cR, cP, aR, aP,
        classifyMixup(
            countRecent: cR, countPrior: cP, attemptsRecent: aR, attemptsPrior: aP,
            minAttempts: minAttempts, minMixups: minMixups)));
  }
  out.sort((a, b) {
    final g = _order.indexOf(a.direction).compareTo(_order.indexOf(b.direction));
    if (g != 0) return g;
    final c = (b.rateRecent ?? b.ratePrior ?? 0).compareTo(a.rateRecent ?? a.ratePrior ?? 0);
    return c != 0 ? c : a.pair.compareTo(b.pair);
  });
  return out;
}

/// When the first trend statement becomes possible: the first day with logged
/// mix-ups plus two windows. Null while nothing is logged. [elapsed] is how
/// many of the 2 × [windowDays] days have passed (capped).
({DateTime from, int elapsed, int needed})? mixupTrendStart(
    Map<String, DayStat> days, DateTime now,
    {int windowDays = 14}) {
  DateTime? first;
  days.forEach((k, s) {
    if (s.pairs.isEmpty) return;
    final d = DateTime.tryParse(k);
    if (d == null) return;
    final u = _date(d);
    if (first == null || u.isBefore(first!)) first = u;
  });
  if (first == null) return null;
  final needed = 2 * windowDays;
  final elapsed = (_date(now).difference(first!).inDays + 1).clamp(0, needed);
  return (from: first!.add(Duration(days: needed)), elapsed: elapsed, needed: needed);
}
