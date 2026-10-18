import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/ui/widgets/paddle_widgets.dart';
import 'package:next_cw_trainer/util/key_adapter_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KeyAdapterState.detected.value = false;
    KeyAdapterState.hideEnabled.value = false;
  });

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  Widget paddles() => IambicPaddles(
      onDitDown: () {}, onDitUp: () {}, onDahDown: () {}, onDahUp: () {});

  testWidgets('touch keys stay while the setting is off, even with an adapter',
      (t) async {
    await t.pumpWidget(app(paddles()));
    KeyAdapterState.setDetected(true);
    await t.pump();
    expect(find.text('DIT  ·'), findsOneWidget);
    expect(find.text('DAH  —'), findsOneWidget);
  });

  testWidgets('touch keys are hidden when detected and enabled, and come back unplugged',
      (t) async {
    await t.pumpWidget(app(paddles()));
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.setDetected(true);
    await t.pump();
    expect(find.text('DIT  ·'), findsNothing);
    expect(find.text('DAH  —'), findsNothing);

    KeyAdapterState.setDetected(false);
    await t.pump();
    expect(find.text('DIT  ·'), findsOneWidget);
  });

  testWidgets('straight key is hidden the same way', (t) async {
    await t.pumpWidget(app(StraightKeyPaddle(onDown: () {}, onUp: () {})));
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.setDetected(true);
    await t.pump();
    expect(find.byType(PaddleButton), findsNothing);
  });

  test('the setting is persisted', () async {
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.hideEnabled.value = false;
    // init() also talks to the platform; the pref read is what matters here.
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(KeyAdapterState.prefKey), isTrue);
  });
}
