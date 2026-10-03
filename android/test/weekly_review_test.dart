import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/practice_log.dart';
import 'package:next_cw_trainer/content/weekly_review.dart';

void main() {
  PracticeLog log() {
    final l = PracticeLog();
    // Week Mon 09-28 … Sun 10-04: 20 min on 2 days; the week before: 10 min.
    l.days['2026-09-28'] = PracticeDay()..seconds = 600;
    l.days['2026-10-02'] = PracticeDay()..seconds = 600;
    l.days['2026-09-21'] = PracticeDay()..seconds = 600;
    l.milestones.addAll(const [
      Milestone('2026-09-29', MilestoneKind.kochHear, 7),
      Milestone('2026-10-01', MilestoneKind.kochHear, 8),
      Milestone('2026-10-01', MilestoneKind.kochEcho, 6),
    ]);
    for (final d in ['2026-09-28', '2026-09-30', '2026-10-02']) {
      l.blocks.add(BlockRecord(d, 'hear', 940, false));
    }
    for (final d in ['2026-09-21', '2026-09-22', '2026-09-23']) {
      l.blocks.add(BlockRecord(d, 'hear', 900, false));
    }
    return l;
  }

  test('on a weekday the last finished week is reviewed', () {
    final r = weeklyReview(log(), DateTime(2026, 10, 7, 12)); // Wed
    expect(r.current, isFalse);
    expect(r.week, '2026-09-28');
    expect(r.seconds, 1200);
    expect(r.prevSeconds, 600);
    expect(r.days, 2);
    expect(r.newCharacters, 2);
    expect(r.errors, closeTo(0.06, 1e-9));
    expect(r.prevErrors, closeTo(0.10, 1e-9));
  });

  test('on Sunday the running week is reviewed', () {
    final r = weeklyReview(log(), DateTime(2026, 10, 4, 12));
    expect(r.current, isTrue);
    expect(r.week, '2026-09-28');
  });

  test('few blocks give no error rate; an empty week is empty', () {
    final l = PracticeLog()..blocks.add(const BlockRecord('2026-09-29', 'hear', 900, false));
    final r = weeklyReview(l, DateTime(2026, 10, 7, 12));
    expect(r.errors, isNull);
    expect(weeklyReview(PracticeLog(), DateTime(2026, 10, 7, 12)).empty, isTrue);
  });
}
