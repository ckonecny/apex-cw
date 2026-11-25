// Engine trace (#18): records every call each screen sends to the native
// engine (method channels) and every stream it opens or closes (event
// channels), from opening the screen until it is closed, and compares that
// with the recorded trace in test/engine_trace/. Written before the channel
// and engine-config cleanup so the cleanup can prove it changed nothing the
// engine sees: same calls, same values, same order.
//
// Update the traces only for a deliberate change in what a screen sends:
//   flutter test test/engine_trace_test.dart --dart-define=UPDATE_TRACE=true
// and review the diff of test/engine_trace/ like code.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/adventure/adventure_store.dart';
import 'package:next_cw_trainer/ui/adventure_screen.dart';
import 'package:next_cw_trainer/ui/audio_trainer_screen.dart';
import 'package:next_cw_trainer/ui/char_practice_screen.dart';
import 'package:next_cw_trainer/ui/char_stats_screen.dart';
import 'package:next_cw_trainer/ui/decoder_screen.dart';
import 'package:next_cw_trainer/ui/echo_trainer_screen.dart';
import 'package:next_cw_trainer/ui/exam_screen.dart';
import 'package:next_cw_trainer/ui/exam_send_screen.dart';
import 'package:next_cw_trainer/ui/generator_screen.dart';
import 'package:next_cw_trainer/ui/head_copy_screen.dart';
import 'package:next_cw_trainer/ui/invaders_screen.dart';
import 'package:next_cw_trainer/ui/keyer_screen.dart';
import 'package:next_cw_trainer/ui/maze_game_screen.dart';
import 'package:next_cw_trainer/ui/memory_chain_screen.dart';
import 'package:next_cw_trainer/ui/mini_qso_screen.dart';
import 'package:next_cw_trainer/ui/morse_chart_screen.dart';
import 'package:next_cw_trainer/ui/morse_tree_screen.dart';
import 'package:next_cw_trainer/ui/morsel_screen.dart';
import 'package:next_cw_trainer/ui/pileup_screen.dart';
import 'package:next_cw_trainer/ui/q_groups_screen.dart';
import 'package:next_cw_trainer/ui/qso_bot_screen.dart';
import 'package:next_cw_trainer/ui/radio_cave_screen.dart';
import 'package:next_cw_trainer/ui/settings_screen.dart';
import 'package:next_cw_trainer/ui/wifi_trx_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _update = bool.fromEnvironment('UPDATE_TRACE');

/// The user's settings, all different from the defaults, so a screen that
/// sends a default instead of the setting shows up in the trace.
const _prefs = <String, Object>{
  'wpm': 23,
  'keyerMode': 3,
  'pitch': 777,
  'toneSoftness': 2,
  'curtisBDitTiming': 60,
  'curtisBDahTiming': 30,
  'acs': 2,
};

const _methodChannels = [
  'cw_tone', 'cw_generator', 'cw_keyer', 'settings', 'reminder', 'shortcuts',
  'share', 'own_playback', 'cw_mic',
];
const _eventChannels = [
  'cw_symbols', 'cw_gen_events', 'cw_straight_wpm', 'cw_straight_edges',
  'settings_events', 'key_adapter_events', 'cw_mic_pcm', 'audio_route_events',
];

/// Answers for calls whose result a screen needs to carry on.
const _replies = <String, Object>{
  'cw_generator.getWordLists': {
    'words': ['HOUSE', 'RADIO', 'MORSE'],
    'abbrevs': ['TNX', 'FB', 'OM'],
  },
};

/// What a screen does in the test after it opened (nothing by default).
typedef _Act = Future<void> Function(WidgetTester tester, Future<void> Function() settle);

class _Case {
  final Widget Function() build;
  final _Act? act;
  /// The screen plays random text (calls, exam texts): the text is masked.
  final bool randomText;
  const _Case(this.build, [this.act, this.randomText = false]);
}

/// Makes a trace comparable from run to run without hiding what matters:
/// - random text in play calls is masked when the case says so;
/// - `setAmbient` (the interference profile's background noise, pushed from
///   its own async flow that races the screen's set-up) keeps its values but
///   not its place: it is listed sorted at the end of its section.
String _normalise(List<String> calls, bool randomText) {
  final out = <String>[];
  final ambient = <String>[];
  void flush() {
    out.addAll((ambient..sort()).map((a) => '~ $a'));
    ambient.clear();
  }
  for (var c in calls) {
    if (c.startsWith('-- ')) {
      flush();
      out.add(c);
      continue;
    }
    if (c.startsWith('cw_tone.setAmbient(')) {
      ambient.add(c);
      continue;
    }
    if (randomText && c.startsWith('cw_generator.playOne(')) c = 'cw_generator.playOne(<text>)';
    out.add(c);
  }
  flush();
  return '${out.join('\n')}\n';
}

Future<void> _tap(WidgetTester t, Future<void> Function() settle, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await t.tap(f.first, warnIfMissed: false);
  await settle();
  // Sessions start after a short "get ready" delay; let a few seconds play.
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 500));
    await settle();
  }
}

Future<void> _tapText(WidgetTester t, Future<void> Function() settle, String text) =>
    _tap(t, settle, find.text(text));

/// Taps the screen's start button (a play icon), if it has one.
Future<void> _tapStart(WidgetTester t, Future<void> Function() settle) async {
  for (final icon in [Icons.play_arrow_rounded, Icons.play_arrow]) {
    final f = find.byIcon(icon);
    if (f.evaluate().isNotEmpty) return _tap(t, settle, f);
  }
}

final _cases = <String, _Case>{
  'adaptive_copy_generator': _Case(() => const GeneratorScreen()),
  'adventure': _Case(() => AdventureScreen(game: adventureGames.first, newGame: true)),
  'audio_trainer': _Case(() => const AudioTrainerScreen()),
  'char_practice': _Case(() => const CharPracticeScreen(ch: 'q')),
  'char_stats': _Case(() => const CharStatsScreen(track: 'hear')),
  'decoder': _Case(() => const DecoderScreen()),
  'echo': _Case(() => const EchoTrainerScreen()),
  'exam': _Case(() => const ExamScreen()),
  'exam_send': _Case(() => const ExamSendScreen()),
  'head_copy': _Case(() => const HeadCopyScreen()),
  'invaders': _Case(() => const InvadersScreen()),
  'keyer': _Case(() => const KeyerScreen()),
  'maze_trailblazer': _Case(() => const MazeGameScreen(game: MazeGame.trailblazer)),
  'maze_fox_hunt': _Case(() => const MazeGameScreen(game: MazeGame.foxHunt)),
  'memory_chain': _Case(() => const MemoryChainScreen()),
  'mini_qso': _Case(() => const MiniQsoScreen()),
  'morse_chart': _Case(() => const MorseChartScreen()),
  'morse_chart_tap': _Case(() => const MorseChartScreen(), (t, s) => _tapText(t, s, 'K')),
  'morse_tree': _Case(() => const MorseTreeScreen()),
  'morsel': _Case(() => const MorselScreen()),
  'pileup': _Case(() => const PileupScreen()),
  'q_groups': _Case(() => const QGroupsScreen()),
  'qso_bot': _Case(() => const QsoBotScreen()),
  'radio_cave': _Case(() => const RadioCaveScreen()),
  'settings': _Case(() => const SettingsScreen()),
  'wifi_trx': _Case(() => const WifiTrxScreen()),
  // The same screens with their session started (config pushed at start).
  'adaptive_copy_generator_start':
      _Case(() => const GeneratorScreen(), (t, s) => _tap(t, s, find.byIcon(Icons.edit_outlined))),
  'adaptive_copy_generator_typing':
      _Case(() => const GeneratorScreen(), (t, s) => _tap(t, s, find.byIcon(Icons.keyboard_outlined))),
  for (final e in {
    'audio_trainer': () => const AudioTrainerScreen(),
    'decoder': () => const DecoderScreen(),
    'echo': () => const EchoTrainerScreen(),
    'exam': () => const ExamScreen(),
    'exam_send': () => const ExamSendScreen(),
    'head_copy': () => const HeadCopyScreen(),
    'invaders': () => const InvadersScreen(),
    'maze_trailblazer': () => const MazeGameScreen(game: MazeGame.trailblazer),
    'memory_chain': () => const MemoryChainScreen(),
    'morsel': () => const MorselScreen(),
    'pileup': () => const PileupScreen(),
    'radio_cave': () => const RadioCaveScreen(),
  }.entries)
    '${e.key}_start':
        _Case(e.value, _tapStart, const {'exam', 'pileup', 'radio_cave', 'echo'}.contains(e.key)),
};

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues(Map.of(_prefs));
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in _eventChannels) {
      m.setMockStreamHandler(
          EventChannel('at.oe1cko.nextcwtrainer/$ch'),
          MockStreamHandler.inline(
            onListen: (a, sink) => calls.add('$ch.listen($a)'),
            onCancel: (a) => calls.add('$ch.cancel($a)'),
          ));
    }
    for (final ch in _methodChannels) {
      m.setMockMethodCallHandler(MethodChannel('at.oe1cko.nextcwtrainer/$ch'), (c) async {
        calls.add('$ch.${c.method}(${c.arguments})');
        return _replies['$ch.${c.method}'];
      });
    }
    final tmp = Directory.systemTemp.createTempSync('engine_trace');
    addTearDown(() => tmp.deleteSync(recursive: true));
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
  });

  for (final e in _cases.entries) {
    testWidgets('engine trace: ${e.key}', (tester) async {
      Future<void> settle() async {
        // Preferences and assets load asynchronously: let the real event loop run.
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 300));
      }

      calls.add('-- open');
      await tester.pumpWidget(MaterialApp(home: e.value.build()));
      await settle();
      await settle();
      if (e.value.act != null) {
        calls.add('-- act');
        await e.value.act!(tester, settle);
      }
      calls.add('-- close');
      await tester.pumpWidget(const SizedBox());
      await settle();
      // Let pending timers (playback waits, game ticks) run out.
      await tester.pump(const Duration(seconds: 15));
      tester.takeException();   // other mocked services may complain; not the point here

      final file = File('test/engine_trace/${e.key}.txt');
      final got = _normalise(calls, e.value.randomText);
      if (_update) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(got);
      } else {
        expect(file.existsSync(), isTrue,
            reason: 'no trace for ${e.key}; record it with --dart-define=UPDATE_TRACE=true');
        expect(got, file.readAsStringSync(),
            reason: '${e.key} sends something different to the engine than recorded');
      }
    });
  }
}
