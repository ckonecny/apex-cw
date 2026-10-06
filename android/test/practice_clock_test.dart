import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/content/practice_log.dart';
import 'package:next_cw_trainer/util/practice_clock.dart';

void main() {
  late DateTime t;
  late PracticeClock clock;

  Future<void> setUpClock([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    t = DateTime(2026, 10, 5, 18, 0, 0);
    clock = PracticeClock(now: () => t, autoTick: false);
    await clock.initForTest(await SharedPreferences.getInstance());
  }

  // Runs the clock for [secs] one-second steps, touching every [touchEvery].
  void run(int secs, {int touchEvery = 5}) {
    for (var i = 0; i < secs; i++) {
      t = t.add(const Duration(seconds: 1));
      if (i % touchEvery == 0) clock.touch();
      clock.tick();
    }
  }

  test('credits active time in a session', () async {
    await setUpClock();
    clock.enter('hear');
    run(60);
    clock.leave();
    final day = clock.log.dayOf('2026-10-05');
    expect(day.seconds, 60);
    expect(day.sessions, 1);
    expect(clock.log.sessions.single.mode, 'hear');
    expect(clock.log.sessions.single.seconds, 60);
    expect(day.modes, {'hear': 60});
  });

  test('time is booked per mode and survives JSON', () async {
    await setUpClock();
    clock.enter('hear');
    run(30);
    clock.leave();
    clock.enter('echo');
    run(20);
    clock.leave();
    final day = clock.log.dayOf('2026-10-05');
    expect(day.seconds, 50);
    expect(day.modes, {'hear': 30, 'echo': 20});
    expect(PracticeDay.fromJson(day.toJson()).modes, {'hear': 30, 'echo': 20});
  });

  test('idle time does not count, activity resumes it', () async {
    await setUpClock();
    clock.enter('echo');
    run(10, touchEvery: 100); // one touch at start
    // 60 s with no touch: only the 20 s after the last touch count.
    for (var i = 0; i < 60; i++) { t = t.add(const Duration(seconds: 1)); clock.tick(); }
    final secs = clock.log.dayOf('2026-10-05').seconds;
    expect(secs, inInclusiveRange(20, 22)); // idleCap 20 s after the last touch
    clock.touch();
    run(5);
    expect(clock.log.dayOf('2026-10-05').seconds, greaterThan(secs));
  });

  test('audio playing counts without touches', () async {
    await setUpClock();
    clock.enter('hear');
    clock.audioPlaying = true;
    for (var i = 0; i < 90; i++) { t = t.add(const Duration(seconds: 1)); clock.tick(); }
    expect(clock.log.dayOf('2026-10-05').seconds, 90);
  });

  test('no time outside a training screen or while disabled', () async {
    await setUpClock();
    run(30);
    expect(clock.log.days, isEmpty);
    clock.log.enabled = false;
    clock.enter('hear');
    run(30);
    expect(clock.log.days, isEmpty);
  });

  test('a stalled timer does not credit the gap', () async {
    await setUpClock();
    clock.enter('hear');
    clock.audioPlaying = true;
    clock.tick();
    t = t.add(const Duration(minutes: 10)); // device asleep
    clock.tick();
    expect(clock.log.dayOf('2026-10-05').seconds, lessThanOrEqualTo(2));
  });

  test('five minutes without credit starts a new session; long sessions count', () async {
    await setUpClock();
    clock.enter('hear');
    clock.audioPlaying = true;
    for (var i = 0; i < 310; i++) { t = t.add(const Duration(seconds: 1)); clock.tick(); }
    clock.audioPlaying = false;
    t = t.add(const Duration(minutes: 6));
    clock.tick();
    clock.audioPlaying = true;
    for (var i = 0; i < 20; i++) { t = t.add(const Duration(seconds: 1)); clock.tick(); }
    final day = clock.log.dayOf('2026-10-05');
    expect(day.sessions, 2);
    expect(day.longSessions, 1);
    expect(clock.log.sessions.length, 2);
    expect(clock.log.sessions.first.seconds, inInclusiveRange(309, 311));
  });

  test('day rolls over at 04:00', () async {
    await setUpClock();
    t = DateTime(2026, 10, 6, 1, 0, 0); // 01:00 still belongs to the 5th
    clock.enter('hear');
    clock.audioPlaying = true;
    for (var i = 0; i < 10; i++) { t = t.add(const Duration(seconds: 1)); clock.tick(); }
    expect(clock.log.dayOf('2026-10-05').seconds, 10);
    expect(clock.log.dayOf('2026-10-06').seconds, 0);
    expect(practiceDayKey(DateTime(2026, 10, 6, 4, 0)), '2026-10-06');
  });

  test('log survives save and load', () async {
    await setUpClock();
    clock.enter('hear');
    run(40);
    clock.milestone(MilestoneKind.kochHear, 12);
    clock.leave();
    await clock.flush();
    final p = await SharedPreferences.getInstance();
    final again = PracticeLog();
    await again.load(p);
    expect(again.dayOf('2026-10-05').seconds, 40);
    expect(again.sessions.single.mode, 'hear');
    expect(again.milestones.single.value, 12);
  });

  test('milestones: no duplicates, records only if higher, nothing when off', () async {
    await setUpClock();
    clock.milestone(MilestoneKind.kochHear, 5);
    clock.milestone(MilestoneKind.kochHear, 5);
    clock.milestone(MilestoneKind.wpmHear, 20, onlyIfHigher: true);
    clock.milestone(MilestoneKind.wpmHear, 18, onlyIfHigher: true);
    clock.milestone(MilestoneKind.wpmHear, 22, onlyIfHigher: true);
    expect(clock.log.milestones.map((m) => '${m.kind}=${m.value}'),
        ['koch.hear=5', 'wpm.hear=20', 'wpm.hear=22']);
    clock.log.enabled = false;
    clock.milestone(MilestoneKind.kochHear, 6);
    expect(clock.log.milestones.length, 3);
  });

  test('enabled flag defaults on and is kept when data is reset', () async {
    await setUpClock({'practice.enabled': false});
    expect(clock.log.enabled, isFalse);
    final p = await SharedPreferences.getInstance();
    await clock.log.reset(p);
    expect(p.getBool('practice.enabled'), isFalse);
  });
}
