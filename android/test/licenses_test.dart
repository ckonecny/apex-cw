import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled GPL copy matches the repo LICENSE', () {
    expect(File('assets/licenses/GPL-3.0.txt').readAsStringSync(),
        File('../LICENSE').readAsStringSync());
  });

  test('app licences are registered and load', () async {
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, containsAll(['Next CW Trainer', 'Zork I–III',
        'Anonymous Pro (font)', 'Space Grotesk (font)']));
    final gpl = entries.firstWhere((e) => e.packages.contains('Next CW Trainer'));
    expect(gpl.paragraphs.map((p) => p.text).join('\n'),
        contains('GNU GENERAL PUBLIC LICENSE'));
  });
}
