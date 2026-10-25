import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/util/app_shortcuts.dart';

// Launcher shortcuts (issue #151): ids are what native code hands back, so
// they must stay unique; labels must exist in both languages; the stored
// choice survives shortcuts being added or removed in later versions.
void main() {
  tearDown(() {
    Strings.lang.value = 0;
    AppShortcuts.applyStored(null, null);
  });

  test('ids are unique', () {
    final ids = AppShortcuts.all.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  for (final lang in [0, 1]) {
    test('labels resolve in language $lang', () {
      Strings.lang.value = lang;
      for (final s in AppShortcuts.all) {
        final l = s.label();
        expect(l, isNotEmpty, reason: s.id);
        expect(l.contains('_'), isFalse, reason: '${s.id}: missing string "$l"');
      }
    });
  }

  test('default: the four that fit every launcher', () {
    AppShortcuts.applyStored(null, null);
    expect(AppShortcuts.active.map((s) => s.id),
        ['hear', 'send', 'audio', 'keyer']);
  });

  test('stored order and choice are kept, unknown ids dropped', () {
    AppShortcuts.applyStored(
      ['chart', 'gone', 'hear', 'owntexts', 'send', 'audio', 'keyer', 'decoder', 'games'],
      ['send', 'gone', 'decoder', 'games'],
    );
    expect(AppShortcuts.active.map((s) => s.id),
        ['chart', 'hear', 'owntexts', 'audio', 'keyer']);
    expect(AppShortcuts.order.value.length, AppShortcuts.all.length);
  });

  test('shortcuts new since the choice was stored are appended', () {
    AppShortcuts.applyStored(['keyer', 'hear'], ['hear']);
    expect(AppShortcuts.order.value.take(2), ['keyer', 'hear']);
    expect(AppShortcuts.order.value.length, AppShortcuts.all.length);
    // New ones are on only if on by default.
    expect(AppShortcuts.active.map((s) => s.id), ['keyer', 'send', 'audio']);
  });
}
