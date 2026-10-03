import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/daily_goal.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/practice_clock.dart';
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
      ]),
    );
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

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) async {
      final s = await DailyGoalSettings.load(p);
      if (mounted) setState(() { _p = p; _s = s; });
    });
  }

  Future<void> _setShow(bool v) async {
    final p = _p;
    if (p == null) return;
    await PracticeClock.instance.log.setEnabled(p, v);
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
              if (_p != null) _s.save(_p!);
            },
          ),
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
          ToggleRow(label: Strings.t('goal_show'),
              value: PracticeClock.instance.log.enabled, onChanged: _setShow),
          desc('goal_show_desc'),
        ]),
      ]),
    );
  }
}
