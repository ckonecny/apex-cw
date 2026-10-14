import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/widgets/setting_rows.dart';
import 'package:next_cw_trainer/ui/widgets/tempo_spacing_section.dart';

Widget _host({
  bool typing = false,
  bool compact = false,
  void Function(int, int)? onSpacing,
  int interChar = 19,
  int interWord = 39,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettingsCard(children: [
            TempoSpacingSection(
              wpm: 20,
              interChar: interChar,
              interWord: interWord,
              typing: typing,
              compact: compact,
              onWpm: (_) {},
              onSpacing: onSpacing ?? (_, _) {},
            ),
          ]),
        ),
      ),
    );

void main() {
  setUp(() => Strings.lang.value = 0);

  testWidgets('paper: both gaps, eff. counts both', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('Zeichenabstand'), findsOneWidget);
    expect(find.text('Wortabstand'), findsOneWidget);
    // 50 * 20 / (31 + 4 * 19 + 39) = 6.85 -> 7
    expect(find.text('20 WPM (eff. 7)'), findsOneWidget);
    expect(find.textContaining('Dits ·'), findsNWidgets(2));
  });

  testWidgets('typing: char gap only, eff. ignores the word gap', (tester) async {
    await tester.pumpWidget(_host(typing: true));
    expect(find.text('Zeichenabstand'), findsOneWidget);
    expect(find.text('Wortabstand'), findsNothing);
    // 50 * 20 / (31 + 4 * 19 + 7) = 8.77 -> 9
    expect(find.text('20 WPM (eff. 9)'), findsOneWidget);
  });

  testWidgets('compact drops the sub line', (tester) async {
    await tester.pumpWidget(_host(compact: true));
    expect(find.textContaining('Dits ·'), findsNothing);
  });

  testWidgets('char gap + keeps the word gap at least as large', (tester) async {
    (int, int)? got;
    await tester.pumpWidget(_host(
        interChar: 20, interWord: 20, onSpacing: (ic, iw) => got = (ic, iw)));
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    expect(got, (21, 21));
  });
}
