// Overflow guard (issues #29, #38): every no-argument screen must survive the
// longest (German) labels, small phones and the largest font scale the app
// allows (1.3, see text_scale_test.dart). A new screen goes into [screens].
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/char_practice_screen.dart';
import 'package:next_cw_trainer/ui/decoder_screen.dart';
import 'package:next_cw_trainer/ui/echo_trainer_screen.dart';
import 'package:next_cw_trainer/content/exam_profile.dart';
import 'package:next_cw_trainer/ui/exam_picker.dart';
import 'package:next_cw_trainer/ui/exam_screen.dart';
import 'package:next_cw_trainer/ui/exam_send_screen.dart';
import 'package:next_cw_trainer/ui/generator_screen.dart';
import 'package:next_cw_trainer/ui/goals_screen.dart';
import 'package:next_cw_trainer/ui/adventure_select_screen.dart';
import 'package:next_cw_trainer/ui/free_screen.dart';
import 'package:next_cw_trainer/ui/games_screen.dart';
import 'package:next_cw_trainer/ui/head_copy_screen.dart';
import 'package:next_cw_trainer/ui/mini_qso_screen.dart';
import 'package:next_cw_trainer/ui/q_groups_screen.dart';
import 'package:next_cw_trainer/ui/understand_screen.dart';
import 'package:next_cw_trainer/ui/q_groups_sheet_screen.dart';
import 'package:next_cw_trainer/ui/home_screen.dart';
import 'package:next_cw_trainer/ui/invaders_screen.dart';
import 'package:next_cw_trainer/ui/keyer_screen.dart';
import 'package:next_cw_trainer/content/char_stats.dart';
import 'package:next_cw_trainer/ui/widgets/decoder_chars_setting.dart';
import 'package:next_cw_trainer/content/mixup_suggest.dart';
import 'package:next_cw_trainer/ui/widgets/mixup_boost_chips.dart';
import 'package:next_cw_trainer/ui/widgets/mixup_trend_view.dart';
import 'package:next_cw_trainer/ui/widgets/mistake_lesson.dart';
import 'package:next_cw_trainer/ui/learn_screen.dart';
import 'package:next_cw_trainer/ui/links_screen.dart';
import 'package:next_cw_trainer/ui/memory_chain_screen.dart';
import 'package:next_cw_trainer/ui/morse_chart_screen.dart';
import 'package:next_cw_trainer/ui/morse_tree_screen.dart';
import 'package:next_cw_trainer/ui/morsel_screen.dart';
import 'package:next_cw_trainer/ui/pileup_screen.dart';
import 'package:next_cw_trainer/ui/qso_bot_screen.dart';
import 'package:next_cw_trainer/ui/radio_cave_screen.dart';
import 'package:next_cw_trainer/ui/wifi_trx_screen.dart';
import 'package:next_cw_trainer/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Per-day stats with mix-ups in both windows of the trend view (#101): one pair
// each for up / down / gone / new / too few, so every group is laid out.
Map<String, DayStat> _mixupDays() {
  final now = DateTime.now();
  DayStat d(Map<String, int> pairs, Map<String, int> att) {
    final s = DayStat()..pairs.addAll(pairs);
    att.forEach((k, v) => s.chars[k] = [v, 0]);
    s.attempts = att.values.fold(0, (a, v) => a + v);
    return s;
  }
  return {
    dayKey(now.subtract(const Duration(days: 2))): d(
        {'K>R': 8, 'F>L': 1, 'B>D': 4, 'S>H': 3, 'Q>G': 0},
        {'K': 40, 'F': 40, 'B': 40, 'S': 40, 'Q': 40}),
    dayKey(now.subtract(const Duration(days: 20))): d(
        {'K>R': 2, 'F>L': 6, 'Q>G': 5, 'S>H': 3},
        {'K': 40, 'F': 40, 'B': 40, 'S': 40, 'Q': 40}),
    dayKey(now.subtract(const Duration(days: 4))): d({'M>–': 1}, {'M': 3}),
  };
}

void main() {
  final screens = <String, Widget Function()>{
    'generator': () => const GeneratorScreen(),
    'decoder': () => const DecoderScreen(),
    'char_practice': () => const CharPracticeScreen(ch: 'q'),
    'echo': () => const EchoTrainerScreen(),
    'settings': () => const SettingsScreen(),
    'goals': () => const GoalsScreen(),
    'adventure_select': () => const AdventureSelectScreen(),
    'goal_settings': () => const GoalSettingsScreen(),
    'links': () => const LinksScreen(),
    'free': () => const FreeScreen(),
    'morse_tree': () => const MorseTreeScreen(),
    'head_copy': () => const HeadCopyScreen(),
    'q_groups': () => const QGroupsScreen(),
    'mini_qso': () => const MiniQsoScreen(),
    'understand': () => const UnderstandScreen(),
    'q_groups_sheet': () => const QGroupsSheetScreen(),
    'q_groups_sheet_all': () => const QGroupsSheetScreen(level: 3),
    'radio_cave': () => const RadioCaveScreen(),
    'invaders': () => const InvadersScreen(),
    'learn': () => const LearnScreen(),
    'exam': () => const ExamScreen(),
    'exam_send': () => const ExamSendScreen(),
    'exam_picker_custom': () => Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [
            ExamPicker(
                selected: ExamProfile.custom(wpm: 8, charWpm: 12),
                custom: ExamProfile.custom(),
                onSelect: (_) {}, onCustomChanged: (_) {}),
          ]),
        ),
    'exam_picker_uk': () => Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [
            ExamPicker(
                selected: examProfileById('uk12f'),
                custom: ExamProfile.custom(),
                onSelect: (_) {}, onCustomChanged: (_) {}),
          ]),
        ),
    'games': () => const GamesScreen(),
    'morse_chart': () => const MorseChartScreen(),
    'keyer': () => const KeyerScreen(),
    // Setting inside the CW Keyer / CW Decoder settings sheets (issue #52).
    'decoder_chars_setting': () => const Scaffold(
        body: SingleChildScrollView(child: DecoderCharsSetting())),
    // "Learn from the mistake" view in Hören → Tippen (issue #50).
    'mistake_lesson': () => Scaffold(
        body: SingleChildScrollView(child: MistakeLesson(
            word: 'quarantine7?', active: 3, display: (c) => c.toUpperCase()))),
    'memory_chain': () => const MemoryChainScreen(),
    'morsel': () => const MorselScreen(),
    'qso_bot': () => const QsoBotScreen(),
    'wifi_trx': () => const WifiTrxScreen(),
    'pileup': () => const PileupScreen(),
    'home': () => const HomeScreen(),
    // Mix-up trends tab (#101): populated, and only fresh data (empty state).
    'mixup_trends': () => Scaffold(
        body: MixupTrendView(days: _mixupDays(), outputCase: 1, onChar: (_) {})),
    'mixup_trends_empty': () => Scaffold(
        body: MixupTrendView(
            days: {dayKey(DateTime.now()): DayStat()..pairs['K>R'] = 1},
            outputCase: 0, onChar: (_) {})),
    // Mix-up pairs of the practice suggestion (#102): one ticked, one left out.
    'mixup_boost_chips': () {
      final pairs = suggestedMixups(_mixupDays(), DateTime.now(), maxPairs: 6, minRate: 0.0);
      return Scaffold(
          body: SingleChildScrollView(
              child: MixupBoostChips(
                  pairs: pairs,
                  excluded: {if (pairs.isNotEmpty) pairs.first.pair},
                  outputCase: 1,
                  onToggle: (_) {})));
    },
    'mixup_trends_none': () => Scaffold(
        body: MixupTrendView(days: const {}, outputCase: 0, onChar: (_) {})),
  };
  for (final e in screens.entries) {
    for (final lang in [0, 1]) {
      for (final scale in [1.0, 1.3]) {
        for (final size in [
          const Size(412, 915),
          const Size(360, 640),
          // Tall: a lazy list then lays out every row, not just the visible ones.
          const Size(360, 8000),
        ]) {
          testWidgets('${e.key} lang $lang scale $scale $size', (tester) async {
            SharedPreferences.setMockInitialValues({});
            Strings.lang.value = lang;
            tester.view.physicalSize = size * 3;
            tester.view.devicePixelRatio = 3;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            addTearDown(() => Strings.lang.value = 0);
            // Name the overflowing widget (file:line) in the failure message.
            final where = <String>[];
            final oldHandler = FlutterError.onError;
            FlutterError.onError = (d) {
              final t = d.toString();
              final m = RegExp(r'overflowed by [^\n]*|file:[^\n]*').allMatches(t);
              where.add(m.map((x) => x.group(0)).join(' @ '));
              oldHandler?.call(d);
            };
            addTearDown(() => FlutterError.onError = oldHandler);
            await tester.pumpWidget(MaterialApp(
              home: e.value(),
            ));
            await tester.pump(const Duration(milliseconds: 300));
            final ex = tester.takeException();
            
            expect(ex, isNull, reason: where.join('\n'));
          });
        }
      }
    }
  }
}
