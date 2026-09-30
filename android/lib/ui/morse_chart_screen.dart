import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/char_color.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart';

/// Interactive character chart: every character of MorseDecoder.table with
/// its code drawn as dots and dashes, grouped into letters, digits and signs.
/// Tapping a tile plays the character at the configured pitch; its elements
/// switch from inactive to active as they sound (generator elementOn/Off
/// events, as in the Morse tree and the tap tile in Hören). Own drawing, not
/// a copy of any published chart.
class MorseChartScreen extends StatefulWidget {
  const MorseChartScreen({super.key});

  @override
  State<MorseChartScreen> createState() => _MorseChartScreenState();
}

class _MorseChartScreenState extends State<MorseChartScreen> {
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  static final _letters =
      List.generate(26, (i) => String.fromCharCode(65 + i));
  static const _digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  static const _signs = ['.', ',', '?', '/', '-', '=', '+', '@', ':'];
  static const _prosigns = ['SK', 'KN', 'KA', 'AS', 'VE', 'BK'];

  // character -> code, from the same table the app plays and decodes with
  static final Map<String, String> _code = {
    for (final e in MorseDecoder.table.entries) e.value: e.key,
  };

  StreamSubscription? _sub;
  int _wpm = 20;
  int _pitch = 600;
  int _softness = 4;
  bool _ready = false;

  String _ch = '';         // character last tapped
  int _lit = 0;
  bool _sounding = false;

  @override
  void initState() {
    super.initState();
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
    await _toneChannel.invokeMethod('setFreq', _pitch).catchError((_) {});
    await _toneChannel
        .invokeMethod('setEnvelopeMs', (_softness + 1).toDouble())
        .catchError((_) {});
    await _genChannel.invokeMethod('setWpm', _wpm).catchError((_) {});
    _sub = cwGenEvents.listen(_onGenEvent);
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _sub?.cancel();
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

  Future<void> _play(String ch) async {
    if (!_ready) return;
    setState(() { _ch = ch; _lit = 0; _sounding = false; });
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

  Widget _section(AppColors c, String titleKey, List<String> chars) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 0, 8),
        child: Text(Strings.t(titleKey).toUpperCase(), style: TextStyle(
            fontFamily: 'CwMono', fontSize: 12, letterSpacing: 1.2,
            color: c.textMuted)),
      ),
      LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        // At least three per row; more when the screen is wide (landscape
        // is locked here, but a tablet or large font may still differ).
        final cols = (box.maxWidth / 104).floor().clamp(3, 8);
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final ch in chars)
            SizedBox(
              width: w,
              child: _ChartTile(
                ch: ch,
                pattern: _code[ch] ?? '',
                active: ch == _ch,
                lit: ch == _ch ? _lit : 0,
                sounding: ch == _ch && _sounding,
                onTap: () => _play(ch),
              ),
            ),
        ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('chart_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(Strings.t('chart_intro'), style: TextStyle(
                fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: _speed(c)),
            _section(c, 'chart_letters', _letters),
            _section(c, 'chart_digits', _digits),
            _section(c, 'chart_signs', _signs),
            _section(c, 'chart_prosigns', _prosigns),
          ],
        ),
      ),
    );
  }
}

class _ChartTile extends StatelessWidget {
  final String ch, pattern;
  final bool active, sounding;
  final int lit;
  final VoidCallback onTap;
  const _ChartTile({
    required this.ch,
    required this.pattern,
    required this.active,
    required this.lit,
    required this.sounding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = charTypeColor(ch, c);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? color : c.border, width: active ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            SizedBox(
              width: 30,
              child: Text(ch, textAlign: TextAlign.center, style: TextStyle(
                  fontFamily: 'CwMono',
                  fontSize: ch.length > 1 ? 15 : 24,
                  fontWeight: FontWeight.w700,
                  color: color)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _Bars(
                      pattern: pattern, lit: lit, sounding: sounding,
                      color: color, off: c.border),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The code as bars: a dit is a dot, a dah a long bar. Same look as the
/// element row of the tap tile, just smaller.
class _Bars extends StatelessWidget {
  final String pattern;
  final int lit;
  final bool sounding;
  final Color color, off;
  const _Bars({
    required this.pattern,
    required this.lit,
    required this.sounding,
    required this.color,
    required this.off,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < pattern.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 40),
          width: pattern[i] == '-' ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: i < lit ? color : off,
            borderRadius: BorderRadius.circular(3.5),
            boxShadow: sounding && i == lit - 1
                ? [BoxShadow(color: color.withValues(alpha: 0.6),
                    blurRadius: 8, spreadRadius: 1)]
                : null,
          ),
        ),
      ],
    ]);
  }
}
