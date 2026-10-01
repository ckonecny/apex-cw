// Own texts (issue #8): the library on the device.
//
// App support directory, owntexts/: index.json (one entry per text: id,
// title, created, progress) and <id>.txt (the text as pasted). Texts never
// leave the device.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OwnTextInfo {
  final String id;
  String title;
  final DateTime created;
  /// Number of words, set when the text is added.
  final int words;
  /// Word to continue from (0 = from the start).
  int pos;

  OwnTextInfo(this.id, this.title, this.created, this.words, this.pos);

  /// Share of the text before [pos], 0–100.
  int get percent => words == 0 ? 0 : (pos * 100 / words).round().clamp(0, 100);

  Map<String, Object> toJson() => {
        'id': id, 'title': title, 'created': created.millisecondsSinceEpoch,
        'words': words, 'pos': pos,
      };

  static OwnTextInfo fromJson(Map<String, dynamic> j) => OwnTextInfo(
        j['id'] as String, j['title'] as String,
        DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        j['words'] as int, j['pos'] as int);
}

class OwnTextStore {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/owntexts');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _index() async => File('${(await _dir()).path}/index.json');

  /// All texts, newest first.
  Future<List<OwnTextInfo>> list() async {
    try {
      final f = await _index();
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List<dynamic>;
      final all = [for (final e in raw) OwnTextInfo.fromJson(e as Map<String, dynamic>)];
      all.sort((a, b) => b.created.compareTo(a.created));
      return all;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<OwnTextInfo> all) async {
    final f = await _index();
    await f.writeAsString(jsonEncode([for (final i in all) i.toJson()]));
  }

  Future<OwnTextInfo> add(String title, String body, int words) async {
    final all = await list();
    final now = DateTime.now();
    final info = OwnTextInfo('t${now.microsecondsSinceEpoch}', title, now, words, 0);
    await File('${(await _dir()).path}/${info.id}.txt').writeAsString(body);
    all.add(info);
    await _writeIndex(all);
    return info;
  }

  Future<String> body(String id) async =>
      File('${(await _dir()).path}/$id.txt').readAsString();

  Future<void> rename(String id, String title) async {
    final all = await list();
    for (final i in all) {
      if (i.id == id) i.title = title;
    }
    await _writeIndex(all);
  }

  Future<void> setPos(String id, int pos) async {
    final all = await list();
    for (final i in all) {
      if (i.id == id) i.pos = pos;
    }
    await _writeIndex(all);
  }

  Future<void> delete(String id) async {
    final all = await list();
    all.removeWhere((i) => i.id == id);
    await _writeIndex(all);
    final f = File('${(await _dir()).path}/$id.txt');
    if (await f.exists()) await f.delete();
  }
}
