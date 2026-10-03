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

  group('spaced sessions (#33)', () {
    PracticeSession sess(int h, int m, int minutes) {
      final st = DateTime(2026, 10, 7, h, m);
      return PracticeSession(st.millisecondsSinceEpoch, 'hear', minutes * 60);
    }

    final spaced = DailyGoalSettings(minutes: 10, grace: true, sessions: 3);

    test('too short or too close sessions do not count', () {
      final c = countedSessions([
        sess(8, 0, 6), // counts, ends 08:06
        sess(8, 10, 6), // only 4 min after the end: no
        sess(8, 21, 4), // far enough but under 5 min: no
        sess(8, 21, 5), // counts (15 min after 08:06)
      ]);
      expect(c.length, 2);
    });

    test('pauses inside a session move its end', () {
      final a = sess(8, 0, 6)..end = DateTime(2026, 10, 7, 8, 12).millisecondsSinceEpoch;
      // 08:20 is 20 min after the real start-based end, but only 8 after 08:12.
      expect(countedSessions([a, sess(8, 20, 6)]).length, 1);
    });

    test('goal needs time and sessions; next one is announced', () {
      final l = PracticeLog();
      l.days['2026-10-07'] = PracticeDay()..seconds = 12 * 60;
      l.sessions.addAll([sess(8, 0, 6), sess(8, 40, 6)]);
      var g = goalStatus(l, spaced, DateTime(2026, 10, 7, 8, 50));
      expect(g.sessionsDone, 2);
      expect(g.met, isFalse);
      expect(g.nextIn, const Duration(minutes: 11));
      expect(g.progress, closeTo(2 / 3, 1e-9));
      l.sessions.add(sess(9, 10, 5));
      g = goalStatus(l, spaced, DateTime(2026, 10, 7, 9, 20));
      expect(g.met, isTrue);
      expect(g.nextIn, isNull);
    });

    test('off: sessions are ignored', () {
      final l = PracticeLog();
      l.days['2026-10-07'] = PracticeDay()..seconds = 600;
      final g = goalStatus(l, s, DateTime(2026, 10, 7, 12));
      expect(g.met, isTrue);
      expect(g.nextIn, isNull);
    });

    test('a past day without enough sessions breaks the streak', () {
      final l = PracticeLog();
      l.days['2026-10-06'] = PracticeDay()..seconds = 900;
      l.sessions.add(PracticeSession(
          DateTime(2026, 10, 6, 9).millisecondsSinceEpoch, 'hear', 900));
      final g = goalStatus(l, DailyGoalSettings(minutes: 10, grace: false, sessions: 3),
          DateTime(2026, 10, 7, 12));
      expect(g.streak, 0);
    });
  });
}
