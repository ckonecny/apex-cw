import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/timing_history.dart';
import 'package:next_cw_trainer/keyer/echo_fist.dart';
import 'package:next_cw_trainer/keyer/fist_analyzer.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/widgets/timing_history_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'echo_fist_test.dart' show key;

void main() {
  test('record and load: index, ratios, cap, bad entries ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final b = EchoFistBlock();
    for (final w in ['ES', 'EST', 'TEN']) {
      b.addWord(w, key(w));
    }
    await const TimingHistory().record(p, b.report(), DateTime(2026, 10, 31));
    final all = const TimingHistory().load(p);
    expect(all, hasLength(1));
    expect(all.first.index, 100);
    expect(all.first.valueOf(TimingMeasure.dah), closeTo(3, 0.05));
    // too few elements: nothing stored
    final small = EchoFistBlock()..addWord('E', key('E'));
    await const TimingHistory().record(p, small.report(), DateTime(2026, 11, 1));
    expect(const TimingHistory().load(p), hasLength(1));
    for (var i = 0; i < TimingHistory.keep + 5; i++) {
      await const TimingHistory().record(p, b.report(), DateTime(2026, 11, 2));
    }
    expect(const TimingHistory().load(p), hasLength(TimingHistory.keep));
    await p.setString('timingHistory', 'nonsense');
    expect(const TimingHistory().load(p), isEmpty);
  });

  testWidgets('card: chips switch the measure, speed bands filter', (t) async {
    Strings.lang.value = 1;
    addTearDown(() => Strings.lang.value = 0);
    TimingRecord r(int day, double wpm, int idx, double dah) => TimingRecord(
        at: DateTime(2026, 10, day),
        wpm: wpm,
        index: idx,
        elements: 40,
        ratios: {FistElement.dah: dah});
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TimingHistoryCard(records: [
      r(1, 12, 60, 2.2),
      r(2, 12, 70, 2.5),
      r(3, 18, 85, 2.9),
    ])))));
    expect(find.text('Index'), findsOneWidget);
    expect(find.text('All speeds'), findsOneWidget);
    expect(find.text('10–15 WPM'), findsOneWidget);
    await t.tap(find.text('Dah'));
    await t.pump();
    expect(find.textContaining('No values'), findsNothing);
    await t.tap(find.text('Letter gap'));
    await t.pump();
    expect(find.textContaining('No values'), findsOneWidget);
    await t.tap(find.text('15–20 WPM'));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('card does not overflow in German at scale 1.3', (t) async {
    Strings.lang.value = 0;
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final recs = [
      for (var i = 0; i < 4; i++)
        TimingRecord(
            at: DateTime(2026, 10, 1 + i),
            wpm: 8.0 + i * 6,
            index: 50 + i * 10,
            elements: 30,
            ratios: {FistElement.dah: 2.5})
    ];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: TimingHistoryCard(records: recs)))));
    expect(t.takeException(), isNull);
  });
}
