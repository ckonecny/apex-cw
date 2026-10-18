// App bar symbol for an external key (#116): dim while no adapter is
// detected, accent colour once one is. A tap opens the keyer settings.
// While it is shown (and [sound] is true) the keyer runs with the general
// Send settings, so dit and dah can be heard and the key tried out.
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/key_adapter_state.dart';
import '../../util/keyer_try.dart';
import '../settings_screen.dart';

class KeyerStatusButton extends StatefulWidget {
  /// False while the screen needs the keyer for itself or must stay quiet
  /// (a running block, a screen that keys on its own).
  final bool sound;
  const KeyerStatusButton({super.key, this.sound = true});

  @override
  State<KeyerStatusButton> createState() => _KeyerStatusButtonState();
}

class _KeyerStatusButtonState extends State<KeyerStatusButton> {
  Animation<double>? _covered;
  bool _on = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another route (settings, statistics, a sheet) on top silences the key.
    final a = ModalRoute.of(context)?.secondaryAnimation;
    if (a != _covered) {
      _covered?.removeStatusListener(_onCover);
      _covered = a;
      _covered?.addStatusListener(_onCover);
    }
    _sync();
  }

  @override
  void didUpdateWidget(KeyerStatusButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _onCover(AnimationStatus _) => _sync();

  void _sync() {
    final covered = _covered != null && _covered!.status != AnimationStatus.dismissed;
    final want = widget.sound && !covered;
    if (want == _on) return;
    _on = want;
    want ? KeyerTry.start() : KeyerTry.stop();
  }

  @override
  void dispose() {
    _covered?.removeStatusListener(_onCover);
    if (_on) KeyerTry.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: KeyAdapterState.detected,
      builder: (context, detected, _) => IconButton(
        icon: Icon(Icons.settings_input_component_outlined, color: detected ? c.accent : c.textFaint),
        tooltip: Strings.t(detected ? 'keyer_btn_detected' : 'keyer_btn_none'),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen(scrollToKeyer: true))),
      ),
    );
  }
}
