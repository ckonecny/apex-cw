import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/ui/widgets/paddle_widgets.dart';
import 'package:next_cw_trainer/util/paddle_layout.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester t, List<String> events) => t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: IambicPaddles(
            onDitDown: () => events.add('ditDown'), onDitUp: () {},
            onDahDown: () => events.add('dahDown'), onDahUp: () {}),
        ),
      ));

  testWidgets('dit left by default; swapping puts dah left, keys keep their meaning',
      (t) async {
    final events = <String>[];
    await pump(t, events);
    expect(t.getCenter(find.text('DIT  ·')).dx < t.getCenter(find.text('DAH  —')).dx, isTrue);

    await PaddleLayout.setSwapped(true);
    await t.pumpAndSettle();
    expect(t.getCenter(find.text('DAH  —')).dx < t.getCenter(find.text('DIT  ·')).dx, isTrue);

    // The button labelled DIT still sends dit, wherever it sits.
    final g = await t.startGesture(t.getCenter(find.text('DIT  ·')));
    await g.up();
    expect(events, ['ditDown']);

    await PaddleLayout.setSwapped(false);
    await t.pumpAndSettle();
    expect(t.getCenter(find.text('DIT  ·')).dx < t.getCenter(find.text('DAH  —')).dx, isTrue);
  });

  test('swap is persisted', () async {
    await PaddleLayout.setSwapped(true);
    PaddleLayout.swapped.value = false;
    await PaddleLayout.load();
    expect(PaddleLayout.swapped.value, isTrue);
    await PaddleLayout.setSwapped(false);
  });
}
