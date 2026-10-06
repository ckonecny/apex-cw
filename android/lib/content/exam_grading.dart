// Grading of the exam simulation's receive part (issue #42): errors counted
// like an examiner — every substituted, missing or extra character is one
// error, whitespace is ignored. Pure Dart.
import 'copy_grading.dart' show gradeTyped;
import '../keyer/morse_decoder.dart' show MorseDecoder;
import 'exam_profile.dart';

class ExamGrade {
  final int errors;
  final int limit;

  /// Per character of the played text without spaces: true = copied right.
  final List<bool> ok;

  /// The played text without spaces, aligned with [ok].
  final String played;

  const ExamGrade(this.errors, this.limit, this.ok, this.played);

  bool get passed => errors <= limit;

  /// Characters that were copied wrong, most frequent first.
  List<MapEntry<String, int>> get weakChars {
    final n = <String, int>{};
    for (var i = 0; i < ok.length; i++) {
      if (!ok[i]) n[played[i]] = (n[played[i]] ?? 0) + 1;
    }
    return n.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}

String _strip(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), '');

/// Levenshtein distance: substitutions, omissions and extra characters.
int examErrors(String played, String typed) {
  final a = _strip(played), b = _strip(typed);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = prev[j] + 1, ins = cur[j - 1] + 1;
      cur[j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
    prev = cur;
  }
  return prev[b.length];
}

ExamGrade gradeExamReceive(String played, String typed, int limit) {
  final a = _strip(played);
  return ExamGrade(examErrors(played, typed), limit, gradeTyped(a, _strip(typed)), a);
}

/// The send part has no official speed measurement here; these are this
/// project's assumptions (docs/DECISIONS.md "Exam simulation"): the keying
/// must reach this share of the text and this share of the exam speed.
const kExamSendMinText = 0.8;
const kExamSendMinSpeed = 0.85;

class ExamSendGrade {
  final int errors, limit;

  /// Characters of the text (without spaces) that were reached, and its length.
  final int reached, total;

  /// Estimated overall speed in WPM (PARIS) from the first to the last element
  /// keyed; 0 when too little was keyed to tell.
  final double wpm;
  final double minWpm;

  /// The reached part of the text without spaces, with per-character marks.
  final String played;
  final List<bool> ok;

  const ExamSendGrade(this.errors, this.limit, this.reached, this.total, this.wpm,
      this.minWpm, this.played, this.ok);

  bool get enoughText => reached >= total * kExamSendMinText;
  bool get fastEnough => wpm >= minWpm;
  bool get passed => errors <= limit && enoughText && fastEnough;

  List<MapEntry<String, int>> get weakChars =>
      ExamGrade(errors, limit, ok, played).weakChars;
}

final _codes = {for (final e in MorseDecoder.table.entries) e.value: e.key};

/// Length of [text] in dit units as sent in Morse (dit 1, dah 3, gap inside a
/// character 1, between characters 3, between words 7); a PARIS word is 50.
/// Characters without a code are skipped.
int morseUnits(String text) {
  var units = 0;
  var pendingChar = false, pendingWord = false;
  for (final ch in text.toUpperCase().split('')) {
    if (ch.trim().isEmpty) {
      if (pendingChar) pendingWord = true;
      continue;
    }
    final code = _codes[ch];
    if (code == null) continue;
    if (pendingChar) units += pendingWord ? 7 : 3;
    pendingWord = false;
    pendingChar = true;
    for (var i = 0; i < code.length; i++) {
      units += code[i] == '.' ? 1 : 3;
      if (i < code.length - 1) units += 1;
    }
  }
  return units;
}

/// Grades keyed text against the exam text. The candidate may stop before the
/// end, so the keyed text is compared with the best-fitting beginning of the
/// text; errors are substitutions, omissions and extras as in the receive part
/// ([examErrors]). [elapsedMs] runs from the first to the last element keyed.
ExamSendGrade gradeExamSend(String target, String keyed, int elapsedMs, ExamProfile p) {
  final a = _strip(target), b = _strip(keyed);
  final n = a.length, m = b.length;
  // d[i] = distance between a[0..i) and b, filled column by column.
  var prev = List<int>.generate(n + 1, (i) => i); // column j = 0
  for (var j = 1; j <= m; j++) {
    final cur = List<int>.filled(n + 1, 0)..[0] = j;
    for (var i = 1; i <= n; i++) {
      final sub = prev[i - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = prev[i] + 1, ins = cur[i - 1] + 1;
      cur[i] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
    prev = cur;
  }
  var best = 0;
  for (var i = 0; i <= n; i++) {
    if (prev[i] <= prev[best]) best = i; // ties: the longer beginning
  }
  final played = a.substring(0, best);
  // The reached part of the text with its word gaps, measured in dit units
  // (a PARIS word is 50), so figures and mixed groups count as they sound.
  var seen = 0, end = 0;
  while (end < target.length && seen < best) {
    if (target[end].trim().isNotEmpty) seen++;
    end++;
  }
  final units = morseUnits(target.substring(0, end));
  final wpm = elapsedMs < 5000 || best == 0 ? 0.0 : (units / 50) / (elapsedMs / 60000);
  return ExamSendGrade(prev[best], p.errorLimit, best, n, wpm,
      p.wpm * kExamSendMinSpeed, played, gradeTyped(played, b));
}
