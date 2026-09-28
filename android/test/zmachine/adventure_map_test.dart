// Maps of Zork I–III: every room is placed, boxes don't overlap, no path is
// drawn through another room, and every direction step of the full
// solution walks a path the map knows (so the FEXIT extras are complete).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/adventure/adventure_map.dart';
import 'package:next_cw_trainer/zmachine/zmachine.dart';

// Must match adventure_map_screen.dart.
const ux = 150.0, uy = 90.0, bw = 124.0, bh = 46.0;

AdventureMap build(String id, ZMachine z) =>
    AdventureMap.build(z, File('assets/zork/${id}_map.json').readAsStringSync());

/// Whether segment p–q passes through the box around c (shrunk a little).
bool crosses(Point<double> p, Point<double> q, Point<double> c) {
  const hw = bw / 2 - 2, hh = bh / 2 - 2;
  for (var i = 0; i <= 100; i++) {
    final t = i / 100;
    final x = p.x + (q.x - p.x) * t, y = p.y + (q.y - p.y) * t;
    if ((x - c.x).abs() < hw && (y - c.y).abs() < hh) return true;
  }
  return false;
}

void main() {
  // id, rooms, moves the solution makes between rooms that are not
  // connected on purpose (random teleports), as room names.
  const games = [
    ('zork1', 110, <String>{}),
    ('zork2', 86, {'Oddly-angled Room'}), // the diamond maze drops you anywhere
    ('zork3', 89, <String>{}),
  ];

  for (final (id, count, teleports) in games) {
    test('$id: every room placed, no overlaps, no path through a room', () {
      final z = ZMachine(File('assets/zork/$id.z3').readAsBytesSync())..start();
      final m = build(id, z);
      final parent = z.parentOf(z.status.roomObject);
      var n = 0;
      for (var r = z.childOf(parent); r != 0; r = z.siblingOf(r)) {
        n++;
        expect(m.rooms.containsKey(r), isTrue, reason: 'not placed: $r ${z.objectName(r)}');
      }
      expect(n, count);
      expect(m.rooms.length, count);

      Point<double> px(MapRoom r) => Point(r.x * ux, r.y * uy);
      final rs = m.rooms.values.toList();
      final overlaps = <String>[];
      for (var i = 0; i < rs.length; i++) {
        for (var j = i + 1; j < rs.length; j++) {
          final a = px(rs[i]), b = px(rs[j]);
          if ((a.x - b.x).abs() < bw + 8 && (a.y - b.y).abs() < bh + 8) {
            overlaps.add('${rs[i].name}(${rs[i].id}) / ${rs[j].name}(${rs[j].id})');
          }
        }
      }
      expect(overlaps, isEmpty);
      final bad = <String>[];
      for (final e in m.edges.where((e) => !e.jump)) {
        final a = m.rooms[e.a]!, b = m.rooms[e.b]!;
        for (final o in rs) {
          if (o.id == e.a || o.id == e.b) continue;
          if (crosses(px(a), px(b), px(o))) {
            bad.add('${a.name}(${a.id})–${b.name}(${b.id}) over ${o.name}(${o.id})');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('$id: the full solution only walks paths the map knows', () {
      final z = ZMachine(File('assets/zork/$id.z3').readAsBytesSync(), random: Random(1));
      z.start();
      final m = build(id, z);
      const dirs = {'n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw', 'u', 'd', 'up', 'down',
        'north', 'south', 'east', 'west', 'in', 'out', 'enter', 'exit', 'land', 'cross'};
      final unknown = <String>{};
      final script = File('test/zmachine/${id}_walkthrough.txt').readAsStringSync();
      for (final raw in script.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final until = line.startsWith('!until ');
        final cmd = until ? line.split(' :: ')[1] : line;
        final re = until ? RegExp(line.substring(7).split(' :: ')[0], caseSensitive: false) : null;
        for (var i = 0; i < (until ? 30 : 1); i++) {
          final from = z.status.roomObject;
          final out = z.input(cmd);
          final to = z.status.roomObject;
          final teleport = teleports.contains(z.objectName(from)) && teleports.contains(z.objectName(to));
          if (from != to && dirs.contains(cmd.toLowerCase()) && !teleport && !m.connected(from, to)) {
            unknown.add('$cmd: ${z.objectName(from)}($from) -> ${z.objectName(to)}($to)');
          }
          if (re != null && re.hasMatch(out)) break;
        }
      }
      expect(unknown, isEmpty);
      // The game's own "visited" flag works for this game.
      expect(m.visited(z).length, greaterThan(count ~/ 2));
    });
  }
}
