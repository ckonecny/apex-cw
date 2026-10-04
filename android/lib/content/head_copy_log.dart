// Results of the comprehension mode (issue #7): one entry per finished round,
// hit rate = right answers / questions. Pure Dart: model, JSON and summary;
// the screen stores the string in the preferences.
import 'dart:convert';

import 'char_stats.dart' show dayKey;

/// Oldest rounds are dropped beyond this many.
const kKeepHcResults = 200;

class HcResult {
  final int time; // epoch ms
  final int level; // 1..3
  final int lang; // 0 German, 1 English (content language)
  final int right, total;

  const HcResult(this.time, this.level, this.lang, this.right, this.total);

  HcResult.fromJson(Map<String, dynamic> j)
      : time = j['t'] as int? ?? 0,
        level = j['l'] as int? ?? 1,
        lang = j['g'] as int? ?? 0,
        right = j['r'] as int? ?? 0,
        total = j['n'] as int? ?? 0;

  Map<String, dynamic> toJson() => {'t': time, 'l': level, 'g': lang, 'r': right, 'n': total};

  /// Hit rate 0..1.
  double get rate => total == 0 ? 0 : right / total;

  String get day => dayKey(DateTime.fromMillisecondsSinceEpoch(time));
}

List<HcResult> hcParseResults(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return [];
    return [for (final e in v) HcResult.fromJson(e as Map<String, dynamic>)];
  } catch (_) {
    return [];
  }
}

String hcEncodeResults(List<HcResult> list) {
  final keep = list.length > kKeepHcResults ? list.sublist(list.length - kKeepHcResults) : list;
  return jsonEncode([for (final r in keep) r.toJson()]);
}

/// Hit rate over the last [n] rounds (all levels), null without rounds.
double? hcRecentRate(List<HcResult> list, {int n = 10}) {
  final last = list.length > n ? list.sublist(list.length - n) : list;
  final total = last.fold<int>(0, (s, r) => s + r.total);
  if (total == 0) return null;
  return last.fold<int>(0, (s, r) => s + r.right) / total;
}
