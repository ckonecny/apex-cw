// Licence guard (CLAUDE.md rule 11, DECISIONS.md "Licence: GPL-3.0").
// The app is GPL-3.0-or-later, so everything it ships must be compatible.
// These tests fail when something new arrives whose licence hasn't been
// checked: a pub package with an unknown or incompatible licence, a file
// under assets/ that no registered licence covers, or a Gradle library.
// A failure is a stop sign, not a chore: check the licence first, and if it
// is incompatible, don't use the thing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/licenses.dart';

// Licences that may be combined with GPL-3.0-or-later.
const _compatible = <String, List<String>>{
  'MIT': ['Permission is hereby granted, free of charge'],
  'BSD': ['Redistribution and use in source and binary forms'],
  'Apache-2.0': ['Apache License', 'Version 2.0'],
  'zlib': ["provided 'as-is'", 'Permission is granted to anyone to use this software'],
  'ISC': ['Permission to use, copy, modify, and/or distribute this software'],
  'MPL-2.0': ['Mozilla Public License Version 2.0'],
  'LGPL': ['GNU LESSER GENERAL PUBLIC LICENSE'],
  'GPL-3.0': ['GNU GENERAL PUBLIC LICENSE', 'Version 3'],
  'OFL-1.1': ['SIL OPEN FONT LICENSE', 'Version 1.1'],
  'Unlicense': ['This is free and unencumbered software released into the public domain'],
};

// Phrases of licences that are not GPL-compatible (non-commercial,
// source-available, "Good, not Evil", ...). Matched case-insensitively.
const _incompatible = <String>[
  'commons clause',
  'business source license',
  'server side public license',
  'elastic license',
  'noncommercial',
  'non-commercial',
  'shall be used for good, not evil',
  'creative commons attribution-noderivatives',
];

// Every file under assets/ must fall under one of these prefixes; each maps
// to the licence entry registered in lib/licenses.dart.
const _assetLicences = <String, String>{
  'assets/zork/': 'Zork I–III',
  'assets/fonts/AnonymousPro': 'Anonymous Pro (font)',
  'assets/fonts/OFL-AnonymousPro.txt': 'Anonymous Pro (font)',
  'assets/fonts/DMSans': 'DM Sans (font)',
  'assets/fonts/OFL-DMSans.txt': 'DM Sans (font)',
  'assets/licenses/GPL-3.0.txt': 'Next CW Trainer',
};

// Gradle libraries (implementation/api/...) that have been licence-checked.
// Currently none: the native side uses only the Android SDK/NDK.
const _gradleAllowed = <String>{};

Map<String, Directory> _packages() {
  final cfgFile = File('.dart_tool/package_config.json');
  final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
  final base = cfgFile.absolute.uri;
  return {
    for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>())
      if (p['name'] != 'next_cw_trainer')
        p['name'] as String:
            Directory(base.resolve(p['rootUri'] as String).toFilePath()),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every pub package has a GPL-3.0-compatible licence', () {
    final problems = <String>[];
    _packages().forEach((name, dir) {
      // Packages inside the Flutter SDK (flutter_test, ...) have no LICENSE
      // of their own; the SDK's LICENSE two levels up covers them.
      var f = File('${dir.path}/LICENSE');
      final sdk = File('${dir.parent.parent.path}/LICENSE');
      if (!f.existsSync() &&
          File('${dir.parent.parent.path}/bin/flutter').existsSync()) {
        f = sdk;
      }
      if (!f.existsSync()) {
        problems.add('$name: no LICENSE file');
        return;
      }
      final text = f.readAsStringSync();
      final lower = text.toLowerCase();
      final bad = _incompatible.where(lower.contains).toList();
      final good = _compatible.entries
          .where((e) => e.value.every((s) => lower.contains(s.toLowerCase())))
          .map((e) => e.key)
          .toList();
      if (bad.isNotEmpty) problems.add('$name: incompatible terms $bad');
      if (good.isEmpty) problems.add('$name: licence not recognised');
    });
    expect(problems, isEmpty,
        reason: 'Check these licences against GPL-3.0-or-later before use '
            '(CLAUDE.md rule 11).');
  });

  test('every asset file is covered by a registered licence', () async {
    final files = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => !p.endsWith('.DS_Store'));
    final uncovered = [
      for (final p in files)
        if (!_assetLicences.keys.any(p.startsWith)) p,
    ];
    expect(uncovered, isEmpty,
        reason: 'New asset: check its licence, register it in '
            'lib/licenses.dart and add it to _assetLicences.');

    registerAppLicenses();
    final registered = (await LicenseRegistry.licenses.toList())
        .expand((e) => e.packages)
        .toSet();
    expect(registered, containsAll(_assetLicences.values.toSet()));
  });

  test('Gradle libraries are licence-checked', () {
    final dep = RegExp(
        r'''^\s*(implementation|api|runtimeOnly|compileOnly)\s*\(\s*["']([^"']+)["']''',
        multiLine: true);
    final found = <String>{
      for (final f in [
        'android/app/build.gradle.kts',
        'android/build.gradle.kts',
      ])
        if (File(f).existsSync())
          for (final m in dep.allMatches(File(f).readAsStringSync())) m.group(2)!,
    };
    expect(found.difference(_gradleAllowed), isEmpty,
        reason: 'New Gradle library: check its licence, then add it to '
            '_gradleAllowed.');
  });
}
