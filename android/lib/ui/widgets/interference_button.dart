import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/interference_profile.dart';
import '../interference_settings_card.dart';
import 'app_ui.dart';

/// App bar icon for the interference simulation (issue #6), next to the
/// statistics and settings icons of screens that play the other station.
/// Dim = off, accent colour = on; a tap switches it on or off, a long press
/// opens the interference settings.
class InterferenceButton extends StatefulWidget {
  const InterferenceButton({super.key});

  @override
  State<InterferenceButton> createState() => _InterferenceButtonState();
}

class _InterferenceButtonState extends State<InterferenceButton> {
  InterferenceProfile? _p;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final p = await InterferenceProfile.load();
    if (mounted) setState(() => _p = p);
  }

  Future<void> _toggle() async {
    final p = (_p ?? await InterferenceProfile.load());
    final n = p.copyWith(enabled: !p.enabled);
    setState(() => _p = n);
    await n.save();
    await n.push();
    if (!mounted) return;
    const keys = ['interf_preset_custom', 'interf_preset_light', 'interf_preset_hf', 'interf_preset_pileup'];
    final msg = n.enabled
        ? '${Strings.t('interf_header')}: ${Strings.t(keys[n.preset])}'
        : '${Strings.t('interf_header')}: ${Strings.t('interf_off')}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)));
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const InterferenceScreen()));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final on = _p?.enabled ?? false;
    return Tooltip(
      message: Strings.t('interf_button_tip'),
      child: InkResponse(
        radius: 24,
        onTap: _toggle,
        onLongPress: _openSettings,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.graphic_eq, color: on ? c.accent : c.textMuted.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}

/// The interference settings on their own page (opened from the badge).
class InterferenceScreen extends StatelessWidget {
  const InterferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('interf_header')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [InterferenceSettingsCard()],
      ),
    );
  }
}
