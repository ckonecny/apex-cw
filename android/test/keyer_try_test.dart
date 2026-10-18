// KeyerTry (#116) pushes the general Send settings to the shared keyer before
// starting it (CLAUDE.md rule 2), so dit/dah on any screen sound like the
// user's answers.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/util/keyer_try.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start pushes mode, speed, pitch and softness, then starts the keyer', () async {
    SharedPreferences.setMockInitialValues({
      'keyerMode': 3,
      'pitch': 777,
      'toneSoftness': 2,
      'toneShift': 0,
      'acs': 2,
      'profile.echo.wpm': 23,
    });
    final calls = <String>[];
    for (final name in ['cw_keyer', 'cw_tone']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('at.oe1cko.nextcwtrainer/$name'), (call) async {
        calls.add('$name.${call.method}(${call.arguments is Map ? '' : call.arguments})');
        return null;
      });
    }
    await KeyerTry.start();
    expect(calls, containsAll([
      'cw_keyer.setMode(3)',
      'cw_keyer.setAcs(2)',
      'cw_tone.setFreq(777)',
      'cw_tone.setEnvelopeMs(3.0)',
      'cw_keyer.start(null)',
    ]));
    expect(calls.where((c) => c.startsWith('cw_keyer.setWpm')), hasLength(1));
    expect(calls.last, 'cw_keyer.start(null)');
  });
}
