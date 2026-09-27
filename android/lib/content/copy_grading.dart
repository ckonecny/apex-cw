// Grading for the Hören typing mode (DECISIONS.md "Hören: typing mode"):
// which played characters were copied right, given what was typed.
//
// A plain position-by-position compare would count every character after a
// missed one as wrong. Instead the typed text is aligned to the played text
// with a Levenshtein alignment: a match is right, a substitution or a
// deletion (played but not typed) is wrong, an insertion (typed but not
// played) is ignored — a character that was not played cannot be wrong.

/// Per played character: true = copied right. [played] and [typed] are
/// compared case-insensitively. An empty [typed] (passed) marks all wrong.
List<bool> gradeTyped(String played, String typed) {
  final a = played.toUpperCase();
  final b = typed.toUpperCase();
  final n = a.length, m = b.length;
  // d[i][j] = edit distance between a[0..i) and b[0..j).
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final sub = d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = d[i - 1][j] + 1;
      final ins = d[i][j - 1] + 1;
      d[i][j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
  }
  // Backtrace. Prefer a match, then a substitution, then a deletion, then
  // an insertion — so "cbnl" vs "cdnl" reads as d→b, not as d missing plus
  // an extra b.
  final ok = List<bool>.filled(n, false);
  var i = n, j = m;
  while (i > 0) {
    if (j > 0 && a[i - 1] == b[j - 1] && d[i][j] == d[i - 1][j - 1]) {
      ok[i - 1] = true;
      i--; j--;
    } else if (j > 0 && d[i][j] == d[i - 1][j - 1] + 1) {
      i--; j--;
    } else if (d[i][j] == d[i - 1][j] + 1) {
      i--;
    } else {
      j--;
    }
  }
  return ok;
}
