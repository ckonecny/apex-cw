// Map of a text adventure (DECISIONS.md "Text adventure: map").
//
// Rooms and exits come from the story file: the rooms are the children of
// the start room's parent, the exits their direction properties. The
// screen position of every room is set by hand per game in
// assets/zork/<id>_map.json, because the games are not geometric. That file
// also names the "visited" attribute (TOUCHBIT) and exits the story only
// computes in a routine (FEXIT), which the data can't show.
import 'dart:convert';

import '../zmachine/zmachine.dart';

/// Direction properties, numbered down from 31 in <DIRECTIONS NORTH EAST
/// WEST SOUTH NE NW SE SW UP DOWN IN OUT LAND …>. Zork II and III add CROSS
/// (18); in Zork I property 18 is something else, so the layout file says
/// how many there are ("directions", default 13).
const mapDirections = {
  31: 'N', 30: 'E', 29: 'W', 28: 'S', 27: 'NE', 26: 'NW', 25: 'SE', 24: 'SW',
  23: 'U', 22: 'D', 21: 'IN', 20: 'OUT', 19: 'LAND', 18: 'CROSS',
};

/// Free text on the map (e.g. the year of a time-travel copy of rooms).
class MapLabel {
  final double x, y;
  final String text;
  const MapLabel(this.x, this.y, this.text);
}

class MapRoom {
  final int id;
  final String name;
  final double x, y;
  const MapRoom(this.id, this.name, this.x, this.y);
}

/// A connection between two rooms, stored once per pair (a < b).
class MapEdge {
  final int a, b;
  /// Only up/down (drawn dashed): stairs, chimneys, climbing.
  final bool vertical;
  /// Leads only from [from] to the other end (drawn with an arrow).
  final int? oneWayFrom;
  /// Too far apart on the map for a line: drawn as a small note at each end
  /// ("↓ Cellar") instead.
  final bool jump;
  const MapEdge(this.a, this.b, {this.vertical = false, this.oneWayFrom, this.jump = false});

  int other(int r) => r == a ? b : a;
}

class AdventureMap {
  final Map<int, MapRoom> rooms;
  final List<MapEdge> edges;
  final int touchAttr;
  final List<MapLabel> labels;
  final Set<int> _pairs;

  AdventureMap._(this.rooms, this.edges, this.touchAttr, this.labels)
      : _pairs = {for (final e in edges) _key(e.a, e.b)};

  static int _key(int a, int b) => a < b ? (a << 8) | b : (b << 8) | a;

  /// Whether the story connects [a] and [b] (either way). A move between
  /// rooms that aren't connected (teleport, several commands in one line)
  /// is not recorded as a walked path.
  bool connected(int a, int b) => _pairs.contains(_key(a, b));

  static AdventureMap build(ZMachine z, String layoutJson) {
    final j = jsonDecode(layoutJson) as Map<String, dynamic>;
    final pos = (j['rooms'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(int.parse(k), ((v as List)[0] as num, v[1] as num)));
    final rooms = <int, MapRoom>{};
    final home = z.status.roomObject;
    final parent = home == 0 ? 0 : z.parentOf(home);
    for (var r = parent == 0 ? 0 : z.childOf(parent); r != 0; r = z.siblingOf(r)) {
      final p = pos[r];
      if (p == null) continue; // not placed: not on the map
      rooms[r] = MapRoom(r, z.objectName(r), p.$1.toDouble(), p.$2.toDouble());
    }

    // Exits: 1 byte = room, 4 = room + condition, 5 = room + door
    // (UEXIT / CEXIT / DEXIT); 2 = no exit, 3 = routine (FEXIT).
    final dirs = <int, Map<int, Set<String>>>{}; // from -> to -> directions
    final lowest = 32 - ((j['directions'] as num?)?.toInt() ?? 13);
    for (final r in rooms.keys) {
      mapDirections.forEach((prop, d) {
        if (prop < lowest) return;
        final b = z.property(r, prop);
        if (b == null || !(b.length == 1 || b.length == 4 || b.length == 5)) return;
        if (!rooms.containsKey(b[0]) || b[0] == r) return;
        dirs.putIfAbsent(r, () => {}).putIfAbsent(b[0], () => {}).add(d);
      });
    }
    for (final e in (j['extra'] as List? ?? const [])) {
      final l = e as List;
      final a = l[0] as int, b = l[1] as int;
      if (!rooms.containsKey(a) || !rooms.containsKey(b)) continue;
      dirs.putIfAbsent(a, () => {}).putIfAbsent(b, () => {}).add(l.length > 2 ? l[2] as String : 'D');
    }

    final jumps = {
      for (final e in (j['jumps'] as List? ?? const []))
        _key((e as List)[0] as int, e[1] as int),
    };
    final edges = <MapEdge>[];
    final done = <int>{};
    dirs.forEach((a, tos) {
      tos.forEach((b, ds) {
        if (!done.add(_key(a, b))) return;
        final back = dirs[b]?[a];
        final all = {...ds, ...?back};
        final vertical = all.every((d) => d == 'U' || d == 'D');
        edges.add(MapEdge(a < b ? a : b, a < b ? b : a,
            vertical: vertical, oneWayFrom: back == null ? a : null,
            jump: jumps.contains(_key(a, b))));
      });
    });
    final labels = [
      for (final l in (j['labels'] as List? ?? const []))
        MapLabel(((l as List)[0] as num).toDouble(), (l[1] as num).toDouble(), l[2] as String),
    ];
    return AdventureMap._(rooms, edges, (j['touchAttr'] as num).toInt(), labels);
  }

  /// Rooms the player has seen: the game's own "visited" flag.
  Set<int> visited(ZMachine z) => {
        for (final r in rooms.keys)
          if (z.hasAttr(r, touchAttr)) r,
      };
}
