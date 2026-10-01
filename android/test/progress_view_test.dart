import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/char_stats.dart';
import 'package:next_cw_trainer/ui/progress_view.dart';

Map<String, DayStat> sample() {
  final days = <String, DayStat>{};
  final now = DateTime.now();
  const chars = ['K', 'M', 'R', 'S', 'U', 'A', 'P', 'T'];
  for (var i = 0; i < 90; i++) {
    if (i % 3 == 2) continue;
    final d = now.subtract(Duration(days: i));
    final s = DayStat();
    for (var k = 0; k < chars.length; k++) {
      final a = 8 + k, e = ((i + k) % 5 == 0) ? 3 : 1;
      s.chars[chars[k]] = [a, e];
      s.attempts += a;
      s.errors += e;
    }
    s.ws = s.attempts * (15 + (90 - i) ~/ 20);
    s.wm = 20;
    days[dayKey(d)] = s;
  }
  return days;
}

void main() {
  testWidgets('progress view renders in all ranges without errors', (t) async {
    t.view.physicalSize = const Size(390, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProgressView(
          days: sample(),
          order: const ['K', 'M', 'R', 'S', 'U', 'A', 'P', 'T'],
          outputCase: 1,
          onChar: (c) => tapped = c,
        ),
      ),
    ));
    expect(find.text('12 Wochen'), findsOneWidget);
    for (final label in ['4 Wochen', 'Alles', '12 Wochen']) {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      final ex = t.takeException();
      if (ex != null) { debugPrint('EX: $ex'); fail('exception'); }
    }
    await t.tap(find.text('Schwächste zuerst'));
    await t.pumpAndSettle();
    await t.tap(find.text('K').first);
    expect(tapped, 'K');
  });

  testWidgets('empty data shows the hint', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProgressView(days: {}, order: [], outputCase: 1, onChar: _noop),
      ),
    ));
    expect(find.textContaining('füllt sich'), findsOneWidget);
  });
}

void _noop(String _) {}
Object? tester(WidgetTester t) => t.takeException();
