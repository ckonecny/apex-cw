import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/char_color.dart';
import '../util/interference_profile.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart';
import 'widgets/interference_button.dart';

/// Interactive Morse tree (dichotomic table): a dit goes left, a dah right,
/// the character sits where its code ends. Drawn from MorseDecoder.table, so
/// it cannot disagree with what the app plays and decodes. Tapping a node
/// plays the character at the configured pitch; the path from the root lights
/// up element by element, driven by the generator's elementOn/elementOff
/// events (same as the tap tile in Hören).
class MorseTreeScreen extends StatefulWidget {
  const MorseTreeScreen({super.key});

  @override
  State<MorseTreeScreen> createState() => _MorseTreeScreenState();
}

class _MorseTreeScreenState extends State<MorseTreeScreen> {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  StreamSubscription? _sub;
  int _wpm = 20;
  int _pitch = 600;
  int _softness = 4;
  bool _ready = false;
  bool _deep = false;      // include level 5: digits and signs

  final _scroll = ScrollController();

  String _path = '';       // code of the character last tapped
  int _lit = 0;            // elements 0.._lit-1 have sounded
  bool _sounding = false;

  @override
  void initState() {
    super.initState();
    InterferenceProfile.requestAmbient(this);
    // The app is locked to portrait (main.dart); the tree is much easier to
    // read in landscape, so it is freed here and locked again in dispose().
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    _wpm      = TrainingProfile.clampWpm(pf.getInt('wpm'));
    _pitch    = p.getInt('pitch') ?? 600;
    _softness = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    if (!mounted) return;
    // Rule 2: the shared engine keeps whatever the last screen set.
    await _keyerChannel.invokeMethod('stop').catchError((_) {});
    await _pushConfig();
    _sub = cwGenEvents.listen(_onGenEvent);
    setState(() => _ready = true);
  }

  Future<void> _pushConfig() async {
    await _toneChannel.invokeMethod('setFreq', _pitch).catchError((_) {});
    await _toneChannel
        .invokeMethod('setEnvelopeMs', (_softness + 1).toDouble())
        .catchError((_) {});
    await _genChannel.invokeMethod('setWpm', _wpm).catchError((_) {});
  }

  @override
  void dispose() {
    InterferenceProfile.releaseAmbient(this);
    _sub?.cancel();
    _scroll.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _genChannel.invokeMethod('stopOne');
    super.dispose();
  }

  void _onGenEvent(dynamic raw) {
    final ev = raw as Map;
    if (!mounted) return;
    switch (ev['type']) {
      case 'elementOn':
        setState(() {
          _lit = int.parse(ev['value'] as String) + 1;
          _sounding = true;
        });
      case 'elementOff':
        setState(() => _sounding = false);
    }
  }

  Future<void> _play(String pattern) async {
    final ch = MorseDecoder.table[pattern];
    if (ch == null || !_ready) return;
    setState(() { _path = pattern; _lit = 0; _sounding = false; });
    // stopOne, not stop: the latter also restarts the keyer. playOne is
    // ignored while a previous play still runs, so cut that first.
    await _genChannel.invokeMethod('stopOne').catchError((_) {});
    await Future.delayed(const Duration(milliseconds: 40));
    // Prosigns need the explicit <XX> form, a bare pair is two letters.
    await _genChannel
        .invokeMethod('playOne', ch.length > 1 ? '<$ch>' : ch)
        .catchError((_) {});
  }

  Future<void> _setWpm(int v) async {
    setState(() => _wpm = v.clamp(TrainingProfile.minWpm, 60));
    await _genChannel.invokeMethod('setWpm', _wpm).catchError((_) {});
  }

  Widget _treeArea({required double? height, required bool landscape}) {
    final maxDepth = _deep ? 5 : 4;
    return LayoutBuilder(builder: (context, box) {
      final h = height ?? box.maxHeight;
      // Deep tree: 32 slots. Landscape has the width for them; portrait
      // gets twice the screen width and scrolls.
      final w = !_deep
          ? box.maxWidth
          : landscape
              ? max(box.maxWidth, 32 * 24.0)
              : box.maxWidth * 2;
      final tree = SizedBox(
        width: w,
        height: h,
        child: _Tree(
          maxDepth: maxDepth, path: _path, lit: _lit,
          sounding: _sounding, onTapNode: _play,
        ),
      );
      if (w <= box.maxWidth) return tree;
      return SizedBox(
        height: h,
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal, controller: _scroll, child: tree),
      );
    });
  }

  Widget _chip() => FilterChip(
        label: Text(Strings.t('tree_digits')),
        selected: _deep,
        onSelected: (v) {
          setState(() => _deep = v);
          // A wider tree scrolls: centre it on the root.
          if (v) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent / 2);
              }
            });
          }
        },
      );

  Widget _speed(AppColors c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(Strings.t('tree_speed'), style: TextStyle(
            fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
        IconButton(
          icon: const Icon(Icons.remove),
          color: c.textMuted,
          onPressed: () => _setWpm(_wpm - 1),
        ),
        Text('$_wpm', style: TextStyle(
            fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
        IconButton(
          icon: const Icon(Icons.add),
          color: c.textMuted,
          onPressed: () => _setWpm(_wpm + 1),
        ),
      ]);

  // Fixed height so nothing jumps when the first character is tapped.
  Widget _code() => SizedBox(
        height: 14,
        child: _path.isEmpty
            ? null
            : MorseElementRow(pattern: _path, lit: _lit, sounding: _sounding),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final maxDepth = _deep ? 5 : 4;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('tree_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
          actions: const [InterferenceButton()],
        ),
        body: landscape
            // Landscape: controls in one slim row, the tree gets the rest.
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(children: [
                  Row(children: [
                    _chip(),
                    const Spacer(),
                    _code(),
                    const Spacer(),
                    _speed(c),
                  ]),
                  Expanded(child: _treeArea(height: null, landscape: true)),
                ]),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Text(Strings.t('tree_intro'), style: TextStyle(
                      fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
                  const SizedBox(height: 12),
                  _treeArea(
                      height: 52.0 * (maxDepth + 1) + 30, landscape: false),
                  const SizedBox(height: 8),
                  Center(child: _code()),
                  const SizedBox(height: 16),
                  Row(children: [_chip(), const Spacer(), _speed(c)]),
                ],
              ),
      ),
    );
  }
}

/// Geometry shared by painting and hit testing. Level d has 2^d slots; the
/// node of code [p] sits in slot bits(p) of its level.
class _Geo {
  final Size size;
  final int maxDepth;
  _Geo(this.size, this.maxDepth);

  static const _padTop = 16.0, _padBottom = 22.0;
  double get rowH => (size.height - _padTop - _padBottom) / maxDepth;
  double get radius => min(size.width / (1 << maxDepth) * 0.46, 15.0);

  Offset pos(String p) {
    var i = 0;
    for (final ch in p.split('')) {
      i = i * 2 + (ch == '-' ? 1 : 0);
    }
    final slots = 1 << p.length;
    return Offset((i + 0.5) * size.width / slots, _padTop + p.length * rowH);
  }
}

/// A node exists when some code of the table passes through it.
bool _exists(String p, int maxDepth) =>
    p.length <= maxDepth &&
    MorseDecoder.table.keys.any((k) => k.startsWith(p));

Iterable<String> _nodes(int maxDepth) sync* {
  for (var d = 1; d <= maxDepth; d++) {
    for (var i = 0; i < (1 << d); i++) {
      final p = List.generate(d, (b) => (i >> (d - 1 - b)) & 1 == 1 ? '-' : '.').join();
      if (_exists(p, maxDepth)) yield p;
    }
  }
}

class _Tree extends StatelessWidget {
  final int maxDepth, lit;
  final String path;
  final bool sounding;
  final void Function(String pattern) onTapNode;
  const _Tree({
    required this.maxDepth, required this.path, required this.lit,
    required this.sounding, required this.onTapNode,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final geo = _Geo(box.biggest, maxDepth);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          String? best;
          var bestDist = double.infinity;
          for (final p in _nodes(maxDepth)) {
            if (!MorseDecoder.table.containsKey(p)) continue;
            final dist = (geo.pos(p) - d.localPosition).distance;
            if (dist < bestDist) { bestDist = dist; best = p; }
          }
          // Generous slop: thumbs are bigger than the nodes.
          if (best != null && bestDist <= max(geo.radius * 1.6, 22)) {
            onTapNode(best);
          }
        },
        child: CustomPaint(
          size: box.biggest,
          painter: _TreePainter(
            c: c, geo: geo, path: path, lit: lit, sounding: sounding),
        ),
      );
    });
  }
}

class _TreePainter extends CustomPainter {
  final AppColors c;
  final _Geo geo;
  final String path;
  final int lit;
  final bool sounding;
  _TreePainter({required this.c, required this.geo, required this.path,
      required this.lit, required this.sounding});

  bool _active(String p) =>
      path.isNotEmpty && p.length <= lit && path.startsWith(p);

  @override
  void paint(Canvas canvas, Size size) {
    final r = geo.radius;
    final nodes = _nodes(geo.maxDepth).toList();

    // Edges first, nodes on top.
    // A dit edge (left) is a row of dots, a dah edge (right) one thick solid
    // line, like the dits and dashes they stand for.
    for (final p in nodes) {
      final parent = geo.pos(p.substring(0, p.length - 1));
      final child = geo.pos(p);
      final color = _active(p) ? c.accent : c.textFaint;
      if (p.endsWith('-')) {
        canvas.drawLine(parent, child, Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..color = color);
      } else {
        final len = (child - parent).distance;
        final n = max((len / 8).round(), 2);
        final dot = Paint()..color = color;
        for (var k = 1; k < n; k++) {
          canvas.drawCircle(Offset.lerp(parent, child, k / n)!, 2, dot);
        }
      }
    }

    // Root: where every code starts.
    final root = geo.pos('');
    canvas.drawCircle(root, 5, Paint()
      ..color = path.isNotEmpty && lit > 0 ? c.accent : c.border);

    for (final p in nodes) {
      final o = geo.pos(p);
      final ch = MorseDecoder.table[p];
      final on = _active(p);
      if (ch == null) {
        canvas.drawCircle(o, 3, Paint()..color = on ? c.accent : c.border);
        continue;
      }
      if (on && sounding && p.length == lit) {
        canvas.drawCircle(o, r + 3, Paint()
          ..color = c.accent.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      }
      canvas.drawCircle(o, r, Paint()..color = on ? c.accent : c.surface);
      canvas.drawCircle(o, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = on ? c.accent : c.border);
      final tp = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontFamily: 'CwMono',
            fontSize: ch.length > 1 ? r * 0.85 : r * 1.15,
            fontWeight: FontWeight.bold,
            color: on ? c.background : charTypeColor(ch, c),
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.path != path || old.lit != lit || old.sounding != sounding ||
      old.geo.size != geo.size || old.geo.maxDepth != geo.maxDepth ||
      old.c != c;
}
