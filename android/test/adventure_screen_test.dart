// Text adventure screen with mocked native channels: starts Zork I, types a
// command on the on-screen keyboard, undoes it, and must not overflow on a
// small phone at the capped font size; keys commands through the decoder
// (<AR>, K as its own word, <ERR>).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/adventure/adventure_store.dart';
import 'package:next_cw_trainer/ui/adventure_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  final played = <String>[];
  final keyer = <MethodCall>[];
  final gen = <String>[];
  MockStreamHandlerEventSink? symbols, genEvents;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('adv_test');
    played.clear();
    keyer.clear();
    gen.clear();
    symbols = null;
    SharedPreferences.setMockInitialValues({'adv.input': 1});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer'),
        (call) async {
      keyer.add(call);
      return null;
    });
    m.setMockStreamHandler(const EventChannel('at.oe1cko.nextcwtrainer/cw_symbols'),
        MockStreamHandler.inline(onListen: (_, sink) { symbols = sink; }));
    for (final ch in ['cw_tone', 'settings']) {
      m.setMockMethodCallHandler(MethodChannel('at.oe1cko.nextcwtrainer/$ch'), (_) async => null);
    }
    m.setMockMethodCallHandler(const MethodChannel('at.oe1cko.nextcwtrainer/cw_generator'),
        (call) async {
      gen.add(call.method);
      if (call.method == 'playOne') played.add(call.arguments as String);
      return null;
    });
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tmp.path);
    m.setMockStreamHandler(const EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events'),
        MockStreamHandler.inline(onListen: (_, sink) { genEvents = sink; }));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  for (final (size, scale) in [(const Size(412, 915), 1.0), (const Size(360, 640), 1.3)]) {
    testWidgets('play a move and undo it at $size, font $scale', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      Future<void> settle() async {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
      }

      await tester.pumpWidget(MaterialApp(
          home: AdventureScreen(game: adventureGames.first, newGame: true)));
      await settle();
      await settle();
      expect(tester.takeException(), isNull);
      expect(played, isNotEmpty);
      expect(played.last, startsWith('WEST OF HOUSE YOU ARE STANDING'));
      expect(played.any((t) => t.contains('COPYRIGHT')), isFalse); // banner is shown only

      await tester.tap(find.text('N'));
      await tester.pump();
      await tester.tap(find.text('⏎'));
      await settle();
      expect(find.textContaining('Score 0 · Moves 1'), findsOneWidget);
      expect(played.last, startsWith('NORTH OF HOUSE'));

      await tester.tap(find.byIcon(Icons.undo));
      await settle();
      expect(find.textContaining('Moves 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle();
    });
  }

  group('keying', () {
    const code = {
      'N': '—·', 'S': '···', 'K': '—·—', 'I': '··', 'AR': '·—·—·', 'ERR': '········',
    };

    Future<void> start(WidgetTester tester, Map<String, Object> prefs,
        {Size size = const Size(412, 915), double scale = 1.0}) async {
      SharedPreferences.setMockInitialValues(prefs);
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
          home: AdventureScreen(game: adventureGames.first, newGame: true)));
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
      }
    }

    Future<void> key(WidgetTester tester, List<String> seq) async {
      for (final t in seq) {
        if (t == '_') {
          symbols!.success('  '); // word gap
        } else {
          for (final e in code[t]!.split('')) {
            symbols!.success(e);
          }
          symbols!.success(' ');
        }
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    }

    testWidgets('keyer set up for the word end; <AR> sends; keying stops playback',
        (tester) async {
      await start(tester, {'adv.interCharSpace': 3, 'adv.interWordSpace': 7, 'adv.wpm': 20});
      expect(find.text('DIT  ·'), findsOneWidget); // paddle input is the default
      // 2 × 3 + 1 + max(7, 7) / 8 = 7.875 → 8 dits, +1 for the native side.
      final iw = keyer.lastWhere((c) => c.method == 'setInterWordSpace');
      expect(iw.arguments, 9);
      expect(keyer.lastWhere((c) => c.method == 'setStraightWordGap').arguments, 8);
      expect(keyer.any((c) => c.method == 'start'), isTrue);

      final stops = gen.where((m) => m == 'stopOne').length;
      await key(tester, ['N']);
      expect(gen.where((m) => m == 'stopOne').length, greaterThan(stops));
      expect(find.text('N'), findsOneWidget);
      await key(tester, ['AR']);
      expect(find.textContaining('Moves 1'), findsOneWidget);
      expect(played.last, startsWith('NORTH OF HOUSE'));
      await done(tester);
    });

    testWidgets('<ERR> deletes the last word; K on its own sends', (tester) async {
      await start(tester, {'adv.send': 1});
      await key(tester, ['S', '_', 'I', 'N']);
      expect(find.text('S IN'), findsOneWidget);
      await key(tester, ['ERR']);
      expect(find.text('S '), findsOneWidget);
      await key(tester, ['ERR', 'N', '_']);
      expect(find.text('N '), findsOneWidget);
      await key(tester, ['K']); // no word gap yet: still a letter
      expect(find.text('N K'), findsOneWidget);
      await key(tester, ['_']);
      expect(find.textContaining('Moves 1'), findsOneWidget);
      expect(played.last, startsWith('NORTH OF HOUSE'));
      await done(tester);
    });

    testWidgets('touch paddles fit a small phone at the capped font size', (tester) async {
      await start(tester, {}, size: const Size(360, 640), scale: 1.3);
      await key(tester, ['S', '_', 'I', 'N', '_', 'S', '_', 'I', 'N', '_', 'S', '_', 'I', 'N']);
      expect(find.text('DIT  ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester);
    });

    testWidgets('button only: <AR> does not send', (tester) async {
      await start(tester, {'adv.send': 2});
      await key(tester, ['N', 'AR']);
      expect(find.textContaining('Moves 0'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_return));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.textContaining('Moves 1'), findsOneWidget);
      await done(tester);
    });
  });

  testWidgets('map: opens on the current room; the whole map asks every time', (tester) async {
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> settle() async {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(MaterialApp(
        home: AdventureScreen(game: adventureGames.first, newGame: true)));
    await settle();
    await tester.tap(find.byIcon(Icons.map_outlined));
    await settle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.textContaining('⚠'));
    await settle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byType(TextButton).last); // show anyway
    await settle();
    expect(find.byType(AlertDialog), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AdventureSettings.mapWarnKey), isNull);

    Future<void> again() async {
      await tester.tap(find.text('Besucht'));
      await settle();
      await tester.tap(find.textContaining('⚠'));
      await settle();
    }
    await again(); // asks again
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byType(TextButton).last);
    await settle();
    expect(prefs.getBool(AdventureSettings.mapWarnKey), isFalse);
    await again(); // not any more
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause goes on from the word; the text button shows and hides', (tester) async {
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> settle() async {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }

    await tester.pumpWidget(MaterialApp(
        home: AdventureScreen(game: adventureGames.first, newGame: true)));
    await settle();
    await settle();
    final first = played.last;
    final stops = gen.where((m) => m == 'stopOne').length;
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(gen.where((m) => m == 'stopOne').length, greaterThan(stops));
    expect(find.byIcon(Icons.pause), findsNothing);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle();
    expect(played.length, 2);
    expect(played.last, first); // no word heard yet: from the start
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // Nochmal: tap = the sentence, then paused at the next word.
    await tester.tap(find.byIcon(Icons.replay));
    await settle();
    final sentence = played.last;
    expect(sentence, startsWith('WEST OF HOUSE'));
    expect(sentence.length, lessThan(first.length));
    genEvents!.success({'type': 'done'});
    await settle();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle();
    expect(first.substring(sentence.length).trim(), startsWith(played.last.split(' ').first));
    // Hold = the whole answer.
    await tester.longPress(find.byIcon(Icons.replay));
    await settle();
    expect(played.last, first);

    // Tap a word = only that word (show the text first to reach it).
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    await tester.tapOnText(find.textRange.ofSubstring('field'));
    await settle();
    expect(played.last, 'FIELD');
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined)); // show
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined)); // hide again
    await tester.pump();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
