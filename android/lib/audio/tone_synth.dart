// CW sidetone via native Android AudioTrack (USAGE_MEDIA, PCM float).
// MethodChannel calls are synchronous on the platform thread → <1 ms latency.

import 'package:flutter/services.dart';

class ToneSynth {
  static const _channel = MethodChannel('at.oe1wkl.morserino_mobile/cw_tone');

  int pitchHz;
  double volume;

  int lastOnsetLatencyMs = 0;
  bool _initialized = false;

  ToneSynth({this.pitchHz = 600, this.volume = 0.7});

  Future<void> init() async {
    if (_initialized) return;
    // The plugin is registered in MainActivity — just set initial params.
    await _channel.invokeMethod('setFreq', pitchHz);
    await _channel.invokeMethod('setVolume', volume);
    _initialized = true;
  }

  // Fire-and-forget: don't await — reduces Dart-side overhead.
  // The platform processes these on its own thread; the audio thread
  // picks up the flag change within the next chunk (~1.5 ms).
  void keyOn() {
    _channel.invokeMethod<void>('keyOn');
    lastOnsetLatencyMs = 0; // actual hw latency not measurable here
  }

  void keyOff() {
    _channel.invokeMethod<void>('keyOff');
  }

  void setPitch(int hz) {
    pitchHz = hz;
    _channel.invokeMethod('setFreq', hz);
  }

  void setVolume(double v) {
    volume = v;
    _channel.invokeMethod('setVolume', v);
  }

  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
    _initialized = false;
  }
}
