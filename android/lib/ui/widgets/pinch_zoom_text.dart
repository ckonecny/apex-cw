import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps a text display so a two-finger pinch changes its font size, without
/// competing with any single-finger scrolling inside [builder] — raw pointer
/// events are tracked directly rather than via a GestureDetector's scale
/// recognizer, which would otherwise fight a nested SingleChildScrollView (or
/// similar) for the gesture arena on a one-finger drag.
///
/// The size is persisted per [prefsKey] via SharedPreferences so each output
/// field (CW Generator/Koch Trainer log, CW Keyer, Echo Trainer) remembers
/// its own size independently.
class PinchZoomFontSize extends StatefulWidget {
  final String prefsKey;
  final double initialSize;
  final double minSize;
  final double maxSize;
  final Widget Function(BuildContext context, double fontSize) builder;

  const PinchZoomFontSize({
    super.key,
    required this.prefsKey,
    required this.builder,
    this.initialSize = 26,
    this.minSize = 14,
    this.maxSize = 48,
  });

  @override
  State<PinchZoomFontSize> createState() => _PinchZoomFontSizeState();
}

class _PinchZoomFontSizeState extends State<PinchZoomFontSize> {
  late double _fontSize = widget.initialSize;
  final Map<int, Offset> _pointers = {};
  double? _startDistance;
  double? _startSize;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
  }

  Future<void> _loadFontSize() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(widget.prefsKey);
    if (v != null && mounted) {
      setState(() => _fontSize = v.clamp(widget.minSize, widget.maxSize));
    }
  }

  Future<void> _saveFontSize() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(widget.prefsKey, _fontSize);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _startDistance = (pts[0] - pts[1]).distance;
      _startSize = _fontSize;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final startDist = _startDistance;
    final startSize = _startSize;
    if (_pointers.length == 2 && startDist != null && startDist > 0 && startSize != null) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      setState(() {
        _fontSize = (startSize * dist / startDist).clamp(widget.minSize, widget.maxSize);
      });
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _startDistance = null;
      _startSize = null;
    }
    if (_pointers.isEmpty) _saveFontSize();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: widget.builder(context, _fontSize),
    );
  }
}
