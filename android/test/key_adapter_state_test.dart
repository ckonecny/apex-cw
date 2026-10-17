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
    KeyAdapterState.dismissed.value = false;
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

  testWidgets('touch keys are replaced by the hint when detected and enabled',
      (t) async {
    await t.pumpWidget(app(paddles()));
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.setDetected(true);
    await t.pump();
    expect(find.text('DIT  ·'), findsNothing);
    expect(find.byType(KeyAdapterHiddenHint), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Unplugged: the touch keys come back by themselves.
    KeyAdapterState.setDetected(false);
    await t.pump();
    expect(find.text('DIT  ·'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('X closes the hint until the next detection', (t) async {
    await t.pumpWidget(app(paddles()));
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.setDetected(true);
    await t.pump();

    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('DIT  ·'), findsNothing); // keys stay hidden, only the hint is gone

    KeyAdapterState.setDetected(false);
    KeyAdapterState.setDetected(true);
    await t.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('straight key is hidden the same way', (t) async {
    await t.pumpWidget(app(StraightKeyPaddle(onDown: () {}, onUp: () {})));
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.setDetected(true);
    await t.pump();
    expect(find.byType(KeyAdapterHiddenHint), findsOneWidget);
  });

  test('the setting is persisted', () async {
    await KeyAdapterState.setHideEnabled(true);
    KeyAdapterState.hideEnabled.value = false;
    // init() also talks to the platform; the pref read is what matters here.
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(KeyAdapterState.prefKey), isTrue);
  });
}
