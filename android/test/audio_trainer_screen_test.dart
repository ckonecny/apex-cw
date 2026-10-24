// Audio trainer screen (#139): the page stays tidy, the options live in the
// gear sheet (length controls follow the content, as in Hören), and the
// settings are its own (profile `audio`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/audio_trainer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    Strings.lang.value = 0;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['cw_symbols', 'cw_straight_wpm', 'cw_gen_events', 'cw_mic']) {
      m.setMockStreamHandler(EventChannel('at.oe1cko.nextcwtrainer/$ch'),
          MockStreamHandler.inline(onListen: (_, sink) {}));
    }
    for (final ch in ['cw_keyer', 'cw_generator', 'cw_tone', 'settings']) {
      m.setMockMethodCallHandler(
          MethodChannel('at.oe1cko.nextcwtrainer/$ch'), (c) async {
        calls.add('$ch.${c.method}(${c.arguments})');
        return null;
      });
    }
  });

  Future<void> open(WidgetTester tester, Map<String, Object> prefs,
      {double scale = 1.0, Size size = const Size(360, 800)}) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: const AudioTrainerScreen(),
      ),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // charset 0 = Koch lesson; content: 0 random, 1 words, 2 abbreviations, 4 mixed.
  Map<String, Object> prefs(int content) => {
        'profile.audio.wpm': 20,
        'profile.audio.charset': 0,
        'profile.audio.content': content,
      };

  final group = find.text('Gruppenlänge (min–max)');
  final word = find.text('Wortlänge (min–max)');
  final abbrev = find.text('Abkürzungslänge (min–max)');
  final language = find.text('Wortsprache');
  final think = find.text('Denkpause');
  final rest = find.text('Pause zwischen Gruppen');
  final voice = find.text('Stimme');
  final volume = find.text('Lautstärke der Stimme');

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump(const Duration(milliseconds: 600));
    // The sheet reads its preferences asynchronously.
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the page itself carries none of the options', (tester) async {
    await open(tester, prefs(4), size: const Size(360, 4000));
    for (final f in [group, word, abbrev, language, think, rest, voice, volume]) {
      expect(f, findsNothing);
    }
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsNothing);
  });

  for (final c in [
    ('random', 0, true, false, false),
    ('words', 1, false, true, false),
    ('abbrevs', 2, false, false, true),
    ('mixed', 4, true, true, true),
  ]) {
    testWidgets('${c.$1}: the sheet shows the matching length controls and the flow',
        (tester) async {
      // A tall view, so the sheet builds every row.
      await open(tester, prefs(c.$2), size: const Size(360, 4000));
      await openSheet(tester);
      expect(group.evaluate().isNotEmpty, c.$3, reason: 'group length');
      expect(word.evaluate().isNotEmpty, c.$4, reason: 'word length');
      expect(language.evaluate().isNotEmpty, c.$4, reason: 'word language');
      expect(abbrev.evaluate().isNotEmpty, c.$5, reason: 'abbreviation length');
      for (final f in [think, rest, voice, volume]) {
        expect(f, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page and sheet at scale 1.3 on a small phone do not overflow',
      (tester) async {
    await open(tester, prefs(4), scale: 1.3, size: const Size(360, 640));
    await openSheet(tester);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the voice volume setting reaches the native player on entry',
      (tester) async {
    await open(tester, {...prefs(0), 'profile.audio.atVolume': 40});
    expect(calls, contains('cw_tone.setVoiceVolume(0.4)'));
  });

  testWidgets('groups per block: 51 in the slider means endless', (tester) async {
    await open(tester, {...prefs(0), 'profile.audio.maxWords': 51});
    expect(find.text('Gruppen: 0'), findsOneWidget); // no "of N"
    await openSheet(tester);
    expect(find.text('endlos'), findsOneWidget);
  });

  testWidgets('groups per block: a number shows "n of N"', (tester) async {
    await open(tester, {...prefs(0), 'profile.audio.maxWords': 7});
    expect(find.text('Gruppen: 0 von 7'), findsOneWidget);
  });

  testWidgets('the voice volume defaults to 70 %', (tester) async {
    await open(tester, prefs(0));
    expect(calls, contains('cw_tone.setVoiceVolume(0.7)'));
  });

  testWidgets('the Koch sequence is the audio trainer\'s own, seeded from the global one',
      (tester) async {
    final p = {...prefs(0), 'kochSeq': 2};
    await open(tester, p);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getInt('audio.kochSeq'), 2); // copied once
    expect(sp.getInt('kochSeq'), 2); // global untouched
  });
}
