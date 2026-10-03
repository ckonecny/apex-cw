// Scoring and high-score table of the grid games, ported from
// MorseGridScore.cpp: characters per minute over the solve time, with 5 s
// added per wrong entry. One table of 7 per game.
import 'dart:convert';

const gridHiN = 7;
const _wrongPenaltyMs = 5000;

class GridScore {
  final int cpm, elapsedMs, wrong, steps, koch;
  const GridScore(this.cpm, this.elapsedMs, this.wrong, this.steps, this.koch);

  Map<String, int> toJson() =>
      {'c': cpm, 't': elapsedMs, 'w': wrong, 's': steps, 'k': koch};
  static GridScore fromJson(Map m) =>
      GridScore(m['c'], m['t'], m['w'], m['s'], m['k']);
}

int gridAdjustedMs(int elapsedMs, int wrong) => elapsedMs + wrong * _wrongPenaltyMs;

/// Effective characters per minute (rounded), as the firmware.
int gridCpm(int elapsedMs, int steps, int wrong) {
  var adj = gridAdjustedMs(elapsedMs, wrong);
  if (adj == 0) adj = 1;
  return (steps * 60000 + adj ~/ 2) ~/ adj;
}

GridScore gridScore(int elapsedMs, int steps, int wrong, int koch) =>
    GridScore(gridCpm(elapsedMs, steps, wrong), elapsedMs, wrong, steps, koch);

/// Inserts [s] into [table] if it ranks (higher CPM first; a tie ranks below
/// the older entry). Returns the 0-based rank, or -1.
int gridRecord(List<GridScore> table, GridScore s) {
  if (s.cpm == 0) return -1;   // the firmware's empty slots are cpm 0
  for (var i = 0; i < gridHiN; i++) {
    if (i >= table.length || s.cpm > table[i].cpm) {
      table.insert(i, s);
      if (table.length > gridHiN) table.removeLast();
      return i;
    }
  }
  return -1;
}

String gridTableToJson(List<GridScore> t) =>
    jsonEncode(t.map((e) => e.toJson()).toList());

List<GridScore> gridTableFromJson(String? raw) {
  try {
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((m) => GridScore.fromJson(m as Map)).toList();
  } catch (_) {
    return [];
  }
}
