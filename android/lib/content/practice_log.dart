// Practice log (issue #30, docs/DECISIONS.md "Practice log"): how long the user
// really practises, in sessions, plus dated milestones. Foundation for the
// daily goal / streak (#31) and the achievements (#34). Pure Dart: models,
// JSON and storage; the clock that feeds it is util/practice_clock.dart.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'char_stats.dart' show dayKey;

/// A practice day rolls over at 04:00 local time, so practice after midnight
/// still counts for the evening before. (The per-character statistics keep
/// their plain calendar days; the two are never mixed in one figure.)
const kPracticeDayRolloverHour = 4;

String practiceDayKey(DateTime d) =>
    dayKey(d.subtract(const Duration(hours: kPracticeDayRolloverHour)));

/// A session counts as "long" from this many seconds on (spaced goal, #33).
/// The same figure is the minimum length of a session in the spaced goal.
const kLongSessionSeconds = 5 * 60;

/// Oldest sessions are dropped beyond this many.
const kKeepSessions = 300;

class PracticeDay {
  int seconds = 0;
  int sessions = 0; // sessions started this day
  int longSessions = 0; // of them (or earlier ones), reaching kLongSessionSeconds

  PracticeDay();

  PracticeDay.fromJson(Map<String, dynamic> j)
      : seconds = j['s'] as int? ?? 0,
        sessions = j['n'] as int? ?? 0,
        longSessions = j['l'] as int? ?? 0;

  Map<String, dynamic> toJson() => {'s': seconds, 'n': sessions, 'l': longSessions};
}

class PracticeSession {
  final int start; // epoch ms
  int seconds;
  final String mode;

  /// Epoch ms of the last credited step (0 = unknown: older entries, then
  /// start + seconds is used). Pauses inside a session make it later than that.
  int end;

  PracticeSession(this.start, this.mode, [this.seconds = 0]) : end = 0;

  PracticeSession.fromJson(Map<String, dynamic> j)
      : start = j['t'] as int? ?? 0,
        seconds = j['d'] as int? ?? 0,
        mode = j['m'] as String? ?? '',
        end = j['e'] as int? ?? 0;

  Map<String, dynamic> toJson() => {'t': start, 'd': seconds, 'm': mode, 'e': end};

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(start);
  DateTime get endTime => end > start
      ? DateTime.fromMillisecondsSinceEpoch(end)
      : startTime.add(Duration(seconds: seconds));
}

class Milestone {
  final String day; // practiceDayKey
  final String kind;
  final int value;

  const Milestone(this.day, this.kind, this.value);

  Milestone.fromJson(Map<String, dynamic> j)
      : day = j['d'] as String? ?? '',
        kind = j['k'] as String? ?? '',
        value = j['v'] as int? ?? 0;

  Map<String, dynamic> toJson() => {'d': day, 'k': kind, 'v': value};
}

/// Milestone kinds (`Milestone.kind`).
class MilestoneKind {
  /// Koch level reached (value = number of characters), per training.
  static const kochHear = 'koch.hear';
  static const kochEcho = 'koch.echo';

  /// New speed record in WPM, per training.
  static const wpmHear = 'wpm.hear';
  static const wpmEcho = 'wpm.echo';
}

class PracticeLog {
  static const enabledKey = 'practice.enabled';
  static const _daysKey = 'practice.days';
  static const _sessionsKey = 'practice.sessions';
  static const _milestonesKey = 'practice.milestones';

  /// Key = practiceDayKey.
  final Map<String, PracticeDay> days = {};

  /// Oldest first.
  final List<PracticeSession> sessions = [];

  /// Oldest first.
  final List<Milestone> milestones = [];

  /// Whether the daily goal / achievements feature is on (general setting,
  /// default on). While off, nothing is recorded; stored data is kept.
  bool enabled = true;

  PracticeDay dayOf(String key) => days[key] ?? PracticeDay();

  /// Adds a milestone. With [onlyIfHigher] it is skipped unless [value]
  /// beats every earlier one of that kind (records); otherwise an identical
  /// kind+value is never logged twice. Returns whether it was added.
  bool addMilestone(String day, String kind, int value, {bool onlyIfHigher = false}) {
    final same = milestones.where((m) => m.kind == kind);
    if (onlyIfHigher) {
      if (same.any((m) => m.value >= value)) return false;
    } else if (same.any((m) => m.value == value)) {
      return false;
    }
    milestones.add(Milestone(day, kind, value));
    return true;
  }

  Future<void> load(SharedPreferences p) async {
    enabled = p.getBool(enabledKey) ?? true;
    days.clear();
    sessions.clear();
    milestones.clear();
    List<dynamic> list(String key) {
      final raw = p.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      try {
        final v = jsonDecode(raw);
        return v is List ? v : const [];
      } catch (_) {
        return const [];
      }
    }

    final rawDays = p.getString(_daysKey);
    if (rawDays != null && rawDays.isNotEmpty) {
      try {
        (jsonDecode(rawDays) as Map<String, dynamic>)
            .forEach((k, v) => days[k] = PracticeDay.fromJson(v as Map<String, dynamic>));
      } catch (_) {
        days.clear();
      }
    }
    sessions.addAll(list(_sessionsKey).map((e) => PracticeSession.fromJson(e as Map<String, dynamic>)));
    milestones.addAll(list(_milestonesKey).map((e) => Milestone.fromJson(e as Map<String, dynamic>)));
  }

  Future<void> save(SharedPreferences p) async {
    if (sessions.length > kKeepSessions) {
      sessions.removeRange(0, sessions.length - kKeepSessions);
    }
    await p.setString(_daysKey, jsonEncode(days.map((k, v) => MapEntry(k, v.toJson()))));
    await p.setString(_sessionsKey, jsonEncode(sessions.map((s) => s.toJson()).toList()));
    await p.setString(_milestonesKey, jsonEncode(milestones.map((m) => m.toJson()).toList()));
  }

  Future<void> setEnabled(SharedPreferences p, bool v) async {
    enabled = v;
    await p.setBool(enabledKey, v);
  }

  /// Wipes the log (not the on/off setting).
  Future<void> reset(SharedPreferences p) async {
    days.clear();
    sessions.clear();
    milestones.clear();
    await p.remove(_daysKey);
    await p.remove(_sessionsKey);
    await p.remove(_milestonesKey);
  }
}
