// On-screen keyboard for the Hören typing mode (DECISIONS.md "Hören: typing
// mode"). Not the system keyboard: QWERTY with a digit row, every key always
// at its fixed place so the fingers learn the positions; keys outside the
// practiced charset are drawn inactive and do nothing. A punctuation row
// and prosign keys only appear when the charset contains any of them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/nav_strip.dart';
import 'app_ui.dart';

const kKeyboardPunct = ['.', ',', ':', '-', '/', '=', '?', '@', '+'];
const kKeyboardProsigns = ['AS', 'KA', 'KN', 'SK', 'VE', 'BK'];

class CwKeyboard extends StatelessWidget {
  /// Active keys, uppercase ("A", "0", ".", or a prosign like "KA").
  final Set<String> active;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final VoidCallback onPass;
  /// false = every key inert (e.g. while the solution is shown).
  final bool enabled;
  /// Draws ⏎ faded (still works) — while the word is still playing.
  final bool submitFaded;
  final bool haptic;
  /// 0 = lower, 1 = UPPER, as the app's output case setting.
  final int outputCase;
  final String passLabel;
  final String submitLabel;

  const CwKeyboard({
    super.key,
    required this.active,
    required this.onKey,
    required this.onBackspace,
    required this.onSubmit,
    required this.onPass,
    required this.passLabel,
    required this.submitLabel,
    this.enabled = true,
    this.submitFaded = false,
    this.haptic = true,
    this.outputCase = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasPunct = kKeyboardPunct.any(active.contains);
    final hasPro = kKeyboardProsigns.any(active.contains);
    // More rows → slightly flatter keys, so the keyboard keeps its height.
    final keyH = hasPunct ? 50.0 : 56.0;

    Widget ch(String k) => _CharKey(
          label: k.length > 1 || outputCase == 1 ? k : k.toLowerCase(),
          prosign: k.length > 1,
          active: enabled && active.contains(k),
          height: keyH,
          haptic: haptic,
          onTap: () => onKey(k),
        );
    Widget gap(int halfUnits) => Expanded(flex: halfUnits, child: const SizedBox());
    Widget unit(Widget w, [int halfUnits = 2]) => Expanded(flex: halfUnits, child: w);

    final rows = <List<Widget>>[
      [for (final k in '1234567890'.split('')) unit(ch(k))],
      [for (final k in 'QWERTYUIOP'.split('')) unit(ch(k))],
      [gap(1), for (final k in 'ASDFGHJKL'.split('')) unit(ch(k)), gap(1)],
      [
        gap(3),
        for (final k in 'ZXCVBNM'.split('')) unit(ch(k)),
        unit(_ActionKey(
            height: keyH, enabled: enabled, haptic: haptic, onTap: onBackspace,
            child: Icon(Icons.backspace_outlined, size: 22, color: c.textMuted)), 3),
      ],
      if (hasPunct) [gap(1), for (final k in kKeyboardPunct) unit(ch(k)), gap(1)],
      [
        unit(_ActionKey(
            height: keyH, enabled: enabled, haptic: haptic, onTap: onPass,
            child: Text(passLabel, style: TextStyle(fontFamily: 'CwMono',
                fontSize: hasPro ? 12 : 15, fontWeight: FontWeight.bold, color: c.textMuted))),
            hasPro ? 3 : 5),
        if (hasPro) for (final k in kKeyboardProsigns) unit(ch(k)) else gap(7),
        unit(_ActionKey(
            height: keyH, enabled: enabled, haptic: haptic, onTap: onSubmit,
            color: c.accent.withValues(alpha: submitFaded ? 0.45 : 1),
            child: Text(submitLabel, style: TextStyle(fontFamily: 'CwMono',
                fontSize: hasPro ? 13 : 16, fontWeight: FontWeight.bold, color: c.background))),
            hasPro ? 5 : 8),
      ],
    ];

    // Fixed key geometry: the labels are already sized for the keys, so the
    // system font size is ignored here (DECISIONS.md "System font size").
    return NavStripColor(color: c.surfaceDark, child: NoTextScale(child: Container(
      color: c.surfaceDark,
      // Clear of the gesture/navigation bar.
      padding: EdgeInsets.fromLTRB(3, 6, 3, 6 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(children: r),
          ),
      ]),
    )));
  }
}

const _hapticChannel = MethodChannel('at.oe1cko.nextcwtrainer/settings');

/// Key vibration: a short native buzz; Flutter's HapticFeedback is only a
/// faint tick on Android 17.
void keyHaptic() {
  _hapticChannel.invokeMethod<void>('keyHaptic').catchError((_) {});
}

// One character key. Reacts on pointer down (not on release) so fast
// two-thumb typing is not lost to the tap gesture arena; while pressed, a
// bubble above the key shows the character, since the thumb covers it.
class _CharKey extends StatefulWidget {
  final String label;
  final bool prosign;
  final bool active;
  final double height;
  final bool haptic;
  final VoidCallback onTap;
  const _CharKey({required this.label, required this.prosign, required this.active,
      required this.height, required this.haptic, required this.onTap});

  @override
  State<_CharKey> createState() => _CharKeyState();
}

class _CharKeyState extends State<_CharKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final on = widget.active;
    final text = Text(widget.label,
        style: TextStyle(
          fontFamily: 'CwMono',
          fontSize: widget.prosign ? 13 : (on ? 20 : 16),
          fontWeight: on ? FontWeight.bold : FontWeight.normal,
          color: !on ? c.textDisabled : (_down ? c.background : c.textPrimary),
          decoration: widget.prosign ? TextDecoration.overline : null,
          decorationColor: !on ? c.textDisabled : (_down ? c.background : c.textPrimary),
        ));
    final key = Container(
      height: widget.height,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: !on ? Colors.transparent : (_down ? c.accent : c.surface),
        borderRadius: BorderRadius.circular(7),
        border: on ? null : Border.all(color: c.border),
      ),
      child: text,
    );
    if (!on) return key;
    return Listener(
      onPointerDown: (_) {
        if (widget.haptic) keyHaptic();
        setState(() => _down = true);
        widget.onTap();
      },
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        key,
        if (_down)
          Positioned(
            bottom: widget.height - 4,
            child: IgnorePointer(
              child: Container(
                width: 52, height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                  boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))],
                ),
                child: Text(widget.label, style: TextStyle(fontFamily: 'CwMono',
                    fontSize: widget.prosign ? 18 : 30, fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ActionKey extends StatelessWidget {
  final double height;
  final bool enabled;
  final bool haptic;
  final VoidCallback onTap;
  final Widget child;
  final Color? color;
  const _ActionKey({required this.height, required this.enabled, required this.haptic,
      required this.onTap, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Material(
          color: color ?? c.surface,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: enabled
                ? () {
                    if (haptic) keyHaptic();
                    onTap();
                  }
                : null,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
