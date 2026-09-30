// Learning resources hub: things that help to learn CW but are not a
// training mode of their own (interactive Morse tree, character chart, links).
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'links_screen.dart';
import 'morse_chart_screen.dart';
import 'morse_tree_screen.dart';
import 'widgets/app_ui.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('learn_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            HubCard(
              icon: Icons.account_tree_outlined,
              title: Strings.t('tree_title'),
              subtitle: Strings.t('tree_subtitle'),
              hint: Strings.t('tree_hint'),
              color: c.accent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MorseTreeScreen())),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.grid_view_rounded,
              title: Strings.t('chart_title'),
              subtitle: Strings.t('chart_subtitle'),
              hint: Strings.t('chart_hint'),
              color: c.accentPurple,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MorseChartScreen())),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.link_rounded,
              title: Strings.t('links_title'),
              subtitle: Strings.t('links_subtitle'),
              hint: Strings.t('links_hint'),
              color: c.info,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LinksScreen())),
            ),
          ],
        ),
      ),
    );
  }
}
