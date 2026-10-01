import 'training_profile.dart';

/// Character set and content of a training (docs/archive/training/P7-zeichenvorrat-startseite.md).
///
/// Koch is not a mode but a character set: the firmware's `kochActive` only
/// filters the characters and weights them.
enum CharSet { koch, all, practice }

/// Index order is persisted (`profile.<kind>.content`), never reorder.
enum ContentKind { random, words, abbrevs, calls, mixed }

/// Which contents a character set offers.
List<ContentKind> allowedContents(CharSet set) {
  switch (set) {
    case CharSet.koch:
      return const [ContentKind.random, ContentKind.words, ContentKind.abbrevs, ContentKind.mixed];
    case CharSet.all:
      return const [ContentKind.random, ContentKind.words, ContentKind.abbrevs,
          ContentKind.calls, ContentKind.mixed];
    case CharSet.practice:
      return const [ContentKind.random];
  }
}

/// A content the set does not offer falls back to random.
ContentKind sanitizeContent(CharSet set, ContentKind content) =>
    allowedContents(set).contains(content) ? content : ContentKind.random;

/// What the native generator needs for one (set, content) pair.
class EngineSelection {
  /// `CwGenerator.Mode` ordinal: 0 random chars, 1 words, 2 call signs,
  /// 3 mixed, 4 practice set, 5 abbreviations.
  final int mode;
  final bool kochActive;

  /// The "Random Groups" option only applies to random content of "all".
  final bool usesRandomOption;
  const EngineSelection(this.mode, this.kochActive, this.usesRandomOption);
}

EngineSelection engineSelection(CharSet set, ContentKind content) {
  final c = sanitizeContent(set, content);
  if (set == CharSet.practice) return const EngineSelection(4, false, false);
  final koch = set == CharSet.koch;
  switch (c) {
    case ContentKind.random:
      return EngineSelection(0, koch, !koch);
    case ContentKind.words:
      return EngineSelection(1, koch, false);
    case ContentKind.calls:
      return const EngineSelection(2, false, false);
    case ContentKind.mixed:
      return EngineSelection(3, koch, false);
    case ContentKind.abbrevs:
      return EngineSelection(5, koch, false);
  }
}

/// The user's choice, stored per training profile.
class CharsetChoice {
  final CharSet set;
  final ContentKind content;
  const CharsetChoice(this.set, this.content);

  static CharsetChoice load(TrainingProfile p) {
    final s = CharSet.values[(p.getInt('charset') ?? 0).clamp(0, CharSet.values.length - 1)];
    final c = ContentKind.values[(p.getInt('content') ?? 0).clamp(0, ContentKind.values.length - 1)];
    return CharsetChoice(s, sanitizeContent(s, c));
  }

  Future<void> save(TrainingProfile p) async {
    await p.setInt('charset', set.index);
    await p.setInt('content', content.index);
  }

  CharsetChoice withSet(CharSet s) => CharsetChoice(s, sanitizeContent(s, content));
  CharsetChoice withContent(ContentKind c) => CharsetChoice(set, sanitizeContent(set, c));

  EngineSelection get engine => engineSelection(set, content);
}

/// Old Koch content position -> content. Generator: random/abbrevs/words/mixed;
/// Echo adds "Adapt. Rand." (random, weighted anyway now).
const _kochHearContent = [ContentKind.random, ContentKind.abbrevs, ContentKind.words, ContentKind.mixed];
const _kochEchoContent = [..._kochHearContent, ContentKind.random];
// Old standalone Echo list: random, words, calls, mixed, practice set, abbrevs.
const _oldEchoContent = [ContentKind.random, ContentKind.words, ContentKind.calls,
    ContentKind.mixed, ContentKind.random, ContentKind.abbrevs];

/// Derives the initial choice from the pre-Phase-7 prefs, once (see
/// `TrainingProfile.migrateIfNeeded`). A stored Koch content position means
/// the Koch Trainer was used: that becomes the Koch lesson set. Otherwise
/// Hören starts with all characters (random) and Geben follows its old list.
CharsetChoice migrateCharsetChoice(String kind, {int? kochContent, int? oldEchoMode}) {
  if (kochContent != null) {
    final list = kind == TrainingProfile.echo ? _kochEchoContent : _kochHearContent;
    return CharsetChoice(CharSet.koch, list[kochContent.clamp(0, list.length - 1)]);
  }
  if (kind == TrainingProfile.echo && oldEchoMode != null) {
    final i = oldEchoMode.clamp(0, _oldEchoContent.length - 1);
    if (i == 4) return const CharsetChoice(CharSet.practice, ContentKind.random);
    return CharsetChoice(CharSet.all, _oldEchoContent[i]);
  }
  return const CharsetChoice(CharSet.all, ContentKind.random);
}
