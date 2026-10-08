import 'package:flutter/material.dart';
import 'widgets/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/block_history.dart';
import '../content/charset_content.dart';
import '../content/daily_goal.dart';
import '../util/practice_clock.dart';
import 'daily_goal_card.dart';
import 'goals_screen.dart';
import '../content/training_profile.dart';
import 'generator_screen.dart';
import 'echo_trainer_screen.dart';
import 'understand_screen.dart';
import 'settings_screen.dart';
import 'free_screen.dart';
import 'games_screen.dart';
import 'learn_screen.dart';
import '../theme/app_colors.dart';
import '../l10n/strings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Kept raw (not as finished strings) so the subtitles are rebuilt in the
  // current language when Strings.lang changes.
  TrainingProfile? _hear;
  TrainingProfile? _echo;
  BlockTrend? _hearTrend;
  BlockTrend? _trend;
  DailyGoalSettings _goal = DailyGoalSettings();

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  String _profileInfo(TrainingProfile pf) {
    final wpm = TrainingProfile.clampWpm(pf.getInt('wpm'));
    final cs = pf.getInt('charset');
    final koch = cs == null || cs == CharSet.koch.index;
    final lesson = pf.getInt('kochLevel');
    return koch && lesson != null
        ? '${Strings.t('block_lesson')} $lesson · $wpm WPM'
        : '$wpm WPM';
  }

  Future<void> _loadInfo() async {
    final p = await SharedPreferences.getInstance();
    final hear = await TrainingProfile.open(TrainingProfile.hear);
    final echo = await TrainingProfile.open(TrainingProfile.echo);
    final hearTrend = trendOf(await const BlockHistory('hear').load(p));
    final trend = trendOf(await const BlockHistory('echo').load(p));
    final goal = await DailyGoalSettings.load(p);
    if (!mounted) return;
    setState(() {
      _hear = hear;
      _echo = echo;
      _hearTrend = hearTrend;
      _trend = trend;
      _goal = goal;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadInfo();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Rebuild the instant the language changes — see the matching comment
    // in settings_screen.dart's build().
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) {
        final hearInfo = _hear == null ? '' : _profileInfo(_hear!) +
            (_hearTrend != null ? ' · ${_hearTrend!.percent} % ${_hearTrend!.arrow}' : '');
        final giveInfo = _echo == null ? '' : _profileInfo(_echo!) +
            (_trend != null ? ' · ${_trend!.percent} % ${_trend!.arrow}' : '');
        return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: Text('APEX CW',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 22,
                  letterSpacing: 0.3, color: c.textPrimary,
                  fontVariations: const [FontVariation('wght', 600)])),
          actions: [
            IconButton(
              icon: Icon(Icons.settings, color: c.textMuted),
              onPressed: () => _open(const SettingsScreen()),
            ),
          ],
        ),
        body: LayoutBuilder(builder: (context, box) {
          // The six cards share the screen height; when that gets too
          // tight for their text (large system font, small screen), they
          // switch to a fixed minimum height and the page scrolls instead.
          final f = textScaleOf(context);
          final minCard = 58 * f;
          final base = 6 * minCard + 2 * 8 + 3 * 16 + 4 * 23 * f + 8 + 24;
          // The goal card comes first: full while everything still fits,
          // then the one-line variant, then the page scrolls.
          final showGoal = PracticeClock.instance.log.enabled;
          final fs = f < 1 ? 1.0 : f; // the ring itself does not shrink
          final fullH = 100 * fs, compactH = 56 * fs;
          final compactGoal = showGoal && box.maxHeight < base + fullH + 12;
          final needed = base + (showGoal ? (compactGoal ? compactH : fullH) + 12 : 0);
          final scroll = box.maxHeight < needed;
          Widget card(Widget w) => scroll ? SizedBox(height: minCard, child: w) : Expanded(child: w);
          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showGoal) ...[
              SizedBox(
                height: compactGoal ? compactH : fullH,
                child: LiveGoalCard(
                  settings: _goal,
                  compact: compactGoal,
                  onTap: () => _open(const GoalsScreen()),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _SectionLabel(Strings.t('home_section_practice')),
            card(_ModeCard(
              icon: Icons.headphones,
              title: Strings.t('block_hear'),
              subtitle: hearInfo.isEmpty
                  ? Strings.t('home_hear_subtitle') : hearInfo,
              color: c.accent,
              onTap: () => _open(const GeneratorScreen()),
            )),
            const SizedBox(height: 8),
            card(_ModeCard(
              icon: Icons.keyboard,
              title: Strings.t('block_give'),
              subtitle: giveInfo.isEmpty
                  ? Strings.t('home_give_subtitle') : giveInfo,
              color: c.accent,
              onTap: () => _open(const EchoTrainerScreen()),
            )),
            const SizedBox(height: 8),
            card(_ModeCard(
              icon: Icons.hearing_rounded,
              title: Strings.t('und_title'),
              subtitle: Strings.t('und_subtitle'),
              color: c.accent,
              onTap: () => _open(const UnderstandScreen()),
            )),
            const SizedBox(height: 16),
            _SectionLabel(Strings.t('home_section_free')),
            card(_ModeCard(
              icon: Icons.lock_open_outlined,
              title: Strings.t('free_title'),
              subtitle: Strings.t('home_free_subtitle'),
              color: c.accentPurple,
              onTap: () => _open(const FreeScreen()),
            )),
            const SizedBox(height: 16),
            _SectionLabel(Strings.t('home_section_games')),
            card(_ModeCard(
              icon: Icons.sports_esports,
              title: Strings.t('games_title'),
              subtitle: Strings.t('home_games_subtitle'),
              color: c.info,
              onTap: () => _open(const GamesScreen()),
            )),
            const SizedBox(height: 16),
            _SectionLabel(Strings.t('home_section_learn')),
            card(_ModeCard(
              icon: Icons.school_outlined,
              title: Strings.t('learn_title'),
              subtitle: Strings.t('home_learn_subtitle'),
              color: c.accent,
              onTap: () => _open(const LearnScreen()),
            )),
          ],
          );
          const padding = EdgeInsets.fromLTRB(16, 8, 16, 24);
          return scroll
              ? ScrollHint(padding: padding, child: column)
              : Padding(padding: padding, child: column);
        }),
      );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text.toUpperCase(), style: TextStyle(
          fontSize: 11, letterSpacing: 1,
          color: c.textMuted)),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({required this.icon, required this.title, required this.subtitle,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                      fontSize: 20, color: c.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                      fontSize: 12, color: c.textMuted)),
                ],
              )),
              Icon(Icons.chevron_right, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
