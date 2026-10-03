// Daily goal and streak (issue #31, docs/DECISIONS.md "Daily goal and streak").
// Pure Dart on top of the practice log (#30): the goal settings and the
// figures the home card and the goal screen show.
import 'package:shared_preferences/shared_preferences.dart';
import 'practice_log.dart';

const kGoalChoices = [5, 10, 15, 20, 30, 60];
const kDefaultGoalMinutes = 10;

class DailyGoalSettings {
  static const minutesKey = 'goal.minutes';
  static const graceKey = 'goal.grace';

  int minutes;

  /// One missed day per calendar week (Mon–Sun) does not break the streak.
  bool grace;

  DailyGoalSettings({this.minutes = kDefaultGoalMinutes, this.grace = true});

  static Future<DailyGoalSettings> load(SharedPreferences p) async => DailyGoalSettings(
      minutes: kGoalChoices.contains(p.getInt(minutesKey))
          ? p.getInt(minutesKey)!
          : kDefaultGoalMinutes,
      grace: p.getBool(graceKey) ?? true);

  Future<void> save(SharedPreferences p) async {
    await p.setInt(minutesKey, minutes);
    await p.setBool(graceKey, grace);
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

  const GoalStatus(this.todaySeconds, this.goalSeconds, this.streak, this.week,
      this.todayIndex, this.weekSeconds);

  bool get met => todaySeconds >= goalSeconds;
  double get progress => (todaySeconds / goalSeconds).clamp(0.0, 1.0);
  int get minutesToday => todaySeconds ~/ 60;
  int get minutesLeft => ((goalSeconds - todaySeconds) / 60).ceil().clamp(0, 9999);
}

DateTime _dateOf(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _keyOf(DateTime utcDate) => '${utcDate.year.toString().padLeft(4, '0')}-'
    '${utcDate.month.toString().padLeft(2, '0')}-${utcDate.day.toString().padLeft(2, '0')}';

DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

/// Today's status. Today never breaks the streak while it is still open; it
/// adds one once the goal is met. Walking back, a missed day is bridged by the
/// grace day (once per Mon–Sun week) only if an older goal day follows it.
GoalStatus goalStatus(PracticeLog log, DailyGoalSettings s, DateTime now) {
  final todayKey = practiceDayKey(now);
  final today = _dateOf(todayKey);
  final goal = s.seconds;
  bool met(DateTime d) => log.dayOf(_keyOf(d)).seconds >= goal;

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
  return GoalStatus(log.dayOf(todayKey).seconds, goal, streak, week, todayIndex, weekSeconds);
}
