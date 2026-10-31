// Hint in the CW Keyer: straight key on an adapter, timing analysis still off.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/keyer_screen.dart';
import 'package:next_cw_trainer/ui/settings_screen.dart';
import 'package:next_cw_trainer/util/key_adapter_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['cw_symbols', 'cw_straight_wpm', 'cw_straight_edges']) {
      m.setMockStreamHandler(EventChannel('at.oe1cko.nextcwtrainer/$ch'),
          MockStreamHandler.inline(onListen: (_, sink) {}));
    }
    for (final ch in ['cw_keyer', 'cw_tone', 'settings']) {
      m.setMockMethodCallHandler(
          MethodChannel('at.oe1cko.nextcwtrainer/$ch'), (c) async => null);
    }
  });

  Future<void> open(WidgetTester t, Map<String, Object> prefs, {bool adapter = true}) async {
    SharedPreferences.setMockInitialValues({'keyerMode': 4, ...prefs});
    Strings.lang.value = 1;
    KeyAdapterState.detected.value = adapter;
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() {
      KeyAdapterState.detected.value = false;
      Strings.lang.value = 0;
    });
    await t.pumpWidget(const MaterialApp(home: KeyerScreen()));
    await t.pump(const Duration(milliseconds: 300));
  }

  final hint = find.textContaining('timing analysis for your straight key');

  testWidgets('shown with adapter + straight key, X closes it for good', (t) async {
    await open(t, {});
    expect(hint, findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    expect(hint, findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('fistHintSeen'), isTrue);
  });

  testWidgets('not shown once closed, when on, without adapter or key', (t) async {
    await open(t, {'fistHintSeen': true});
    expect(hint, findsNothing);
    await open(t, {'fistAnalyzer': true});
    expect(hint, findsNothing);
    await open(t, {}, adapter: false);
    expect(hint, findsNothing);
    await open(t, {'keyerMode': 0});
    expect(hint, findsNothing);
  });

  testWidgets('tap opens the settings', (t) async {
    await open(t, {});
    await t.tap(hint);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('analysis on without adapter: note, closable for good', (t) async {
    final note = find.textContaining('needs a key on an adapter');
    await open(t, {'fistAnalyzer': true}, adapter: false);
    expect(note, findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    expect(note, findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('fistNoAdapterHintSeen'), isTrue);
    await open(t, {'fistAnalyzer': true, 'fistNoAdapterHintSeen': true}, adapter: false);
    expect(note, findsNothing);
  });
}
