import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/content/cw_content.dart';
import 'package:next_cw_trainer/ui/adaptive_copy_body.dart';

// The parent (GeneratorScreen) builds the body with default kochLevel 5 and
// only then loads the real level; the idle weak-char panel must follow.
Widget _body(int level) => MaterialApp(
      home: Scaffold(
        body: AdaptiveCopyBody(
          kochLevel: level,
          activeKochChars: kochActiveChars(level),
          contentModeIndex: 0,
          contentModeOrdinals: const [0],
          contentModeLabels: const ['Random'],
          wpm: 20,
          groupLength: 5,
          maxWords: 0,
          abbrevLengthMax: 0,
          interCharSpace: 3,
          interWordSpace: 7,
        ),
      ),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

void main() {
  testWidgets('weak chars beyond the initial level appear once the level arrives', (t) async {
    Map<String, dynamic> weak(double ema) => {'a': 20, 'e': 6, 'ema': ema, 'lb': 1, 'w': 5};
    SharedPreferences.setMockInitialValues({
      'charStats.hear': jsonEncode({'U': weak(0.31), 'Y': weak(0.26)}),
    });
    await t.pumpWidget(_body(5));
    await _settle(t);
    expect(find.textContaining('31%'), findsOneWidget);
    expect(find.textContaining('26%'), findsNothing);

    await t.pumpWidget(_body(27));
    await _settle(t);
    expect(find.textContaining('31%'), findsOneWidget);
    expect(find.textContaining('26%'), findsOneWidget);
  });
}
