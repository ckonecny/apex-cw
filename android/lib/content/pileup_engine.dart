// Game rules of Fight the Pileup, ported from the single-player part of
// MorsePileup.cpp: call signs queue up, the oldest one is "active" and plays
// in CW, you key it back. Pure Dart with an explicit clock (milliseconds) and
// an injectable call source, so every rule is unit-testable.
//
// Rules (firmware numbers):
//  * 3 lives; every `dropsPerLife` dropped callers cost one life.
//  * A caller is dropped when its defend window (`callerTimeout`, counted
//    from activation) runs out, or when it waits in the queue for the same
//    time without being served ("MISSED").
//  * Correct call: 100 + 10 x streak points, then the pileup pauses and you
//    key one earned "attack" call (+50, no time pressure). Wrong: streak 0.
//  * Timeout: -25 points (never below 0).
import 'dart:math';

const pileupMaxCallers = 6;
const pileupStartLives = 3;
const _scoreCorrect = 100;
const _scoreStreakBonus = 10;
const _scoreTimeout = -25;
const _scoreAttack = 50;

class PileupDifficulty {
  final String label;
  final int callerTimeout, spawnMax, spawnMin, initialCallers, dropsPerLife, playsBeforeReveal;
  const PileupDifficulty(this.label, this.callerTimeout, this.spawnMax, this.spawnMin,
      this.initialCallers, this.dropsPerLife, this.playsBeforeReveal);
}

const pileupDifficulties = [
  PileupDifficulty('EASY', 45000, 12000, 5000, 1, 5, 3),
  PileupDifficulty('NORMAL', 30000, 8000, 3000, 1, 4, 3),
  PileupDifficulty('HARD', 20000, 5000, 2000, 2, 3, 2),
  PileupDifficulty('EXPERT', 12000, 3500, 1500, 3, 2, 1),
];

class PileupCaller {
  final String call;
  int activeSince;     // defend-window start (set when it becomes active)
  int queuedSince;     // arrival, shifted forward by the attack pauses
  PileupCaller(this.call, this.activeSince, this.queuedSince);
}

/// What a tick or a submit produced, for sound and the flash text.
enum PileupEvent { none, correct, wrong, timeout, missed, lifeLost, attackSent, tryAgain, over }

class PileupEngine {
  final String Function() _nextCall;
  PileupDifficulty difficulty;

  PileupEngine(this._nextCall, {this.difficulty = const PileupDifficulty('EASY', 45000, 12000, 5000, 1, 5, 3)});

  final List<PileupCaller> callers = [];
  PileupCaller? current;

  int lives = pileupStartLives;
  int score = 0;
  int streak = 0, bestStreak = 0;
  int blocked = 0, dropped = 0, attacksSent = 0;
  int _eliminations = 0;
  int _lastSpawn = 0;
  int _spawnInterval = 0;

  bool attackMode = false;
  String attackPrompt = '';
  int _attackModeStart = 0;

  /// Points awarded by the last correct defend (for the "+N" flash).
  int lastBonus = 0;

  bool get over => lives <= 0;

  void start(int now) {
    callers.clear();
    current = null;
    lives = pileupStartLives;
    score = 0;
    streak = bestStreak = 0;
    blocked = dropped = attacksSent = 0;
    _eliminations = 0;
    attackMode = false;
    attackPrompt = '';
    _spawnInterval = difficulty.spawnMax;
    for (var i = 0; i < difficulty.initialCallers && i < pileupMaxCallers; i++) {
      _spawn(now);
    }
    _lastSpawn = now;
  }

  void _addScore(int points) => score = max(0, score + points);

  void _spawn(int now) {
    if (callers.length >= pileupMaxCallers) return;
    var call = _nextCall().toUpperCase();
    for (var retry = 0; retry < 5 && callers.any((c) => c.call == call); retry++) {
      call = _nextCall().toUpperCase();
    }
    callers.add(PileupCaller(call, now, now));
    _lastSpawn = now;
  }

  /// Advances the clock. [typing]: a response is being keyed, so the active
  /// caller must not time out under the player's fingers. Returns the events
  /// in the order they happened.
  List<PileupEvent> tick(int now, {required bool typing}) {
    final ev = <PileupEvent>[];
    if (over) return ev;

    if (attackMode) {
      if (attackPrompt.isEmpty) attackPrompt = _nextCall().toUpperCase();
      return ev;   // no spawning, no timeouts while the earned attack is up
    }

    if (callers.length < pileupMaxCallers && now - _lastSpawn > _spawnInterval) {
      _spawn(now);
    }

    // One caller at a time; it gets its full window from activation.
    if (current == null && callers.isNotEmpty) {
      current = callers.reduce((a, b) => a.activeSince <= b.activeSince ? a : b);
      current!.activeSince = now;
    }

    final cur = current;
    if (cur != null && !typing && now - cur.activeSince > difficulty.callerTimeout) {
      callers.remove(cur);
      current = null;
      dropped++;
      streak = 0;
      _addScore(_scoreTimeout);
      ev.add(PileupEvent.timeout);
    }

    // Backlog give-up: a queued caller (not the active one) loses patience.
    for (final c in callers) {
      if (identical(c, current)) continue;
      if (now - c.queuedSince > difficulty.callerTimeout) {
        callers.remove(c);
        dropped++;
        ev.add(PileupEvent.missed);
        break;   // at most one per tick, as the firmware
      }
    }

    final threshold = dropped ~/ difficulty.dropsPerLife;
    if (threshold > _eliminations) {
      _eliminations = threshold;
      if (lives > 0) {
        lives--;
        ev.add(PileupEvent.lifeLost);
      }
    }
    if (over) ev.add(PileupEvent.over);
    return ev;
  }

  /// A keyed response is submitted. Defends the active caller, or answers the
  /// earned attack prompt.
  PileupEvent submit(String input, int now) {
    if (over || input.isEmpty) return PileupEvent.none;
    final typed = input.toUpperCase();

    if (attackMode) {
      if (attackPrompt.isEmpty) return PileupEvent.none;
      if (typed != attackPrompt) return PileupEvent.tryAgain;
      attacksSent++;
      _addScore(_scoreAttack);
      attackPrompt = '';
      attackMode = false;
      final paused = now - _attackModeStart;      // callers did not age meanwhile
      for (final c in callers) {
        c.queuedSince += paused;
      }
      _lastSpawn = now;
      return PileupEvent.attackSent;
    }

    final cur = current;
    if (cur == null) return PileupEvent.none;
    if (typed != cur.call) {
      streak = 0;
      return PileupEvent.wrong;
    }
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    lastBonus = _scoreCorrect + streak * _scoreStreakBonus;
    _addScore(lastBonus);
    blocked++;
    callers.remove(cur);
    current = null;
    final range = difficulty.spawnMax - difficulty.spawnMin;
    _spawnInterval = difficulty.spawnMax - min(streak, 20) * range ~/ 20;
    attackMode = true;
    _attackModeStart = now;
    attackPrompt = '';
    return PileupEvent.correct;
  }

  /// Share of callers defended, in percent.
  int get accuracy {
    final total = blocked + dropped;
    return total > 0 ? blocked * 100 ~/ total : 0;
  }
}
