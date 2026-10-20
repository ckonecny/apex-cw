// Own texts in the background (issues #21, #22): talks to the Android
// foreground service (OwnTextPlaybackService.kt) that keeps the player alive
// with the screen off and shows lock-screen / notification / headset controls.
// Only the own-texts player uses this; the sound itself still comes from the
// shared generator.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

class OwnTextPlayback {
  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/own_playback');
  static const _events = EventChannel('at.oe1cko.nextcwtrainer/own_playback_events');
  static const _reminder = MethodChannel('at.oe1cko.nextcwtrainer/reminder');

  /// Buttons from the lock screen, notification and headset:
  /// "play", "pause", "next" (next sentence), "prev" (previous sentence).
  static Stream<String> get commands => _events.receiveBroadcastStream().cast<String>();

  /// Without the notification permission (Android 13+) the player still runs
  /// in the background, but shows no controls; asked only once.
  static Future<void> ensureNotificationPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('own.notifAsked') == true) return;
      await prefs.setBool('own.notifAsked', true);
      if (await _reminder.invokeMethod<bool>('hasPermission') != true) {
        await _reminder.invokeMethod('requestPermission');
      }
    } catch (_) {}
  }

  static Future<void> update({required String title, required bool playing}) async {
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'playing': playing,
        'channel': Strings.t('ot_bg_channel'),
        'play': Strings.t('ot_bg_play'),
        'pause': Strings.t('ot_bg_pause'),
        'next': Strings.t('ot_bg_next'),
        'prev': Strings.t('ot_bg_prev'),
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
