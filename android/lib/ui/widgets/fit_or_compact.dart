import 'package:flutter/material.dart';

// Shows builder(false) while it fits into [availableHeight], else
// builder(true). The full variant is laid out offstage to measure it, so the
// choice adapts to font scale, orientation and content without a guess.
// [below] (the tempo block) is measured too and kept at the bottom, so the
// card is only judged against the room left above it.
class FitOrCompact extends StatefulWidget {
  final double availableHeight;
  final Widget? below;
  final Widget Function(bool compact) builder;
  const FitOrCompact({super.key, required this.availableHeight, required this.builder, this.below});

  @override
  State<FitOrCompact> createState() => _FitOrCompactState();
}

class _FitOrCompactState extends State<FitOrCompact> {
  final _fullKey = GlobalKey();
  final _belowKey = GlobalKey();
  bool _compact = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _fullKey.currentContext?.size?.height;
      final below = _belowKey.currentContext?.size?.height ?? 0;
      if (!mounted || h == null) return;
      final compact = h + below + 12 > widget.availableHeight;
      if (compact != _compact) setState(() => _compact = compact);
    });
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Stack(children: [
            Positioned(
              left: 0, right: 0, top: 0,
              child: Offstage(child: KeyedSubtree(key: _fullKey, child: widget.builder(false))),
            ),
            widget.builder(_compact),
          ]),
        ),
        if (widget.below != null) KeyedSubtree(key: _belowKey, child: widget.below!),
      ],
    );
  }
}
