// Layout at large system font sizes: the app caps the text scale at
// kMaxTextScale (main.dart), and the home screen must not overflow at any
// system setting (DECISIONS.md "System font size: capped at 1.3").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Pixel font-size steps, and two phone sizes (Pixel 7, small phone).
  for (final scale in [0.85, 1.0, 1.3, 1.5, 2.0]) {
    for (final size in [const Size(412, 915), const Size(360, 640)]) {
      testWidgets('home at font scale $scale, $size', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(const NextCwTrainerApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
