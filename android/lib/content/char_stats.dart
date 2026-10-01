// Per-character learning statistics, one track for hearing (Adaptive Copy,
// Koch generator) and one for sending (Echo Trainer "Adapt. Rand."). See docs/ADAPTIVE-COPY.md for the design.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'charStats';
const _legacyWeightsKey = 'adaptiveWeights';

// How much a single miss/hit moves the moving error rate — not yet consumed
// by any UI, kept for the Adaptive Copy engine (docs/ADAPTIVE-COPY.md).
const _emaAlpha = 0.2;

class CharStat {
  int attempts = 0;
  int errors = 0;
  double emaErrorRate = 0.0;
  int lastBlock = 0;
  // 1..20 draw weight — same range/formula the Echo Trainer's "Adapt. Rand."
  // used before this store existed (wrong: +2, right: -1, clamped).
  int weight = 1;
  // Last [historyLen] results, oldest first, '1' = right / '0' = wrong. Feeds
  // the result strip in the detail sheet; empty for data from before it existed.
  String history = '';
  // Epoch ms of the last attempt (0 = unknown / older data).
  int lastTs = 0;

  static const historyLen = 30;

  CharStat();

  // Books one result into the strip and the timestamp — the single place, so
  // record() and recordWord() cannot drift apart.
  void _log(bool correct) {
    final h = history + (correct ? '1' : '0');
    history = h.length > historyLen ? h.substring(h.length - historyLen) : h;
    lastTs = DateTime.now().millisecondsSinceEpoch;
  }

  CharStat.fromJson(Map<String, dynamic> j)
      : attempts = j['a'] as int? ?? 0,
        errors = j['e'] as int? ?? 0,
        emaErrorRate = (j['ema'] as num?)?.toDouble() ?? 0.0,
        lastBlock = j['lb'] as int? ?? 0,
        weight = j['w'] as int? ?? 1,
        history = j['h'] as String? ?? '',
        lastTs = j['t'] as int? ?? 0;

  Map<String, dynamic> toJson() => {
        'a': attempts, 'e': errors, 'ema': emaErrorRate, 'lb': lastBlock, 'w': weight,
        if (history.isNotEmpty) 'h': history,
        if (lastTs > 0) 't': lastTs,
      };

  // Share of right answers over all attempts; null before the first one.
  double? get overallRate => attempts == 0 ? null : (attempts - errors) / attempts;

  // How many right answers in a row lift the moving average to `threshold`
  // (hit rate) — 0 if already there, null if that would take absurdly long
  // (threshold 1.0). Same EMA step as CharStatsStore.record.
  int? correctsToReach(double threshold) {
    var ema = emaErrorRate;
    for (var n = 0; n <= 100; n++) {
      if (1 - ema >= threshold) return n;
      ema *= 1 - _emaAlpha;
    }
    return null;
  }
}

class CharStatsStore {
  static const hear = 'hear';
  static const echo = 'echo';

  // Two separate tracks (docs/archive/training/P4-zeichenstatistik.md): what is
  // heard wrongly is not what is sent wrongly. Stored as `charStats.<track>`.
  final String track;
  CharStatsStore([this.track = hear]);

  final Map<String, CharStat> stats = {};
  // Confusions "T>G" (target > given, '–' = left out) → count, first wrong
  // char of each first attempt only. Display only (docs/archive/training/P8).
  final Map<String, int> pairs = {};

  String get _pairsKey => '$_key.pairs';

  List<MapEntry<String, int>> topPairs([int n = 10]) {
    final l = pairs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(n).toList();
  }

  String get _key => '$_prefsKey.$track';

  // Moves the old single store (and the even older Echo "char:weight" list)
  // into the hearing track, once. The echo track starts empty.
  static Future<void> migrateIfNeeded(SharedPreferences p) async {
    final old = p.getString(_prefsKey);
    if (old != null) {
      if (old.isNotEmpty && p.getString('$_prefsKey.$hear') == null) {
        await p.setString('$_prefsKey.$hear', old);
      }
      await p.remove(_prefsKey);
    }
    final legacy = p.getString(_legacyWeightsKey);
    if (legacy != null) {
      if (legacy.isNotEmpty && p.getString('$_prefsKey.$hear') == null) {
        final store = CharStatsStore(hear);
        for (final part in legacy.split(',')) {
          final kv = part.split(':');
          if (kv.length != 2) continue;
          final w = int.tryParse(kv[1]);
          if (w == null) continue;
          store.stats[kv[0]] = CharStat()..weight = w.clamp(1, 20);
        }
        await store.save(p);
      }
      await p.remove(_legacyWeightsKey);
    }
  }

  Future<void> load(SharedPreferences p) async {
    await migrateIfNeeded(p);
    stats.clear();
    pairs.clear();
    final rp = p.getString(_pairsKey);
    if (rp != null && rp.isNotEmpty) {
      (jsonDecode(rp) as Map<String, dynamic>).forEach((k, v) => pairs[k] = v as int);
    }
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) => stats[k] = CharStat.fromJson(v as Map<String, dynamic>));
    }
  }

  Future<void> save(SharedPreferences p) async {
    final encoded = <String, dynamic>{};
    stats.forEach((k, v) => encoded[k] = v.toJson());
    await p.setString(_key, jsonEncode(encoded));
    await p.setString(_pairsKey, jsonEncode(pairs));
  }

  // Wipes this track's per-character history only.
  Future<void> reset(SharedPreferences p) async {
    stats.clear();
    pairs.clear();
    await p.remove(_key);
    await p.remove(_pairsKey);
  }

  // Draw weight for a character — defaults to 1 (never drawn / already
  // mastered back down to baseline).
  int weightFor(String char) => stats[char]?.weight ?? 1;

  // Records one attempt at `char`. `block` is an optional counter the caller
  // maintains (e.g. Adaptive Copy block index) — left at 0 for callers, like
  // the Echo Trainer today, that don't track blocks.
  void record(String char, bool correct, {int block = 0}) {
    final s = stats.putIfAbsent(char, () => CharStat());
    s.attempts++;
    if (!correct) s.errors++;
    s.emaErrorRate = _emaAlpha * (correct ? 0 : 1) + (1 - _emaAlpha) * s.emaErrorRate;
    s.lastBlock = block;
    s._log(correct);
    s.weight = (correct ? s.weight - 1 : s.weight + 2).clamp(1, 20);
  }

  // Books one Echo word after its FIRST attempt (docs/archive/training/P6). Weights
  // follow Koch::increaseWordProbability / decreaseWordProbability in
  // MorsePreferences.cpp: first wrong char +4, its neighbours +2 (only if a
  // different char), a fully right word -1 per char. Attempts/errors/EMA:
  // chars before the first wrong one count as right, the wrong one as an
  // error, chars after it are not counted (unknown whether heard).
  // Returns the confusion pair "T>G" of the first wrong char, or null.
  String? recordWord(String target, String received, {int block = 0}) {
    final t = target.toUpperCase(), r = received.trim().toUpperCase();
    var failed = -1;
    for (var i = 0; i < t.length; i++) {
      if (i >= r.length || t[i] != r[i]) { failed = i; break; }
    }
    void bump(String ch, {bool? correct, int weight = 0}) {
      if (ch.trim().isEmpty) return;
      final s = stats.putIfAbsent(ch, () => CharStat());
      if (correct != null) {
        s.attempts++;
        if (!correct) s.errors++;
        s.emaErrorRate = _emaAlpha * (correct ? 0 : 1) + (1 - _emaAlpha) * s.emaErrorRate;
        s.lastBlock = block;
        s._log(correct);
      }
      s.weight = (s.weight + weight).clamp(1, 20);
    }
    if (failed == -1) {
      for (final ch in t.split('')) { bump(ch, correct: true, weight: -1); }
      return null;
    }
    final pair = '${t[failed]}>${failed < r.length ? r[failed] : '–'}';
    if (t[failed].trim().isNotEmpty) pairs[pair] = (pairs[pair] ?? 0) + 1;
    for (var i = 0; i < failed; i++) { bump(t[i], correct: true); }
    bump(t[failed], correct: false, weight: 4);
    if (failed > 0 && t[failed - 1] != t[failed]) bump(t[failed - 1], weight: 2);
    if (failed + 1 < t.length && t[failed + 1] != t[failed]) bump(t[failed + 1], weight: 2);
    return pair;
  }
}

// Lifetime-EMA weak characters among `activeChars`, worst first — shared
// between Adaptive Copy's result screen and the Koch Trainer's start screen
// (both let the user tap a char to include/exclude it from a boosted draw).
// Needs enough attempts to be meaningful (not one unlucky group) and an
// error rate clearly above noise.
Map<String, double> weakCharsLifetime(
  CharStatsStore store,
  List<String> activeChars, {
  int minAttempts = 8,
  double threshold = 0.12,
  int maxShown = 5,
}) {
  final entries = <MapEntry<String, double>>[];
  for (final ch in activeChars) {
    final s = store.stats[ch];
    if (s == null || s.attempts < minAttempts) continue;
    if (s.emaErrorRate < threshold) continue;
    entries.add(MapEntry(ch, s.emaErrorRate));
  }
  entries.sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(entries.take(maxShown));
}
