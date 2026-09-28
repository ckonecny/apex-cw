// Dev helper: plays a story file headless with a walkthrough script.
//   dart run tool/zplay.dart <story> <seed> <script> [--quiet]
// Script lines: a command, "# comment", or
//   "!until <regex> :: <command>"  repeats the command (max 30×) until the
//   game's answer matches the regex (case-insensitive).
import 'dart:io';
import 'dart:math';
import 'package:next_cw_trainer/zmachine/zmachine.dart';

void main(List<String> args) {
  final z = ZMachine(File(args[0]).readAsBytesSync(), random: Random(int.parse(args[1])));
  final quiet = args.contains('--quiet');
  void out(String s) { if (!quiet) stdout.write(s); }
  out(z.start());
  var failed = false;
  for (final raw in File(args[2]).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (z.state != ZState.waitingForInput) break;
    if (line.startsWith('!until ')) {
      final parts = line.substring(7).split(' :: ');
      final re = RegExp(parts[0], caseSensitive: false);
      var ok = false;
      for (var i = 0; i < 30 && z.state == ZState.waitingForInput; i++) {
        out('[${parts[1]}]\n');
        final r = z.input(parts[1]);
        out(r);
        if (re.hasMatch(r)) { ok = true; break; }
      }
      if (!ok) { stdout.writeln('!! until failed: $line'); failed = true; break; }
      continue;
    }
    out('[$line]\n');
    out(z.input(line));
  }
  final s = z.status;
  stdout.writeln('\n[${failed ? "FAILED " : ""}state ${z.state.name}, room ${s.room}, score ${s.score}, moves ${s.moves}]');
}
