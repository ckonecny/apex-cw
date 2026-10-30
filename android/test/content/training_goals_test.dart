import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/training_goals.dart';
import 'package:shared_preferences/shared_preferences.dart';

const v = GoalValues(
  koch: true,
  kochLevel: 10,
  kochTotal: 40,
  interChar: 5,
  interWord: 11,
  groups: true,
  groupLength: 2,
  wpm: 20,
);

List<LeverGoal> order(Map<GoalLever, int?> targets) => [
  for (final e in targets.entries) LeverGoal(e.key, target: e.value),
];

List<bool> window(int right, int wrong) => [
  ...List.filled(right, true),
  ...List.filled(wrong, false),
];

GoalSuggestion? decide(
  List<LeverGoal> o, {
  GoalValues values = v,
  List<bool>? w,
  bool unlock = false,
  GoalStep? last,
  bool snoozed = false,
}) => decideGoal(
  order: o,
  values: values,
  window: w ?? window(95, 5),
  windowSize: 100,
  high: 0.9,
  low: 0.7,
  unlockReady: unlock,
  lastStep: last,
  snoozed: snoozed,
);

void main() {
  goalWindowTests();
  goalRulesTests();
  goalReadyTests();
  group('activeGoal', () {
    test('no goal set: nothing active', () {
      expect(
        activeGoal(
          order({GoalLever.wpm: null, GoalLever.charSpacing: null}),
          v,
        ),
        isNull,
      );
    });

    test('first unreached goal in the user order', () {
      final o = order({GoalLever.wpm: 25, GoalLever.charSpacing: 3});
      expect(activeGoal(o, v)!.lever, GoalLever.wpm);
    });

    test('a reached goal is skipped; turning the value back reopens it', () {
      final o = order({GoalLever.charSpacing: 5, GoalLever.wpm: 25});
      expect(activeGoal(o, v)!.lever, GoalLever.wpm);
      expect(
        activeGoal(o, v.withValue(GoalLever.charSpacing, 6))!.lever,
        GoalLever.charSpacing,
      );
    });

    test('a lever that does not apply is skipped, not blocking', () {
      final o = order({GoalLever.newChars: 0, GoalLever.wpm: 25});
      const words = GoalValues(interChar: 5, interWord: 11, wpm: 20);
      expect(activeGoal(o, words)!.lever, GoalLever.wpm);
      final typing = order({GoalLever.wordSpacing: 7, GoalLever.wpm: 25});
      const t = GoalValues(interChar: 5, interWord: 11, wpm: 20, typing: true);
      expect(activeGoal(typing, t)!.lever, GoalLever.wpm);
    });

    test('new characters "all" means the whole sequence', () {
      final o = order({GoalLever.newChars: 0});
      expect(goalReached(o.first, v), isFalse);
      expect(goalReached(o.first, v.withValue(GoalLever.newChars, 40)), isTrue);
    });
  });

  group('nextValue', () {
    test('one step, never past the goal', () {
      expect(
        nextValue(const LeverGoal(GoalLever.charSpacing, target: 3), v),
        4,
      );
      expect(nextValue(const LeverGoal(GoalLever.wpm, target: 21), v), 21);
      expect(
        nextValue(const LeverGoal(GoalLever.groupLength, target: 5), v),
        3,
      );
    });

    test('word gap never below the character gap', () {
      const tight = GoalValues(interChar: 7, interWord: 7, wpm: 20);
      expect(
        nextValue(const LeverGoal(GoalLever.wordSpacing, target: 6), tight),
        isNull,
      );
    });

    test('give speed only with an own cap below the listening speed', () {
      const g = LeverGoal(GoalLever.giveWpm, target: 18);
      expect(
        leverApplies(
          GoalLever.giveWpm,
          const GoalValues(interChar: 3, interWord: 7, wpm: 20),
        ),
        isFalse,
      );
      const capped = GoalValues(
        interChar: 3,
        interWord: 7,
        wpm: 20,
        giveCap: 14,
      );
      expect(leverApplies(GoalLever.giveWpm, capped), isTrue);
      expect(nextValue(g, capped), 15);
      const straight = GoalValues(
        interChar: 3,
        interWord: 7,
        wpm: 20,
        giveCap: 14,
        straightKey: true,
      );
      expect(leverApplies(GoalLever.giveWpm, straight), isFalse);
    });
  });

  group('decideGoal', () {
    final o = order({GoalLever.charSpacing: 3, GoalLever.wpm: 25});

    test('no goals: no proposal, however good', () {
      expect(decide(order({GoalLever.charSpacing: null})), isNull);
    });

    test('needs a full window at or above the high threshold', () {
      expect(decide(o, w: window(60, 0)), isNull);
      expect(decide(o, w: window(89, 11)), isNull);
      final s = decide(o, w: window(90, 10))!;
      expect(s.lever, GoalLever.charSpacing);
      expect((s.from, s.to), (5, 4));
      expect((s.position, s.count, s.target, s.stepsLeft), (1, 2, 3, 1));
      expect(s.rate, 0.9);
    });

    test('new characters follow the unlock rule, not the window', () {
      final k = order({GoalLever.newChars: 0, GoalLever.charSpacing: 3});
      expect(decide(k), isNull);
      final s = decide(k, w: window(10, 0), unlock: true)!;
      expect((s.lever, s.from, s.to), (GoalLever.newChars, 10, 11));
      expect(s.rate, isNull);
    });

    test('badly going: undo the last step if it is still in place', () {
      final last = GoalStep(DateTime(2026), GoalLever.charSpacing, 6, 5);
      final s = decide(o, w: window(60, 40), last: last)!;
      expect(
        (s.back, s.lever, s.from, s.to),
        (true, GoalLever.charSpacing, 5, 6),
      );
      // Changed by hand since: nothing to undo.
      expect(
        decide(
          o,
          w: window(60, 40),
          last: last,
          values: v.withValue(GoalLever.charSpacing, 4),
        ),
        isNull,
      );
      // New characters are never taken back.
      final unlock = GoalStep(DateTime(2026), GoalLever.newChars, 9, 10);
      expect(decide(o, w: window(60, 40), last: unlock), isNull);
      // An undo is not undone again.
      final back = GoalStep(
        DateTime(2026),
        GoalLever.charSpacing,
        5,
        6,
        kind: GoalStepKind.back,
      );
      expect(decide(o, w: window(60, 40), last: back), isNull);
    });

    test('"Not now" silences every proposal', () {
      expect(decide(o, snoozed: true), isNull);
    });
  });

  group('GoalStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'window keeps the last N and restarts on a change of the settings',
      () async {
        final p = await SharedPreferences.getInstance();
        final st = GoalStore(p, 'hear');
        await st.recordBlock(window(80, 0), 'a');
        expect((await st.recordBlock(window(50, 0), 'a')).length, 100);
        expect((await st.recordBlock(window(10, 0), 'b')).length, 10);
      },
    );

    test('accepting logs the step and empties the window', () async {
      final p = await SharedPreferences.getInstance();
      final st = GoalStore(p, 'hear');
      await st.setOrder(order({GoalLever.charSpacing: 4}));
      await st.recordBlock(window(100, 0), v.signature);
      const s = GoalSuggestion(lever: GoalLever.charSpacing, from: 5, to: 4);
      final reached = await st.accept(
        s,
        v.withValue(GoalLever.charSpacing, 4),
        DateTime(2026, 11, 2),
      );
      expect(reached, isTrue);
      expect(st.window, isEmpty);
      expect(
        st.lastStep!.encode(),
        GoalStep(
          DateTime(2026, 11, 2),
          GoalLever.charSpacing,
          5,
          4,
          reached: true,
        ).encode(),
      );
    });

    test('order keeps targets, start values and adds missing levers', () async {
      final p = await SharedPreferences.getInstance();
      final st = GoalStore(p, 'echo');
      await st.setOrder([
        const LeverGoal(GoalLever.wpm, target: 25, start: 18),
      ]);
      final o = st.order;
      expect(o.first.lever, GoalLever.wpm);
      expect((o.first.target, o.first.start), (25, 18));
      expect(o.map((g) => g.lever).toSet(), echoLevers.toSet());
    });

    test('"Not now" lasts 15 minutes', () async {
      final p = await SharedPreferences.getInstance();
      final st = GoalStore(p, 'hear');
      final t = DateTime(2026, 11, 2, 10);
      await st.snooze(t);
      expect(st.snoozed(t.add(const Duration(minutes: 14))), isTrue);
      expect(st.snoozed(t.add(const Duration(minutes: 15))), isFalse);
    });

    test('new users: no goals, the tip', () async {
      final p = await SharedPreferences.getInstance();
      await GoalStore.migrateIfNeeded(p);
      expect(setGoals(GoalStore(p, 'hear').order), isEmpty);
      expect(p.getInt(GoalStore.homeCardKey), 1);
      await GoalStore(p, 'hear').setOrder(order({GoalLever.wpm: 25}));
      expect(p.getInt(GoalStore.homeCardKey), 0);
    });

    test(
      'existing users: today\'s behaviour becomes goals, no tempo goal',
      () async {
        SharedPreferences.setMockInitialValues({
          'adaptiveBlockEma': 0.9,
          'profile.hear.interCharSpace': 8,
        });
        final p = await SharedPreferences.getInstance();
        await GoalStore.migrateIfNeeded(p);
        final hear = setGoals(GoalStore(p, 'hear').order);
        expect(
          [for (final g in hear) (g.lever, g.target)],
          [
            (GoalLever.newChars, 0),
            (GoalLever.charSpacing, 3),
            (GoalLever.wordSpacing, 7),
          ],
        );
        expect(hear[1].start, 8);
        final echo = setGoals(GoalStore(p, 'echo').order);
        expect(
          [for (final g in echo) g.lever],
          [GoalLever.newChars, GoalLever.charSpacing],
        );
        expect(p.getInt(GoalStore.homeCardKey), 2);
      },
    );
  });
}

void goalWindowTests() {
  group('GoalStore.windowFor', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('window only counts for the settings it was recorded with', () async {
      final st = GoalStore(await SharedPreferences.getInstance(), 'hear');
      await st.recordBlock([true, false, true], 'sigA');
      expect(st.windowFor('sigA'), [true, false, true]);
      expect(st.windowFor('sigB'), isEmpty);
    });
  });
}

void goalRulesTests() {
  group('goalRules', () {
    test('defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final r = goalRules(p, 'echo');
      expect((r.lowPct, r.highPct, r.unlockOccurrences), (70, 90, 20));
    });

    test('Geben follows Hören until it has its own value', () async {
      SharedPreferences.setMockInitialValues({'adaptiveHighThresholdPct': 80});
      final p = await SharedPreferences.getInstance();
      expect(goalRules(p, 'echo').highPct, 80);
      await p.setInt(goalRuleKey('echo', 'adaptiveHighThresholdPct'), 95);
      expect(goalRules(p, 'echo').highPct, 95);
      expect(goalRules(p, 'hear').highPct, 80);
    });
  });
}

void goalReadyTests() {
  List<bool> w(int right, int wrong) => [
    ...List.filled(right, true),
    ...List.filled(wrong, false),
  ];

  group('goalReady', () {
    test('few items: still at the start, whatever the rate', () {
      expect(goalReady(w(10, 0), 0.9), GoalReady.start);
      expect(goalReady(w(0, 10), 0.9), GoalReady.start);
      expect(goalReady(const [], 0.9), GoalReady.start);
    });

    test('words follow the rate once there are enough items', () {
      expect(goalReady(w(50, 30), 0.9), GoalReady.notYet);
      expect(goalReady(w(86, 14), 0.9), GoalReady.almost);
      expect(goalReady(w(90, 10), 0.9), GoalReady.onTrack);
    });
  });

  group('goalReadyBar', () {
    test('a bad rate keeps the bar low even with many items', () {
      final bar = goalReadyBar(w(40, 40), 100, 0.9);
      expect(bar, closeTo(0.5 / 0.9 * 0.8, 1e-9));
      expect(bar, lessThan(0.5));
    });

    test('grows with the amount at a good rate', () {
      expect(goalReadyBar(w(10, 0), 100, 0.9), closeTo(0.1, 1e-9));
      expect(goalReadyBar(w(80, 0), 100, 0.9), closeTo(0.8, 1e-9));
    });

    test('full only with a full window at or above the rate', () {
      expect(goalReadyBar(w(90, 10), 100, 0.9), closeTo(1, 1e-9));
      expect(goalReadyBar(w(89, 11), 100, 0.9), lessThan(1));
      expect(goalReadyBar(const [], 100, 0.9), 0);
    });
  });
}
