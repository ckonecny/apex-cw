// Keyer and audio output on their own pages (shortcuts out of a training):
// they load and store the same settings as the sections in the settings list.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/settings_section_screens.dart';
import 'package:next_cw_trainer/util/settings_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final calls = <String>[];
  late MockStreamHandlerEventSink sink;

  setUp(() {
    calls.clear();
    Strings.lang.value = 1;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('at.oe1cko.nextcwtrainer/settings'), (c) async {
      calls.add('${c.method}(${c.arguments})');
      if (c.method == 'getOutputDeviceKinds') return {'preferred': 0, 'available': [0, 1, 3]};
      return null;
    });
    m.setMockStreamHandler(const EventChannel('at.oe1cko.nextcwtrainer/settings_events'),
        MockStreamHandler.inline(onListen: (_, s) {
          sink = s;
        }));
  });
  tearDown(() => Strings.lang.value = 0);

  testWidgets('keyer page shows the stored mode and stores a change', (t) async {
    SharedPreferences.setMockInitialValues({'keyerMode': 4, 'straightStartWpm': 22});
    await t.pumpWidget(const MaterialApp(home: KeyerSettingsScreen()));
    await t.pumpAndSettle();
    expect(find.text('Keyer'), findsOneWidget);
    expect(find.text('22 WPM'), findsOneWidget); // straight key: start speed
    await t.tap(find.text('Iambic B'));
    await t.pumpAndSettle();
    expect(calls, contains('setKeyerMode(1)'));
    expect((await SharedPreferences.getInstance()).getInt('keyerMode'), 1);
    expect(find.text('75%'), findsOneWidget); // CurtisB dit timing appears
  });

  testWidgets('audio page lists the outputs and follows the route event', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(const MaterialApp(home: AudioOutputScreen()));
    await t.pumpAndSettle();
    expect(find.text('Active: Speaker'), findsOneWidget);
    await t.runAsync(() async => sink.success({'type': 'audioRoute', 'value': 'Bluetooth'}));
    await t.pumpAndSettle();
    expect(find.text('Active: Bluetooth'), findsOneWidget);
    await t.tap(find.text('Bluetooth'));
    await t.pumpAndSettle();
    expect(calls, contains('setOutputDeviceKind(3)'));
  });

  test('two listeners share the one native event sink', () async {
    final a = <Map>[], b = <Map>[];
    final sa = SettingsEvents.stream.listen(a.add);
    final sb = SettingsEvents.stream.listen(b.add);
    await Future<void>.delayed(Duration.zero);
    sink.success({'type': 'keyDiag', 'value': 'x'});
    await Future<void>.delayed(Duration.zero);
    expect(a.length, 1);
    expect(b.length, 1);
    await sa.cancel();
    sink.success({'type': 'keyDiag', 'value': 'y'});
    await Future<void>.delayed(Duration.zero);
    expect(b.length, 2);
    await sb.cancel();
  });
}
