import 'dart:async';

import '../keyer/channels.dart';

/// The native settings event channel (paddle learning, key diagnostics, audio
/// route) as one shared broadcast stream. An EventChannel has a single native
/// sink, so two widgets listening on it directly would cancel each other; the
/// settings screen and the audio output card listen here instead.
class SettingsEvents {
  SettingsEvents._();

  static const _channel = Channels.settingsEvents;
  static StreamSubscription? _native;
  static final StreamController<Map> _out = StreamController<Map>.broadcast(
    onListen: () => _native = _channel
        .receiveBroadcastStream()
        .listen((e) => _out.add(e as Map)),
    onCancel: () {
      _native?.cancel();
      _native = null;
    },
  );

  /// Events as maps with 'type' and 'value' (both strings).
  static Stream<Map> get stream => _out.stream;
}
