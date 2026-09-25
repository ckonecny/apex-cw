import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import '../../util/char_color.dart';

/// Shown when a Koch character is tapped in Hören or Geben: listen to it, or
/// practise it with the echo drill (docs/training/P7, decision 6).
Future<void> showCharActionsSheet(BuildContext context,
    {required String ch,
    required int outputCase,
    required VoidCallback onListen,
    required VoidCallback onEcho}) {
  final c = AppColors.of(context);
  final shown = outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(shown,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 32,
                  fontWeight: FontWeight.bold, color: charTypeColor(ch, c))),
        ),
        ListTile(
          leading: Icon(Icons.hearing, color: c.accent),
          title: Text(Strings.t('char_listen'),
              style: TextStyle(fontFamily: 'CwMono', color: c.textPrimary)),
          onTap: () { Navigator.pop(sheetContext); onListen(); },
        ),
        ListTile(
          leading: Icon(Icons.repeat, color: c.accentPurple),
          title: Text(Strings.t('char_echo_practice'),
              style: TextStyle(fontFamily: 'CwMono', color: c.textPrimary)),
          onTap: () { Navigator.pop(sheetContext); onEcho(); },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Plays [ch] three times in a row at [wpm], separated by the configured
/// inter-word space. Waits for each play's 'done' event on the shared
/// generator (rule 2: wpm/spacing are pushed here, nothing is assumed).
Future<void> playCharThrice(String ch, {required int wpm, required int interWordSpace}) async {
  const channel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  const events = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  await channel.invokeMethod('setWpm', wpm);
  await channel.invokeMethod('setInterWordSpace', interWordSpace);
  final gapMs = (1200 / wpm * interWordSpace).round();
  var done = Completer<void>();
  final sub = events.receiveBroadcastStream().listen((raw) {
    if ((raw as Map)['type'] == 'done' && !done.isCompleted) done.complete();
  });
  try {
    for (var i = 0; i < 3; i++) {
      done = Completer<void>();
      await channel.invokeMethod('playOne', ch.toUpperCase());
      await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
      if (i < 2) await Future.delayed(Duration(milliseconds: gapMs));
    }
  } finally {
    await sub.cancel();
  }
}
