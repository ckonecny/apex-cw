// The confirmation tone choice (Off / Classic / Marimba / Gentle): stored
// value and migration from the old on/off switch, what reaches the native
// side, the preview when picking one, and the settings row on a small phone.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/settings_screen.dart';
import 'package:next_cw_trainer/util/confirm_tone.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
const _settingsChannel = MethodChannel('at.oe1cko.nextcwtrainer/settings');
const _settingsEvents = MethodChannel('at.oe1cko.nextcwtrainer/settings_events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (c) async {
      calls.add(c);
      return null;
    });
    // The Settings screen asks the native side about paddles, outputs, version.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_settingsChannel, (c) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_settingsEvents, (c) async => null);
  });

  group('stored choice', () {
    Future<ConfirmTone> load(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      return ConfirmTone.fromPrefs(await SharedPreferences.getInstance());
    }

    test('default is the firmware tone', () async {
      expect(await load({}), ConfirmTone.classic);
    });

    test('the old switch migrates: on = classic, off = off', () async {
      expect(await load({'confirmTone': true}), ConfirmTone.classic);
      expect(await load({'confirmTone': false}), ConfirmTone.off);
    });

    test('a saved choice wins over the old switch', () async {
      expect(await load({'confirmTone': false, 'confirmToneStyle': 2}),
          ConfirmTone.marimba);
      expect(await load({'confirmToneStyle': 3}), ConfirmTone.sanft);
      expect(await load({'confirmToneStyle': 0}), ConfirmTone.off);
    });

    test('an unknown value falls back to the old switch / default', () async {
      expect(await load({'confirmToneStyle': 9}), ConfirmTone.classic);
      expect(await load({'confirmToneStyle': 9, 'confirmTone': false}), ConfirmTone.off);
    });

    test('save round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      for (final t in ConfirmTone.values) {
        await t.save(p);
        expect(ConfirmTone.fromPrefs(p), t);
      }
    });
  });

  test('the numbers the Kotlin side relies on (CwTonePlugin.STYLE_*)', () {
    expect(ConfirmTone.off.index, 0);
    expect(ConfirmTone.classic.index, 1);
    expect(ConfirmTone.marimba.index, 2);
    expect(ConfirmTone.sanft.index, 3);
    expect(ConfirmTone.uiOrder.toSet(), ConfirmTone.values.toSet());
    expect(ConfirmTone.uiOrder.length, ConfirmTone.values.length);
  });

  group('playing', () {
    test('sends the style and whether it was right', () async {
      ConfirmTone.marimba.play(_channel, true);
      ConfirmTone.sanft.play(_channel, false);
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), everyElement('playConfirmTone'));
      expect(calls.map((c) => c.arguments), [
        {'ok': true, 'style': 2},
        {'ok': false, 'style': 3},
      ]);
    });

    test('off plays nothing', () async {
      ConfirmTone.off.play(_channel, true);
      await ConfirmTone.off.preview();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
    });

    testWidgets('preview: right now, wrong a second later', (t) async {
      await t.runAsync(() async => ConfirmTone.marimba.preview());
      // runAsync waited for the real second: both halves played, in order.
      expect(calls.map((c) => (c.arguments as Map)['ok']), [true, false]);
    });

    testWidgets('a newer preview or cancelPreview stops the older one', (t) async {
      await t.runAsync(() async {
        final first = ConfirmTone.marimba.preview();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        ConfirmTone.cancelPreview();
        await first;
      });
      expect(calls.map((c) => (c.arguments as Map)['ok']), [true]);
    });
  });

  group('settings row (Einstellungen, Allgemein)', () {
    Future<void> open(WidgetTester t, int lang) async {
      SharedPreferences.setMockInitialValues({});
      Strings.lang.value = lang;
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: const SettingsScreen(),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
          find.text(Strings.t('settings_confirm_tone_help')), 200,
          scrollable: find.byType(Scrollable).first);
    }

    // The sheet scrolls: bring the option on screen before tapping it, or the
    // tap lands outside the sheet.
    Future<void> tapOption(WidgetTester t, String key) async {
      final f = find.text(Strings.t(key));
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
    }

    for (final lang in [0, 1]) {
      testWidgets('lang $lang: four choices, no overflow, picking one saves and plays',
          (t) async {
        await open(t, lang);
        for (final k in ['opt_confirm_classic', 'opt_confirm_marimba',
            'opt_confirm_gentle', 'opt_confirm_none']) {
          expect(find.text(Strings.t(k)), findsOneWidget);
        }
        expect(t.takeException(), isNull);

        await tapOption(t, 'opt_confirm_gentle');
        await t.pump();
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        final p = await SharedPreferences.getInstance();
        expect(ConfirmTone.fromPrefs(p), ConfirmTone.sanft);
        expect(calls.last.arguments, {'ok': true, 'style': 3});

        // The "wrong" half follows after a second.
        await t.pump(const Duration(milliseconds: 1100));
        expect(calls.last.arguments, {'ok': false, 'style': 3});

        // Tapping the chosen one again plays it again.
        calls.clear();
        await tapOption(t, 'opt_confirm_gentle');
        await t.pump();
        expect(calls.single.arguments, {'ok': true, 'style': 3});
        await t.pump(const Duration(milliseconds: 1100));

        await tapOption(t, 'opt_confirm_none');
        await t.pump();
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        expect(ConfirmTone.fromPrefs(p), ConfirmTone.off);
        await t.pump(const Duration(milliseconds: 1100));
      });
    }
  });
}
