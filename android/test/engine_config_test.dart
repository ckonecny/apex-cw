// CLAUDE.md rule 2: CwGenerator, CwKeyer and the tone engine are shared native
// singletons; nothing re-syncs them, so every screen must push its own
// config when it opens. This test opens the screens with recording channel
// mocks and fixes DISTINCTIVE (non-default) preference values, so a screen
// that forgets a setter, sends a default instead of the user's value, or
// reads the wrong preference key fails here instead of on the phone.
//
// A new screen that uses the keyer or the generator goes into one of the
// lists below. Screens that push their config only when a session starts
// (after a button press) are listed in [_pushedAtSessionStart]; they are not
// covered here.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/ui/char_practice_screen.dart';
import 'package:next_cw_trainer/ui/head_copy_screen.dart';
import 'package:next_cw_trainer/ui/invaders_screen.dart';
import 'package:next_cw_trainer/ui/keyer_screen.dart';
import 'package:next_cw_trainer/ui/memory_chain_screen.dart';
import 'package:next_cw_trainer/ui/mini_qso_screen.dart';
import 'package:next_cw_trainer/ui/morse_chart_screen.dart';
import 'package:next_cw_trainer/ui/morse_tree_screen.dart';
import 'package:next_cw_trainer/ui/pileup_screen.dart';
import 'package:next_cw_trainer/ui/q_groups_screen.dart';
import 'package:next_cw_trainer/ui/qso_bot_screen.dart';
import 'package:next_cw_trainer/ui/radio_cave_screen.dart';
import 'package:next_cw_trainer/ui/wifi_trx_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's settings, all different from the defaults.
const _prefs = <String, Object>{
  'wpm': 23,
  'keyerMode': 3,
  'pitch': 777,
  'toneSoftness': 2,
  'curtisBDitTiming': 60,
  'curtisBDahTiming': 30,
  'acs': 2,
};

/// What the tone engine must have received from those prefs.
const _toneCalls = ['cw_tone.setFreq(777)', 'cw_tone.setEnvelopeMs(3.0)'];

/// Screens that configure the keyer on entry (and may start it).
final _keyerScreens = <String, Widget Function()>{
  'keyer': () => const KeyerScreen(),
  'qso_bot': () => const QsoBotScreen(),
  'wifi_trx': () => const WifiTrxScreen(),
  'radio_cave': () => const RadioCaveScreen(),
  'invaders': () => const InvadersScreen(),
  'memory_chain': () => const MemoryChainScreen(),
  'pileup': () => const PileupScreen(),
};

/// Screens that configure the generator (spacing included) on entry.
final _generatorScreens = <String, Widget Function()>{
  'head_copy': () => const HeadCopyScreen(),
  'q_groups': () => const QGroupsScreen(),
  'mini_qso': () => const MiniQsoScreen(),
};

/// Single-character playback only: speed and tone, no spacing needed.
final _singleCharScreens = <String, Widget Function()>{
  'morse_chart': () => const MorseChartScreen(),
  'morse_tree': () => const MorseTreeScreen(),
};

// Not covered (config is pushed when a session starts, behind a button):
// echo, exam, exam_send, generator (Geben), morsel, adventure, decoder (only
// the tone). Each has its own test or is exercised on the phone.
// ignore: unused_element
const _pushedAtSessionStart = [
  'echo', 'exam', 'exam_send', 'generator', 'morsel', 'adventure', 'decoder',
];

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues(Map.of(_prefs));
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['cw_symbols', 'cw_straight_wpm', 'cw_gen_events', 'cw_mic']) {
      m.setMockStreamHandler(EventChannel('at.oe1cko.nextcwtrainer/$ch'),
          MockStreamHandler.inline(onListen: (_, sink) {}));
    }
    for (final ch in ['cw_keyer', 'cw_generator', 'cw_tone', 'settings']) {
      m.setMockMethodCallHandler(MethodChannel('at.oe1cko.nextcwtrainer/$ch'), (c) async {
        calls.add('$ch.${c.method}(${c.arguments})');
        return null;
      });
    }
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(home: screen));
    // Preferences load asynchronously: let the real event loop run.
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();   // other mocked services may complain; not the point here
  }

  void expectAll(List<String> wanted, String screen) {
    final missing = wanted.where((w) => !calls.contains(w)).toList();
    expect(missing, isEmpty,
        reason: '$screen did not push ${missing.join(', ')}.\nIt sent: ${calls.join(' | ')}');
  }

  for (final e in _keyerScreens.entries) {
    testWidgets('${e.key}: keyer and tone config from the user\'s settings', (tester) async {
      await open(tester, e.value());
      expectAll([
        ..._toneCalls,
        'cw_keyer.setWpm(23)',
        'cw_keyer.setMode(3)',
        'cw_keyer.setCurtisBTiming({dit: 60, dah: 30})',
        'cw_keyer.setAcs(2)',
      ], e.key);
    });
  }

  for (final e in _generatorScreens.entries) {
    testWidgets('${e.key}: generator speed, spacing and tone on entry', (tester) async {
      await open(tester, e.value());
      expectAll(_toneCalls, e.key);
      final names = calls.map((c) => c.split('(').first).toSet();
      expect(
        names.containsAll([
          'cw_generator.setWpm',
          'cw_generator.setInterCharSpace',
          'cw_generator.setInterWordSpace',
        ]),
        isTrue,
        reason: '${e.key} sent: ${calls.join(' | ')}',
      );
    });
  }

  for (final e in _singleCharScreens.entries) {
    testWidgets('${e.key}: generator speed and tone on entry', (tester) async {
      await open(tester, e.value());
      expectAll(_toneCalls, e.key);
      expect(calls.any((c) => c.startsWith('cw_generator.setWpm(')), isTrue,
          reason: '${e.key} sent: ${calls.join(' | ')}');
    });
  }

  // Two phases: it plays the character through the generator (speed from the
  // settings), and sets the keyer speed only right before the answer.
  testWidgets('char_practice: generator speed and keyer config on entry', (tester) async {
    await open(tester, const CharPracticeScreen(ch: 'q'));
    expectAll([
      ..._toneCalls.where((c) => c.contains('Envelope')),
      'cw_generator.setWpm(23)',
      'cw_keyer.setMode(3)',
      'cw_keyer.setCurtisBTiming({dit: 60, dah: 30})',
      'cw_keyer.setAcs(2)',
    ], 'char_practice');
    // The screen waits up to 10 s for the playback to end: let that timer run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('keyer screens set the config before they start the keyer', (tester) async {
    await open(tester, const KeyerScreen());
    final start = calls.indexOf('cw_keyer.start(null)');
    expect(start, greaterThan(0));
    for (final need in ['cw_keyer.setMode(3)', 'cw_keyer.setCurtisBTiming({dit: 60, dah: 30})']) {
      expect(calls.indexOf(need), inInclusiveRange(0, start - 1), reason: calls.join(' | '));
    }
  });
}
