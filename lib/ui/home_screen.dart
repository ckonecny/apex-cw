import 'package:flutter/material.dart';
import 'keyer_screen.dart';
import 'generator_screen.dart';
import 'echo_trainer_screen.dart';
import 'settings_screen.dart';
import '../theme/app_colors.dart';
import '../l10n/strings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Rebuild the instant the language changes — see the matching comment
    // in settings_screen.dart's build().
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text('Morserino Mobile',
            style: TextStyle(fontFamily: 'CwMono', fontSize: 18,
                color: c.textPrimary)),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.settings_input_component,
              title: 'CW Keyer',
              subtitle: Strings.t('home_keyer_subtitle'),
              color: c.accent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const KeyerScreen())),
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.graphic_eq,
              title: 'CW Generator',
              subtitle: Strings.t('home_generator_subtitle'),
              color: c.info,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GeneratorScreen())),
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.school,
              title: 'Koch Trainer',
              subtitle: 'K M R S U A P T L O …',
              color: c.warning,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GeneratorScreen(kochMode: true))),
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.repeat,
              title: 'Echo Trainer',
              subtitle: Strings.t('home_echo_subtitle'),
              color: c.accentPurple,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EchoTrainerScreen())),
            ),
          ],
        ),
      ),
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    fontFamily: 'CwMono', fontSize: 18,
                    fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(
                    fontFamily: 'CwMono', fontSize: 12,
                    color: c.textMuted)),
              ],
            )),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}
