// Training goals (Trainingsziele): per training (Hören / Geben) the user sets
// a target value per lever and the order to work through them. The app only
// proposes the next step towards the first goal not yet reached; nothing is
// ever changed without a tap. No goal = no proposal (DECISIONS.md "Training
// goals"). Pure Dart apart from the SharedPreferences store at the bottom.
import 'package:shared_preferences/shared_preferences.dart';

enum GoalLever { newChars, charSpacing, wordSpacing, groupLength, wpm, giveWpm }

/// Levers each training offers, in the default order. Geben has no word
/// spacing (it only sets the answer pause), Hören no give speed.
const hearLevers = [
  GoalLever.newChars,
  GoalLever.charSpacing,
  GoalLever.wordSpacing,
  GoalLever.groupLength,
  GoalLever.wpm,
];
const echoLevers = [
  GoalLever.newChars,
  GoalLever.charSpacing,
  GoalLever.groupLength,
  GoalLever.wpm,
  GoalLever.giveWpm,
];
List<GoalLever> leversOf(String kind) =>
    kind == 'echo' ? echoLevers : hearLevers;

/// Spacing goes down towards its goal, everything else up.
bool lowerIsHarder(GoalLever l) =>
    l == GoalLever.charSpacing || l == GoalLever.wordSpacing;

/// Range a goal can be set to (newChars: 0 = all characters).
(int, int) goalRange(GoalLever l) => switch (l) {
  GoalLever.newChars => (2, 60),
  GoalLever.charSpacing => (3, 45),
  GoalLever.wordSpacing => (6, 105),
  GoalLever.groupLength => (1, 8),
  GoalLever.wpm || GoalLever.giveWpm => (10, 60),
};

/// Readiness window: the last 100 graded characters since the last change,
/// in Hören and Geben alike (Geben: per character of the first try).
int goalWindow(String kind) => 100;

/// When a step is suggested, per training: the two success thresholds
/// (percent) and the occurrences each character needs for "New characters".
/// Hören keeps the original keys; Geben has its own and follows Hören's value
/// until it is changed there once.
class GoalRules {
  final int lowPct, highPct, unlockOccurrences;
  const GoalRules(this.lowPct, this.highPct, this.unlockOccurrences);
  double get high => highPct / 100;
  double get low => lowPct / 100;
}

String goalRuleKey(String kind, String name) =>
    kind == 'echo' ? 'echo.$name' : name;

const _ruleLow = 'adaptiveLowThresholdPct';
const _ruleHigh = 'adaptiveHighThresholdPct';
const _ruleOcc = 'adaptiveUnlockOccurrences';

GoalRules goalRules(SharedPreferences p, String kind) {
  int get(String name, int def) =>
      p.getInt(goalRuleKey(kind, name)) ?? p.getInt(name) ?? def;
  return GoalRules(
    get(_ruleLow, 70).clamp(30, 95),
    get(_ruleHigh, 90).clamp(50, 99),
    get(_ruleOcc, 20).clamp(5, 50),
  );
}

/// "Nicht jetzt" pauses all proposals of the training for this long.
const goalSnooze = Duration(minutes: 15);

/// The current settings of one training as the goals read them.
class GoalValues {
  final bool koch; // character set Koch: only then "new characters" applies
  final int kochLevel, kochTotal;
  final int interChar, interWord;
  final bool groups; // content plays character groups (group length applies)
  final int groupLength; // shortest group
  final int wpm;
  final int giveCap; // Geben: answer speed cap, 0 = same as Hören
  final bool typing; // Hören on the keyboard: the word gap has no effect
  final bool straightKey; // Geben with a straight key: own spacing and speed

  const GoalValues({
    this.koch = false,
    this.kochLevel = 0,
    this.kochTotal = 0,
    required this.interChar,
    required this.interWord,
    this.groups = false,
    this.groupLength = 5,
    required this.wpm,
    this.giveCap = 0,
    this.typing = false,
    this.straightKey = false,
  });

  /// Effective give speed: the cap, but never above the listening speed.
  int get giveWpm => giveCap <= 0 ? wpm : (giveCap < wpm ? giveCap : wpm);

  int valueOf(GoalLever l) => switch (l) {
    GoalLever.newChars => kochLevel,
    GoalLever.charSpacing => interChar,
    GoalLever.wordSpacing => interWord,
    GoalLever.groupLength => groupLength,
    GoalLever.wpm => wpm,
    GoalLever.giveWpm => giveWpm,
  };

  /// The same values with one lever changed (a step just applied).
  GoalValues withValue(GoalLever l, int v) => GoalValues(
    koch: koch,
    kochLevel: l == GoalLever.newChars ? v : kochLevel,
    kochTotal: kochTotal,
    interChar: l == GoalLever.charSpacing ? v : interChar,
    interWord: l == GoalLever.wordSpacing
        ? v
        : l == GoalLever.charSpacing && interWord < v
        ? v
        : interWord,
    groups: groups,
    groupLength: l == GoalLever.groupLength ? v : groupLength,
    wpm: l == GoalLever.wpm ? v : wpm,
    giveCap: l == GoalLever.giveWpm ? v : giveCap,
    typing: typing,
    straightKey: straightKey,
  );

  /// Everything that sets the difficulty; a change starts the window anew.
  String get signature =>
      '${koch ? kochLevel : 0}|$interChar|$interWord|${groups ? groupLength : 0}'
      '|$wpm|$giveCap|$straightKey';
}

class LeverGoal {
  final GoalLever lever;
  final int? target; // null = no goal; newChars 0 = all characters
  final int? start; // value when the goal was set, for the statistics
  const LeverGoal(this.lever, {this.target, this.start});
}

/// The goal value a lever has to reach with the current values (newChars:
/// "all" is the length of the Koch sequence).
int effectiveTarget(LeverGoal g, GoalValues v) {
  final t = g.target!;
  if (g.lever != GoalLever.newChars) return t;
  return t == 0 || t > v.kochTotal ? v.kochTotal : t;
}

bool goalReached(LeverGoal g, GoalValues v) {
  if (g.target == null) return false;
  final now = v.valueOf(g.lever), t = effectiveTarget(g, v);
  return lowerIsHarder(g.lever) ? now <= t : now >= t;
}

/// Whether the lever means anything with the current settings; one that
/// doesn't is skipped (not blocked) by the order.
bool leverApplies(GoalLever l, GoalValues v) => switch (l) {
  GoalLever.newChars => v.koch && v.kochTotal > 0,
  GoalLever.charSpacing => !v.straightKey,
  GoalLever.wordSpacing => !v.typing,
  GoalLever.groupLength => v.groups,
  GoalLever.wpm => true,
  // Only with an own cap below the listening speed (as before the goals).
  GoalLever.giveWpm => !v.straightKey && v.giveCap > 0 && v.giveCap < v.wpm,
};

/// One step towards the goal, never past it; null when no step is possible.
int? nextValue(LeverGoal g, GoalValues v) {
  final now = v.valueOf(g.lever), t = effectiveTarget(g, v);
  final int next = switch (g.lever) {
    GoalLever.newChars => now + 1,
    GoalLever.charSpacing => now - 1,
    // The word gap never drops below the character gap.
    GoalLever.wordSpacing => now - 1 < v.interChar ? now : now - 1,
    GoalLever.groupLength => now + 1,
    GoalLever.wpm => now + 1,
    GoalLever.giveWpm => v.giveCap + 1,
  };
  final (lo0, hi) = goalRange(g.lever);
  // A Koch sequence shorter than the range's minimum must not invert it.
  final newChars = g.lever == GoalLever.newChars;
  final lo = newChars && v.kochTotal < lo0 ? v.kochTotal : lo0;
  final clamped = lowerIsHarder(g.lever)
      ? (next < t ? t : next).clamp(lo, hi)
      : (next > t ? t : next).clamp(lo, newChars ? v.kochTotal : hi);
  final from = g.lever == GoalLever.giveWpm ? v.giveCap : now;
  return clamped == from ? null : clamped;
}

/// The goal the app works on: the first one in the user's order that has a
/// target, applies now and is not reached. Null = no proposals.
LeverGoal? activeGoal(List<LeverGoal> order, GoalValues v) {
  for (final g in order) {
    if (g.target == null || !leverApplies(g.lever, v) || goalReached(g, v)) {
      continue;
    }
    if (nextValue(g, v) == null) continue;
    return g;
  }
  return null;
}

/// Goals with a target, in order (for "goal 2 of 5").
List<LeverGoal> setGoals(List<LeverGoal> order) => [
  for (final g in order)
    if (g.target != null) g,
];

enum GoalStepKind { step, back }

class GoalStep {
  final DateTime at;
  final GoalLever lever;
  final int from, to;
  final GoalStepKind kind;
  final bool reached; // this step reached the goal
  const GoalStep(
    this.at,
    this.lever,
    this.from,
    this.to, {
    this.kind = GoalStepKind.step,
    this.reached = false,
  });

  String encode() =>
      '${at.millisecondsSinceEpoch}|${lever.name}|$from|$to|${kind.name}|${reached ? 1 : 0}';

  static GoalStep? decode(String s) {
    final f = s.split('|');
    if (f.length < 6) return null;
    final ms = int.tryParse(f[0]),
        from = int.tryParse(f[2]),
        to = int.tryParse(f[3]);
    final lever = GoalLever.values.where((l) => l.name == f[1]).firstOrNull;
    final kind = GoalStepKind.values.where((k) => k.name == f[4]).firstOrNull;
    if (ms == null ||
        from == null ||
        to == null ||
        lever == null ||
        kind == null) {
      return null;
    }
    return GoalStep(
      DateTime.fromMillisecondsSinceEpoch(ms),
      lever,
      from,
      to,
      kind: kind,
      reached: f[5] == '1',
    );
  }
}

/// What the result page offers after a block.
class GoalSuggestion {
  final GoalLever lever;
  final int from, to;
  final bool back; // undo the last step instead of a step forward
  final int position, count; // "goal position of count"
  final int? target; // effective goal value (forward only)
  final int stepsLeft; // steps still needed after this one (forward only)
  final double? rate; // hit rate over the window, null for new characters
  const GoalSuggestion({
    required this.lever,
    required this.from,
    required this.to,
    this.back = false,
    this.position = 0,
    this.count = 0,
    this.target,
    this.stepsLeft = 0,
    this.rate,
  });
}

/// Hit rate of the window, null while it holds fewer than [size] items.
double? windowRate(List<bool> window, int size) {
  if (window.length < size) return null;
  final last = window.sublist(window.length - size);
  return last.where((r) => r).length / size;
}

/// Fewer graded items than this: the readiness line says "still at the start".
const goalReadyMinItems = 30;

/// How far below the needed rate still counts as "almost there".
const goalAlmostGap = 0.05;

enum GoalReady { start, notYet, almost, onTrack }

/// Hit rate of everything in the window so far (null while it is empty).
double? windowRateSoFar(List<bool> window) =>
    window.isEmpty ? null : window.where((r) => r).length / window.length;

/// Readiness for the next step in words. The rate counts as soon as there
/// are a few items; before that only "at the start".
GoalReady goalReady(List<bool> window, double high) {
  final rate = windowRateSoFar(window);
  if (rate == null || window.length < goalReadyMinItems) return GoalReady.start;
  if (rate >= high) return GoalReady.onTrack;
  if (rate >= high - goalAlmostGap) return GoalReady.almost;
  return GoalReady.notYet;
}

/// Bar value 0..1: hit rate relative to the needed rate, times how much of
/// the window is filled. Full only with a full window at or above [high], so
/// many items with a bad rate never show a high bar.
double goalReadyBar(List<bool> window, int size, double high) {
  final rate = windowRateSoFar(window);
  if (rate == null) return 0;
  final filled = (window.length / size).clamp(0.0, 1.0);
  return ((rate / high).clamp(0.0, 1.0) * filled).clamp(0.0, 1.0);
}

/// Decides the proposal after a block. [window] already holds this block.
/// [unlockReady]: every active Koch character is practised enough (the
/// existing per-character rule); it drives the "new characters" goal only.
GoalSuggestion? decideGoal({
  required List<LeverGoal> order,
  required GoalValues values,
  required List<bool> window,
  required int windowSize,
  required double high,
  required double low,
  required bool unlockReady,
  GoalStep? lastStep,
  bool snoozed = false,
}) {
  if (snoozed) return null;
  final rate = windowRate(window, windowSize);
  // Going badly: offer to undo the last step, whatever the lever — except
  // new characters, which are never taken away again.
  if (rate != null &&
      rate < low &&
      lastStep != null &&
      lastStep.kind == GoalStepKind.step &&
      lastStep.lever != GoalLever.newChars &&
      _stepValue(lastStep.lever, values) == lastStep.to) {
    return GoalSuggestion(
      lever: lastStep.lever,
      from: lastStep.to,
      to: lastStep.from,
      back: true,
      rate: rate,
    );
  }
  final g = activeGoal(order, values);
  if (g == null) return null;
  final ready = g.lever == GoalLever.newChars
      ? unlockReady
      : (rate != null && rate >= high);
  if (!ready) return null;
  final to = nextValue(g, values)!;
  final t = effectiveTarget(g, values);
  final goals = setGoals(order);
  return GoalSuggestion(
    lever: g.lever,
    from: g.lever == GoalLever.giveWpm
        ? values.giveCap
        : values.valueOf(g.lever),
    to: to,
    position: goals.indexOf(g) + 1,
    count: goals.length,
    target: t,
    stepsLeft: (t - to).abs(),
    rate: g.lever == GoalLever.newChars ? null : rate,
  );
}

// The stored value a step changed (the give cap, not the effective speed).
int _stepValue(GoalLever l, GoalValues v) =>
    l == GoalLever.giveWpm ? v.giveCap : v.valueOf(l);

/// Persisted goals and progress of one training (`goals.<kind>.*`).
class GoalStore {
  static const _versionKey = 'goalsVersion';

  /// Start-page card: 1 = tip for new users, 2 = "new" notice after the
  /// update, 0 / missing = dismissed.
  static const homeCardKey = 'goalsHomeCard';
  static const _logMax = 200;

  final SharedPreferences _p;
  final String kind;
  GoalStore(this._p, this.kind);

  static Future<GoalStore> open(String kind) async {
    final p = await SharedPreferences.getInstance();
    await migrateIfNeeded(p);
    return GoalStore(p, kind);
  }

  String _k(String f) => 'goals.$kind.$f';

  /// All levers of the training in the user's order, each with or without a
  /// target. Unknown or missing levers are appended in the default order.
  List<LeverGoal> get order {
    final out = <LeverGoal>[];
    for (final part in (_p.getString(_k('order')) ?? '').split(',')) {
      final f = part.split(':');
      final lever = leversOf(kind).where((l) => l.name == f[0]).firstOrNull;
      if (lever == null || out.any((g) => g.lever == lever)) continue;
      out.add(
        LeverGoal(
          lever,
          target: f.length > 1 ? int.tryParse(f[1]) : null,
          start: f.length > 2 ? int.tryParse(f[2]) : null,
        ),
      );
    }
    for (final l in leversOf(kind)) {
      if (!out.any((g) => g.lever == l)) out.add(LeverGoal(l));
    }
    return out;
  }

  Future<void> setOrder(List<LeverGoal> goals) async {
    await _p.setString(
      _k('order'),
      goals
          .map((g) => '${g.lever.name}:${g.target ?? ''}:${g.start ?? ''}')
          .join(','),
    );
    // The tip has done its job once a goal is set.
    if (goals.any((g) => g.target != null) && _p.getInt(homeCardKey) == 1) {
      await _p.setInt(homeCardKey, 0);
    }
  }

  String? get windowSignature => _p.getString(_k('sig'));

  List<bool> get window => [
    for (final ch in (_p.getString(_k('window')) ?? '').split('')) ch == '1',
  ];

  /// Adds one block's graded items. A change of the settings since the last
  /// block (step taken, value set by hand) starts the window anew.
  Future<List<bool>> recordBlock(List<bool> results, String signature) async {
    var w = _p.getString(_k('sig')) == signature ? window : <bool>[];
    w = [...w, ...results];
    final size = goalWindow(kind);
    if (w.length > size) w = w.sublist(w.length - size);
    await _p.setString(_k('sig'), signature);
    await _p.setString(_k('window'), w.map((r) => r ? '1' : '0').join());
    return w;
  }

  /// The window as it stands for the given settings (empty once they changed
  /// or a step was applied), for the "On the way to" card.
  List<bool> windowFor(String signature) =>
      _p.getString(_k('sig')) == signature ? window : const [];

  bool snoozed(DateTime now) =>
      now.millisecondsSinceEpoch < (_p.getInt(_k('snooze')) ?? 0);
  Future<void> snooze(DateTime now) =>
      _p.setInt(_k('snooze'), now.add(goalSnooze).millisecondsSinceEpoch);

  List<GoalStep> get log => [
    for (final s in _p.getStringList(_k('log')) ?? const <String>[])
      ?GoalStep.decode(s),
  ];

  GoalStep? get lastStep {
    final l = log;
    return l.isEmpty ? null : l.last;
  }

  /// Records an accepted proposal and starts the window anew.
  Future<void> logStep(GoalStep s) async {
    final l = [
      ...(_p.getStringList(_k('log')) ?? const <String>[]),
      s.encode(),
    ];
    await _p.setStringList(
      _k('log'),
      l.length > _logMax ? l.sublist(l.length - _logMax) : l,
    );
    await _p.remove(_k('window'));
  }

  /// Block end: adds the graded items to the window and decides what the
  /// result page offers.
  Future<GoalSuggestion?> afterBlock({
    required List<bool> results,
    required GoalValues values,
    required double high,
    required double low,
    required bool unlockReady,
    required DateTime now,
  }) async {
    final w = await recordBlock(results, values.signature);
    return decideGoal(
      order: order,
      values: values,
      window: w,
      windowSize: goalWindow(kind),
      high: high,
      low: low,
      unlockReady: unlockReady,
      lastStep: lastStep,
      snoozed: snoozed(now),
    );
  }

  /// The user tapped "Apply"; [after] are the values with the step applied.
  /// Returns true when this step reached its goal.
  Future<bool> accept(GoalSuggestion s, GoalValues after, DateTime now) async {
    final g = order.where((g) => g.lever == s.lever).firstOrNull;
    final reached = !s.back && g != null && goalReached(g, after);
    await logStep(
      GoalStep(
        now,
        s.lever,
        s.from,
        s.to,
        kind: s.back ? GoalStepKind.back : GoalStepKind.step,
        reached: reached,
      ),
    );
    return reached;
  }

  /// Once: existing users get today's built-in behaviour as goals (new
  /// characters, then character spacing 3, then word spacing 7; no tempo
  /// goal) and a "new" notice; new users get no goals and the tip.
  static Future<void> migrateIfNeeded(SharedPreferences p) async {
    if ((p.getInt(_versionKey) ?? 0) >= 1) return;
    final existing =
        p.containsKey('adaptiveBlockEma') ||
        p.containsKey('echoBlockEma') ||
        p.containsKey('profile.hear.wpm') ||
        p.containsKey('profile.echo.wpm');
    if (existing) {
      for (final kind in ['hear', 'echo']) {
        if (p.containsKey('goals.$kind.order')) continue;
        final ic = p.getInt('profile.$kind.interCharSpace');
        final iw = p.getInt('profile.$kind.interWordSpace');
        final goals = [
          for (final l in leversOf(kind))
            switch (l) {
              GoalLever.newChars => LeverGoal(
                l,
                target: 0,
                start: p.getInt('profile.$kind.kochLevel'),
              ),
              GoalLever.charSpacing => LeverGoal(l, target: 3, start: ic),
              GoalLever.wordSpacing => LeverGoal(l, target: 7, start: iw),
              _ => LeverGoal(l),
            },
        ];
        await GoalStore(p, kind).setOrder(goals);
      }
    }
    await p.setInt(homeCardKey, existing ? 2 : 1);
    await p.setInt(_versionKey, 1);
  }
}
