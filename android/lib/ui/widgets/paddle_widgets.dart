// Shared touch-paddle widgets: used by CW Keyer and — since the Echo Trainer
// also needs to receive keyed input, whether from touch or a vband adapter —
// the Echo Trainer too (including Koch "Neu lernen" / "Vorhören").
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/bluetooth_hint.dart';
import '../../util/key_adapter_state.dart';
import '../../util/paddle_layout.dart';
import '../settings_screen.dart';

// Stands in for the touch keys while a key adapter is detected and hiding is
// switched on (#95). The Bluetooth warning stays: it matters for real keys too.
class _HiddenPaddles extends StatelessWidget {
  const _HiddenPaddles();

  @override
  Widget build(BuildContext context) => const Column(
      mainAxisSize: MainAxisSize.min,
      children: [BluetoothLatencyHint(), KeyAdapterHiddenHint()]);
}

class IambicPaddles extends StatelessWidget {
  final VoidCallback onDitDown, onDitUp, onDahDown, onDahUp;
  const IambicPaddles({super.key, required this.onDitDown, required this.onDitUp,
      required this.onDahDown, required this.onDahUp});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: KeyAdapterState.listenable,
      builder: (context, _) => KeyAdapterState.paddlesHidden
          ? const _HiddenPaddles() : _buildPaddles(context));

  Widget _buildPaddles(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const BluetoothLatencyHint(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ValueListenableBuilder<bool>(
          valueListenable: PaddleLayout.swapped,
          builder: (context, swapped, _) {
            final dit = Expanded(child: PaddleButton(label: 'DIT  ·',
                color: c.accent, onDown: onDitDown, onUp: onDitUp));
            final dah = Expanded(child: PaddleButton(label: 'DAH  —',
                color: c.warning, onDown: onDahDown, onUp: onDahUp));
            return Row(children: [
              swapped ? dah : dit,
              const SizedBox(width: 12),
              swapped ? dit : dah,
            ]);
          },
        ),
      ),
    ]);
  }
}

// Uses raw Listener (pointer events) instead of GestureDetector's tap
// recognizer — a long hold must never be reinterpreted/canceled, since the
// hold duration itself is what decides dit vs. dah.
class StraightKeyPaddle extends StatefulWidget {
  final VoidCallback onDown, onUp;
  const StraightKeyPaddle({super.key, required this.onDown, required this.onUp});

  @override
  State<StraightKeyPaddle> createState() => _StraightKeyPaddleState();
}

class _StraightKeyPaddleState extends State<StraightKeyPaddle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: KeyAdapterState.listenable,
      builder: (context, _) => KeyAdapterState.paddlesHidden
          ? const _HiddenPaddles() : _buildKey(context));

  Widget _buildKey(BuildContext context) {
    final c = AppColors.of(context);
    final color = c.info;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const BluetoothLatencyHint(),
      Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Listener(
        onPointerDown: (_) { setState(() => _pressed = true);  widget.onDown(); },
        onPointerUp:   (_) { setState(() => _pressed = false); widget.onUp(); },
        onPointerCancel: (_) { setState(() => _pressed = false); widget.onUp(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 30),
          height: 90,
          decoration: BoxDecoration(
            color: _pressed ? color.withValues(alpha: 0.3) : c.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(child: Text(Strings.t('paddle_key'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color.withValues(alpha: _pressed ? 1.0 : 0.75)))),
        ),
      ),
    ),
    ]);
  }
}

// One-line warning above the paddles while the sidetone plays over Bluetooth:
// its 100–250 ms delay can't be calibrated away and disturbs your rhythm when
// keying. Hidden when switched off in Settings or closed for this app run.
class BluetoothLatencyHint extends StatelessWidget {
  const BluetoothLatencyHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([BluetoothHint.bluetoothActive,
          BluetoothHint.enabled, BluetoothHint.dismissed]),
      builder: (context, _) {
        if (!BluetoothHint.bluetoothActive.value || !BluetoothHint.enabled.value
            || BluetoothHint.dismissed.value) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            Expanded(child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsScreen(scrollToAudio: true))),
              child: Row(children: [
                Icon(Icons.bluetooth_audio, size: 14, color: c.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(Strings.t('bt_latency_hint'),
                    style: TextStyle(fontSize: 11, color: c.warning))),
                Icon(Icons.settings, size: 14, color: c.textFaint),
              ]),
            )),
            InkWell(
              onTap: () => BluetoothHint.dismissed.value = true,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: c.textFaint),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// One discreet line in place of the hidden touch keys (#95). The X closes it
// until the next time an adapter is detected; tapping it opens the setting.
class KeyAdapterHiddenHint extends StatelessWidget {
  const KeyAdapterHiddenHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: KeyAdapterState.dismissed,
      builder: (context, dismissed, _) {
        if (dismissed) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            Expanded(child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsScreen(scrollToKeyer: true))),
              child: Row(children: [
                Icon(Icons.keyboard_hide_outlined, size: 14, color: c.info),
                const SizedBox(width: 6),
                Expanded(child: Text(Strings.t('key_adapter_hidden_hint'),
                    style: TextStyle(fontSize: 11, color: c.textMuted))),
                Icon(Icons.settings, size: 14, color: c.textFaint),
              ]),
            )),
            InkWell(
              onTap: () => KeyAdapterState.dismissed.value = true,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: c.textFaint),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class PaddleButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onDown, onUp;
  final double height;
  const PaddleButton({super.key, required this.label, required this.color,
      required this.onDown, required this.onUp, this.height = 90});
  @override
  State<PaddleButton> createState() => _PaddleButtonState();
}

class _PaddleButtonState extends State<PaddleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Listener(
      onPointerDown: (_) { setState(() => _pressed = true); widget.onDown(); },
      onPointerUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onPointerCancel: (_) { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 30),
        height: widget.height,
        decoration: BoxDecoration(
          color: _pressed ? widget.color.withValues(alpha: 0.3) : c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: Text(widget.label,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                fontWeight: FontWeight.bold,
                color: widget.color.withValues(alpha: _pressed ? 1.0 : 0.75)))),
      ),
    );
  }
}
