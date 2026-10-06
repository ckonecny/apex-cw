// Plain-language texts for the exam simulation (issue #42): amateur-radio
// German without umlauts (AE OE UE SS), as in the voluntary exams. Pure Dart.
import 'dart:math';

import 'exam_grading.dart' show morseUnits;
import 'exam_profile.dart';
import 'exam_texts_en.dart';

const _sentences = [
  'Heute ist das Wetter gut und die Bedingungen auf dem Zwanzig Meter Band sind ausgezeichnet',
  'Ich habe gestern mit einer Station in Italien gesprochen und einen guten Rapport erhalten',
  'Die Antenne steht auf dem Dach und ist mit einem Koaxialkabel an das Funkgeraet angeschlossen',
  'Mein Name ist Peter und ich wohne in der Naehe von Wien',
  'Bitte wiederholen Sie das Rufzeichen noch einmal langsamer',
  'Der Sender hat eine Leistung von hundert Watt und arbeitet auf vierzehn Megahertz',
  'Morgen faehrt der Ortsverband zu einem Ausflug auf den Berg und baut dort eine Funkstation auf',
  'Das Signal ist heute sehr laut und klar, vielen Dank fuer den Anruf',
  'Zum Aufbau eines Dipols braucht man Draht, zwei Isolatoren und ein langes Seil',
  'Im Winter gibt es oft wenig Sonnenflecken und die Ausbreitung auf den hohen Baendern ist schlecht',
  'Wir treffen uns jeden Dienstag um 19 Uhr im Klubheim zum gemeinsamen Funkabend',
  'Die Pruefung besteht aus einem technischen Teil und einem Teil ueber Betriebstechnik und Vorschriften',
  'Mit einem Netzteil von 13 Volt und 20 Ampere laeuft die Station zuverlaessig',
  'Das Rufzeichen eines Funkamateurs besteht aus Buchstaben und Ziffern und ist weltweit eindeutig',
  'Beim Funkbetrieb gilt immer, sauber zu arbeiten und anderen Stationen nicht zu stoeren',
  'Gestern abend habe ich zum ersten Mal Japan gehoert und konnte leider nicht antworten',
  'Ein guter Funkamateur hoert zuerst lange zu und ruft erst dann eine Station an',
  'Die Reichweite auf Kurzwelle haengt von der Tageszeit und von der Jahreszeit ab',
  'Das Morsen ueben wir am besten jeden Tag zehn bis zwanzig Minuten lang',
  'Fuer den Fieldday brauchen wir ein Zelt, einen Generator, Tische und mehrere Antennen',
  'Der Empfang war heute schwach, aber bei Station DL1ABC konnte ich alles aufnehmen',
  'Im Mai 2025 fand das grosse Treffen aller Funkamateure in der Stadthalle statt',
  'Die Frequenz 7030 kHz wird gerne fuer Verbindungen mit niedriger Geschwindigkeit benutzt',
  'Ein Kondensator speichert Ladung, eine Spule speichert Energie in einem Magnetfeld',
  'Ich rufe CQ und warte, ob mir jemand antwortet',

  // Short sentences, mainly for the 5 WPM exams (about 40 to 70 characters).
  'Ich hoere Sie laut und deutlich',
  'Bitte rufen Sie mich spaeter noch einmal',
  'Das Wetter ist heute schoen und warm',
  'Ich benutze eine Vertikalantenne im Garten',
  'Die Station laeuft mit einer kleinen Leistung',
  'Der Sonntag ist ein guter Tag zum Funken',
  'Vielen Dank fuer das nette Gespraech',
  'Heute abend ist das Band lange offen',
  'Mein Funkgeraet steht im Keller neben dem Netzteil',
  'Die Antenne haengt zwischen zwei hohen Baeumen',
  'Ich bin seit zwei Jahren als Funkamateur aktiv',
  'Das Signal wird gegen Abend deutlich staerker',
  'Wir bauen am Samstag einen neuen Mast auf',
  'Am Morgen ist auf dem Vierzig Meter Band viel los',
  'Der Funkverkehr ueber den Atlantik war heute gut',
  'Mit Morsezeichen kommt man auch mit wenig Leistung weit',
  'Ein sauberes Signal macht Freude beim Hoeren',
  'Bitte geben Sie mir noch einmal den Namen durch',
  'Der Ortsverband trifft sich im ersten Stock',
  'Ich lerne seit einem halben Jahr Morsen',
  'Das Netzteil ist warm geworden, ich schalte es kurz aus',
  'Gestern hat es stark gewittert und ich habe die Antenne abgeklemmt',
  'Der Kontest beginnt am Samstag um 12 Uhr und endet am Sonntag um 12 Uhr',
  'Bei einem Notfall kann der Amateurfunk die Verbindung herstellen',
  'Mit 5 Watt habe ich gestern die Kanarischen Inseln erreicht',
  'Die Tastatur ersetzt den Stift nicht, am Ende zaehlt die Handschrift',
  'Das Rufzeichen muss bei jeder Aussendung genannt werden',
  'Gute Funker hoeren mehr zu als sie senden',
  'Die Sonnenaktivitaet steigt und die oberen Baender oeffnen sich wieder',
  'Ein Dipol fuer 40 Meter ist etwa 20 Meter lang',
  'Der Balun sitzt direkt am Speisepunkt der Antenne',
  'Die Stehwellenmessung zeigt einen guten Wert auf allen Baendern',
  'Heute hat mich eine Station in Kanada gerufen',
  'Ich suche noch eine Verbindung mit Neuseeland fuer mein Diplom',
  'Am Wochenende findet in unserem Ort ein Flohmarkt fuer Funkgeraete statt',
  'Eine Spule und ein Kondensator bilden zusammen einen Schwingkreis',
  'Die Ausbreitung ueber die Ionosphaere haengt von der Frequenz ab',
  'Wer langsam und sauber gibt, wird besser verstanden als ein schneller Funker',
  'Zum Ueben nehme ich jeden Abend zehn Minuten Zeit',
  'Beim Fieldday waren dieses Jahr mehr als dreissig Funkamateure dabei',
  'Mein Nachbar hoert mich manchmal im Radio, das stoert ihn sehr',
  'Das Funkgeraet hat einen eingebauten Keyer und einen Speicher fuer Texte',
  'Ich antworte gleich, wenn die Frequenz wieder frei ist',
  'Die Reichweite hing gestern stark vom Standort ab',
  'Ein Kopfhoerer hilft, schwache Signale besser zu verstehen',
  'Im Sommer sind die Nachte kurz und die Bedingungen oft unruhig',
  'Die Verbindung kam sofort zustande und dauerte nur wenige Minuten',
  'Der Zug nach Salzburg faehrt um 8 Uhr 15 vom Bahnhof ab',
  'Das Treffen am Mittwoch faellt wegen der Feiertage aus',
  'Fuer den Test brauche ich Stift, Papier und einen Kopfhoerer',
  'Die Pruefung dauert drei Minuten und wird einmal gesendet',
  'Ich nehme das Funkgeraet mit auf den Berg und rufe von dort',
  'Der Akku haelt etwa zwei Stunden bei voller Sendeleistung',
  'Eine gute Erdung schuetzt die Station bei einem Gewitter',
  'Der Wetterbericht meldet fuer morgen Regen und starken Wind',
  'Jeder Funkamateur sollte seine Pruefungsunterlagen sorgfaeltig aufbewahren',
  'Das Seminar fuer Anfaenger beginnt im Oktober und dauert acht Wochen',
  'Wir pruefen die Antennenanlage vor dem Winter auf Schaeden',
  'Er hat die Pruefung beim ersten Versuch bestanden und freut sich sehr',
  'Mit dem Handfunkgeraet erreicht man den Umsetzer auf dem Berg',
  'Das Morsen hilft auch bei schlechtem Wetter und schwachen Signalen',
  'Ein kurzer Anruf genuegt, wenn die Frequenz frei ist',
  'Die Verlaengerung der Antenne um einen Meter brachte eine deutliche Verbesserung',
  'Im Heimnetz laeuft ein kleiner Computer fuer das Logbuch',
  'Das Logbuch fuehre ich auf Papier und trage jede Verbindung sofort ein',
  'Die Bestaetigungskarten kommen meist nach einigen Wochen mit der Post',
  'Nach dem Mittagessen gehe ich in den Garten und hoere eine Stunde lang',
  'Der erste Funkkontakt mit einem anderen Kontinent bleibt unvergesslich',
  'Mein Lehrer sagte immer, hoere zuerst und schreibe dann',
  'Die Zahl der Funkamateure in Europa liegt bei ueber 700000',
  'Beim Morsen zaehlt der Rhythmus mehr als die Geschwindigkeit',
  'Am Freitag gibt es im Klubheim Kaffee und Kuchen',
  'Der Mast ist 12 Meter hoch und wird mit vier Seilen abgespannt',
  'Eine Leitung von 50 Ohm passt gut zu den meisten Antennen',
  'Ich habe heute 14 Stationen gearbeitet und 9 Laender gehoert',
  'Dein Signal kommt mit Staerke 5 und Lesbarkeit 9 an',
  'Es gibt nur wenige Dinge, die so ruhig machen wie Morsen',
  'Der Empfaenger rauscht heute stark, wahrscheinlich liegt es am Wetter',
  'Das Schiff meldet sich jeden Abend zur gleichen Zeit',
  'Die Pause zwischen den Woertern ist beim Morsen genauso wichtig wie die Zeichen',
];

const _names = [
  'PETER',
  'ANNA',
  'HANS',
  'MARIA',
  'KLAUS',
  'ERIKA',
  'WERNER',
  'SUSI',
  'JOSEF',
  'LISA',
  'THOMAS',
  'EVA',
  'MARKUS',
  'INGE',
  'FRITZ',
  'GERDA',
  'OTTO',
  'HELGA',
];
const _towns = [
  'WIEN',
  'GRAZ',
  'LINZ',
  'SALZBURG',
  'INNSBRUCK',
  'KLAGENFURT',
  'BREGENZ',
  'BERLIN',
  'HAMBURG',
  'MUENCHEN',
  'KOELN',
  'DRESDEN',
  'BREMEN',
  'ZUERICH',
  'BERN',
];
const _kHz = [
  '3560',
  '7030',
  '7040',
  '10120',
  '14050',
  '14060',
  '18090',
  '21050',
];
const _rst = ['599', '579', '559', '589', '449', '339', '569'];
const _ants = ['DIPOL', 'VERTIKAL', 'YAGI', 'LANGDRAHT', 'LOOP'];

String _call(Random r) {
  const pre = ['OE', 'OE', 'DL', 'DK', 'DJ', 'HB9'];
  final p = pre[r.nextInt(pre.length)];
  final d = p == 'HB9' ? '' : '${1 + r.nextInt(9)}';
  final n = 2 + r.nextInt(2);
  final l = String.fromCharCodes([
    for (var i = 0; i < n; i++) 65 + r.nextInt(26),
  ]);
  return '$p$d$l';
}

T _pick<T>(Random r, List<T> l) => l[r.nextInt(l.length)];

/// QSO-style lines with call signs, names, towns, reports and frequencies,
/// generated fresh for each use so they never repeat.
final List<String Function(Random)> _templates = [
  (r) =>
      'HALLO ${_call(r)} HIER IST ${_call(r)} MEIN NAME IST ${_pick(r, _names)}',
  (r) =>
      'MEIN QTH IST ${_pick(r, _towns)} UND DEIN RAPPORT IST ${_pick(r, _rst)}',
  (r) =>
      '${_call(r)} DE ${_call(r)} DEIN SIGNAL IST ${_pick(r, _rst)} IN ${_pick(r, _towns)}',
  (r) =>
      'ICH ARBEITE AUF ${_pick(r, _kHz)} KHZ MIT ${5 + 5 * r.nextInt(20)} WATT',
  (r) =>
      'ICH HABE EINE ${_pick(r, _ants)} ANTENNE UND ${10 + r.nextInt(90)} WATT',
  (r) => 'DANKE ${_pick(r, _names)} FUER DAS QSO MIT ${_call(r)} BIS BALD',
  (r) =>
      'DIE STATION ${_call(r)} IST AUS ${_pick(r, _towns)} UND AKTIV AUF ${_pick(r, _kHz)} KHZ',
  (r) =>
      'WIR TREFFEN UNS AM ${1 + r.nextInt(28)} UM ${8 + r.nextInt(12)} UHR IN ${_pick(r, _towns)}',
];

List<String> _lastRun = [];

/// A text for one exam part of [p]: plain text, figure groups or mixed groups,
/// by [ExamProfile.kind]. Figure and mixed groups are [ExamProfile.targetGroups]
/// groups of five characters separated by spaces.
String examText(ExamProfile p, [Random? rng]) {
  final r = rng ?? Random();
  if (p.kind == ExamKind.plain) return _plainText(p, r);
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const digits = '0123456789';
  final pool = p.kind == ExamKind.figures ? digits : letters + digits;
  return [
    for (var g = 0; g < p.targetGroups; g++)
      String.fromCharCodes([for (var i = 0; i < 5; i++) pool.codeUnitAt(r.nextInt(pool.length))]),
  ].join(' ');
}

/// Plain text for one exam part of [p], as long in Morse as the part lasts
/// ([ExamProfile.targetUnits], cut at a word boundary): sentences from the fixed pool and from the
/// templates in random order, none twice in a run and none of the sentences of
/// the run before. Upper case, single spaces. With [ExamProfile.punctuation]
/// some sentences end with a full stop, a question mark or `=`, and with
/// [ExamProfile.prosigns] the text ends with `+` (AR). Without
/// [ExamProfile.punctuation] all punctuation is dropped.
String _plainText(ExamProfile p, Random r) {
  final en = p.lang == 'en';
  final fixed = [...(en ? examSentencesEn : _sentences)]..shuffle(r);
  final used = <String>[];
  final out = StringBuffer();
  final target = p.targetUnits;
  while (morseUnits(out.toString()) < target) {
    // Roughly 8 dit units per character of German text.
    final left = (target - morseUnits(out.toString())) ~/ 8;
    // Every third sentence is generated; the others come from the pool and
    // fit the length that is still missing, so a 5 WPM text is one or two
    // short sentences instead of one long one.
    String? s;
    if (r.nextInt(3) == 0) s = en ? examTemplateEn(p.family, r) : _pick(r, _templates)(r);
    s ??= fixed.firstWhere(
      (c) =>
          !used.contains(c) && !_lastRun.contains(c) && c.length <= left + 12,
      orElse: () => fixed.firstWhere(
        (c) => !used.contains(c) && !_lastRun.contains(c),
        orElse: () => fixed.firstWhere((c) => !used.contains(c)),
      ),
    );
    used.add(s);
    s = s.toUpperCase();
    if (p.punctuation) {
      const ends = ['.', '?', '=', '.'];
      if (!s.endsWith('.')) s += ends[r.nextInt(ends.length)];
    } else {
      s = s.replaceAll(RegExp('[.,=?/]'), '');
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (out.isNotEmpty) out.write(' ');
    out.write(s);
  }
  _lastRun = used;
  // Drop trailing words while the text still reaches the exam length, so it
  // lasts as long as the exam and no longer.
  final words = out.toString().split(' ');
  while (words.length > 1 && morseUnits(words.sublist(0, words.length - 1).join(' ')) >= target) {
    words.removeLast();
  }
  var text = words.join(' ');
  if (p.prosigns) text = '$text +';
  return text;
}

/// The fixed German sentence pool (for tests).
List<String> get examSentencePool => _sentences;
