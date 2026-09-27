import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../keyer/morse_decoder.dart';
import '../../theme/app_colors.dart';
import '../../util/char_color.dart';

const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
// One shared stream for the tile, playCharThrice() and the character practice
// screen: a second receiveBroadcastStream() call on the same channel replaces
// the first one's platform message handler, so the tile would stop getting
// events.
final Stream<dynamic> cwGenEvents = const EventChannel(
  'at.oe1cko.nextcwtrainer/cw_gen_events',
).receiveBroadcastStream();

// char → dit/dah pattern, the inverse of the decoder's table.
final Map<String, String> _patterns = {
  for (final e in MorseDecoder.table.entries) e.value: e.key,
};

/// Dit/dah pattern ('.'/'-') of a single character, '' if unknown.
String morsePattern(String ch) => _patterns[ch.toUpperCase()] ?? '';

/// Tap on a Koch character in Hören or Geben (Sia's suggestion, 2026-09-27):
/// dims the screen and shows a tile with the character and its code. Each
/// element lights up while it sounds, driven by the generator's
/// elementOn/elementOff events so the display cannot drift from the audio;
/// every repetition starts again from grey. The tile closes itself after
/// [play] completes; a tap anywhere cancels playback and closes it at once.
/// Long press opens the echo drill instead (caller).
Future<void> showCharPlayback(
  BuildContext context, {
  required String ch,
  required int outputCase,
  required Future<void> Function() play,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) =>
        _CharPlaybackTile(ch: ch, outputCase: outputCase, play: play),
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _CharPlaybackTile extends StatefulWidget {
  final String ch;
  final int outputCase;
  final Future<void> Function() play;
  const _CharPlaybackTile({
    required this.ch,
    required this.outputCase,
    required this.play,
  });

  @override
  State<_CharPlaybackTile> createState() => _CharPlaybackTileState();
}

class _CharPlaybackTileState extends State<_CharPlaybackTile> {
  StreamSubscription? _sub;
  int _lit = 0; // elements 0.._lit-1 have sounded (or are sounding)
  bool _sounding = false;

  String get _pattern => morsePattern(widget.ch);

  @override
  void initState() {
    super.initState();
    _sub = cwGenEvents.listen((raw) {
      final ev = raw as Map;
      if (!mounted) return;
      switch (ev['type']) {
        case 'elementOn':
          final idx = int.parse(ev['value'] as String);
          // Element 0 marks a new repetition: back to grey.
          setState(() {
            _lit = idx + 1;
            _sounding = true;
          });
        case 'elementOff':
          setState(() => _sounding = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.play();
      } finally {
        if (!_cancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shown = widget.outputCase == 1
        ? widget.ch.toUpperCase()
        : widget.ch.toLowerCase();
    final pattern = _pattern;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelCharPlayback();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _cancelCharPlayback,
        child: Center(
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(minWidth: 220),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shown,
                    style: TextStyle(
                      fontFamily: 'CwMono',
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: charTypeColor(widget.ch, c),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MorseElementRow(
                    pattern: pattern,
                    lit: _lit,
                    sounding: _sounding,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A character's code as dits and dahs. Elements 0..[lit]-1 are drawn in
/// [color] (accent by default), the rest grey; with [sounding] the last lit
/// one glows (it is playing right now).
class MorseElementRow extends StatelessWidget {
  final String pattern;
  final int lit;
  final bool sounding;
  final Color? color;
  const MorseElementRow({
    super.key,
    required this.pattern,
    required this.lit,
    this.sounding = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pattern.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _Element(
            dah: pattern[i] == '-',
            lit: i < lit,
            sounding: sounding && i == lit - 1,
            color: color ?? c.accent,
            off: c.border,
          ),
        ],
      ],
    );
  }
}

class _Element extends StatelessWidget {
  final bool dah, lit, sounding;
  final Color color, off;
  const _Element({
    required this.dah,
    required this.lit,
    required this.sounding,
    required this.color,
    required this.off,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 40),
      width: dah ? 42 : 14,
      height: 14,
      decoration: BoxDecoration(
        color: lit ? color : off,
        borderRadius: BorderRadius.circular(7),
        boxShadow: sounding
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

// Cancellation of the running playCharThrice(): only one tile is ever open,
// so module-level state is enough. _wake ends whichever wait is pending
// (a play's 'done' or the gap between repetitions).
bool _cancelled = false;
Completer<void>? _wake;

void _cancelCharPlayback() {
  if (_cancelled) return;
  _cancelled = true;
  // stopOne, not stop: the latter also restarts the keyer.
  _genChannel.invokeMethod('stopOne');
  if (_wake != null && !_wake!.isCompleted) _wake!.complete();
}

/// Plays [ch] three times in a row at [wpm], separated by the configured
/// inter-word space. Waits for each play's 'done' event on the shared
/// generator (rule 2: wpm/spacing are pushed here, nothing is assumed).
Future<void> playCharThrice(
  String ch, {
  required int wpm,
  required int interWordSpace,
}) async {
  _cancelled = false;
  await _genChannel.invokeMethod('setWpm', wpm);
  await _genChannel.invokeMethod('setInterWordSpace', interWordSpace);
  final gapMs = (1200 / wpm * interWordSpace).round();
  final sub = cwGenEvents.listen((raw) {
    if ((raw as Map)['type'] == 'done' && _wake != null && !_wake!.isCompleted) {
      _wake!.complete();
    }
  });
  try {
    for (var i = 0; i < 3 && !_cancelled; i++) {
      _wake = Completer<void>();
      await _genChannel.invokeMethod('playOne', ch.toUpperCase());
      await _wake!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      if (i < 2 && !_cancelled) {
        _wake = Completer<void>();
        await _wake!.future.timeout(
          Duration(milliseconds: gapMs),
          onTimeout: () {},
        );
      }
    }
  } finally {
    _wake = null;
    await sub.cancel();
  }
}
