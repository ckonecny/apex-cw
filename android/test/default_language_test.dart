import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';

void main() {
  test('German phone starts in German, every other language in English', () {
    expect(Strings.defaultFor('de'), 0);
    for (final c in ['en', 'fr', 'es', 'sv', 'ja', '']) {
      expect(Strings.defaultFor(c), 1, reason: c);
    }
  });
}
