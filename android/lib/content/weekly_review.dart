// Weekly review (issue #35, docs/DECISIONS.md "Weekly review"): the figures of
// one Mon–Sun week next to the week before, worked out from the practice log.
import 'achievements.dart';
import 'practice_log.dart';

class WeeklyReview {
  /// Monday (practiceDayKey format) of the reviewed week.
  final String week;

  /// The week is still running (it is Sunday), otherwise it is the last one.
  final bool current;
  final int seconds, prevSeconds;
  final int days; // practice days with any credited time
  final int newCharacters;

  /// Mean error rate 0..1 over the week's blocks; null below [kReviewBlocks].
  final double? errors, prevErrors;

  const WeeklyReview(this.week, this.current, this.seconds, this.prevSeconds, this.days,
      this.newCharacters, this.errors, this.prevErrors);

  /// Nothing to show for a week without any practice.
  bool get empty => seconds == 0 && errors == null && newCharacters == 0;
}

/// Blocks a week needs before its error rate is shown.
const kReviewBlocks = 3;

/// The review on Sunday covers the running week, on every other day the last
/// one that ended.
WeeklyReview weeklyReview(PracticeLog log, DateTime now) {
  final today = practiceDayKey(now);
  final thisWeek = weekOfDayKey(today);
  final sunday = DateTime.utc(int.parse(today.substring(0, 4)), int.parse(today.substring(5, 7)),
          int.parse(today.substring(8, 10))).weekday == DateTime.sunday;
  final week = sunday ? thisWeek : previousWeekKey(thisWeek);
  final before = previousWeekKey(week);

  int seconds(String w) => log.days.entries
      .where((e) => weekOfDayKey(e.key) == w)
      .fold(0, (a, e) => a + e.value.seconds);
  double? errors(String w) {
    final b = log.blocks.where((b) => weekOfDayKey(b.day) == w).toList();
    return b.length < kReviewBlocks ? null : b.fold(0.0, (a, x) => a + x.errors) / b.length;
  }

  // Characters unlocked: the training that went furthest counts.
  final levels = <String, Set<int>>{};
  for (final m in log.milestones) {
    if ((m.kind == MilestoneKind.kochHear || m.kind == MilestoneKind.kochEcho) &&
        weekOfDayKey(m.day) == week) {
      levels.putIfAbsent(m.kind, () => {}).add(m.value);
    }
  }
  final chars = levels.values.fold<int>(0, (a, s) => s.length > a ? s.length : a);
  final days = log.days.entries
      .where((e) => e.value.seconds > 0 && weekOfDayKey(e.key) == week)
      .length;
  return WeeklyReview(week, sunday, seconds(week), seconds(before), days, chars,
      errors(week), errors(before));
}
