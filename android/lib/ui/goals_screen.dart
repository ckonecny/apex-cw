import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/achievements.dart';
import '../content/daily_goal.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/practice_clock.dart';
import '../util/reminder.dart';
import 'daily_goal_card.dart';
import 'widgets/app_ui.dart';
import 'widgets/setting_rows.dart';

/// Achievements page (#34 will extend it). For now: today, streak, week, and
/// the gear icon to its settings.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  DailyGoalSettings _s = DailyGoalSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DailyGoalSettings.load(await SharedPreferences.getInstance());
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = goalStatus(PracticeClock.instance.log, _s, DateTime.now());
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('goal_title')),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GoalSettingsScreen()));
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        DailyGoalCard(status: g, compact: false, onTap: () {}),
        const SizedBox(height: 16),
        SettingsCard(children: [
          _row(c, Strings.t('goal_today'), _min(g.todaySeconds)),
          const SettingsDivider(),
          _row(c, Strings.t('goal_week'), _min(g.weekSeconds)),
        ]),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(Strings.t('ach_title').toUpperCase(), style: TextStyle(
              fontFamily: 'CwMono', fontSize: 11, letterSpacing: 1, color: c.textMuted)),
        ),
        SettingsCard(children: [
          for (final (i, a) in achievements(PracticeClock.instance.log).indexed) ...[
            if (i > 0) const SettingsDivider(),
            _achievement(c, a),
          ],
        ]),
      ]),
    );
  }

  Widget _achievement(AppColors c, Achievement a) {
    final color = a.unlocked ? c.accent : c.textFaint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(a.unlocked ? Icons.emoji_events : Icons.lock_outline, color: color, size: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ach_${a.id}'), style: TextStyle(
              fontFamily: 'CwMono', fontSize: 14,
              color: a.unlocked ? c.textPrimary : c.textMuted)),
          const SizedBox(height: 2),
          Text(Strings.t('ach_${a.id}_d'), style: TextStyle(
              fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
          const SizedBox(height: 2),
          Text(a.unlocked ? _date(a.earned!) : Strings.t('ach_locked'), style: TextStyle(
              fontFamily: 'CwMono', fontSize: 11, color: color)),
        ])),
      ]),
    );
  }

  /// Day key `2026-10-07` as `07.10.2026` (German) or unchanged (English).
  String _date(String key) {
    final p = key.split('-');
    return Strings.lang.value == 0 ? '${p[2]}.${p[1]}.${p[0]}' : key;
  }

  String _min(int seconds) =>
      Strings.t('goal_minutes_unit').replaceFirst('{n}', '${seconds ~/ 60}');

  Widget _row(AppColors c, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
          const Spacer(),
          Text(value, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
        ]),
      );
}

class GoalSettingsScreen extends StatefulWidget {
  const GoalSettingsScreen({super.key});

  @override
  State<GoalSettingsScreen> createState() => _GoalSettingsScreenState();
}

class _GoalSettingsScreenState extends State<GoalSettingsScreen> {
  DailyGoalSettings _s = DailyGoalSettings();
  SharedPreferences? _p;
  bool _remOn = false;
  int _remMin = Reminder.defaultMinutes;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) async {
      final s = await DailyGoalSettings.load(p);
      final on = await Reminder.isOn();
      final m = await Reminder.minutes();
      if (mounted) setState(() { _p = p; _s = s; _remOn = on; _remMin = m; });
    });
  }

  Future<void> _setReminder(bool v) async {
    final on = await Reminder.setOn(v);
    if (!mounted) return;
    setState(() => _remOn = on);
    if (v && !on) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.t('reminder_denied'))));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context,
        initialTime: TimeOfDay(hour: _remMin ~/ 60, minute: _remMin % 60));
    if (t == null || !mounted) return;
    setState(() => _remMin = t.hour * 60 + t.minute);
    await Reminder.setMinutes(_remMin);
  }

  Future<void> _setShow(bool v) async {
    final p = _p;
    if (p == null) return;
    await PracticeClock.instance.log.setEnabled(p, v);
    Reminder.refresh();
    if (!mounted) return;
    // Hidden: nothing left to look at here, back to the start page.
    if (!v) {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget desc(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(Strings.t(key), style: TextStyle(
              fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
        );
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('goal_settings_title')),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SettingsCard(children: [
          SegmentRow(
            label: Strings.t('goal_daily'),
            options: [for (final m in kGoalChoices)
              Strings.t('goal_minutes_unit').replaceFirst('{n}', '$m')],
            selected: kGoalChoices.indexOf(_s.minutes),
            onChanged: (i) {
              setState(() => _s.minutes = kGoalChoices[i]);
              if (_p != null) _s.save(_p!).then((_) => Reminder.refresh());
            },
          ),
          const SettingsDivider(),
          SegmentRow(
            label: Strings.t('goal_sessions'),
            options: [Strings.t('goal_sessions_off'),
              for (final n in kSessionChoices) '$n×'],
            selected: _s.sessions == 0 ? 0 : kSessionChoices.indexOf(_s.sessions) + 1,
            onChanged: (i) {
              setState(() => _s.sessions = i == 0 ? 0 : kSessionChoices[i - 1]);
              if (_p != null) _s.save(_p!).then((_) => Reminder.refresh());
            },
          ),
          desc('goal_sessions_desc'),
          const SettingsDivider(),
          ToggleRow(label: Strings.t('goal_grace'), value: _s.grace,
              onChanged: (v) {
                setState(() => _s.grace = v);
                if (_p != null) _s.save(_p!);
              }),
          desc('goal_grace_desc'),
        ]),
        const SizedBox(height: 24),
        SettingsCard(children: [
          ToggleRow(label: Strings.t('reminder_label'), value: _remOn, onChanged: _setReminder),
          if (_remOn) ...[
            const SettingsDivider(),
            InkWell(
              onTap: _pickTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Text(Strings.t('reminder_time'), style: TextStyle(
                      fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
                  const Spacer(),
                  Text('${(_remMin ~/ 60).toString().padLeft(2, '0')}:'
                      '${(_remMin % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.accent)),
                ]),
              ),
            ),
          ],
          desc('reminder_desc'),
        ]),
        const SizedBox(height: 24),
        SettingsCard(children: [
          ToggleRow(label: Strings.t('goal_show'),
              value: PracticeClock.instance.log.enabled, onChanged: _setShow),
          desc('goal_show_desc'),
        ]),
      ]),
    );
  }
}
