// Own texts and the audio trainer in the background (issues #21, #22, #140):
// talks to the Android foreground service (OwnTextPlaybackService.kt) that
// keeps the player alive with the screen off and shows lock-screen /
// notification / headset controls. Only one of the two screens runs at a time;
// the sound itself still comes from the shared generator.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

class OwnTextPlayback {
  static const _channel = MethodChannel('at.oe1cko.nextcwtrainer/own_playback');
  static const _events = EventChannel(
    'at.oe1cko.nextcwtrainer/own_playback_events',
  );
  static const _reminder = MethodChannel('at.oe1cko.nextcwtrainer/reminder');

  /// Buttons from the lock screen, notification and headset:
  /// "play", "pause", "next" (next sentence / group), "prev" (previous
  /// sentence / repeat the group); with [update]'s `tune` (audio trainer,
  /// #152) "tempo_down", "tempo_up", "gap_down", "gap_up" instead of next/prev.
  static Stream<String> get commands =>
      _events.receiveBroadcastStream().cast<String>();

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

  /// [labelPrefix] picks the notification texts (`ot_bg_*` own texts,
  /// `at_bg_*` audio trainer); [channelId] keeps each screen's notification
  /// channel apart in the system settings. [subtitle] replaces "APEX CW"
  /// under the title; [tune] swaps previous/next for tempo and spacing −/+.
  static Future<void> update({
    required String title,
    required bool playing,
    String labelPrefix = 'ot_bg',
    String channelId = 'own_text_playback',
    String subtitle = '',
    bool tune = false,
  }) async {
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'subtitle': subtitle,
        'tune': tune,
        'playing': playing,
        'channelId': channelId,
        'channel': Strings.t('${labelPrefix}_channel'),
        'play': Strings.t('ot_bg_play'),
        'pause': Strings.t('ot_bg_pause'),
        'next': Strings.t('${labelPrefix}_next'),
        'prev': Strings.t('${labelPrefix}_prev'),
        for (final a in ['tempo_down', 'tempo_up', 'gap_down', 'gap_up'])
          a: Strings.t('at_bg_$a'),
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
