// Dev tool: renders a map layout as SVG, to check the hand-placed rooms.
//   dart run tool/zmap_svg.dart zork1 > map.svg
import 'dart:io';

import 'package:next_cw_trainer/adventure/adventure_map.dart';
import 'package:next_cw_trainer/zmachine/zmachine.dart';

void main(List<String> args) {
  final id = args[0];
  final z = ZMachine(File('assets/zork/$id.z3').readAsBytesSync())..start();
  final m = AdventureMap.build(z, File('assets/zork/${id}_map.json').readAsStringSync());
  const ux = 150.0, uy = 90.0, w = 120.0, h = 44.0;
  final xs = m.rooms.values.map((r) => r.x), ys = m.rooms.values.map((r) => r.y);
  final minX = xs.reduce((a, b) => a < b ? a : b), minY = ys.reduce((a, b) => a < b ? a : b);
  final maxX = xs.reduce((a, b) => a > b ? a : b), maxY = ys.reduce((a, b) => a > b ? a : b);
  double px(double x) => (x - minX) * ux + w;
  double py(double y) => (y - minY) * uy + h;
  final b = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${(maxX - minX) * ux + 2 * w}" '
        'height="${(maxY - minY) * uy + 2 * h}" font-family="sans-serif" font-size="11">')
    ..writeln('<rect width="100%" height="100%" fill="#fff"/>');
  for (final e in m.edges) {
    final a = m.rooms[e.a]!, c = m.rooms[e.b]!;
    if (e.jump) {
      for (final (r, o) in [(a, c), (c, a)]) {
        b.writeln('<text x="${px(r.x)}" y="${py(r.y) + h / 2 + 11}" text-anchor="middle" '
            'fill="#07a" font-size="10">→ ${o.name}</text>');
      }
      continue;
    }
    b.writeln('<line x1="${px(a.x)}" y1="${py(a.y)}" x2="${px(c.x)}" y2="${py(c.y)}" '
        'stroke="${e.oneWayFrom != null ? '#c00' : '#555'}" stroke-width="1.5"'
        '${e.vertical ? ' stroke-dasharray="5,4"' : ''}/>');
  }
  for (final l in m.labels) {
    b.writeln('<text x="${px(l.x)}" y="${py(l.y)}" text-anchor="middle" font-size="14" '
        'font-weight="bold" fill="#999">${l.text}</text>');
  }
  for (final r in m.rooms.values) {
    b.writeln('<rect x="${px(r.x) - w / 2}" y="${py(r.y) - h / 2}" width="$w" height="$h" rx="6" '
        'fill="#eef" stroke="#336"/>');
    b.writeln('<text x="${px(r.x)}" y="${py(r.y) - 2}" text-anchor="middle">${r.name}</text>');
    b.writeln('<text x="${px(r.x)}" y="${py(r.y) + 13}" text-anchor="middle" fill="#999">${r.id}</text>');
  }
  b.writeln('</svg>');
  stdout.write(b);
}
