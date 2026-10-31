import 'package:flutter/material.dart';
import 'app_ui.dart';

/// A centred, scrollable page area that shows [builder]\(true) while that
/// fits into [availableHeight] and [builder]\(false) otherwise. The full
/// variant is laid out offstage to measure it (like FitOrCompact), so the
/// choice adapts to font scale, phone size and content without a guess.
class FitFull extends StatefulWidget {
  const FitFull(
      {super.key,
      required this.availableHeight,
      required this.builder,
      this.padding = EdgeInsets.zero});

  final double availableHeight;
  final EdgeInsets padding;
  final Widget Function(bool full) builder;

  @override
  State<FitFull> createState() => _FitFullState();
}

class _FitFullState extends State<FitFull> {
  final _key = GlobalKey();
  bool _full = true;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _key.currentContext?.size?.height;
      if (!mounted || h == null) return;
      final full = h + widget.padding.vertical <= widget.availableHeight;
      if (full != _full) setState(() => _full = full);
    });
    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Offstage(child: KeyedSubtree(key: _key, child: widget.builder(true))),
      ),
      Positioned.fill(
        child: ScrollHint(center: true, padding: widget.padding, child: widget.builder(_full)),
      ),
    ]);
  }
}
