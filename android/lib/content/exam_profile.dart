// Exam simulation (issue #42, docs/DECISIONS.md "Exam simulation"): the
// optional Morse proficiency exams that exist in some countries, as data
// profiles, plus one user-defined profile. Pure Dart. Parameters come from
// public sources (see docs/DECISIONS.md) and may differ from the official exam
// — the screen says so.

/// What the text of a part consists of.
enum ExamKind {
  /// Amateur-radio plain text (German sentences, QSO lines).
  plain,

  /// Groups of five figures.
  figures,

  /// Groups of five random letters and figures.
  groups,
}

class ExamProfile {
  /// Unique key of the profile (results and the send speed are stored by it).
  final String id;

  /// Country/organisation: 'at', 'de', 'uk', 'nz', 'in', 'us' or 'custom'.
  final String family;

  /// Overall speed in WPM (PARIS standard).
  final int wpm;

  /// Character speed in WPM; above [wpm] means Farnsworth spacing.
  final int charWpm;

  /// Length of the receive and of the send part, minutes.
  final int minutes;

  /// Most errors/omissions still passing, per part.
  final int errorLimit;

  /// Extra attempts per part after a fail (shown, not enforced).
  final int retries;

  final ExamKind kind;

  /// Plain text only: punctuation (. , ? = /) in the text; the prosign AR
  /// (typed as +) at its end.
  final bool punctuation, prosigns;

  /// False for exams that only test receiving (ARRL).
  final bool hasSend;

  const ExamProfile({
    required this.id,
    required this.family,
    required this.wpm,
    int? charWpm,
    this.minutes = 3,
    required this.errorLimit,
    this.retries = 0,
    this.kind = ExamKind.plain,
    this.punctuation = false,
    this.prosigns = false,
    this.hasSend = true,
  }) : charWpm = charWpm ?? wpm;

  bool get farnsworth => charWpm > wpm;

  /// Length of a plain-text part in dit units: a PARIS word is 50 units, so the
  /// part lasts [minutes] at [wpm] (a text of "wpm × 5 characters" would last
  /// only about 5/6 of that, spaces and short characters being quick).
  int get targetUnits => wpm * 50 * minutes;

  /// Groups in a figure or letter/figure group part. A group of five figures
  /// takes about 89 dit units with its gaps, one of mixed characters about 71
  /// (a PARIS word is 50), so the part lasts about [minutes] at [wpm].
  int get targetGroups {
    final units = kind == ExamKind.figures ? 89 : 71;
    final n = (wpm * minutes * 50 / units).round();
    return n < 3 ? 3 : n;
  }

  /// Inter-character space in dit units for the shared generator (3 = standard).
  int get interChar => farnsworth ? (3 * _stretch).round() : 3;

  /// Inter-word space in dit units (7 = standard).
  int get interWord => farnsworth ? (7 * _stretch).round() : 7;

  /// Factor by which Farnsworth stretches the 19 gap units of a PARIS word so
  /// that the whole word takes 60 / wpm seconds with characters at [charWpm].
  double get _stretch {
    final wordSec = 60.0 / wpm;
    final charSec = 31 * 1.2 / charWpm;
    return (wordSec - charSec) / (19 * 1.2 / charWpm);
  }

  // ---- user-defined profile ----

  static const customFamily = 'custom';
  static const customMaxWpm = 40;

  /// The user-defined profile; its id carries all settings, so the history and
  /// the "ready" forecast belong to one configuration.
  factory ExamProfile.custom({
    int wpm = 12,
    int? charWpm,
    int minutes = 3,
    int errorLimit = 4,
    int retries = 0,
    ExamKind kind = ExamKind.plain,
    bool punctuation = false,
    bool prosigns = false,
  }) {
    final w = wpm.clamp(5, customMaxWpm);
    final cw = (charWpm ?? w).clamp(w, customMaxWpm);
    final m = minutes.clamp(1, 10);
    final e = errorLimit.clamp(0, 20);
    final rt = retries.clamp(0, 5);
    final punct = kind == ExamKind.plain && punctuation;
    final pros = kind == ExamKind.plain && prosigns;
    return ExamProfile(
      id: 'custom:$w/$cw/$m/$e/$rt/${kind.name}/${punct ? 1 : 0}${pros ? 1 : 0}',
      family: customFamily,
      wpm: w,
      charWpm: cw,
      minutes: m,
      errorLimit: e,
      retries: rt,
      kind: kind,
      punctuation: punct,
      prosigns: pros,
    );
  }

  Map<String, dynamic> toJson() => {
        'w': wpm, 'c': charWpm, 'm': minutes, 'e': errorLimit, 'r': retries,
        'k': kind.name, 'p': punctuation, 'a': prosigns,
      };

  factory ExamProfile.fromJson(Map<String, dynamic> j) => ExamProfile.custom(
        wpm: j['w'] as int? ?? 12,
        charWpm: j['c'] as int?,
        minutes: j['m'] as int? ?? 3,
        errorLimit: j['e'] as int? ?? 4,
        retries: j['r'] as int? ?? 0,
        kind: ExamKind.values.firstWhere((k) => k.name == j['k'], orElse: () => ExamKind.plain),
        punctuation: j['p'] as bool? ?? false,
        prosigns: j['a'] as bool? ?? false,
      );

  ExamProfile copyWith({
    int? wpm,
    int? charWpm,
    int? minutes,
    int? errorLimit,
    int? retries,
    ExamKind? kind,
    bool? punctuation,
    bool? prosigns,
  }) =>
      ExamProfile.custom(
        wpm: wpm ?? this.wpm,
        charWpm: charWpm ?? this.charWpm,
        minutes: minutes ?? this.minutes,
        errorLimit: errorLimit ?? this.errorLimit,
        retries: retries ?? this.retries,
        kind: kind ?? this.kind,
        punctuation: punctuation ?? this.punctuation,
        prosigns: prosigns ?? this.prosigns,
      );
}

/// Families in the order of the picker (the custom profile comes last).
const examFamilies = ['at', 'de', 'uk', 'nz', 'in', 'us'];

/// Austria: receive and send 3 minutes each, at least 12 WPM; the error limit
/// is not published (the ÖVSV course material says 2–3 are tolerated), so the
/// stricter 3 is used.
const examAt12 = ExamProfile(id: 'at12', family: 'at', wpm: 12, errorLimit: 3);

/// Germany (BNetzA): 3 minutes, at most 4 errors, one retry per part; the
/// characters include digits, = ? / . , and the prosigns.
const examDe5 = ExamProfile(
    id: 'de5', family: 'de', wpm: 5, errorLimit: 4, retries: 1, punctuation: true, prosigns: true);

final List<ExamProfile> examProfiles = [
  examAt12,
  const ExamProfile(
      id: 'de5f', family: 'de', wpm: 5, charWpm: 9, errorLimit: 4, retries: 1,
      punctuation: true, prosigns: true),
  examDe5,
  const ExamProfile(
      id: 'de12', family: 'de', wpm: 12, errorLimit: 4, retries: 1,
      punctuation: true, prosigns: true),
  // UK, RSGB Certificate of Competency: plain text 3 minutes (at most 4
  // errors) and figures in groups of five for 1 minute (at most 3 errors).
  for (final s in const [5, 10, 12, 15, 20, 25, 30]) ...[
    ExamProfile(id: 'uk$s', family: 'uk', wpm: s, errorLimit: 4, punctuation: true),
    ExamProfile(id: 'uk${s}f', family: 'uk', wpm: s, minutes: 1, errorLimit: 3, kind: ExamKind.figures),
  ],
  // New Zealand, NZART: 5 WPM, 3 minutes, at most 4 errors, up to 5 attempts.
  const ExamProfile(id: 'nz5', family: 'nz', wpm: 5, errorLimit: 4, retries: 4),
  // India, WPC: 5 or 8 WPM, receive 1 minute without a mistake.
  for (final s in const [5, 8])
    ExamProfile(id: 'in$s', family: 'in', wpm: s, minutes: 1, errorLimit: 0),
  // USA, ARRL Code Proficiency: 1 minute of solid copy, receive only.
  for (final s in const [10, 15, 20, 25, 30, 35, 40])
    ExamProfile(id: 'us$s', family: 'us', wpm: s, minutes: 1, errorLimit: 0, hasSend: false),
];

/// The preset profiles of one family, in picker order.
List<ExamProfile> examFamilyProfiles(String family) =>
    [for (final p in examProfiles) if (p.family == family) p];

/// The profile with [id], or the Austrian one when unknown. Does not know the
/// custom profile (the screen keeps that one in its preferences).
ExamProfile examProfileById(String? id) =>
    examProfiles.firstWhere((p) => p.id == id, orElse: () => examAt12);
