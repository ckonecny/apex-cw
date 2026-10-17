// Practice suggestion from recurring mix-ups (issue #102, docs/DECISIONS.md
// "Mix-up practice suggestion"). Pure Dart on the trends of mixup_trend.dart:
// which pairs "K>R" keep happening, and which characters to boost for them.
// Proposal only — the UI lets the user tick pairs off, nothing changes silently.
import 'char_stats.dart';
import 'mixup_trend.dart';

/// Pairs worth practising, worst first, at most [maxPairs].
///
/// A pair qualifies when its trend is rising or new, or when it is simply
/// frequent: recent rate ≥ [minRate] with enough attempts and mix-ups (a
/// permanently bad pair would otherwise never be suggested, and the trend
/// needs four weeks of data). Falling and vanished pairs never qualify, nor
/// pairs where the character was left out ('–') or the same character.
/// With [candidates] only pairs whose played character can be drawn count.
List<MixupTrend> suggestedMixups(Map<String, DayStat> days, DateTime now,
    {int windowDays = 14,
    int minAttempts = 15,
    int minMixups = 3,
    double minRate = 0.10,
    int maxPairs = 3,
    Iterable<String>? candidates}) {
  final allowed = candidates?.map((c) => c.toUpperCase()).toSet();
  final out = <MixupTrend>[];
  for (final t in mixupTrends(days, now,
      windowDays: windowDays, minAttempts: minAttempts, minMixups: minMixups)) {
    if (t.given == '–' || t.given == t.played) continue;
    if (allowed != null && !allowed.contains(t.played.toUpperCase())) continue;
    final ok = switch (t.direction) {
      MixupDirection.up || MixupDirection.fresh => true,
      MixupDirection.down || MixupDirection.gone => false,
      _ => t.attemptsRecent >= minAttempts &&
          t.countRecent >= minMixups &&
          (t.rateRecent ?? 0) >= minRate,
    };
    if (ok) out.add(t);
  }
  out.sort((a, b) {
    final c = (b.rateRecent ?? 0).compareTo(a.rateRecent ?? 0);
    return c != 0 ? c : a.pair.compareTo(b.pair);
  });
  return out.take(maxPairs).toList();
}

/// The characters to boost for [pairs], in the spelling of [candidates] (the
/// drawable characters). Both characters of a pair count; a character that is
/// also weak or in several pairs appears once — the boost is a set, weights
/// never add up.
Set<String> mixupBoostChars(Iterable<MixupTrend> pairs, Iterable<String> candidates) {
  final byUpper = <String, List<String>>{};
  for (final c in candidates) {
    byUpper.putIfAbsent(c.toUpperCase(), () => []).add(c);
  }
  final out = <String>{};
  for (final t in pairs) {
    for (final ch in [t.played, t.given]) {
      out.addAll(byUpper[ch.toUpperCase()] ?? const []);
    }
  }
  return out;
}
