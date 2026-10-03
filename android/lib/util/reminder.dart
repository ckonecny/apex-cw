import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/daily_goal.dart';
import '../content/practice_log.dart';
import '../l10n/strings.dart';
import 'practice_clock.dart';

/// Fire times for the next [days] days at [minutes] past midnight, all after
/// [now]. Today's is skipped when the goal of today's practice day is already
/// met (issue #32: only remind while the goal is open).
List<DateTime> reminderTimes(DateTime now, int minutes, bool goalMet, {int days = 7}) {
  final out = <DateTime>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(now.year, now.month, now.day + i, minutes ~/ 60, minutes % 60);
    if (!day.isAfter(now)) continue;
    if (goalMet && dayKeyOf(day) == practiceDayKey(now)) continue;
    out.add(day);
  }
  return out;
}

String dayKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Optional daily reminder (docs/DECISIONS.md "Reminder"). Off by default.
/// Scheduled locally by native code (Reminder.kt); nothing leaves the device.
class Reminder {
  static const onKey = 'reminder.on';
  static const minutesKey = 'reminder.minutes';
  static const defaultMinutes = 19 * 60;
  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/reminder');

  static Future<bool> isOn() async =>
      (await SharedPreferences.getInstance()).getBool(onKey) ?? false;

  static Future<int> minutes() async =>
      ((await SharedPreferences.getInstance()).getInt(minutesKey) ?? defaultMinutes)
          .clamp(0, 24 * 60 - 1);

  /// Turns the reminder on or off. Turning on asks for the notification
  /// permission; returns the resulting state (false if it was refused).
  static Future<bool> setOn(bool on) async {
    final p = await SharedPreferences.getInstance();
    if (on) {
      try {
        if (await _channel.invokeMethod<bool>('requestPermission') != true) {
          await p.setBool(onKey, false);
          return false;
        }
      } on MissingPluginException {
        return false;
      }
    }
    await p.setBool(onKey, on);
    await refresh();
    return on;
  }

  static Future<void> setMinutes(int m) async {
    await (await SharedPreferences.getInstance()).setInt(minutesKey, m);
    await refresh();
  }

  /// Re-plans the next reminders from the current goal state. Call at start,
  /// when a training ends or the app goes to the background, and after any
  /// change of the reminder or goal settings.
  static Future<void> refresh() async {
    try {
      final p = await SharedPreferences.getInstance();
      final log = PracticeClock.instance.log;
      if (!(p.getBool(onKey) ?? false) || !log.enabled) {
        await _channel.invokeMethod('cancel');
        return;
      }
      final now = DateTime.now();
      final goal = await DailyGoalSettings.load(p);
      final met = goalStatus(log, goal, now).met;
      final times = reminderTimes(now, await minutes(), met);
      await _channel.invokeMethod('schedule', {
        'times': [for (final t in times) t.millisecondsSinceEpoch],
        'title': Strings.t('reminder_title'),
        'body': Strings.t('reminder_body').replaceFirst('{n}', '${goal.minutes}'),
        'channel': Strings.t('reminder_channel'),
      });
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }
}
