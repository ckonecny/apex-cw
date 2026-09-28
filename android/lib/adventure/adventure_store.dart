// Games list and save games for the text adventures.
//
// Per game, in the app's support directory under adventure/<id>/:
//   auto.bin + auto.json   automatic save after every command (+ transcript)
//   slots.json             the player's own saves (name, room, score, …)
//   slot_<id>.bin/.json    one own save (snapshot + transcript + walked paths)
// Snapshots are ZSnapshot.toBytes(); no export (not needed, user decision).
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../zmachine/zmachine.dart';

class AdventureGame {
  final String id;
  final String asset;
  /// The work's title, shown in the selection and credits only.
  final String title;
  /// 1, 2, 3 → "Teil I" / "Part I" in the game screen.
  final int part;
  const AdventureGame(this.id, this.asset, this.title, this.part);
}

const adventureGames = [
  AdventureGame('zork1', 'assets/zork/zork1.z3', 'Zork I: The Great Underground Empire', 1),
  AdventureGame('zork2', 'assets/zork/zork2.z3', 'Zork II: The Wizard of Frobozz', 2),
  AdventureGame('zork3', 'assets/zork/zork3.z3', 'Zork III: The Dungeon Master', 3),
];

/// One line of the transcript.
class LogEntry {
  /// output: a game answer (the last one is played); banner: shown only
  /// (the copyright banner); info: app notes.
  static const output = 0, command = 1, info = 2, banner = 3;
  final int kind;
  final String text;
  const LogEntry(this.kind, this.text);

  List<Object> toJson() => [kind, text];
  static LogEntry fromJson(List<dynamic> j) => LogEntry(j[0] as int, j[1] as String);
}

class SaveInfo {
  final String id; // 'auto' or a slot id
  final String name;
  final String room;
  final int score, moves;
  final DateTime time;
  const SaveInfo(this.id, this.name, this.room, this.score, this.moves, this.time);

  Map<String, Object> toJson() => {
        'id': id, 'name': name, 'room': room, 'score': score, 'moves': moves,
        'time': time.millisecondsSinceEpoch,
      };
  static SaveInfo fromJson(Map<String, dynamic> j) => SaveInfo(
        j['id'] as String, j['name'] as String, j['room'] as String,
        j['score'] as int, j['moves'] as int,
        DateTime.fromMillisecondsSinceEpoch(j['time'] as int));

  SaveInfo renamed(String n) => SaveInfo(id, n, room, score, moves, time);
}

/// A loaded save: machine state, the transcript to show again and the
/// paths walked so far (for the map, [room, room] pairs).
class SaveData {
  final SaveInfo info;
  final ZSnapshot snapshot;
  final List<LogEntry> log;
  final List<(int, int)> walked;
  const SaveData(this.info, this.snapshot, this.log, this.walked);
}

class AdventureStore {
  static const _logKeep = 300;
  final String gameId;
  AdventureStore(this.gameId);

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/adventure/$gameId');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> _write(String name, SaveInfo info, ZSnapshot s, List<LogEntry> log,
      List<(int, int)> walked) async {
    final d = await _dir();
    final keep = log.length > _logKeep ? log.sublist(log.length - _logKeep) : log;
    await File('${d.path}/$name.bin').writeAsBytes(s.toBytes(), flush: true);
    await File('${d.path}/$name.json').writeAsString(jsonEncode({
      'info': info.toJson(),
      'log': keep.map((e) => e.toJson()).toList(),
      'walked': [for (final (a, b) in walked) [a, b]],
    }), flush: true);
  }

  Future<SaveData?> _read(String name) async {
    try {
      final d = await _dir();
      final bin = File('${d.path}/$name.bin');
      final meta = File('${d.path}/$name.json');
      if (!await bin.exists() || !await meta.exists()) return null;
      final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      return SaveData(
        SaveInfo.fromJson(j['info'] as Map<String, dynamic>),
        ZSnapshot.fromBytes(await bin.readAsBytes()),
        [for (final e in j['log'] as List) LogEntry.fromJson(e as List)],
        [for (final e in (j['walked'] as List? ?? const [])) ((e as List)[0] as int, e[1] as int)],
      );
    } catch (_) {
      return null; // damaged save: treated as missing
    }
  }

  // ---- automatic save ----

  Future<void> saveAuto(ZSnapshot s, ZStatus st, List<LogEntry> log, List<(int, int)> walked) =>
      _write('auto', SaveInfo('auto', '', st.room, st.score, st.moves, DateTime.now()), s, log, walked);

  Future<SaveData?> loadAuto() => _read('auto');

  Future<SaveInfo?> autoInfo() async {
    try {
      final d = await _dir();
      final f = File('${d.path}/auto.json');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return SaveInfo.fromJson(j['info'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAuto() async {
    final d = await _dir();
    for (final n in ['auto.bin', 'auto.json']) {
      final f = File('${d.path}/$n');
      if (await f.exists()) await f.delete();
    }
  }

  // ---- own saves ----

  Future<List<SaveInfo>> slots() async {
    try {
      final d = await _dir();
      final f = File('${d.path}/slots.json');
      if (!await f.exists()) return [];
      final l = jsonDecode(await f.readAsString()) as List;
      final list = [for (final e in l) SaveInfo.fromJson(e as Map<String, dynamic>)];
      list.sort((a, b) => b.time.compareTo(a.time));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeSlots(List<SaveInfo> l) async {
    final d = await _dir();
    await File('${d.path}/slots.json')
        .writeAsString(jsonEncode(l.map((e) => e.toJson()).toList()), flush: true);
  }

  Future<SaveInfo> addSlot(ZSnapshot s, ZStatus st, List<LogEntry> log, List<(int, int)> walked,
      String name) async {
    final now = DateTime.now();
    final info = SaveInfo('${now.millisecondsSinceEpoch}', name, st.room, st.score, st.moves, now);
    await _write('slot_${info.id}', info, s, log, walked);
    final l = await slots();
    await _writeSlots([info, ...l]);
    return info;
  }

  Future<SaveData?> loadSlot(String id) =>
      id == 'auto' ? loadAuto() : _read('slot_$id');

  Future<void> renameSlot(String id, String name) async {
    final l = await slots();
    await _writeSlots([for (final s in l) s.id == id ? s.renamed(name) : s]);
  }

  Future<void> deleteSlot(String id) async {
    final l = await slots();
    await _writeSlots([for (final s in l) if (s.id != id) s]);
    final d = await _dir();
    for (final n in ['slot_$id.bin', 'slot_$id.json']) {
      final f = File('${d.path}/$n');
      if (await f.exists()) await f.delete();
    }
  }
}
