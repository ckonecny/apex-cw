// Daily goal and streak (issue #31, docs/DECISIONS.md "Daily goal and streak").
// Pure Dart on top of the practice log (#30): the goal settings and the
// figures the home card and the goal screen show.
import 'package:shared_preferences/shared_preferences.dart';
import 'practice_log.dart';

const kGoalChoices = [5, 10, 15, 20, 30, 60];
const kDefaultGoalMinutes = 10;

/// Spaced goal (#33): number of sessions per day (0 = off). Each session
/// credits at most goal / n of the daily goal; practice starting less than
/// [kSessionPause] after the end of the previous one belongs to that one.
const kSessionChoices = [3, 5];
const kSessionPause = Duration(minutes: 15);

class DailyGoalSettings {
  static const minutesKey = 'goal.minutes';
  static const graceKey = 'goal.grace';
  static const sessionsKey = 'goal.sessions';

  int minutes;

  /// 0 = plain daily total; 3 / 5 = the total must also be spread over that
  /// many spaced sessions.
  int sessions;

  /// One missed day per calendar week (Mon–Sun) does not break the streak.
  bool grace;

  DailyGoalSettings(
      {this.minutes = kDefaultGoalMinutes, this.grace = true, this.sessions = 0});

  static Future<DailyGoalSettings> load(SharedPreferences p) async => DailyGoalSettings(
      minutes: kGoalChoices.contains(p.getInt(minutesKey))
          ? p.getInt(minutesKey)!
          : kDefaultGoalMinutes,
      grace: p.getBool(graceKey) ?? true,
      sessions: kSessionChoices.contains(p.getInt(sessionsKey)) ? p.getInt(sessionsKey)! : 0);

  Future<void> save(SharedPreferences p) async {
    await p.setInt(minutesKey, minutes);
    await p.setBool(graceKey, grace);
    await p.setInt(sessionsKey, sessions);
  }

  int get seconds => minutes * 60;
}

enum DotState { met, frozen, missed, today, todayMet, future }

class GoalStatus {
  final int todaySeconds;
  final int goalSeconds;
  final int streak;

  /// Monday … Sunday of the current week.
  final List<DotState> week;

  /// Index (0 = Monday) of today in [week].
  final int todayIndex;

  /// Practice seconds of the current week (Mon–Sun).
  final int weekSeconds;

  /// Spaced goal: sessions wanted (0 = off) and sessions that reached their
  /// share today.
  final int sessionsGoal;
  final int sessionsDone;

  /// Seconds that count towards the goal: all of today's practice, or with
  /// the spaced goal at most goal / n per session.
  final int creditSeconds;

  /// Spaced goal: time until practice counts again, while the current session
  /// has reached its share; null otherwise.
  final Duration? nextIn;

  const GoalStatus(this.todaySeconds, this.goalSeconds, this.streak, this.week,
      this.todayIndex, this.weekSeconds, this.creditSeconds,
      {this.sessionsGoal = 0, this.sessionsDone = 0, this.nextIn});

  bool get met => creditSeconds >= goalSeconds;
  double get progress => (creditSeconds / goalSeconds).clamp(0.0, 1.0);

  int get minutesToday => todaySeconds ~/ 60;
  int get creditMinutes => creditSeconds ~/ 60;
  int get minutesLeft => ((goalSeconds - creditSeconds) / 60).ceil().clamp(0, 9999);
}

DateTime _dateOf(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _keyOf(DateTime utcDate) => '${utcDate.year.toString().padLeft(4, '0')}-'
    '${utcDate.month.toString().padLeft(2, '0')}-${utcDate.day.toString().padLeft(2, '0')}';

/// The sessions of one day that count as "spread" for the achievement, oldest
/// first: at least [kLongSessionSeconds] long and starting at least
/// [kSessionPause] after the end of the previous counted one.
List<PracticeSession> countedSessions(Iterable<PracticeSession> day) {
  final list = day.toList()..sort((a, b) => a.start.compareTo(b.start));
  final out = <PracticeSession>[];
  for (final s in list) {
    if (s.seconds < kLongSessionSeconds) continue;
    if (out.isNotEmpty && s.startTime.isBefore(out.last.endTime.add(kSessionPause))) continue;
    out.add(s);
  }
  return out;
}

/// One slot of the spaced goal: sessions that start less than [kSessionPause]
/// after the end of the previous one are merged.
class SpreadSlot {
  int seconds;
  DateTime end;
  SpreadSlot(this.seconds, this.end);
}

List<SpreadSlot> spreadSlots(Iterable<PracticeSession> day) {
  final list = day.toList()..sort((a, b) => a.start.compareTo(b.start));
  final out = <SpreadSlot>[];
  for (final s in list) {
    if (out.isNotEmpty && s.startTime.isBefore(out.last.end.add(kSessionPause))) {
      out.last.seconds += s.seconds;
      if (s.endTime.isAfter(out.last.end)) out.last.end = s.endTime;
    } else {
      out.add(SpreadSlot(s.seconds, s.endTime));
    }
  }
  return out;
}

/// Seconds of [day] that count for the spaced goal: each slot credits at most
/// goal / [n]; the sum is capped at the goal.
int spreadCredit(Iterable<PracticeSession> day, int goalSeconds, int n) {
  final cap = goalSeconds ~/ n;
  var sum = 0;
  for (final slot in spreadSlots(day)) {
    sum += slot.seconds < cap ? slot.seconds : cap;
  }
  return sum < goalSeconds ? sum : goalSeconds;
}

DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

/// Today's status. Today never breaks the streak while it is still open; it
/// adds one once the goal is met. Walking back, a missed day is bridged by the
/// grace day (once per Mon–Sun week) only if an older goal day follows it.
GoalStatus goalStatus(PracticeLog log, DailyGoalSettings s, DateTime now) {
  final todayKey = practiceDayKey(now);
  final today = _dateOf(todayKey);
  final goal = s.seconds;
  final byDay = <String, List<PracticeSession>>{};
  if (s.sessions > 0) {
    for (final x in log.sessions) {
      byDay.putIfAbsent(practiceDayKey(x.startTime), () => []).add(x);
    }
  }
  // A day without session entries (dropped from the log) counts by time alone.
  int credit(String k) => s.sessions == 0 || !byDay.containsKey(k)
      ? log.dayOf(k).seconds
      : spreadCredit(byDay[k]!, goal, s.sessions);
  bool met(DateTime d) => credit(_keyOf(d)) >= goal;

  final earliest = log.days.keys.isEmpty ? todayKey : (log.days.keys.toList()..sort()).first;
  var streak = 0;
  final frozen = <String>{};
  if (met(today)) streak++;
  final usedWeeks = <String>{};
  final pending = <String>[];
  var d = today.subtract(const Duration(days: 1));
  while (_keyOf(d).compareTo(earliest) >= 0) {
    if (met(d)) {
      streak++;
      frozen.addAll(pending);
      pending.clear();
    } else {
      final w = _keyOf(_mondayOf(d));
      if (s.grace && !usedWeeks.contains(w)) {
        usedWeeks.add(w);
        pending.add(_keyOf(d));
      } else {
        break;
      }
    }
    d = d.subtract(const Duration(days: 1));
  }

  final monday = _mondayOf(today);
  final todayIndex = today.weekday - 1;
  var weekSeconds = 0;
  final week = <DotState>[];
  for (var i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    final k = _keyOf(day);
    weekSeconds += log.dayOf(k).seconds;
    week.add(i > todayIndex
        ? DotState.future
        : i == todayIndex
            ? (met(day) ? DotState.todayMet : DotState.today)
            : met(day)
                ? DotState.met
                : frozen.contains(k)
                    ? DotState.frozen
                    : DotState.missed);
  }
  final slots = s.sessions == 0 ? <SpreadSlot>[] : spreadSlots(byDay[todayKey] ?? const []);
  final cap = s.sessions == 0 ? 0 : goal ~/ s.sessions;
  Duration? nextIn;
  if (slots.isNotEmpty && slots.last.seconds >= cap && credit(todayKey) < goal) {
    final due = slots.last.end.add(kSessionPause);
    if (due.isAfter(now)) nextIn = due.difference(now);
  }
  return GoalStatus(log.dayOf(todayKey).seconds, goal, streak, week, todayIndex, weekSeconds,
      credit(todayKey),
      sessionsGoal: s.sessions,
      sessionsDone: slots.where((x) => x.seconds >= cap).length,
      nextIn: nextIn);
}
