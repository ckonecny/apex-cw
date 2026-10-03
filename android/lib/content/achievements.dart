// Achievements (issue #34, docs/DECISIONS.md "Achievements"): a small fixed set,
// worked out from the practice log (#30) every time the page opens. Nothing is
// stored per achievement, so a rule change applies to the whole history.
import 'daily_goal.dart';
import 'practice_log.dart';

class AchievementId {
  static const charFirst = 'char_first';
  static const char3Week = 'char_3week';
  static const charStreak = 'char_streak';
  static const spreadDay = 'spread_day';
  static const spreadDays = 'spread_days';
  static const errBetter = 'err_better';
  static const errUnder5 = 'err_under5';
  static const interUnder10 = 'inter_under10';
  static const speedRecord = 'speed_record';
  static const comeback = 'comeback';

  static const all = [
    charFirst, char3Week, charStreak, spreadDay, spreadDays,
    errBetter, errUnder5, interUnder10, speedRecord, comeback,
  ];
}

class Achievement {
  final String id;

  /// practiceDayKey of the day it was earned, null while locked.
  final String? earned;
  const Achievement(this.id, this.earned);
  bool get unlocked => earned != null;
}

/// Weeks in a row with a new character that earn [AchievementId.charStreak].
const kCharStreakWeeks = 4;

/// Distinct days that earn [AchievementId.spreadDays].
const kSpreadDays = 5;

/// Days without practice before a return counts as a comeback.
const kComebackDays = 7;

DateTime _dateOf(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _keyOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _weekOf(String dayKey) {
  final d = _dateOf(dayKey);
  return _keyOf(d.subtract(Duration(days: d.weekday - 1)));
}

String _prevWeek(String week) => _keyOf(_dateOf(week).subtract(const Duration(days: 7)));

/// All achievements in display order. Unlocked ones carry the day they were
/// earned (the first time the rule was met).
List<Achievement> achievements(PracticeLog log) {
  final earned = <String, String>{};
  void earn(String id, String? day) {
    if (day == null || day.isEmpty) return;
    final old = earned[id];
    if (old == null || day.compareTo(old) < 0) earned[id] = day;
  }

  // --- New characters (Koch levels reached, per training) ---------------
  final kochs = log.milestones
      .where((m) => m.kind == MilestoneKind.kochHear || m.kind == MilestoneKind.kochEcho)
      .toList();
  if (kochs.isNotEmpty) {
    earn(AchievementId.charFirst, (kochs.map((m) => m.day).toList()..sort()).first);
  }
  // Characters per training and week; the better of the two trainings counts.
  final perWeek = <String, Map<String, Set<int>>>{}; // week -> kind -> levels
  for (final m in kochs) {
    perWeek.putIfAbsent(_weekOf(m.day), () => {}).putIfAbsent(m.kind, () => {}).add(m.value);
  }
  final lastDayOfWeek = <String, String>{};
  for (final m in kochs) {
    final w = _weekOf(m.day);
    final cur = lastDayOfWeek[w];
    if (cur == null || m.day.compareTo(cur) > 0) lastDayOfWeek[w] = m.day;
  }
  for (final e in perWeek.entries) {
    final most = e.value.values.fold<int>(0, (a, s) => s.length > a ? s.length : a);
    if (most >= 3) earn(AchievementId.char3Week, lastDayOfWeek[e.key]);
  }
  final weeks = perWeek.keys.toList()..sort();
  var run = 0;
  String? prev;
  for (final w in weeks) {
    run = prev != null && _prevWeek(w) == prev ? run + 1 : 1;
    prev = w;
    if (run >= kCharStreakWeeks) earn(AchievementId.charStreak, lastDayOfWeek[w]);
  }

  // --- Practice spread over the day --------------------------------------
  final byDay = <String, List<PracticeSession>>{};
  for (final s in log.sessions) {
    byDay.putIfAbsent(practiceDayKey(s.startTime), () => []).add(s);
  }
  final spreadDays = <String>[];
  for (final e in byDay.entries) {
    if (countedSessions(e.value).length >= kSessionChoices.first) spreadDays.add(e.key);
  }
  spreadDays.sort();
  if (spreadDays.isNotEmpty) earn(AchievementId.spreadDay, spreadDays.first);
  if (spreadDays.length >= kSpreadDays) earn(AchievementId.spreadDays, spreadDays[kSpreadDays - 1]);

  // --- Error rate and interference ---------------------------------------
  final byWeek = <String, List<BlockRecord>>{};
  for (final b in log.blocks) {
    byWeek.putIfAbsent(_weekOf(b.day), () => []).add(b);
  }
  double avg(List<BlockRecord> l) => l.fold(0.0, (a, b) => a + b.errors) / l.length;
  for (final e in byWeek.entries) {
    final before = byWeek[_prevWeek(e.key)];
    if (e.value.length >= 3 && before != null && before.length >= 3 && avg(e.value) < avg(before)) {
      earn(AchievementId.errBetter, e.value.last.day);
    }
  }
  var streak = 0;
  for (final b in log.blocks) {
    streak = b.errors < 0.05 ? streak + 1 : 0;
    if (streak >= 3) earn(AchievementId.errUnder5, b.day);
    if (b.interference && b.errors < 0.10) earn(AchievementId.interUnder10, b.day);
  }

  // --- Speed record -------------------------------------------------------
  final speeds = log.milestones
      .where((m) => m.kind == MilestoneKind.wpmHear || m.kind == MilestoneKind.wpmEcho);
  if (speeds.isNotEmpty) earn(AchievementId.speedRecord, (speeds.map((m) => m.day).toList()..sort()).first);

  // --- Comeback after a break --------------------------------------------
  final days = log.days.entries.where((e) => e.value.seconds > 0).map((e) => e.key).toList()..sort();
  for (var i = 1; i < days.length; i++) {
    if (_dateOf(days[i]).difference(_dateOf(days[i - 1])).inDays > kComebackDays) {
      earn(AchievementId.comeback, days[i]);
      break;
    }
  }

  return [for (final id in AchievementId.all) Achievement(id, earned[id])];
}
