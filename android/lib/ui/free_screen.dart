// Hub for the free modes: keying, decoding, WiFi and the QSO bot. Grouped
// one level down (like the games) so the home screen fits without scrolling.
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'decoder_screen.dart';
import 'keyer_screen.dart';
import 'own_texts_screen.dart';
import 'qso_bot_screen.dart';
import 'widgets/app_ui.dart';
import 'wifi_trx_screen.dart';

class FreeScreen extends StatelessWidget {
  const FreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    void open(Widget s) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => s));
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('free_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            HubCard(
              icon: Icons.tune,
              title: 'CW Keyer',
              subtitle: Strings.t('home_keyer_subtitle'),
              hint: Strings.t('free_keyer_hint'),
              color: c.accentPurple,
              onTap: () => open(const KeyerScreen()),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.hearing,
              title: Strings.t('dec_title'),
              subtitle: Strings.t('home_decoder_subtitle'),
              hint: Strings.t('free_decoder_hint'),
              color: c.accentPurple,
              onTap: () => open(const DecoderScreen()),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.wifi,
              title: 'WiFi Trx',
              subtitle: Strings.t('home_wifitrx_subtitle'),
              hint: Strings.t('free_wifi_hint'),
              color: c.warning,
              onTap: () => open(const WifiTrxScreen()),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.forum_outlined,
              title: 'QSO Bot',
              subtitle: Strings.t('home_qso_subtitle'),
              hint: Strings.t('free_qso_hint'),
              color: c.warning,
              onTap: () => open(const QsoBotScreen()),
            ),
            const SizedBox(height: 12),
            HubCard(
              icon: Icons.menu_book_outlined,
              title: Strings.t('ot_title'),
              subtitle: Strings.t('ot_subtitle'),
              hint: Strings.t('free_ot_hint'),
              color: c.accent,
              onTap: () => open(const OwnTextsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
