// Results of the exam simulation (issue #42): one entry per finished part.
// Pure Dart: model, JSON and the pass forecast; the screen stores the string
// in the preferences.
import 'dart:convert';

/// Oldest entries are dropped beyond this many.
const kKeepExamResults = 200;

class ExamResult {
  final int time; // epoch ms
  final String profile; // ExamProfile.id
  final String part; // 'rx' receive, 'tx' send
  final int errors, limit;
  final String weak; // wrongly copied or keyed characters, e.g. "PJ6"

  /// Send part: estimated speed in WPM, 0 when not measured.
  final int wpm;
  final bool? verdict;

  const ExamResult(this.time, this.profile, this.part, this.errors, this.limit, this.weak,
      {this.wpm = 0, this.verdict});

  ExamResult.fromJson(Map<String, dynamic> j)
      : time = j['t'] as int? ?? 0,
        profile = j['p'] as String? ?? '',
        part = j['a'] as String? ?? 'rx',
        errors = j['e'] as int? ?? 0,
        limit = j['l'] as int? ?? 0,
        weak = j['w'] as String? ?? '',
        wpm = j['m'] as int? ?? 0,
        verdict = j['k'] as bool?;

  Map<String, dynamic> toJson() => {'t': time, 'p': profile, 'a': part, 'e': errors, 'l': limit, 'w': weak,
        if (wpm > 0) 'm': wpm,
        if (verdict != null) 'k': verdict,
      };

  /// The send part also needs enough text and speed, so it stores its verdict.
  bool get passed => verdict ?? errors <= limit;
}

List<ExamResult> examParseResults(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return [];
    return [for (final e in v) ExamResult.fromJson(e as Map<String, dynamic>)];
  } catch (_) {
    return [];
  }
}

String examEncodeResults(List<ExamResult> list) {
  final keep = list.length > kKeepExamResults ? list.sublist(list.length - kKeepExamResults) : list;
  return jsonEncode([for (final r in keep) r.toJson()]);
}

/// The last [n] results of [profile] and [part], oldest first.
List<ExamResult> examRecent(List<ExamResult> all, String profile, String part, {int n = 5}) {
  final m = [for (final r in all) if (r.profile == profile && r.part == part) r];
  return m.length > n ? m.sublist(m.length - n) : m;
}

/// "Ready" forecast: the last [need] runs all passed. Null without enough runs.
bool? examReady(List<ExamResult> all, String profile, String part, {int need = 3}) {
  final m = examRecent(all, profile, part, n: need);
  if (m.length < need) return null;
  return m.every((r) => r.passed);
}
