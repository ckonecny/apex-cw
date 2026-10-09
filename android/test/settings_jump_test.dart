// Long press on the Koch / Words chip opens the settings sheet scrolled to
// the matching section.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/training_profile.dart';
import 'package:next_cw_trainer/l10n/strings.dart';
import 'package:next_cw_trainer/ui/widgets/training_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> open(WidgetTester t, TrainingSection? jumpTo) async {
    SharedPreferences.setMockInitialValues({});
    Strings.lang.value = 1;
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showTrainingSettingsSheet(ctx,
                profile: TrainingProfile.hear,
                jumpTo: jumpTo,
                sections: [
                  TrainingSection.content,
                  TrainingSection.spacing,
                  TrainingSection.wordSelection,
                  TrainingSection.hearFlow,
                  TrainingSection.adaptive,
                ]),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  bool onScreen(WidgetTester t, String text) {
    final f = find.text(text);
    if (f.evaluate().isEmpty) return false;
    final r = t.getRect(f.first);
    return r.top >= 0 && r.bottom <= 640;
  }

  testWidgets('without jumpTo the sheet starts at the top', (t) async {
    await open(t, null);
    expect(find.text(Strings.t('settings_profile_hear')), findsOneWidget);
    expect(onScreen(t, Strings.t('settings_group_length')), isFalse);
  });

  testWidgets('jumpTo wordSelection scrolls the word settings into view', (t) async {
    await open(t, TrainingSection.wordSelection);
    // Default content is random, so the section shows the group length row.
    expect(onScreen(t, Strings.t('settings_group_length')), isTrue);
  });
}
