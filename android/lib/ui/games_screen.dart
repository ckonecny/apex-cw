// Games hub: the firmware's single-player CW games (docs/PORTING-MAP.md)
// plus the text adventures (app only).
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'adventure_select_screen.dart';
import 'invaders_screen.dart';
import 'maze_game_screen.dart';
import 'memory_chain_screen.dart';
import 'morsel_screen.dart';
import 'pileup_screen.dart';
import 'radio_cave_screen.dart';
import 'widgets/app_ui.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  // The list is longer than most screens: a visible scrollbar shows that it goes on.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('games_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              HubCard(
                icon: Icons.rocket_launch_outlined,
                title: 'Morse Invaders',
                subtitle: Strings.t('inv_subtitle'),
                hint: Strings.t('inv_hint'),
                color: c.accentPurple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InvadersScreen()),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.castle_outlined,
                title: Strings.t('adv_title'),
                subtitle: Strings.t('adv_subtitle'),
                hint: Strings.t('adv_hint'),
                color: c.accent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdventureSelectScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.grid_view_rounded,
                title: 'Morsel',
                subtitle: Strings.t('morsel_subtitle'),
                hint: Strings.t('morsel_hint'),
                color: c.info,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MorselScreen()),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.link_rounded,
                title: 'Memory Chain',
                subtitle: Strings.t('mc_subtitle'),
                hint: Strings.t('mc_hint'),
                color: c.warning,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MemoryChainScreen()),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.route_outlined,
                title: 'Trailblazer',
                subtitle: Strings.t('tb_subtitle'),
                hint: Strings.t('tb_hint'),
                color: c.accentPurple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const MazeGameScreen(game: MazeGame.trailblazer),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.travel_explore,
                title: 'Fox Hunt',
                subtitle: Strings.t('fh_subtitle'),
                hint: Strings.t('fh_hint'),
                color: c.info,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const MazeGameScreen(game: MazeGame.foxHunt),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.cell_tower,
                title: 'Fight the Pileup',
                subtitle: Strings.t('pu_subtitle'),
                hint: Strings.t('pu_hint'),
                color: c.danger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PileupScreen()),
                ),
              ),
              const SizedBox(height: 12),
              HubCard(
                icon: Icons.settings_input_antenna,
                title: 'Radio Cave',
                subtitle: Strings.t('rc_subtitle'),
                hint: Strings.t('rc_hint'),
                color: c.danger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RadioCaveScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
