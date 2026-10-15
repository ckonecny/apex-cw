// Grading for the Hören typing mode (DECISIONS.md "Hören: typing mode"):
// which played characters were copied right, given what was typed.
//
// A plain position-by-position compare would count every character after a
// missed one as wrong. Instead the typed text is aligned to the played text
// with a Levenshtein alignment: a match is right, a substitution or a
// deletion (played but not typed) is wrong, an insertion (typed but not
// played) is ignored — a character that was not played cannot be wrong.

/// Per played character: the typed character it was aligned to, or null when
/// it was left out. Shared by [gradeTyped] and [firstMixup] so the alignment
/// exists once. Both texts are compared upper-cased.
List<String?> _alignTyped(String played, String typed) {
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
  final aligned = List<String?>.filled(n, null);
  var i = n, j = m;
  while (i > 0) {
    if (j > 0 && a[i - 1] == b[j - 1] && d[i][j] == d[i - 1][j - 1]) {
      aligned[i - 1] = b[j - 1];
      i--; j--;
    } else if (j > 0 && d[i][j] == d[i - 1][j - 1] + 1) {
      aligned[i - 1] = b[j - 1];
      i--; j--;
    } else if (d[i][j] == d[i - 1][j] + 1) {
      i--;
    } else {
      j--;
    }
  }
  return aligned;
}

/// Per played character: true = copied right. [played] and [typed] are
/// compared case-insensitively. An empty [typed] (passed) marks all wrong.
List<bool> gradeTyped(String played, String typed) {
  final a = played.toUpperCase();
  final aligned = _alignTyped(played, typed);
  return [for (var i = 0; i < a.length; i++) aligned[i] == a[i]];
}

/// The mix-up of the first wrongly copied character, as "played>typed"
/// (upper-case; '–' = left out), or null when everything was right. Same pair
/// format as `CharStatsStore.recordWord` (Geben). Blanks in [played] are not
/// characters and never count.
String? firstMixup(String played, String typed) {
  final a = played.toUpperCase();
  final aligned = _alignTyped(played, typed);
  for (var i = 0; i < a.length; i++) {
    if (a[i].trim().isEmpty || aligned[i] == a[i]) continue;
    return '${a[i]}>${aligned[i] ?? '–'}';
  }
  return null;
}

/// Whether [typed] counts as a right copy of [played] in the typing mode:
/// identical (case-insensitive), or the played text followed only by
/// repetitions of its last character — a key pressed twice at the end is a
/// typing slip, not a mis-heard character (issue #62). Any other extra or
/// missing character is still wrong.
bool isTypedRight(String played, String typed) {
  final a = played.toUpperCase();
  final b = typed.toUpperCase();
  if (a.isEmpty || !b.startsWith(a)) return false;
  final last = a[a.length - 1];
  for (var i = a.length; i < b.length; i++) {
    if (b[i] != last) return false;
  }
  return true;
}
