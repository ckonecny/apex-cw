import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../ui/audio_trainer_screen.dart';
import '../ui/decoder_screen.dart';
import '../ui/echo_trainer_screen.dart';
import '../ui/games_screen.dart';
import '../ui/generator_screen.dart';
import '../ui/home_screen.dart';
import '../ui/keyer_screen.dart';
import '../ui/morse_chart_screen.dart';
import '../ui/own_texts_screen.dart';
import 'share_intake.dart';

/// One launcher shortcut: its id (also what native code hands back), label,
/// icon (the same one as on the app's own card) and screen.
class AppShortcut {
  final String id;
  final String Function() label;
  final IconData icon;
  final Widget Function() screen;
  const AppShortcut(this.id, this.label, this.icon, this.screen);
}

/// Launcher shortcuts (long-press on the app icon, issue #151). Native code
/// (AppShortcuts.kt) publishes what this hands it and holds the id of a
/// tapped shortcut; this takes it, on start and whenever one is tapped while
/// the app is running, and opens that screen.
class AppShortcuts {
  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/shortcuts');

  /// Every shortcut on offer, in the default order. Which are published and
  /// in which order is the user's choice ([order], [off]; Settings → App
  /// shortcuts), since launchers show only the first four or five.
  static final all = <AppShortcut>[
    AppShortcut('hear', () => Strings.t('block_hear'), Icons.headphones,
        () => const GeneratorScreen()),
    AppShortcut('send', () => Strings.t('block_give'), Icons.keyboard,
        () => const EchoTrainerScreen()),
    AppShortcut('audio', () => Strings.t('at_title'),
        Icons.record_voice_over_outlined, () => const AudioTrainerScreen()),
    AppShortcut('keyer', () => 'CW Keyer', Icons.tune,
        () => const KeyerScreen()),
    AppShortcut('decoder', () => Strings.t('dec_title'), Icons.hearing,
        () => const DecoderScreen()),
    AppShortcut('owntexts', () => Strings.t('ot_title'),
        Icons.menu_book_outlined, () => const OwnTextsScreen()),
    AppShortcut('games', () => Strings.t('games_title'), Icons.sports_esports,
        () => const GamesScreen()),
    AppShortcut('chart', () => Strings.t('chart_title'),
        Icons.grid_view_rounded, () => const MorseChartScreen()),
  ];

  /// Off unless switched on: the default shows what fits every launcher.
  static const _defaultOn = {'hear', 'send', 'audio', 'keyer'};

  /// All shortcut ids in the user's order, and the ones switched off.
  static final order = ValueNotifier<List<String>>([for (final s in all) s.id]);
  static final off = ValueNotifier<Set<String>>(
      {for (final s in all) if (!_defaultOn.contains(s.id)) s.id});

  static const _kOrder = 'appShortcutOrder';
  static const _kOff = 'appShortcutOff';

  static AppShortcut? byId(String id) => all.where((s) => s.id == id).firstOrNull;

  /// The published shortcuts, in order.
  static List<AppShortcut> get active => [
        for (final id in order.value)
          if (!off.value.contains(id)) ?byId(id),
      ];

  /// Applies a stored choice: unknown ids are dropped, shortcuts added in a
  /// later version are appended (switched off unless on by default).
  static void applyStored(List<String>? storedOrder, List<String>? storedOff) {
    final known = {for (final s in all) s.id};
    final o = [...?storedOrder?.where(known.contains)];
    final newIds = [for (final s in all) if (!o.contains(s.id)) s.id];
    order.value = [...o, ...newIds];
    off.value = storedOff == null
        ? {for (final s in all) if (!_defaultOn.contains(s.id)) s.id}
        : {
            ...storedOff.where(known.contains),
            for (final id in newIds) if (!_defaultOn.contains(id)) id,
          };
  }

  static Future<void> setChoice(List<String> newOrder, Set<String> newOff) async {
    order.value = List.unmodifiable(newOrder);
    off.value = Set.unmodifiable(newOff);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kOrder, newOrder);
    await p.setStringList(_kOff, newOff.toList());
    await _publish();
  }

  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') await _take();
    });
    // The navigator exists only after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _take());
    final p = await SharedPreferences.getInstance();
    applyStored(p.getStringList(_kOrder), p.getStringList(_kOff));
    await _publish();
    Strings.lang.addListener(_publish);
  }

  static Future<void> _publish() async {
    final items = [
      for (final s in active)
        {'id': s.id, 'short': s.label(), 'long': s.label(), 'icon': await _icon(s.icon)},
    ];
    await _channel.invokeMethod('publish', items);
  }

  static Future<void> _take() async {
    final id = await _channel.invokeMethod<String>('take');
    final nav = ShareIntake.navigatorKey.currentState;
    if (id == null || nav == null) return;
    final s = byId(id);
    if (s == null) return;
    // Back to Home first, so no training screen keeps running underneath;
    // Home opens it so its cards refresh afterwards, as after a normal visit.
    nav.popUntil((r) => r.isFirst);
    final open = HomeScreen.open;
    if (open != null) {
      open(s.screen());
    } else {
      nav.push(MaterialPageRoute(builder: (_) => s.screen()));
    }
  }

  // Launcher colours, fixed so the icons match the navy app icon in any theme.
  static const _bg = Color(0xFF1C2540);
  static const _fg = Color(0xFF3ECAA8);

  /// The icon as an adaptive-icon PNG: full-bleed background, glyph inside
  /// the safe zone (the launcher masks the outer third away).
  static Future<Uint8List> _icon(IconData icon) async {
    const size = 288.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)
      ..drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = _bg);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size * 0.4,
          color: _fg,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }
}
