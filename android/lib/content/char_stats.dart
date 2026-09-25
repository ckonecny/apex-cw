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

  CharStat();

  CharStat.fromJson(Map<String, dynamic> j)
      : attempts = j['a'] as int? ?? 0,
        errors = j['e'] as int? ?? 0,
        emaErrorRate = (j['ema'] as num?)?.toDouble() ?? 0.0,
        lastBlock = j['lb'] as int? ?? 0,
        weight = j['w'] as int? ?? 1;

  Map<String, dynamic> toJson() =>
      {'a': attempts, 'e': errors, 'ema': emaErrorRate, 'lb': lastBlock, 'w': weight};
}

class CharStatsStore {
  static const hear = 'hear';
  static const echo = 'echo';

  // Two separate tracks (docs/training/P4-zeichenstatistik.md): what is
  // heard wrongly is not what is sent wrongly. Stored as `charStats.<track>`.
  final String track;
  CharStatsStore([this.track = hear]);

  final Map<String, CharStat> stats = {};

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
  }

  // Wipes this track's per-character history only.
  Future<void> reset(SharedPreferences p) async {
    stats.clear();
    await p.remove(_key);
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
    s.weight = (correct ? s.weight - 1 : s.weight + 2).clamp(1, 20);
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
