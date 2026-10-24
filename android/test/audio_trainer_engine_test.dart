import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/audio_trainer_engine.dart';

/// Records what the engine did, in order, and lets the test script the content.
class _Rig {
  final log = <String>[];
  final contents = <String>[];
  var _next = 0;
  Completer<void>? morseGate;
  Completer<void>? voiceGate;
  late AudioTrainerEngine engine;

  _Rig({AudioTrainerConfig config = const AudioTrainerConfig()}) {
    engine = AudioTrainerEngine(
      config: config,
      nextContent: () async => contents[_next++ % contents.length],
      playMorse: (t) async {
        log.add('morse:$t');
        await (morseGate?.future ?? _settle());
      },
      stopMorse: () async => log.add('stopMorse'),
      playVoice: (c) async {
        log.add('voice:$c');
        await (voiceGate?.future ?? _settle());
      },
      stopVoice: () async => log.add('stopVoice'),
      delay: (d) async {
        log.add('wait:${d.inMilliseconds}');
        await _settle(); // a real timer turn, so the loop never starves the event queue
      },
    );
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Lets the engine run until [cond] holds (bounded, so a bug fails, not hangs).
Future<void> _until(bool Function() cond) async {
  for (var i = 0; i < 50 && !cond(); i++) {
    await _settle();
  }
}

void main() {
  group('audioTrainerGroup', () {
    test('upper-cases and keeps letters and digits', () {
      expect(audioTrainerGroup('ab3z'), 'AB3Z');
    });
    test('drops punctuation, prosigns and unknown characters', () {
      expect(audioTrainerGroup('a.b,<KA>c/ä'), 'ABC');
    });
    test('empty when nothing speakable is left', () {
      expect(audioTrainerGroup('.,?<SK>'), '');
    });
  });

  test('sample names match the files written by make_voice_samples.py', () {
    expect(voiceSampleName('kristin', 'A'), 'voice_kristin_a');
    expect(voiceSampleName('bryce', '7'), 'voice_bryce_7');
    expect(audioTrainerVoices, ['kristin', 'bryce']);
  });

  test('each group: Morse, think pause, its voices, pause, then the next', () async {
    final r = _Rig(
        config: const AudioTrainerConfig(
            thinkPause: Duration(milliseconds: 4000),
            voiceGap: Duration(milliseconds: 500),
            groupPause: Duration(milliseconds: 3000)));
    r.contents.addAll(['ab', 'c1']);
    final done = r.engine.run();
    // stop as the third group is drawn, i.e. after two complete groups
    r.engine.state.addListener(() {
      if (r.engine.state.value.groupsDone == 2) r.engine.stop();
    });
    await done;
    expect(r.log.take(11).toList(), [
      'morse:AB',
      'wait:4000',
      'voice:A', 'wait:500', 'voice:B',
      'wait:3000',
      'morse:C1',
      'wait:4000',
      'voice:C', 'wait:500', 'voice:1',
    ]);
    // groupsDone == 2 stops the run before the second pause
    expect(r.log, contains('stopMorse'));
    expect(r.engine.state.value.phase, AudioTrainerPhase.idle);
    expect(r.engine.state.value.groupsDone, 2);
  });

  test('the run ends by itself after maxGroups, without a last pause', () async {
    final r = _Rig(
        config: const AudioTrainerConfig(
            maxGroups: 2,
            thinkPause: Duration(milliseconds: 4000),
            groupPause: Duration(milliseconds: 3000)));
    r.contents.addAll(['a', 'b']);
    await r.engine.run();
    expect(r.log.where((l) => l.startsWith('morse:')).toList(), ['morse:A', 'morse:B']);
    // one pause between the two groups, none after the last
    expect(r.log.where((l) => l == 'wait:3000').length, 1);
    expect(r.engine.state.value.finished, isTrue);
    expect(r.engine.state.value.groupsDone, 2);
    expect(r.engine.state.value.phase, AudioTrainerPhase.idle);
    expect(r.engine.running, isFalse);
  });

  test('maxGroups 0 runs until stopped', () async {
    final r = _Rig(config: const AudioTrainerConfig());
    r.contents.add('a');
    final done = r.engine.run();
    await _until(() => r.engine.state.value.groupsDone >= 3);
    expect(r.engine.running, isTrue);
    expect(r.engine.state.value.finished, isFalse);
    await r.engine.stop();
    await done;
  });

  test('groups without speakable characters are drawn again', () async {
    final r = _Rig();
    r.contents.addAll(['.,', '<SK>', 'q']);
    final done = r.engine.run();
    await _settle();
    await r.engine.stop();
    await done;
    expect(r.log.first, 'morse:Q');
  });

  test('gives up with an error when nothing speakable can be drawn', () async {
    final r = _Rig();
    r.contents.add('...');
    expect(r.engine.run(), throwsStateError);
  });

  test('state follows the phases and the spoken character', () async {
    final r = _Rig();
    r.contents.addAll(['ab', 'cd']);
    r.morseGate = Completer<void>();
    final seen = <AudioTrainerPhase>[];
    r.engine.state.addListener(() {
      final p = r.engine.state.value.phase;
      if (seen.isEmpty || seen.last != p) seen.add(p);
    });
    final done = r.engine.run();
    await _settle();
    expect(r.engine.state.value.phase, AudioTrainerPhase.morse);
    expect(r.engine.state.value.group, 'AB');
    r.voiceGate = Completer<void>();
    r.morseGate!.complete();
    await _until(() => r.engine.state.value.solutionChar == 0);
    expect(r.engine.state.value.phase, AudioTrainerPhase.solution);
    expect(r.engine.state.value.solutionChar, 0);
    await r.engine.stop();
    await done;
    expect(seen.take(3).toList(),
        [AudioTrainerPhase.morse, AudioTrainerPhase.think, AudioTrainerPhase.solution]);
  });

  test('stop ends a Morse that never reports completion', () async {
    final r = _Rig();
    r.contents.add('ab');
    r.morseGate = Completer<void>(); // never completed
    final done = r.engine.run();
    await _settle();
    await r.engine.stop();
    await done;
    expect(r.log, contains('stopMorse'));
    expect(r.engine.running, isFalse);
    expect(r.engine.state.value.phase, AudioTrainerPhase.idle);
  });

  test('pause holds the flow at the next step, resume continues', () async {
    final r = _Rig();
    r.contents.add('ab');
    r.voiceGate = Completer<void>();
    final done = r.engine.run();
    await _until(() => r.log.contains('voice:A'));
    expect(r.log, contains('voice:A'));
    r.engine.pause();
    expect(r.engine.state.value.paused, isTrue);
    r.voiceGate!.complete();
    await _settle();
    await _settle();
    await _settle();
    expect(r.log.contains('voice:B'), isFalse); // held before the second voice
    r.voiceGate = null;
    r.engine.resume();
    await _until(() => r.log.contains('voice:B'));
    expect(r.log, contains('voice:B'));
    await r.engine.stop();
    await done;
  });

  test('stop while paused ends the run', () async {
    final r = _Rig();
    r.contents.add('ab');
    final done = r.engine.run();
    await _settle();
    r.engine.pause();
    await _settle();
    await r.engine.stop();
    await done;
    expect(r.engine.running, isFalse);
    expect(r.engine.state.value.paused, isFalse);
  });
}
