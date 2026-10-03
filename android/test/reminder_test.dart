import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/util/reminder.dart';

void main() {
  final evening = DateTime(2026, 10, 7, 12); // Wed noon
  const at19 = 19 * 60;

  test('seven days from today when the goal is open', () {
    final t = reminderTimes(evening, at19, false);
    expect(t.length, 7);
    expect(t.first, DateTime(2026, 10, 7, 19));
    expect(t.last, DateTime(2026, 10, 13, 19));
  });

  test("today is skipped when today's goal is met", () {
    final t = reminderTimes(evening, at19, true);
    expect(t.length, 6);
    expect(t.first, DateTime(2026, 10, 8, 19));
  });

  test('a time already passed today is not scheduled', () {
    final t = reminderTimes(DateTime(2026, 10, 7, 20), at19, false);
    expect(t.first, DateTime(2026, 10, 8, 19));
  });

  test('after midnight the practice day is still yesterday', () {
    // 01:00 on Thu belongs to Wed's practice day: Wed's goal met must not
    // suppress Thursday 07:00.
    final t = reminderTimes(DateTime(2026, 10, 8, 1), 7 * 60, true);
    expect(t.first, DateTime(2026, 10, 8, 7));
  });
}
