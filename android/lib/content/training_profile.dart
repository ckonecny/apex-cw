import 'package:shared_preferences/shared_preferences.dart';

/// Per-training settings ("profiles"), see docs/training/P2-trainingsprofile.md.
///
/// Hearing (CW Generator / Koch generator / Adaptive Copy) and Sending (Echo
/// Trainer) each keep their own copy of these fields, stored as
/// `profile.<kind>.<field>`. Everything not listed here stays a global pref.
class TrainingProfile {
  static const hear = 'hear';
  static const echo = 'echo';

  static const _intFields = [
    'wpm',
    'kochLevel', 'groupLength', 'randomOption', 'maxWords', 'wordLengthMax',
    'abbrevLengthMax', 'interCharSpace', 'interWordSpace', 'boostLevel',
  ];
  static const _stringFields = ['practiceChars'];
  static const _versionKey = 'profileVersion';

  /// Copies the old global values into both profiles, once. The globals are
  /// left in place (rollback) but no longer read by the trainings. Missing
  /// values stay missing so the readers' defaults apply; an empty string is
  /// treated as missing too (a stored '' defeats `?? default`).
  static Future<void> migrateIfNeeded(SharedPreferences p) async {
    if ((p.getInt(_versionKey) ?? 0) >= 1) return;
    for (final kind in [hear, echo]) {
      for (final f in _intFields) {
        final v = p.getInt(f);
        if (v != null) await p.setInt('profile.$kind.$f', v);
      }
      for (final f in _stringFields) {
        final v = p.getString(f);
        if (v != null && v.isNotEmpty) await p.setString('profile.$kind.$f', v);
      }
    }
    await p.setInt(_versionKey, 1);
  }

  final SharedPreferences _p;
  final String kind;
  TrainingProfile(this._p, this.kind);

  static Future<TrainingProfile> open(String kind) async {
    final p = await SharedPreferences.getInstance();
    await migrateIfNeeded(p);
    return TrainingProfile(p, kind);
  }

  String _k(String f) {
    assert(_intFields.contains(f) || _stringFields.contains(f), 'not a profile field: $f');
    return 'profile.$kind.$f';
  }

  int? getInt(String f) => _p.getInt(_k(f));
  Future<void> setInt(String f, int v) => _p.setInt(_k(f), v);
  String? getString(String f) => _p.getString(_k(f));
  Future<void> setString(String f, String v) => _p.setString(_k(f), v);
}
