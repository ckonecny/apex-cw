// The platform channels to the native side (MainActivity.kt and the plugins
// it registers), defined once (#18). Screens use these instead of spelling
// the channel name: a typo in a name compiles and then silently goes nowhere.
import 'package:flutter/services.dart';

const _p = 'at.oe1cko.nextcwtrainer';

abstract final class Channels {
  // ── Method channels: Dart → native ──
  /// Tone engine: pitch, envelope, volume, interference, effects, voice.
  static const tone = MethodChannel('$_p/cw_tone');
  /// CwGenerator: speed, spacing, content, playback (shared singleton).
  static const generator = MethodChannel('$_p/cw_generator');
  /// CwKeyer: speed, mode, timing, start/stop (shared singleton).
  static const keyer = MethodChannel('$_p/cw_keyer');
  /// App-wide native settings, keep-screen-on, key adapter, diagnostics.
  static const settings = MethodChannel('$_p/settings');
  static const ownPlayback = MethodChannel('$_p/own_playback');
  static const mic = MethodChannel('$_p/cw_mic');
  static const reminder = MethodChannel('$_p/reminder');
  static const share = MethodChannel('$_p/share');
  static const shortcuts = MethodChannel('$_p/shortcuts');

  // ── Event channels: native → Dart ──
  /// Decoded keyer symbols.
  static const symbols = EventChannel('$_p/cw_symbols');
  /// Generator events (element, character, word, done).
  static const genEvents = EventChannel('$_p/cw_gen_events');
  /// Measured speed of a straight key.
  static const straightWpm = EventChannel('$_p/cw_straight_wpm');
  /// Straight-key edges (timing analysis).
  static const straightEdges = EventChannel('$_p/cw_straight_edges');
  static const settingsEvents = EventChannel('$_p/settings_events');
  static const keyAdapterEvents = EventChannel('$_p/key_adapter_events');
  static const micPcm = EventChannel('$_p/cw_mic_pcm');
  static const audioRouteEvents = EventChannel('$_p/audio_route_events');
  static const ownPlaybackEvents = EventChannel('$_p/own_playback_events');
}
