import 'package:flutter/material.dart';

// Shows builder(false) while it fits into [availableHeight], else
// builder(true). The full variant is laid out offstage to measure it, so the
// choice adapts to font scale, orientation and content without a guess.
class FitOrCompact extends StatefulWidget {
  final double availableHeight;
  final Widget Function(bool compact) builder;
  const FitOrCompact({super.key, required this.availableHeight, required this.builder});

  @override
  State<FitOrCompact> createState() => _FitOrCompactState();
}

class _FitOrCompactState extends State<FitOrCompact> {
  final _fullKey = GlobalKey();
  bool _compact = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _fullKey.currentContext?.size?.height;
      if (!mounted || h == null) return;
      final compact = h > widget.availableHeight;
      if (compact != _compact) setState(() => _compact = compact);
    });
    return Stack(children: [
      Positioned(
        left: 0, right: 0, top: 0,
        child: Offstage(child: KeyedSubtree(key: _fullKey, child: widget.builder(false))),
      ),
      widget.builder(_compact),
    ]);
  }
}
