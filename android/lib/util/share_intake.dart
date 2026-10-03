import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/own_texts_screen.dart';

/// Text shared into the app from another app's Share menu (issue #24). Native
/// code (MainActivity.kt) holds the text; this takes it, on start and
/// whenever a new share arrives while the app is running, and opens Own texts
/// with the import dialog.
class ShareIntake {
  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/share');
  static final navigatorKey = GlobalKey<NavigatorState>();

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await _take();
    });
    // The navigator exists only after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _take());
  }

  static Future<void> _take() async {
    final text = await _channel.invokeMethod<String>('take');
    final nav = navigatorKey.currentState;
    if (text == null || nav == null) return;
    // Back to Home first, so no training screen keeps running underneath.
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => OwnTextsScreen(sharedText: text)),
      (r) => r.isFirst,
    );
  }
}
