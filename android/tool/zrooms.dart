// Dev tool: dumps a story file's rooms and exits (for the map layout).
//   dart run tool/zrooms.dart assets/zork/zork1.z3
import 'dart:io';

import 'package:next_cw_trainer/zmachine/zmachine.dart';

const dirs = {31: 'N', 30: 'E', 29: 'W', 28: 'S', 27: 'NE', 26: 'NW', 25: 'SE', 24: 'SW',
  23: 'U', 22: 'D', 21: 'IN', 20: 'OUT', 19: 'LAND', 18: 'CROSS'};

void main(List<String> args) {
  final z = ZMachine(File(args[0]).readAsBytesSync());
  z.start();
  final rooms = z.parentOf(z.status.roomObject);
  for (var r = z.childOf(rooms); r != 0; r = z.siblingOf(r)) {
    final ex = <String>[];
    dirs.forEach((p, d) {
      final b = z.property(r, p);
      if (b == null) return;
      switch (b.length) {
        case 1: ex.add('$d>${b[0]}');
        case 2: ex.add('$d:no');
        case 3: ex.add('$d:fn');
        case 4: ex.add('$d>${b[0]}?g${b[1]}');
        case 5: ex.add('$d>${b[0]}?door${b[1]}');
        default: ex.add('$d:len${b.length}');
      }
    });
    print('$r\t${z.objectName(r)}\t${ex.join(' ')}');
  }
}
