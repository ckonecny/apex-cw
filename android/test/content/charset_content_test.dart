import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/content/charset_content.dart';
import 'package:next_cw_trainer/content/training_profile.dart';

void main() {
  test('contents per character set', () {
    expect(allowedContents(CharSet.practice), [ContentKind.random]);
    expect(allowedContents(CharSet.koch).contains(ContentKind.calls), isFalse);
    expect(allowedContents(CharSet.all).contains(ContentKind.calls), isTrue);
    expect(sanitizeContent(CharSet.koch, ContentKind.calls), ContentKind.random);
  });

  test('engine mapping', () {
    var e = engineSelection(CharSet.koch, ContentKind.abbrevs);
    expect((e.mode, e.kochActive, e.usesRandomOption), (5, true, false));
    e = engineSelection(CharSet.koch, ContentKind.random);
    expect((e.mode, e.kochActive, e.usesRandomOption), (0, true, false));
    e = engineSelection(CharSet.all, ContentKind.random);
    expect((e.mode, e.kochActive, e.usesRandomOption), (0, false, true));
    e = engineSelection(CharSet.all, ContentKind.calls);
    expect((e.mode, e.kochActive), (2, false));
    e = engineSelection(CharSet.all, ContentKind.mixed);
    expect((e.mode, e.kochActive), (3, false));
    e = engineSelection(CharSet.practice, ContentKind.words);
    expect((e.mode, e.kochActive), (4, false));
  });

  test('switching set keeps a valid content', () {
    const c = CharsetChoice(CharSet.all, ContentKind.calls);
    expect(c.withSet(CharSet.koch).content, ContentKind.random);
    expect(c.withSet(CharSet.all).content, ContentKind.calls);
  });

  test('migration: Koch positions become the Koch set', () async {
    SharedPreferences.setMockInitialValues({'kochModeIndex': 1, 'kochEchoModeIndex': 4, 'echoModeIndex': 2});
    final p = await SharedPreferences.getInstance();
    await TrainingProfile.migrateIfNeeded(p);
    var h = CharsetChoice.load(TrainingProfile(p, TrainingProfile.hear));
    var e = CharsetChoice.load(TrainingProfile(p, TrainingProfile.echo));
    expect((h.set, h.content), (CharSet.koch, ContentKind.abbrevs));
    expect((e.set, e.content), (CharSet.koch, ContentKind.random)); // Adapt. Rand.
  });

  test('migration: without Koch prefs Echo follows its old list, Hören = all/random', () async {
    SharedPreferences.setMockInitialValues({'echoModeIndex': 4});
    final p = await SharedPreferences.getInstance();
    await TrainingProfile.migrateIfNeeded(p);
    final h = CharsetChoice.load(TrainingProfile(p, TrainingProfile.hear));
    final e = CharsetChoice.load(TrainingProfile(p, TrainingProfile.echo));
    expect((h.set, h.content), (CharSet.all, ContentKind.random));
    expect((e.set, e.content), (CharSet.practice, ContentKind.random));
  });

  test('migration from version 1 keeps an existing choice and is idempotent', () async {
    SharedPreferences.setMockInitialValues({'profileVersion': 1, 'kochModeIndex': 3});
    final p = await SharedPreferences.getInstance();
    await TrainingProfile.migrateIfNeeded(p);
    final pr = TrainingProfile(p, TrainingProfile.hear);
    expect(CharsetChoice.load(pr).content, ContentKind.mixed);
    await const CharsetChoice(CharSet.all, ContentKind.calls).save(pr);
    await TrainingProfile.migrateIfNeeded(p);
    expect(CharsetChoice.load(pr).content, ContentKind.calls);
  });
}
