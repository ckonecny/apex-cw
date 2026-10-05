// Understanding (head copy): one entry in the games hub for the three listening
// modes that need no key, like the adventure selection (docs/DECISIONS.md
// "Head copy / comprehension", "Understanding group").
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'head_copy_screen.dart';
import 'mini_qso_screen.dart';
import 'q_groups_screen.dart';
import 'widgets/app_ui.dart';

class UnderstandScreen extends StatelessWidget {
  const UnderstandScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('und_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            HubCard(
              icon: Icons.hearing_rounded,
              title: Strings.t('hc_title'),
              subtitle: Strings.t('hc_subtitle'),
              hint: Strings.t('hc_hint'),
              color: c.accent,
              onTap: () => open(const HeadCopyScreen()),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.question_answer_outlined,
              title: Strings.t('qg_title'),
              subtitle: Strings.t('qg_subtitle'),
              hint: Strings.t('qg_hint'),
              color: c.info,
              onTap: () => open(const QGroupsScreen()),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.forum_outlined,
              title: Strings.t('mq_title'),
              subtitle: Strings.t('mq_subtitle'),
              hint: Strings.t('mq_hint'),
              color: c.warning,
              onTap: () => open(const MiniQsoScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
