import 'package:flutter/material.dart';

/// Colour of the strip behind the system navigation bar. main.dart keeps the
/// whole app clear of the bars, so that strip shows the page background; a
/// bottom-docked widget (the on-screen keyboard) claims it with [NavStripColor]
/// so its colour runs to the screen edge.
class NavStrip {
  static final ValueNotifier<Color?> color = ValueNotifier(null);
}

class NavStripColor extends StatefulWidget {
  final Color color;
  final Widget child;
  const NavStripColor({super.key, required this.color, required this.child});

  @override
  State<NavStripColor> createState() => _NavStripColorState();
}

class _NavStripColorState extends State<NavStripColor> {
  @override
  void initState() {
    super.initState();
    _set(widget.color);
  }

  @override
  void didUpdateWidget(NavStripColor old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color) _set(widget.color);
  }

  @override
  void dispose() {
    final mine = widget.color;
    // After the frame: changing the notifier while the tree is being torn
    // down would rebuild main's builder mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (NavStrip.color.value == mine) NavStrip.color.value = null;
    });
    super.dispose();
  }

  void _set(Color c) => WidgetsBinding.instance.addPostFrameCallback(
    (_) => NavStrip.color.value = c,
  );

  @override
  Widget build(BuildContext context) => widget.child;
}
