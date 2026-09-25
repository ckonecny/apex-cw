import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_cw_trainer/content/training_profile.dart';

void main() {
  test('migration copies globals into both profiles once', () async {
    SharedPreferences.setMockInitialValues({
      'kochLevel': 12, 'groupLength': 4, 'practiceChars': 'abc', 'boostLevel': 1,
    });
    final p = await SharedPreferences.getInstance();
    await TrainingProfile.migrateIfNeeded(p);
    for (final k in [TrainingProfile.hear, TrainingProfile.echo]) {
      final pr = TrainingProfile(p, k);
      expect(pr.getInt('kochLevel'), 12);
      expect(pr.getInt('groupLength'), 4);
      expect(pr.getString('practiceChars'), 'abc');
      expect(pr.getInt('maxWords'), isNull);
    }
    // profiles diverge, second migration must not overwrite
    await TrainingProfile(p, TrainingProfile.echo).setInt('kochLevel', 5);
    await p.setInt('kochLevel', 99);
    await TrainingProfile.migrateIfNeeded(p);
    expect(TrainingProfile(p, TrainingProfile.echo).getInt('kochLevel'), 5);
    expect(TrainingProfile(p, TrainingProfile.hear).getInt('kochLevel'), 12);
  });

  test('empty practiceChars is not migrated', () async {
    SharedPreferences.setMockInitialValues({'practiceChars': ''});
    final p = await SharedPreferences.getInstance();
    await TrainingProfile.migrateIfNeeded(p);
    expect(TrainingProfile(p, TrainingProfile.hear).getString('practiceChars'), isNull);
  });
}
