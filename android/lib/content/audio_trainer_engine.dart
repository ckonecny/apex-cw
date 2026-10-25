import 'dart:async';

import 'package:flutter/foundation.dart';

// Audio trainer (issue #139): the app plays one character group in Morse, the
// user only thinks it, and after a pause the app speaks the spelling-alphabet
// word of every character in the order it was sent; then the next group
// follows. Nothing is typed or graded, so there are no statistics.
//
// UI-free: Morse, voice samples, content and waiting are injected, so the
// whole flow (including pause and stop) is unit-testable without audio.

/// Punctuation and operator characters that have a voice sample, with the
/// word spoken and the sample's file-name key (`voice_kristin_question`).
/// Prosigns and other characters have none.
const audioTrainerSymbols = {
  '.': 'period',
  ',': 'comma',
  ':': 'colon',
  '-': 'dash',
  '/': 'slash',
  '=': 'equals',
  '?': 'question',
  '@': 'at',
  '+': 'plus',
};

/// Characters that have a voice sample: a-z, 0-9 and [audioTrainerSymbols].
final _sampleChar = RegExp(r'^[A-Z0-9.,:\-/=?@+]$');
final _prosign = RegExp(r'<[A-Za-z]{2}>');

/// A generated group reduced to what can be spoken afterwards: upper case,
/// prosigns and characters without a sample dropped. Empty = unusable.
String audioTrainerGroup(String raw) => raw
    .replaceAll(_prosign, '')
    .toUpperCase()
    .split('')
    .where(_sampleChar.hasMatch)
    .join();

/// Android raw resource name of a voice sample: `voice_kristin_a`.
String voiceSampleName(String voice, String char) =>
    'voice_${voice}_${audioTrainerSymbols[char] ?? char.toLowerCase()}';

/// The voices shipped in `res/raw` (see `tools/make_voice_samples.py`).
const audioTrainerVoices = ['kristin', 'bryce'];

class AudioTrainerConfig {
  /// Silence after the last Morse character before the solution starts.
  final Duration thinkPause;

  /// Silence between two spoken characters of the solution.
  final Duration voiceGap;

  /// Silence after the solution before the next group.
  final Duration groupPause;

  /// Groups per block: the run ends after this many. 0 = until stopped.
  final int maxGroups;

  const AudioTrainerConfig({
    this.maxGroups = 0,
    this.thinkPause = const Duration(seconds: 4),
    this.voiceGap = const Duration(milliseconds: 500),
    this.groupPause = const Duration(seconds: 3),
  });
}

enum AudioTrainerPhase { idle, morse, think, solution, rest }

class AudioTrainerState {
  final AudioTrainerPhase phase;

  /// Groups finished so far (the running one is not counted).
  final int groupsDone;

  /// The current group, empty before the first one.
  final String group;

  /// Which character the solution is speaking, -1 outside it.
  final int solutionChar;
  final bool paused;

  /// The block is complete ([AudioTrainerConfig.maxGroups] reached).
  final bool finished;

  const AudioTrainerState({
    this.phase = AudioTrainerPhase.idle,
    this.groupsDone = 0,
    this.group = '',
    this.solutionChar = -1,
    this.paused = false,
    this.finished = false,
  });

  AudioTrainerState copyWith({
    AudioTrainerPhase? phase,
    int? groupsDone,
    String? group,
    int? solutionChar,
    bool? paused,
    bool? finished,
  }) => AudioTrainerState(
    phase: phase ?? this.phase,
    groupsDone: groupsDone ?? this.groupsDone,
    group: group ?? this.group,
    solutionChar: solutionChar ?? this.solutionChar,
    paused: paused ?? this.paused,
    finished: finished ?? this.finished,
  );
}

class _Stopped implements Exception {
  const _Stopped();
}

/// The running group is cut short ([AudioTrainerEngine.skipGroup] /
/// [AudioTrainerEngine.repeatGroup]).
class _Jumped implements Exception {
  final bool repeat;
  const _Jumped(this.repeat);
}

class AudioTrainerEngine {
  /// One raw group from the native generator (`getNextContent`).
  final Future<String> Function() nextContent;

  /// Plays text in Morse and completes when the sound has ended.
  final Future<void> Function(String text) playMorse;

  /// Aborts a running [playMorse].
  final Future<void> Function() stopMorse;

  /// Speaks the sample of one character and completes when it has ended.
  final Future<void> Function(String char) playVoice;

  /// Aborts a running [playVoice].
  final Future<void> Function() stopVoice;

  /// Waiting; replaceable in tests.
  final Future<void> Function(Duration) delay;

  AudioTrainerConfig config;

  /// Draws per group before giving up on getting a speakable one.
  static const maxDraws = 20;

  final state = ValueNotifier(const AudioTrainerState());

  bool _stopRequested = false;
  bool _running = false;
  Completer<void>? _resume;
  Completer<void> _stopSig = Completer<void>();
  Completer<void> _jumpSig = Completer<void>();
  bool _jumpRepeat = false;

  AudioTrainerEngine({
    required this.nextContent,
    required this.playMorse,
    required this.stopMorse,
    required this.playVoice,
    required this.stopVoice,
    this.config = const AudioTrainerConfig(),
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;

  bool get running => _running;

  void _set(AudioTrainerState s) => state.value = s;
  void _update(AudioTrainerState Function(AudioTrainerState) f) =>
      state.value = f(state.value);

  /// Runs group after group until [stop] or until the block is complete. Completes when stopped.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    _stopRequested = false;
    _stopSig = Completer<void>();
    _jumpSig = Completer<void>();
    _set(const AudioTrainerState());
    String? again;
    try {
      while (true) {
        try {
          if (!await _cycle(again)) break;
          again = null;
        } on _Jumped catch (j) {
          // Cut short from outside: next group, or the same one once more.
          again = j.repeat ? state.value.group : null;
          _jumpSig = Completer<void>();
        }
      }
    } on _Stopped {
      // normal end
    } finally {
      _running = false;
      _resume = null;
      _set(
        state.value.copyWith(
          phase: AudioTrainerPhase.idle,
          solutionChar: -1,
          paused: false,
        ),
      );
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    _resume?.complete();
    if (!_stopSig.isCompleted) _stopSig.complete();
    await stopMorse();
    await stopVoice();
  }

  /// Ends the running group at once and goes on with a new one (headset
  /// "next"). Resumes a paused run.
  Future<void> skipGroup() => _jump(false);

  /// Ends the running group at once and plays the same group again (headset
  /// "previous"). Resumes a paused run.
  Future<void> repeatGroup() => _jump(true);

  Future<void> _jump(bool repeat) async {
    if (!_running || _stopRequested || _jumpSig.isCompleted) return;
    _jumpRepeat = repeat;
    _jumpSig.complete();
    if (state.value.paused) resume();
    await stopMorse();
    await stopVoice();
  }

  /// Holds the flow at the next step boundary (a running sound ends first).
  void pause() {
    if (!_running || state.value.paused) return;
    _resume = Completer<void>();
    _update((s) => s.copyWith(paused: true));
  }

  void resume() {
    if (!state.value.paused) return;
    _update((s) => s.copyWith(paused: false));
    _resume?.complete();
    _resume = null;
  }

  Future<void> _step() async {
    if (_stopRequested) throw const _Stopped();
    final r = _resume;
    if (r != null) {
      await r.future;
      if (_stopRequested) throw const _Stopped();
    }
  }

  /// Awaits [f], or ends the run as soon as [stop] is called (a stopped
  /// native sound may never report completion).
  Future<void> _guard(Future<void> f) async {
    await Future.any([f, _stopSig.future, _jumpSig.future]);
    if (_stopRequested) throw const _Stopped();
    if (_jumpSig.isCompleted) throw _Jumped(_jumpRepeat);
  }

  Future<void> _wait(Duration d) async {
    await _step();
    if (d > Duration.zero) await _guard(delay(d));
    await _step();
  }

  Future<String> _drawGroup() async {
    String g = '';
    for (var i = 0; i < maxDraws && g.isEmpty; i++) {
      await _step();
      await _guard(nextContent().then((t) => g = audioTrainerGroup(t)));
    }
    if (g.isEmpty) throw StateError('no speakable group after $maxDraws draws');
    return g;
  }

  /// One group: Morse, thinking pause, solution, pause. False once the block
  /// is complete.
  Future<bool> _cycle(String? again) async {
    final group = again ?? await _drawGroup();
    _update(
      (s) => s.copyWith(
        phase: AudioTrainerPhase.morse,
        group: group,
        solutionChar: -1,
      ),
    );
    await _step();
    await _guard(playMorse(group));

    _update((s) => s.copyWith(phase: AudioTrainerPhase.think));
    await _wait(config.thinkPause);

    _update((s) => s.copyWith(phase: AudioTrainerPhase.solution));
    for (var c = 0; c < group.length; c++) {
      if (c > 0) await _wait(config.voiceGap);
      await _step();
      _update((s) => s.copyWith(solutionChar: c));
      await _guard(playVoice(group[c]));
    }

    final done = state.value.groupsDone + 1;
    if (config.maxGroups > 0 && done >= config.maxGroups) {
      _update(
        (s) => s.copyWith(
          phase: AudioTrainerPhase.rest,
          groupsDone: done,
          solutionChar: -1,
          finished: true,
        ),
      );
      return false;
    }
    _update(
      (s) => s.copyWith(
        phase: AudioTrainerPhase.rest,
        groupsDone: done,
        solutionChar: -1,
      ),
    );
    await _wait(config.groupPause);
    return true;
  }
}
