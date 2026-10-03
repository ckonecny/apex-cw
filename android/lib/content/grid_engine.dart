// Grid engine shared by Trailblazer and Fox Hunt, ported from
// MorseGridEngine.cpp: a 12x4 grid of Koch characters with a hidden,
// self-avoiding path from the left to the right edge. Both games walk the
// same path one cell at a time; they differ only in how a step is triggered
// (Trailblazer: key the highlighted letter; Fox Hunt: key the direction
// toward a letter you hear). Pure Dart with an injectable Random, so it is
// unit-testable.
import 'dart:math';

const gridCols = 12;
const gridRows = 4;

/// Compass direction; the order matches the firmware's N/S/W/E legend.
enum GridDir { n, s, w, e }

/// One legend slot: the key letter for a direction, whether it substitutes
/// for the canonical compass letter, and which one.
class DirInfo {
  final String ltr;
  final bool substituted;
  final String canonical;
  const DirInfo(this.ltr, this.substituted, this.canonical);
}

class GridEngine {
  final Random _random;
  GridEngine([Random? random]) : _random = random ?? Random();

  static const _canon = ['N', 'S', 'W', 'E'];

  List<String> _grid = List.filled(gridCols * gridRows, 'M');
  final List<int> _pathCol = [], _pathRow = [];
  final List<bool> _visited = List.filled(gridCols * gridRows, false);
  List<String> _pool = ['M'];
  int _pos = 0;

  String cell(int col, int row) => _grid[row * gridCols + col];
  int get pathLength => _pathCol.length;
  int get currentIndex => _pos;
  bool get atEnd => _pos >= pathLength - 1;
  int pathColAt(int i) => _pathCol[i];
  int pathRowAt(int i) => _pathRow[i];

  /// The character at the next path cell: what Trailblazer highlights and
  /// Fox Hunt plays. Undefined once [atEnd].
  String get nextChar => cell(_pathCol[_pos + 1], _pathRow[_pos + 1]);

  /// Fresh grid and hidden path, every cell drawn from [pool] (the Koch
  /// lesson set). Resets the position to the start of the path.
  void generate(List<String> pool) {
    _pool = pool.isEmpty ? ['M'] : List.of(pool);
    _genPath();
    _grid = [for (var i = 0; i < gridCols * gridRows; i++) _randomChar()];
    _fixNeighbourCollisions();
    _pos = 0;
  }

  String _randomChar() => _pool[_random.nextInt(_pool.length)];

  // Randomised self-avoiding DFS from column 0 to the last column. The grid
  // has no obstacles, so one exhaustive pass always succeeds; the
  // straight-line fallback is defensive only (as in the firmware).
  bool _walk(int c, int r) {
    _visited[r * gridCols + c] = true;
    _pathCol.add(c);
    _pathRow.add(r);
    if (c == gridCols - 1) return true;

    const dc = [1, -1, 0, 0], dr = [0, 0, 1, -1];
    final order = [0, 1, 2, 3];
    for (var i = 3; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    for (final o in order) {
      final nc = c + dc[o], nr = r + dr[o];
      if (nc < 0 || nc >= gridCols || nr < 0 || nr >= gridRows) continue;
      if (_visited[nr * gridCols + nc]) continue;
      if (_walk(nc, nr)) return true;
    }
    _pathCol.removeLast();
    _pathRow.removeLast();
    _visited[r * gridCols + c] = false;
    return false;
  }

  void _genPath() {
    _visited.fillRange(0, _visited.length, false);
    _pathCol.clear();
    _pathRow.clear();
    final startRow = _random.nextInt(gridRows);
    if (!_walk(0, startRow)) {
      _pathCol.clear();
      _pathRow.clear();
      for (var c = 0; c < gridCols; c++) {
        _pathCol.add(c);
        _pathRow.add(startRow);
      }
    }
  }

  // Fox Hunt plays the next path cell's character and expects the direction
  // toward it, so no two neighbours of a path cell may share a character
  // (otherwise a correctly heard letter doesn't tell the direction). A few
  // passes, since a fix at one cell can reintroduce a clash next door. The
  // firmware stops after 3 passes and can leave a rare clash behind; here the
  // passes continue (up to 12) until a pass changes nothing.
  void _fixNeighbourCollisions() {
    for (var pass = 0; pass < 12; pass++) {
      var changed = false;
      for (var p = 0; p < pathLength; p++) {
        final c = _pathCol[p], r = _pathRow[p];
        final ni = <int>[
          if (r > 0) (r - 1) * gridCols + c,
          if (r < gridRows - 1) (r + 1) * gridCols + c,
          if (c > 0) r * gridCols + (c - 1),
          if (c < gridCols - 1) r * gridCols + (c + 1),
        ];
        for (var i = 1; i < ni.length; i++) {
          for (var j = 0; j < i; j++) {
            if (_grid[ni[i]] != _grid[ni[j]]) continue;
            final victim = i;   // no prosigns in this app's pool
            for (var tries = 0; tries < 40; tries++) {
              final cand = _randomChar();
              var clash = false;
              for (var k = 0; k < ni.length; k++) {
                if (k != victim && _grid[ni[k]] == cand) {
                  clash = true;
                  break;
                }
              }
              if (!clash) {
                _grid[ni[victim]] = cand;
                changed = true;
                break;
              }
            }
          }
        }
      }
      if (!changed) break;
    }
  }

  /// The four legend slots against [pool]: the canonical N/S/W/E letter where
  /// it is learned, otherwise the first not yet assigned learned letter ('?'
  /// if none is left).
  static List<DirInfo> directionLegend(List<String> pool) {
    final letters = [
      for (final c in pool)
        if (c.length == 1 && RegExp('[A-Z]').hasMatch(c)) c,
    ];
    final ltr = List<String?>.filled(4, null);
    final subst = List<bool>.filled(4, false);
    final used = <String>{};
    for (var d = 0; d < 4; d++) {
      if (letters.contains(_canon[d])) {
        ltr[d] = _canon[d];
        used.add(_canon[d]);
      }
    }
    for (var d = 0; d < 4; d++) {
      if (ltr[d] != null) continue;
      subst[d] = true;
      ltr[d] = '?';
      for (final l in letters) {
        if (!used.contains(l)) {
          ltr[d] = l;
          used.add(l);
          break;
        }
      }
    }
    return [for (var d = 0; d < 4; d++) DirInfo(ltr[d]!, subst[d], _canon[d])];
  }

  /// Does one step in [d] from the current cell land on the next path cell?
  bool directionMatchesNext(GridDir d) {
    if (atEnd) return false;
    var c = _pathCol[_pos], r = _pathRow[_pos];
    switch (d) {
      case GridDir.n: r -= 1;
      case GridDir.s: r += 1;
      case GridDir.w: c -= 1;
      case GridDir.e: c += 1;
    }
    return c == _pathCol[_pos + 1] && r == _pathRow[_pos + 1];
  }

  /// Moves to the next path cell (on a correct answer).
  void advance() {
    if (_pos < pathLength - 1) _pos++;
  }
}
