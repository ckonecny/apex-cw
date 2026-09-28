// Text adventure map: "Visited" (rooms you have seen, paths you have
// walked — the map players drew on paper) and "Whole map" (every room of
// the part, behind a spoiler warning). Layout and data: adventure_map.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adventure/adventure_map.dart';
import '../adventure/adventure_store.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'adventure_screen.dart' show AdventureSettings, romanPart;
import 'widgets/app_ui.dart';

const _ux = 150.0, _uy = 90.0; // one layout unit in logical pixels
const _bw = 124.0, _bh = 46.0; // room box
const _pad = 120.0;

class AdventureMapScreen extends StatefulWidget {
  final AdventureGame game;
  final AdventureMap map;
  final Set<int> visited;
  final List<(int, int)> walked;
  final int here;
  const AdventureMapScreen({super.key, required this.game, required this.map,
      required this.visited, required this.walked, required this.here});

  @override
  State<AdventureMapScreen> createState() => _AdventureMapScreenState();
}

class _AdventureMapScreenState extends State<AdventureMapScreen> {
  bool _whole = false;
  final _ctl = TransformationController();
  Size? _viewport;

  late final double _minX = widget.map.rooms.values.map((r) => r.x).reduce(min);
  late final double _minY = widget.map.rooms.values.map((r) => r.y).reduce(min);
  late final double _maxX = widget.map.rooms.values.map((r) => r.x).reduce(max);
  late final double _maxY = widget.map.rooms.values.map((r) => r.y).reduce(max);
  Size get _canvas => Size((_maxX - _minX) * _ux + 2 * _pad, (_maxY - _minY) * _uy + 2 * _pad);
  Offset _pos(MapRoom r) => Offset((r.x - _minX) * _ux + _pad, (r.y - _minY) * _uy + _pad);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Puts the current room in the middle of the screen.
  void _center(Size viewport) {
    final r = widget.map.rooms[widget.here];
    if (r == null) return;
    final p = _pos(r);
    _ctl.value = Matrix4.identity()
      ..translate(viewport.width / 2 - p.dx, viewport.height / 2 - p.dy);
  }

  Future<void> _setWhole(bool whole) async {
    if (whole && !_whole) {
      // Asks every time, until "Don't ask again" (back on in the settings).
      final p = await SharedPreferences.getInstance();
      if (p.getBool(AdventureSettings.mapWarnKey) ?? true) {
        if (!mounted) return;
        final (ok, noAsk) = await _confirmWhole();
        if (!ok) return;
        if (noAsk) await p.setBool(AdventureSettings.mapWarnKey, false);
      }
    }
    if (mounted) setState(() => _whole = whole);
  }

  /// (show, don't ask again).
  Future<(bool, bool)> _confirmWhole() async {
    final c = AppColors.of(context);
    TextStyle mono(double s, Color col, {bool bold = false}) => TextStyle(fontFamily: 'CwMono',
        fontSize: s, color: col, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    var noAsk = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        backgroundColor: c.surface,
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: c.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(Strings.t('adv_map_whole_q'), style: mono(16, c.textPrimary, bold: true))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('adv_map_whole_body').replaceAll('{n}', romanPart(widget.game.part)),
              style: mono(13, c.textMuted)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setSt(() => noAsk = !noAsk),
            child: Row(children: [
              Checkbox(value: noAsk, activeColor: c.accent,
                  onChanged: (v) => setSt(() => noAsk = v ?? false)),
              Expanded(child: Text(Strings.t('adv_map_whole_noask'), style: mono(13, c.textPrimary))),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(Strings.t('cancel'), style: mono(13, c.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(Strings.t('adv_map_whole_show'), style: mono(13, c.warning, bold: true))),
        ],
      )),
    );
    return (ok == true, noAsk);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t('adv_map')),
        leading: IconButton(icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            tooltip: Strings.t('adv_map_here'),
            icon: Icon(Icons.my_location, color: c.textMuted),
            onPressed: () { final v = _viewport; if (v != null) _center(v); },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(child: _tab(c, Strings.t('adv_map_visited'), !_whole, () => _setWhole(false))),
            const SizedBox(width: 8),
            Expanded(child: _tab(c, '${Strings.t('adv_map_whole')} ⚠', _whole, () => _setWhole(true))),
          ]),
        ),
        Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (context, box) {
            final first = _viewport == null;
            _viewport = box.biggest;
            if (first) _center(box.biggest);
            return InteractiveViewer(
              transformationController: _ctl,
              constrained: false,
              minScale: 0.25,
              maxScale: 2.5,
              boundaryMargin: EdgeInsets.all(max(box.maxWidth, box.maxHeight)),
              child: CustomPaint(
                size: _canvas,
                painter: _MapPainter(
                  map: widget.map,
                  pos: _pos,
                  here: widget.here,
                  visited: widget.visited,
                  walked: widget.walked,
                  whole: _whole,
                  colors: c,
                ),
              ),
            );
          }),
        )),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.of(context).padding.bottom),
          child: Text(Strings.t(_whole ? 'adv_map_legend_whole' : 'adv_map_legend'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
        ),
      ]),
    );
  }

  Widget _tab(AppColors c, String label, bool on, VoidCallback onTap) => Material(
        color: on ? c.accent.withValues(alpha: 0.18) : c.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? c.accent : c.border)),
            child: Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
                fontWeight: on ? FontWeight.bold : FontWeight.normal,
                color: on ? c.accent : c.textMuted)),
          ),
        ),
      );
}

class _MapPainter extends CustomPainter {
  final AdventureMap map;
  final Offset Function(MapRoom) pos;
  final int here;
  final Set<int> visited;
  final List<(int, int)> walked;
  final bool whole;
  final AppColors colors;

  _MapPainter({required this.map, required this.pos, required this.here, required this.visited,
      required this.walked, required this.whole, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    // What is shown: the whole map, or what the player has seen / walked.
    final walkedKeys = {for (final (a, b) in walked) (a, b)};
    final seen = {...visited, here, for (final (a, b) in walked) ...[a, b]};
    final rooms = whole ? map.rooms.keys.toSet() : seen.where(map.rooms.containsKey).toSet();
    final edges = whole
        ? map.edges
        : map.edges.where((e) => walkedKeys.contains((e.a, e.b))).toList();

    for (final l in map.labels) {
      _text(canvas, l.text, pos(MapRoom(0, '', l.x, l.y)), 300, TextStyle(fontFamily: 'CwMono',
          fontSize: 13, fontWeight: FontWeight.bold, color: c.textFaint));
    }

    // Paths first, the rooms are drawn over them.
    final notes = <int, List<String>>{};
    for (final e in edges) {
      final a = map.rooms[e.a]!, b = map.rooms[e.b]!;
      final known = seen.contains(e.a) && seen.contains(e.b);
      final col = known ? c.textMuted : c.textDisabled;
      if (e.jump) {
        final arrow = e.vertical ? '↕' : '→';
        notes.putIfAbsent(e.a, () => []).add('$arrow ${b.name}');
        notes.putIfAbsent(e.b, () => []).add('$arrow ${a.name}');
        continue;
      }
      final pa = pos(a), pb = pos(b);
      final paint = Paint()
        ..color = col
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      if (e.vertical) {
        _dashed(canvas, pa, pb, paint);
      } else {
        canvas.drawLine(pa, pb, paint);
      }
      final from = e.oneWayFrom;
      if (from != null) {
        final (s, t) = from == e.a ? (pa, pb) : (pb, pa);
        _arrow(canvas, s, t, Paint()..color = col);
      }
    }

    for (final id in rooms) {
      final r = map.rooms[id]!;
      final p = pos(r);
      final isHere = id == here;
      final known = seen.contains(id);
      final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: p, width: _bw, height: _bh), const Radius.circular(8));
      canvas.drawRRect(rect, Paint()
        ..color = isHere
            ? Color.alphaBlend(c.accent.withValues(alpha: 0.25), c.surface)
            : known ? c.surface : c.surfaceDark);
      canvas.drawRRect(rect, Paint()
        ..color = isHere ? c.accent : known ? c.border : c.border.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHere ? 2.5 : 1.2);
      _text(canvas, r.name, p, _bw - 10, TextStyle(fontFamily: 'CwMono', fontSize: 12,
          fontWeight: isHere ? FontWeight.bold : FontWeight.normal,
          color: isHere ? c.accent : known ? c.textPrimary : c.textFaint));
      var y = p.dy + _bh / 2 + 8;
      for (final n in notes[id] ?? const <String>[]) {
        // A note names the far end only if the player may know it.
        final far = n.substring(2);
        if (!whole && !map.rooms.values.any((o) => o.name == far && seen.contains(o.id))) continue;
        _text(canvas, n, Offset(p.dx, y), _bw + 30,
            TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.info));
        y += 13;
      }
    }
  }

  void _text(Canvas canvas, String s, Offset center, double maxW, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += 10) {
      canvas.drawLine(a + u * t, a + u * min(t + 6, len), paint);
    }
  }

  /// Arrowhead at the edge of the target box.
  static void _arrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    final d = to - from;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    // Where the line enters the target box.
    final tx = u.dx.abs() < 1e-6 ? double.infinity : (_bw / 2) / u.dx.abs();
    final ty = u.dy.abs() < 1e-6 ? double.infinity : (_bh / 2) / u.dy.abs();
    final tip = to - u * min(tx, ty);
    final n = Offset(-u.dy, u.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - u * 10 + n * 5).dx, (tip - u * 10 + n * 5).dy)
      ..lineTo((tip - u * 10 - n * 5).dx, (tip - u * 10 - n * 5).dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.whole != whole || old.here != here || old.colors != colors;
}
