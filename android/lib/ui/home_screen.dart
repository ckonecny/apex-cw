import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/block_history.dart';
import '../content/charset_content.dart';
import '../content/training_profile.dart';
import 'keyer_screen.dart';
import 'generator_screen.dart';
import 'echo_trainer_screen.dart';
import 'settings_screen.dart';
import 'wifi_trx_screen.dart';
import 'qso_bot_screen.dart';
import 'games_screen.dart';
import 'decoder_screen.dart';
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
  BlockTrend? _trend;

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
    final trend = trendOf(await const BlockHistory('echo').load(p));
    if (!mounted) return;
    setState(() {
      _hear = hear;
      _echo = echo;
      _trend = trend;
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
      builder: (context, _, __) {
        final hearInfo = _hear == null ? '' : _profileInfo(_hear!);
        final giveInfo = _echo == null ? '' : _profileInfo(_echo!) +
            (_trend != null ? ' · ${_trend!.percent} % ${_trend!.arrow}' : '');
        return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: Text('Next CW Trainer',
              style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 22,
                  letterSpacing: 0.3, color: c.textPrimary,
                  fontVariations: const [FontVariation('wght', 600)])),
          actions: [
            IconButton(
              icon: Icon(Icons.settings, color: c.textMuted),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(Strings.t('home_section_practice')),
            Expanded(child: _ModeCard(
              icon: Icons.headphones,
              title: Strings.t('block_hear'),
              subtitle: hearInfo.isEmpty
                  ? Strings.t('home_hear_subtitle') : hearInfo,
              color: c.accent,
              onTap: () => _open(const GeneratorScreen()),
            )),
            const SizedBox(height: 8),
            Expanded(child: _ModeCard(
              icon: Icons.keyboard,
              title: Strings.t('block_give'),
              subtitle: giveInfo.isEmpty
                  ? Strings.t('home_give_subtitle') : giveInfo,
              color: c.accent,
              onTap: () => _open(const EchoTrainerScreen()),
            )),
            const SizedBox(height: 16),
            _SectionLabel(Strings.t('home_section_free')),
            Expanded(child: _ModeCard(
              icon: Icons.tune,
              title: 'CW Keyer',
              subtitle: Strings.t('home_keyer_subtitle'),
              color: c.accentPurple,
              onTap: () => _open(const KeyerScreen()),
            )),
            const SizedBox(height: 8),
            Expanded(child: _ModeCard(
              icon: Icons.hearing,
              title: Strings.t('dec_title'),
              subtitle: Strings.t('home_decoder_subtitle'),
              color: c.accentPurple,
              onTap: () => _open(const DecoderScreen()),
            )),
            const SizedBox(height: 8),
            Expanded(child: _ModeCard(
              icon: Icons.wifi,
              title: 'WiFi Trx',
              subtitle: Strings.t('home_wifitrx_subtitle'),
              color: c.warning,
              onTap: () => _open(const WifiTrxScreen()),
            )),
            const SizedBox(height: 8),
            Expanded(child: _ModeCard(
              icon: Icons.forum_outlined,
              title: 'QSO Bot',
              subtitle: Strings.t('home_qso_subtitle'),
              color: c.warning,
              onTap: () => _open(const QsoBotScreen()),
            )),
            const SizedBox(height: 16),
            _SectionLabel(Strings.t('home_section_games')),
            Expanded(child: _ModeCard(
              icon: Icons.sports_esports,
              title: Strings.t('games_title'),
              subtitle: Strings.t('home_games_subtitle'),
              color: c.info,
              onTap: () => _open(const GamesScreen()),
            )),
          ],
          ),
        ),
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
          fontFamily: 'CwMono', fontSize: 11, letterSpacing: 1,
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
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                      fontFamily: 'CwMono', fontSize: 20, color: c.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(
                      fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
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
