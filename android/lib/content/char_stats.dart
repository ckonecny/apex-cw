// Shared per-character learning statistics, used by both the Echo Trainer's
// "Adapt. Rand." weighting and (planned) the Adaptive Copy mode's character
// selection / speed adaptation. See docs/ADAPTIVE-COPY.md for the design.
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
  final Map<String, CharStat> stats = {};

  Future<void> load(SharedPreferences p) async {
    stats.clear();
    final raw = p.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) => stats[k] = CharStat.fromJson(v as Map<String, dynamic>));
      return;
    }
    // Migrate the Echo Trainer's old "char:weight,char:weight" format, if
    // present, so existing users don't lose their learned weights.
    final legacy = p.getString(_legacyWeightsKey);
    if (legacy != null && legacy.isNotEmpty) {
      for (final part in legacy.split(',')) {
        final kv = part.split(':');
        if (kv.length != 2) continue;
        final w = int.tryParse(kv[1]);
        if (w == null) continue;
        stats[kv[0]] = CharStat()..weight = w.clamp(1, 20);
      }
      await save(p);
      await p.remove(_legacyWeightsKey);
    }
  }

  Future<void> save(SharedPreferences p) async {
    final encoded = <String, dynamic>{};
    stats.forEach((k, v) => encoded[k] = v.toJson());
    await p.setString(_prefsKey, jsonEncode(encoded));
  }

  // Wipes all per-character history (Settings "Reset Character Statistics").
  // Affects both Echo Trainer's "Adapt. Rand." weighting and Adaptive Copy's
  // weak-character/unlock/boost logic, since they share this store.
  Future<void> reset(SharedPreferences p) async {
    stats.clear();
    await p.remove(_prefsKey);
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
