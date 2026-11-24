import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'audio_output_card.dart';
import 'keyer_settings_card.dart';
import 'widgets/app_ui.dart';

/// One section of the settings on its own page, for shortcuts out of a
/// training (key icon, Bluetooth hint). A jump to a section of the long
/// settings list could land beside it whenever a card above it grows while
/// loading (e.g. Störungen switched on); a page of its own cannot.
class _SectionScreen extends StatelessWidget {
  final String titleKey;
  final Widget child;
  const _SectionScreen({required this.titleKey, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t(titleKey)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [child]),
      ),
    );
  }
}

/// The keyer settings on their own page (key icon, keyer screen).
class KeyerSettingsScreen extends StatelessWidget {
  const KeyerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SectionScreen(titleKey: 'settings_keyer', child: KeyerSettingsCard());
}

/// The audio output settings on their own page (Bluetooth hint).
class AudioOutputScreen extends StatelessWidget {
  const AudioOutputScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SectionScreen(titleKey: 'settings_audio_output', child: AudioOutputCard());
}
