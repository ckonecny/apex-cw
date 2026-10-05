// Q-groups for the Q-groups mode (issue #41, DECISIONS.md "Q-groups mode").
// Own wording of the standard meanings, written for this app and checked
// against the ITU list. Where the statement is a request to the other station
// (QRP, QRO, QRS, QRQ, QSY), it is worded as one.
//
// Every group has a statement ("QRZ") meaning and, where it is in use, a
// question ("QRZ?") meaning in each language. [level] 1..3 is by how common the group is. [cluster] marks
// groups whose meanings are close to each other (noise, speed, power,
// frequency ...): two groups of one cluster never meet in the same question,
// so there is never a second defensible answer. "..." stands for the value
// that follows the group on air (a place, a name, a number).

class QText {
  /// [question] is null where the question form is hardly ever used on air.
  final String statement;
  final String? question;
  const QText(this.statement, [this.question]);
}

class QGroup {
  final String code;
  final int level;
  final String cluster;
  final QText de, en;
  const QGroup(this.code, this.level, this.cluster, this.de, this.en);

  QText text(String lang) => lang == 'de' ? de : en;
}

const qgLevels = 3;

const qGroups = <QGroup>[
  // ---- level 1: the ones heard in nearly every contact
  QGroup(
    'QTH', 1, 'place',
    QText('Mein Standort ist ...', 'Wo ist dein Standort?'),
    QText('My location is ...', 'What is your location?'),
  ),
  QGroup(
    'QRZ', 1, 'call',
    QText('Du wirst von ... gerufen', 'Wer ruft mich?'),
    QText('You are being called by ...', 'Who is calling me?'),
  ),
  QGroup(
    'QSL', 1, 'confirm',
    QText('Ich bestätige den Empfang', 'Kannst du den Empfang bestätigen?'),
    QText('I confirm reception', 'Can you confirm reception?'),
  ),
  QGroup(
    'QRM', 1, 'noise',
    QText('Ich werde durch andere Stationen gestört'),
    QText('I am disturbed by other stations'),
  ),
  QGroup(
    'QRP', 1, 'power',
    QText('Verringere deine Sendeleistung', 'Soll ich die Sendeleistung verringern?'),
    QText('Reduce your power', 'Shall I reduce my power?'),
  ),
  QGroup(
    'QRT', 1, 'stop',
    QText('Ich stelle den Sendebetrieb ein', 'Soll ich den Sendebetrieb einstellen?'),
    QText('I am closing down', 'Shall I stop transmitting?'),
  ),
  QGroup(
    'QSB', 1, 'signal',
    QText('Deine Zeichen schwanken in der Stärke'),
    QText('Your signals are fading'),
  ),
  QGroup(
    'QRV', 1, 'ready',
    QText('Ich bin bereit', 'Bist du bereit?'),
    QText('I am ready', 'Are you ready?'),
  ),

  // ---- level 2
  QGroup(
    'QRL', 2, 'frequency',
    QText('Die Frequenz ist besetzt', 'Ist die Frequenz besetzt?'),
    QText('The frequency is busy', 'Is the frequency busy?'),
  ),
  QGroup(
    'QRG', 2, 'frequency',
    QText('Deine genaue Frequenz ist ...', 'Wie lautet meine genaue Frequenz?'),
    QText('Your exact frequency is ...', 'What is my exact frequency?'),
  ),
  QGroup(
    'QSY', 2, 'frequency',
    QText('Wechsle die Frequenz', 'Soll ich die Frequenz wechseln?'),
    QText('Change frequency', 'Shall I change frequency?'),
  ),
  QGroup(
    'QRN', 2, 'noise',
    QText('Ich werde durch atmosphärische Störungen gestört'),
    QText('I am troubled by static'),
  ),
  QGroup(
    'QRS', 2, 'speed',
    QText('Gib langsamer', 'Soll ich langsamer geben?'),
    QText('Send slower', 'Shall I send slower?'),
  ),
  QGroup(
    'QRQ', 2, 'speed',
    QText('Gib schneller', 'Soll ich schneller geben?'),
    QText('Send faster', 'Shall I send faster?'),
  ),
  QGroup(
    'QRX', 2, 'wait',
    QText('Bitte warten, ich rufe dich später wieder', 'Wann rufst du mich wieder?'),
    QText('Please stand by, I will call you again later', 'When will you call me again?'),
  ),
  QGroup(
    'QSO', 2, 'contact',
    QText('Ich kann mit ... direkt verkehren', 'Kannst du mit ... direkt verkehren?'),
    QText('I can communicate with ... direct', 'Can you communicate with ... direct?'),
  ),

  // ---- level 3
  QGroup(
    'QRA', 3, 'call',
    QText('Der Name meiner Station ist ...', 'Wie heißt deine Station?'),
    QText('The name of my station is ...', 'What is the name of your station?'),
  ),
  QGroup(
    'QRB', 3, 'place',
    QText('Die ungefähre Entfernung zwischen uns beträgt ...', 'Wie weit sind wir ungefähr voneinander entfernt?'),
    QText('The approximate distance between us is ...', 'How far apart are we, approximately?'),
  ),
  QGroup(
    'QRK', 3, 'signal',
    QText('Deine Verständlichkeit ist ...', 'Wie ist meine Verständlichkeit?'),
    QText('Your intelligibility is ...', 'What is my intelligibility?'),
  ),
  QGroup(
    'QRO', 3, 'power',
    QText('Erhöhe deine Sendeleistung', 'Soll ich die Sendeleistung erhöhen?'),
    QText('Increase your power', 'Shall I increase my power?'),
  ),
  QGroup(
    'QSA', 3, 'signal',
    QText('Deine Signalstärke ist ...', 'Wie stark ist mein Signal?'),
    QText('Your signal strength is ...', 'How strong is my signal?'),
  ),
  QGroup(
    'QSP', 3, 'confirm',
    QText('Ich vermittle eine Nachricht an ...', 'Vermittelst du eine Nachricht an ...?'),
    QText('I will relay a message to ...', 'Will you relay a message to ...?'),
  ),
  QGroup(
    'QTR', 3, 'time',
    QText('Die genaue Zeit ist ...', 'Wie spät ist es genau?'),
    QText('The exact time is ...', 'What is the exact time?'),
  ),
  QGroup(
    'QRU', 3, 'stop',
    QText('Ich habe nichts für dich', 'Hast du etwas für mich?'),
    QText('I have nothing for you', 'Have you anything for me?'),
  ),
];

/// Problems with the group list; empty when it is sound. Used by the tests.
/// Each question (statement or question form) needs enough groups of its own
/// level, outside the right one's cluster, to fill the three wrong options.
List<String> qgValidate(List<QGroup> groups, {int options = 4}) {
  final problems = <String>[];
  final codes = <String>{};
  for (final g in groups) {
    if (!codes.add(g.code)) problems.add('${g.code}: duplicate');
    if (g.level < 1 || g.level > qgLevels) problems.add('${g.code}: level ${g.level}');
    for (final lang in const ['de', 'en']) {
      final t = g.text(lang);
      if (t.statement.trim().isEmpty || (t.question?.trim().isEmpty ?? false)) problems.add('${g.code}: empty $lang text');
      if (t.statement == t.question) problems.add('${g.code}: $lang statement equals question');
    }
    if ((g.de.question == null) != (g.en.question == null)) problems.add('${g.code}: question form in one language only');
    final others = groups.where((o) => o.level == g.level && o.cluster != g.cluster);
    final statements = others.length;
    final questions = others.where((o) => o.de.question != null).length;
    if (statements < options - 1) problems.add('${g.code}: only $statements usable wrong statements in level ${g.level}');
    if (g.de.question != null && questions < options - 1) {
      problems.add('${g.code}: only $questions usable wrong questions in level ${g.level}');
    }
  }
  for (var l = 1; l <= qgLevels; l++) {
    if (!groups.any((g) => g.level == l)) problems.add('level $l is empty');
  }
  return problems;
}

/// Values that follow a group on air, for the levels that play it in context
/// ("QTH WIEN"). Only groups whose meaning ends in "..." appear here; plain
/// ASCII, as the CW engine plays it. Fictional values only.
const qgTails = <String, List<String>>{
  'QTH': ['WIEN', 'GRAZ', 'LINZ', 'BERLIN', 'HAMBURG', 'MUENCHEN', 'BERN'],
  'QRA': ['TOM', 'ANNA', 'MAX', 'EVA', 'PAUL'],
  'QRB': ['50 KM', '120 KM', '300 KM', '800 KM'],
  'QRG': ['7030', '14060', '3560', '10120'],
  'QRK': ['3', '4', '5'],
  'QSA': ['3', '4', '5'],
  'QTR': ['0915', '1830', '2145'],
};
