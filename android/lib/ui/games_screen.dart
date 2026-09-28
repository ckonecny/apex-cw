// Games hub: the firmware's single-player CW games (docs/PORTING-MAP.md)
// plus the text adventures (app only).
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'adventure_select_screen.dart';
import 'invaders_screen.dart';
import 'memory_chain_screen.dart';
import 'morsel_screen.dart';
import 'widgets/app_ui.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('games_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _GameCard(
              icon: Icons.grid_view_rounded,
              title: 'Morsel',
              subtitle: Strings.t('morsel_subtitle'),
              hint: Strings.t('morsel_hint'),
              color: c.info,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MorselScreen())),
            ),
            const SizedBox(height: 12),
            _GameCard(
              icon: Icons.rocket_launch_outlined,
              title: 'Morse Invaders',
              subtitle: Strings.t('inv_subtitle'),
              hint: Strings.t('inv_hint'),
              color: c.accentPurple,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InvadersScreen())),
            ),
            const SizedBox(height: 12),
            _GameCard(
              icon: Icons.link_rounded,
              title: 'Memory Chain',
              subtitle: Strings.t('mc_subtitle'),
              hint: Strings.t('mc_hint'),
              color: c.warning,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MemoryChainScreen())),
            ),
            const SizedBox(height: 12),
            _GameCard(
              icon: Icons.castle_outlined,
              title: Strings.t('adv_title'),
              subtitle: Strings.t('adv_subtitle'),
              hint: Strings.t('adv_hint'),
              color: c.accent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdventureSelectScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, hint;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({required this.icon, required this.title, required this.subtitle,
      required this.hint, required this.color, required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    fontFamily: 'CwMono', fontSize: 20, color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(
                    fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
                const SizedBox(height: 6),
                Text(hint, style: TextStyle(
                    fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
              ],
            )),
            Icon(Icons.chevron_right, color: c.textFaint),
          ]),
        ),
      ),
    );
  }
}
