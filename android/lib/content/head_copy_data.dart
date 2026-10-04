// Building blocks for the comprehension mode (issue #7, DECISIONS.md
// "Head copy / comprehension"). Own text, written for this app.
//
// Slots are not drawn independently: a place carries a tag, an activity
// (verb + object) lists the place tags it fits, so no nonsense sentence can
// come out. Tags are the same in every language.

class HcPlace {
  final String text;
  final String tag;
  const HcPlace(this.text, this.tag);
}

/// A verb with its object, e.g. "trinkt" / "trinken" + "Kaffee".
class HcActivity {
  final String verbSg, verbPl, rest;
  final Set<String> tags;
  const HcActivity(this.verbSg, this.verbPl, this.rest, this.tags);

  String get id => '$verbSg|$rest';
}

class HcPhrases {
  /// The finished sentence, with the final full stop.
  final String Function(String who, bool plural, HcActivity a, String place, String? time, bool timeFirst) sentence;
  final String qWho;
  final String Function(String who, bool plural) qWhat;
  final String Function(String who, bool plural, HcActivity a) qWhere;
  final String Function(String who, bool plural, HcActivity a, String place) qWhen;
  /// How an activity reads as an answer option, e.g. "trinkt Kaffee".
  final String Function(HcActivity a, bool plural) activityText;
  const HcPhrases({
    required this.sentence,
    required this.qWho,
    required this.qWhat,
    required this.qWhere,
    required this.qWhen,
    required this.activityText,
  });
}

class HcContent {
  final String code;
  final List<String> names, pairs, times;
  final List<HcPlace> places;
  final List<HcActivity> activities;
  final HcPhrases phrases;
  const HcContent(this.code, this.names, this.pairs, this.places, this.times, this.activities, this.phrases);
}

String _join(List<String> parts) => parts.where((p) => p.isNotEmpty).join(' ');

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// German word order: a definite object comes before the place ("repariert
// das Fahrrad in der Werkstatt"), an indefinite one, a bare noun or a verb
// complement after it ("isst zu Hause eine Birne", "geht in Salzburg
// schwimmen"). Read off the start of the object, so nothing is marked by hand.
final _definite = RegExp(r'^(das|die|den|dem|der) ');

List<String> _deTail(HcActivity a, String place) =>
    _definite.hasMatch(a.rest) ? [a.rest, place] : [place, a.rest];

List<HcActivity> _variants(String sg, String pl, List<String> rests, String tags) =>
    [for (final r in rests) HcActivity(sg, pl, r, tags.split(' ').toSet())];

List<HcPlace> _tagged(String tag, List<String> texts) => [for (final t in texts) HcPlace(t, tag)];

// ── Deutsch ──────────────────────────────────────────────────────────────

final deContent = HcContent(
  'de',
  const ['Anna', 'Peter', 'Susi', 'Max', 'Lena', 'Paul', 'Eva', 'Tom', 'Nina', 'Karl', 'Mia', 'Jonas', 'Lisa', 'Franz'],
  const ['Anna und Max', 'Lena und Paul', 'Eva und Tom'],
  [
    const HcPlace('in der Küche', 'kueche'),
    const HcPlace('im Wohnzimmer', 'wohnzimmer'),
    const HcPlace('zu Hause', 'zuhause'),
    const HcPlace('im Garten', 'garten'),
    const HcPlace('in der Werkstatt', 'werkstatt'),
    const HcPlace('im Park', 'park'),
    const HcPlace('im Kaffeehaus', 'kaffeehaus'),
    const HcPlace('im Laden', 'laden'),
    const HcPlace('auf dem Markt', 'markt'),
    const HcPlace('in der Firma', 'firma'),
    const HcPlace('in der Schule', 'schule'),
    const HcPlace('in der Bibliothek', 'bibliothek'),
    const HcPlace('am Bahnhof', 'bahnhof'),
    const HcPlace('an der Haltestelle', 'haltestelle'),
    const HcPlace('auf dem Sportplatz', 'sport'),
    const HcPlace('im Schwimmbad', 'bad'),
    const HcPlace('am See', 'see'),
    const HcPlace('im Wald', 'wald'),
    const HcPlace('in den Bergen', 'berg'),
    const HcPlace('im Tal', 'tal'),
    ..._tagged('stadt', [
      for (final c in ['Graz', 'Wien', 'Linz', 'Salzburg', 'Innsbruck', 'Bonn', 'Berlin', 'Hamburg', 'Kiel', 'Bern', 'Basel', 'Dresden'])
        'in $c'
    ]),
  ],
  const [
    'heute', 'am Montag', 'am Dienstag', 'am Mittwoch', 'am Donnerstag', 'am Freitag', 'am Samstag',
    'am Sonntag', 'am Morgen', 'am Abend', 'um 7 Uhr', 'um 14 Uhr', 'morgen',
  ],
  [
    ..._variants('trinkt', 'trinken', ['Kaffee'], 'kueche wohnzimmer zuhause kaffeehaus park firma stadt'),
    ..._variants('liest', 'lesen', ['die Zeitung'], 'kueche wohnzimmer zuhause kaffeehaus park firma bibliothek bahnhof stadt'),
    ..._variants('repariert', 'reparieren', ['das Fahrrad', 'das Motorrad', 'das Moped', 'das Auto'], 'garten werkstatt stadt'),
    ..._variants('kauft', 'kaufen', ['Brot'], 'laden markt stadt'),
    ..._variants('kocht', 'kochen', ['das Essen'], 'kueche zuhause stadt'),
    ..._variants('backt', 'backen', ['einen Kuchen', 'eine Torte', 'eine Pizza'], 'kueche zuhause stadt'),
    ..._variants('isst', 'essen', ['einen Apfel', 'eine Birne', 'eine Banane'], 'kueche zuhause garten park firma stadt'),
    ..._variants('spielt', 'spielen', ['Fussball'], 'sport park garten schule stadt'),
    ..._variants('geht', 'gehen', ['schwimmen'], 'bad see stadt'),
    ..._variants('wandert', 'wandern', [''], 'berg wald see tal'),
    ..._variants('malt', 'malen', ['ein Bild'], 'wohnzimmer zuhause garten park schule stadt'),
    ..._variants('schreibt', 'schreiben', ['einen Brief'], 'kueche wohnzimmer zuhause firma kaffeehaus bibliothek stadt'),
    ..._variants('wartet', 'warten', ['auf den Bus'], 'haltestelle bahnhof stadt'),
    ..._variants('putzt', 'putzen', ['das Fenster'], 'kueche wohnzimmer zuhause firma werkstatt schule laden'),
    ..._variants('streichelt', 'streicheln', ['die Katze', 'den Hund'], 'kueche wohnzimmer zuhause garten park stadt'),
    ..._variants('singt', 'singen', ['ein Lied'], 'wohnzimmer kueche zuhause garten park schule stadt'),
    ..._variants('sucht', 'suchen', ['die Brille'], 'kueche wohnzimmer zuhause firma garten bahnhof stadt'),
  ],
  HcPhrases(
    sentence: (who, pl, a, place, time, timeFirst) {
      final verb = pl ? a.verbPl : a.verbSg;
      final parts = timeFirst && time != null
          ? [_cap(time), verb, who, ..._deTail(a, place)]
          : [who, verb, time ?? '', ..._deTail(a, place)];
      return '${_join(parts)}.';
    },
    qWho: 'Um wen geht es?',
    qWhat: (who, pl) => pl ? 'Welche Tätigkeit üben $who aus?' : 'Welche Tätigkeit übt $who aus?',
    qWhere: (who, pl, a) => 'Wo ${_join([pl ? a.verbPl : a.verbSg, who, a.rest])}?',
    qWhen: (who, pl, a, place) => 'Wann ${_join([pl ? a.verbPl : a.verbSg, who, ..._deTail(a, place)])}?',
    activityText: (a, pl) => _join([pl ? a.verbPl : a.verbSg, a.rest]),
  ),
);

// ── English ──────────────────────────────────────────────────────────────

final enContent = HcContent(
  'en',
  const ['Anna', 'Peter', 'Sue', 'Max', 'Emma', 'Paul', 'Eve', 'Tom', 'Kate', 'Jack', 'Mia', 'Sam', 'Lisa', 'Ben'],
  const ['Anna and Max', 'Emma and Paul', 'Eve and Tom'],
  [
    const HcPlace('in the kitchen', 'kueche'),
    const HcPlace('in the living room', 'wohnzimmer'),
    const HcPlace('at home', 'zuhause'),
    const HcPlace('in the garden', 'garten'),
    const HcPlace('in the workshop', 'werkstatt'),
    const HcPlace('in the park', 'park'),
    const HcPlace('in the cafe', 'kaffeehaus'),
    const HcPlace('in the shop', 'laden'),
    const HcPlace('at the market', 'markt'),
    const HcPlace('in the office', 'firma'),
    const HcPlace('at school', 'schule'),
    const HcPlace('in the library', 'bibliothek'),
    const HcPlace('at the station', 'bahnhof'),
    const HcPlace('at the bus stop', 'haltestelle'),
    const HcPlace('at the sports field', 'sport'),
    const HcPlace('at the pool', 'bad'),
    const HcPlace('at the lake', 'see'),
    const HcPlace('in the forest', 'wald'),
    const HcPlace('in the mountains', 'berg'),
    const HcPlace('in the valley', 'tal'),
    ..._tagged('stadt', [
      for (final c in ['London', 'Paris', 'Rome', 'Dublin', 'Boston', 'Denver', 'Sydney', 'Toronto', 'Berlin', 'Vienna', 'Oslo', 'Madrid'])
        'in $c'
    ]),
  ],
  const [
    'today', 'every day', 'every morning', 'every evening', 'on Monday', 'on Tuesday', 'on Wednesday',
    'on Thursday', 'on Friday', 'on Saturday', 'on Sunday', 'at 7 am', 'at 2 pm',
  ],
  [
    ..._variants('drinks', 'drink', ['coffee'], 'kueche wohnzimmer zuhause kaffeehaus park firma stadt'),
    ..._variants('reads', 'read', ['the newspaper'], 'kueche wohnzimmer zuhause kaffeehaus park firma bibliothek bahnhof stadt'),
    ..._variants('repairs', 'repair', ['the bike', 'the motorbike', 'the moped', 'the car'], 'garten werkstatt stadt'),
    ..._variants('buys', 'buy', ['bread'], 'laden markt stadt'),
    ..._variants('cooks', 'cook', ['dinner'], 'kueche zuhause stadt'),
    ..._variants('bakes', 'bake', ['a cake', 'a pie', 'a pizza'], 'kueche zuhause stadt'),
    ..._variants('eats', 'eat', ['an apple', 'a pear', 'a banana'], 'kueche zuhause garten park firma stadt'),
    ..._variants('plays', 'play', ['soccer'], 'sport park garten schule stadt'),
    ..._variants('goes', 'go', ['swimming'], 'bad see stadt'),
    ..._variants('hikes', 'hike', [''], 'berg wald see tal'),
    ..._variants('paints', 'paint', ['a picture'], 'wohnzimmer zuhause garten park schule stadt'),
    ..._variants('writes', 'write', ['a letter'], 'kueche wohnzimmer zuhause firma kaffeehaus bibliothek stadt'),
    ..._variants('waits', 'wait', ['for the bus'], 'haltestelle bahnhof stadt'),
    ..._variants('cleans', 'clean', ['the window'], 'kueche wohnzimmer zuhause firma werkstatt schule laden'),
    ..._variants('feeds', 'feed', ['the cat', 'the dog'], 'kueche wohnzimmer zuhause garten park stadt'),
    ..._variants('sings', 'sing', ['a song'], 'wohnzimmer kueche zuhause garten park schule stadt'),
    ..._variants('looks', 'look', ['for the glasses'], 'kueche wohnzimmer zuhause firma garten bahnhof stadt'),
  ],
  HcPhrases(
    sentence: (who, pl, a, place, time, timeFirst) {
      final verb = pl ? a.verbPl : a.verbSg;
      final parts = timeFirst && time != null
          ? [_cap(time), who, verb, a.rest, place]
          : [who, verb, a.rest, place, time ?? ''];
      return '${_join(parts)}.';
    },
    qWho: 'Who is it about?',
    qWhat: (who, pl) => 'What ${pl ? 'do' : 'does'} $who do?',
    qWhere: (who, pl, a) => 'Where ${pl ? 'do' : 'does'} ${_join([who, a.verbPl, a.rest])}?',
    qWhen: (who, pl, a, place) => 'When ${pl ? 'do' : 'does'} ${_join([who, a.verbPl, a.rest, place])}?',
    activityText: (a, pl) => _join([pl ? a.verbPl : a.verbSg, a.rest]),
  ),
);
