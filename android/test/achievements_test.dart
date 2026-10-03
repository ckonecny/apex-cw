import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/achievements.dart';
import 'package:next_cw_trainer/content/practice_log.dart';

void main() {
  String? earned(PracticeLog l, String id) =>
      achievements(l).firstWhere((a) => a.id == id).earned;

  test('empty log: everything locked, all ids listed', () {
    final a = achievements(PracticeLog());
    expect(a.length, AchievementId.all.length);
    expect(a.any((x) => x.unlocked), isFalse);
  });

  test('new characters: first, three in a week, four weeks in a row', () {
    final l = PracticeLog();
    // Weeks: Mon 2026-09-14, 09-21, 09-28, 10-05.
    l.milestones.addAll(const [
      Milestone('2026-09-15', MilestoneKind.kochHear, 6),
      Milestone('2026-09-22', MilestoneKind.kochHear, 7),
      Milestone('2026-09-29', MilestoneKind.kochHear, 8),
      Milestone('2026-10-06', MilestoneKind.kochHear, 9),
    ]);
    expect(earned(l, AchievementId.charFirst), '2026-09-15');
    expect(earned(l, AchievementId.charStreak), '2026-10-06');
    expect(earned(l, AchievementId.char3Week), isNull);
    l.milestones.addAll(const [
      Milestone('2026-10-07', MilestoneKind.kochHear, 10),
      Milestone('2026-10-08', MilestoneKind.kochHear, 11),
    ]);
    expect(earned(l, AchievementId.char3Week), '2026-10-08');
  });

  test('a skipped week breaks the weekly series', () {
    final l = PracticeLog();
    l.milestones.addAll(const [
      Milestone('2026-09-15', MilestoneKind.kochHear, 6),
      Milestone('2026-09-22', MilestoneKind.kochHear, 7),
      Milestone('2026-10-06', MilestoneKind.kochHear, 8),
      Milestone('2026-10-13', MilestoneKind.kochHear, 9),
    ]);
    expect(earned(l, AchievementId.charStreak), isNull);
  });

  test('blocks: under 5 % three times in a row, interference, better week', () {
    final l = PracticeLog();
    BlockRecord b(String day, int correct, {bool i = false}) => BlockRecord(day, 'hear', correct, i);
    l.blocks.addAll([
      b('2026-09-29', 900), b('2026-09-30', 920), b('2026-10-01', 940), // week 1: 8 % errors
      b('2026-10-06', 960), b('2026-10-07', 970), b('2026-10-08', 980, i: true), // week 2
    ]);
    expect(earned(l, AchievementId.errBetter), '2026-10-08');
    expect(earned(l, AchievementId.errUnder5), '2026-10-08');
    expect(earned(l, AchievementId.interUnder10), '2026-10-08');
    l.blocks.clear();
    l.blocks.addAll([b('2026-10-06', 960), b('2026-10-07', 900), b('2026-10-08', 960)]);
    expect(earned(l, AchievementId.errUnder5), isNull);
  });

  test('spread days, speed record and comeback', () {
    final l = PracticeLog();
    PracticeSession s(int d, int h) => PracticeSession(
        DateTime(2026, 10, d, h).millisecondsSinceEpoch, 'hear', 360);
    for (var d = 1; d <= 5; d++) {
      l.sessions.addAll([s(d, 8), s(d, 12), s(d, 18)]);
    }
    expect(earned(l, AchievementId.spreadDay), '2026-10-01');
    expect(earned(l, AchievementId.spreadDays), '2026-10-05');
    l.milestones.add(const Milestone('2026-10-03', MilestoneKind.wpmEcho, 18));
    expect(earned(l, AchievementId.speedRecord), '2026-10-03');
    l.days['2026-10-01'] = PracticeDay()..seconds = 60;
    l.days['2026-10-09'] = PracticeDay()..seconds = 60;
    expect(earned(l, AchievementId.comeback), '2026-10-09');
    l.days['2026-10-09'] = PracticeDay()..seconds = 0;
    l.days['2026-10-08'] = PracticeDay()..seconds = 60;
    expect(earned(l, AchievementId.comeback), isNull); // 7 days apart only
  });

  test('block records survive a save/load round trip', () async {
    final l = PracticeLog();
    l.blocks.add(const BlockRecord('2026-10-07', 'echo', 953, true));
    final b = PracticeLog()..blocks.addAll(l.blocks.map((x) => BlockRecord.fromJson(x.toJson())));
    expect(b.blocks.single.interference, isTrue);
    expect(b.blocks.single.errors, closeTo(0.047, 1e-9));
  });
}
