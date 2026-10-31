import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/keyer/echo_fist.dart';
import 'package:next_cw_trainer/keyer/fist_analyzer.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/widgets/echo_fist_card.dart';

/// Keys [target] with the given dit and factors; returns (start, end) presses.
List<(int, int)> key(String target,
    {int dit = 60, double dah = 3, double el = 1, double letter = 3, double word = 7}) {
  final pat = EchoFistBlock.pattern(target)!;
  final out = <(int, int)>[];
  var t = 1000;
  for (var i = 0; i < pat.length; i++) {
    final code = pat[i];
    if (code == null) continue;
    for (var j = 0; j < code.length; j++) {
      final len = (code[j] == '.' ? dit : dit * dah).round();
      out.add((t, t + len));
      t += len;
      if (j < code.length - 1) {
        t += (dit * el).round();
      } else if (i < pat.length - 1) {
        t += (dit * (pat[i + 1] == null ? word : letter)).round();
      }
    }
  }
  return out;
}

EchoFistBlock block(List<String> words, {double dah = 3, double letter = 3}) {
  final b = EchoFistBlock();
  for (final w in words) {
    b.addWord(w, key(w, dah: dah, letter: letter));
  }
  return b;
}

void main() {
  const words = ['CQ', 'TEST', 'DE', 'OE1CKO', 'K'];

  test('ideal keying: index 100', () {
    final r = block(words).report();
    expect(r.index, 100);
    expect(r.wpm, closeTo(20, 0.1));
  });

  test('a dah keyed like a dit is a timing error, not a skipped word', () {
    final b = block(words, dah: 1.2);
    expect(b.skipped, 0);
    final r = b.report();
    expect(r.stats[FistElement.dah]!.deviation, lessThan(-1));
    expect(r.index!, lessThan(80));
    expect(FistHints.once(r).map((h) => h.key), contains('fist_h_dah_short'));
  });

  test('missing or extra element: real error, left out', () {
    final b = EchoFistBlock();
    b.addWord('CQ', key('CQ').sublist(1)); // one element missing
    b.addWord('TEST', [...key('TEST'), (9000, 9060)]); // one extra
    b.addWord('DE', key('DE'));
    expect(b.skipped, 2);
    expect(b.words, 1);
  });

  test('letters run together show as short letter gap', () {
    final r = block(words, letter: 1.5).report();
    expect(r.stats[FistElement.letterGap]!.deviation, lessThan(-0.8));
    expect(FistHints.once(r).map((h) => h.key), contains('fist_h_letterGap_short'));
  });

  test('prosigns and spaces in the target', () {
    expect(EchoFistBlock.pattern('<KA>'), ['-.-.-']);
    expect(EchoFistBlock.pattern('A B'), ['.-', null, '-...']);
    expect(EchoFistBlock.pattern('A~'), isNull);
    final b = EchoFistBlock()..addWord('A B', key('A B'));
    expect(b.words, 1);
    expect(b.report().stats[FistElement.wordGap]!.ratio, closeTo(7, 0.1));
  });

  test('too few elements gives no index; clear resets', () {
    final b = block(['E', 'T']);
    expect(b.report().index, isNull);
    b.clear();
    expect(b.words, 0);
    expect(b.report().elements, 0);
  });

  testWidgets('card shows the index, tap opens the bars', (t) async {
    Strings.lang.value = 1;
    addTearDown(() => Strings.lang.value = 0);
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final b = block(words, dah: 2);
    b.addWord('CQ', key('CQ').sublist(1));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EchoFistCard(report: b.report(), skipped: b.skipped))));
    expect(find.textContaining('/ 100'), findsOneWidget);
    await t.tap(find.byType(EchoFistCard));
    await t.pumpAndSettle();
    expect(find.text('Letter gap'), findsOneWidget);
    expect(find.textContaining('1 words'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('full card shows the bars without a tap', (t) async {
    Strings.lang.value = 1;
    addTearDown(() => Strings.lang.value = 0);
    final b = block(words, dah: 2);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EchoFistCard(report: b.report(), skipped: 0, full: true))));
    expect(find.text('Letter gap'), findsOneWidget);
  });
}
