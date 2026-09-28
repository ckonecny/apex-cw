// Z-machine interpreter checked against the real story files: full
// solutions of Zork I (350/350), Zork II (400/400) and Zork III (7/7, the
// Treasury), plus save/restore, snapshots (autosave, undo) and restart.
//
// The solution relies on a fixed random seed (fights, the thief). If a Dart
// SDK update ever changes Random(seed), the fight loops (!until) usually
// absorb it; otherwise pick a new seed with tool/zplay.dart.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/zmachine/zmachine.dart';

ZMachine load(String name, {int seed = 1}) =>
    ZMachine(File('assets/zork/$name.z3').readAsBytesSync(), random: Random(seed));

/// Plays a walkthrough script (same format as tool/zplay.dart) and returns
/// the whole transcript.
String play(ZMachine z, String script) {
  final out = StringBuffer(z.start());
  for (final raw in script.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    expect(z.state, ZState.waitingForInput, reason: 'before "$line"');
    if (line.startsWith('!until ')) {
      final parts = line.substring(7).split(' :: ');
      final re = RegExp(parts[0], caseSensitive: false);
      var ok = false;
      for (var i = 0; i < 30 && !ok; i++) {
        final r = z.input(parts[1]);
        out.write(r);
        ok = re.hasMatch(r);
      }
      expect(ok, isTrue, reason: 'never matched: $line');
    } else {
      out.write(z.input(line));
    }
  }
  return out.toString();
}

void main() {
  test('Zork I: full solution scores 350 of 350', () {
    final z = load('zork1');
    final t = play(z, File('test/zmachine/zork1_walkthrough.txt').readAsStringSync());
    expect(t, contains('Your score is 350 (total of 350 points)'));
    expect(t, contains('Master Adventurer'));
    expect(z.status.score, 350);
  });

  test('Zork II: full solution scores 400 of 400', () {
    // At seed 1 the Wizard casts "Fantasize" early, whose table bug writes
    // into static memory (dropped since 2026-09-28; it used to crash here).
    final z = load('zork2');
    final t = play(z, File('test/zmachine/zork2_walkthrough.txt').readAsStringSync());
    expect(t, contains('Your score would be 400 (total of 400 points)'));
    expect(z.status.score, 400);
  });

  test('Zork III: full solution reaches the Treasury of Zork, 7 of 7', () {
    final z = load('zork3');
    final t = play(z, File('test/zmachine/zork3_walkthrough.txt').readAsStringSync());
    expect(z.status.room, 'Treasury of Zork');
    expect(t, contains('Your potential is 7 of a possible 7'));
  });

  test('Zork I: opening text and status line', () {
    final z = load('zork1');
    final t = z.start();
    expect(t, contains('ZORK I: The Great Underground Empire'));
    expect(t, contains('West of House\nYou are standing in an open field'));
    expect(z.state, ZState.waitingForInput);
    expect(z.status.room, 'West of House');
    expect(z.status.score, 0);
    expect(z.input('open mailbox'), contains('reveals a leaflet'));
    expect(z.status.moves, 1);
  });

  test('host snapshot survives bytes and loads into a fresh machine', () {
    final a = load('zork1');
    a.start();
    for (final c in ['n', 'e', 'open window', 'w']) {
      a.input(c);
    }
    expect(a.status.room, 'Kitchen');
    final bytes = a.snapshot().toBytes();

    final b = load('zork1');
    b.start();
    expect(b.load(ZSnapshot.fromBytes(bytes)), isEmpty);
    expect(b.state, ZState.waitingForInput);
    expect(b.status.room, 'Kitchen');
    expect(b.status.score, 10);
    expect(b.input('w'), contains('Living Room'));
  });

  test('undo: loading the previous snapshot takes a move back', () {
    final z = load('zork1');
    z.start();
    final before = z.snapshot();
    z.input('n');
    expect(z.status.room, 'North of House');
    z.load(before);
    expect(z.status.room, 'West of House');
    expect(z.status.moves, 0);
    expect(z.input('s'), contains('South of House'));
  });

  test('in-game SAVE and RESTORE go through the host', () {
    final z = load('zork1');
    ZSnapshot? saved;
    z.onSave = (s) {
      saved = s;
      return true;
    };
    z.start();
    z.input('n');
    expect(z.input('save'), contains('Ok.'));
    expect(saved, isNotNull);
    z.input('n');
    expect(z.status.room, 'Forest Path');

    z.input('restore');
    expect(z.state, ZState.waitingForRestore);
    final t = z.completeRestore(ZSnapshot.fromBytes(saved!.toBytes()));
    expect(t, contains('Ok.'));
    expect(z.state, ZState.waitingForInput);
    expect(z.status.room, 'North of House');
  });

  test('RESTORE without a snapshot fails gracefully', () {
    final z = load('zork1');
    z.start();
    z.input('restore');
    expect(z.completeRestore(null), contains('Failed.'));
    expect(z.state, ZState.waitingForInput);
  });

  test('RESTART starts over', () {
    final z = load('zork1');
    z.start();
    z.input('n');
    z.input('restart');
    final t = z.input('y');
    expect(t, contains('West of House'));
    expect(z.status.room, 'West of House');
    expect(z.status.moves, 0);
  });

  test('snapshot of another story is rejected', () {
    final z1 = load('zork1')..start();
    final z2 = load('zork2')..start();
    expect(() => z2.load(z1.snapshot()), throwsA(isA<ZMachineError>()));
  });

  for (final (name, title, room) in [
    ('zork2', 'ZORK II: The Wizard of Frobozz', 'Inside the Barrow'),
    ('zork3', 'ZORK III: The Dungeon Master', 'Endless Stair'),
  ]) {
    test('$name starts and takes commands', () {
      final z = load(name);
      final t = z.start();
      expect(t, contains(title));
      expect(z.status.room, room);
      expect(z.input('inventory'), isNotEmpty);
      expect(z.input('look'), contains(room));
      expect(z.state, ZState.waitingForInput);
    });
  }
}
