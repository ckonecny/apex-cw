import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/daily_goal.dart';
import 'package:next_cw_trainer/content/practice_log.dart';

void main() {
  // Wed 2026-10-07, 12:00. Week: Mon 10-05 … Sun 10-11.
  final now = DateTime(2026, 10, 7, 12);
  PracticeLog logWith(Map<String, int> minutes) {
    final l = PracticeLog();
    minutes.forEach((k, m) => l.days[k] = PracticeDay()..seconds = m * 60);
    return l;
  }

  final s = DailyGoalSettings(minutes: 10, grace: true);

  test('empty log: no streak, nothing met', () {
    final g = goalStatus(PracticeLog(), s, now);
    expect(g.streak, 0);
    expect(g.met, isFalse);
    expect(g.todayIndex, 2);
    expect(g.week[2], DotState.today);
    expect(g.week[3], DotState.future);
  });

  test('open today does not break, met today adds one', () {
    final l = logWith({'2026-10-05': 10, '2026-10-06': 12, '2026-10-07': 4});
    var g = goalStatus(l, s, now);
    expect(g.streak, 2);
    expect(g.progress, closeTo(0.4, 1e-9));
    expect(g.minutesLeft, 6);
    l.days['2026-10-07']!.seconds = 600;
    g = goalStatus(l, s, now);
    expect(g.streak, 3);
    expect(g.week[2], DotState.todayMet);
  });

  test('one grace day per week bridges a single miss', () {
    // Mon met, Tue missed (grace), Wed (today) met.
    final l = logWith({'2026-10-05': 10, '2026-10-07': 10});
    final g = goalStatus(l, s, now);
    expect(g.streak, 2);
    expect(g.week[1], DotState.frozen);
  });

  test('second miss in the same week breaks the streak', () {
    // Last week fully met; Mon and Tue missed, today met.
    final l = logWith({
      '2026-10-02': 10, '2026-10-03': 10, '2026-10-04': 10, '2026-10-07': 10
    });
    final g = goalStatus(l, s, now);
    expect(g.streak, 1);
    expect(g.week[0], DotState.missed);
  });

  test('without grace one miss breaks it', () {
    final l = logWith({'2026-10-05': 10, '2026-10-07': 10});
    final g = goalStatus(l, DailyGoalSettings(minutes: 10, grace: false), now);
    expect(g.streak, 1);
    expect(g.week[1], DotState.missed);
  });

  test('a grace day before the first practice day is not bridged', () {
    final l = logWith({'2026-10-06': 10});
    final g = goalStatus(l, s, now);
    expect(g.streak, 1);
  });

  test('week minutes and 04:00 day rollover', () {
    final l = logWith({'2026-10-05': 10, '2026-10-06': 5});
    final g = goalStatus(l, s, DateTime(2026, 10, 7, 3, 30));
    // 03:30 still belongs to Tue 10-06.
    expect(g.todayIndex, 1);
    expect(g.todaySeconds, 300);
    expect(g.weekSeconds, 900);
  });
}
