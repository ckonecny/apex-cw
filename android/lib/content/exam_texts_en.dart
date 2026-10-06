// English plain-language texts for the exam simulation (issue #42): for the
// exams of countries whose language is not German (UK, New Zealand, India,
// USA). Amateur-radio English with figures; call signs and towns follow the
// country. Pure Dart.
import 'dart:math';

const examSentencesEn = [
  'The weather is fine today and the bands are open on twenty metres',
  'I worked a station in Italy yesterday and received a good report',
  'The antenna is on the roof and connects to the radio with coaxial cable',
  'My name is Peter and I live near a small town on the coast',
  'Please repeat your call sign once more and a little slower',
  'The transmitter runs one hundred watts on fourteen megahertz',
  'Tomorrow the club drives to the hill and sets up a station there',
  'Your signal is strong and clear today, thank you for the call',
  'To build a dipole you need wire, two insulators and a long rope',
  'In winter there are few sunspots and the high bands are poor',
  'We meet every Tuesday at 7 pm in the clubhouse for the radio night',
  'The exam has a technical part and a part on operating and regulations',
  'With a power supply of 13 volts and 20 amps the station runs reliably',
  'The call sign of an amateur has letters and figures and is unique worldwide',
  'Good operating practice means a clean signal and no interference to others',
  'Last night I heard Japan for the first time but could not answer',
  'A good operator listens for a long time before calling a station',
  'The range on shortwave depends on the time of day and the season',
  'It is best to practise Morse every day for ten to twenty minutes',
  'For field day we need a tent, a generator, tables and several antennas',
  'Reception was weak today but I could copy station G3ABC without trouble',
  'In May 2025 the big meeting of amateurs was held at the town hall',
  'The frequency 7030 kHz is often used for slow speed contacts',
  'A capacitor stores charge and a coil stores energy in a magnetic field',
  'I call CQ and wait to see if anyone answers',
  // Short ones for the slow exams (about 40 to 70 characters).
  'I can hear you loud and clear',
  'Please call me again later',
  'The weather is nice and warm today',
  'I use a vertical antenna in the garden',
  'The station runs on a very low power',
  'Sunday is a good day for the radio',
  'Thank you for the nice chat',
  'The band stays open late this evening',
  'My radio sits in the basement next to the power supply',
  'The antenna hangs between two tall trees',
  'I have been an active amateur for two years',
  'The signal gets much stronger towards evening',
  'We will put up a new mast on Saturday',
  'The forty metre band is busy in the morning',
  'Contacts across the Atlantic were good today',
  'With Morse you can get far on low power',
  'A clean signal is a joy to listen to',
  'Please give me the name once more',
  'The club meets on the first floor',
  'I have been learning Morse for half a year',
  'The power supply got warm so I switched it off',
  'Yesterday there was a storm and I disconnected the antenna',
  'The contest starts on Saturday at 12 noon and ends on Sunday at 12 noon',
  'In an emergency amateur radio can set up a link',
  'With 5 watts I reached the Canary Islands yesterday',
  'The call sign must be given with every transmission',
  'Good operators listen more than they transmit',
  'Solar activity is rising and the upper bands open again',
  'A dipole for 40 metres is about 20 metres long',
  'The balun sits right at the feed point of the antenna',
  'The SWR reading shows a good value on all bands',
  'Today a station in Canada called me',
  'I am still looking for a contact with New Zealand for my award',
  'There is a flea market for radios in our town this weekend',
  'A coil and a capacitor together form a tuned circuit',
  'Propagation through the ionosphere depends on the frequency',
  'Whoever sends slowly and cleanly is understood better than a fast operator',
  'I take ten minutes every evening to practise',
  'At field day this year more than thirty amateurs took part',
  'My neighbour sometimes hears me on his radio and it annoys him',
  'The radio has a built in keyer and a memory for texts',
  'I will answer as soon as the frequency is free again',
  'The range yesterday depended strongly on the location',
  'Headphones help to understand weak signals better',
  'In summer the nights are short and conditions are often unsettled',
  'The contact was made at once and lasted only a few minutes',
  'The train to Bristol leaves the station at 8 15',
  'The meeting on Wednesday is cancelled because of the holiday',
  'For the test I need a pen, paper and headphones',
  'The test lasts three minutes and is sent once',
  'I take the radio up the hill and call from there',
  'The battery lasts about two hours at full power',
  'Good grounding protects the station in a thunderstorm',
  'The forecast gives rain and strong wind for tomorrow',
  'Every amateur should keep the licence papers in a safe place',
  'The course for beginners starts in October and lasts eight weeks',
  'We check the antenna system for damage before winter',
  'He passed the exam at the first try and is very happy',
  'With a handheld you can reach the repeater on the hill',
  'Morse helps in bad weather and with weak signals',
  'A short call is enough when the frequency is free',
  'Making the antenna one metre longer gave a clear improvement',
  'A small computer at home runs the log book',
  'I keep my log on paper and enter every contact at once',
  'The QSL cards usually arrive after a few weeks in the post',
  'After lunch I go into the garden and listen for an hour',
  'The first contact with another continent is never forgotten',
  'My teacher always said listen first and then write',
  'The number of amateurs in Europe is over 700000',
  'In Morse the rhythm counts more than the speed',
  'On Friday there is coffee and cake in the clubhouse',
  'The mast is 12 metres high and held by four guy ropes',
  'A line of 50 ohms suits most antennas',
  'Today I worked 14 stations and heard 9 countries',
  'Your signal is five and nine here',
  'Few things are as calming as Morse',
  'The receiver is noisy today, probably because of the weather',
  'The ship reports in every evening at the same time',
  'The gap between the words is as important in Morse as the characters',
  'The old tube radio still works and has a warm sound',
  'A long wire antenna needs a good tuner and a short feed line',
  'He sent the message twice so that nothing was lost',
  'The lighthouse keeper learned Morse as a young man',
];

const _namesEn = [
  'JOHN', 'MARY', 'PETER', 'ANNE', 'DAVID', 'SUSAN', 'GEORGE', 'HELEN', 'ROBERT',
  'LINDA', 'PAUL', 'CLARE', 'MARK', 'JANE', 'TOM', 'ALICE', 'FRANK', 'RUTH',
];

class _Region {
  final List<String> prefixes, towns;
  const _Region(this.prefixes, this.towns);
}

const _uk = _Region(['G', 'G', 'M', '2E'], [
  'LONDON', 'LEEDS', 'BRISTOL', 'YORK', 'OXFORD', 'CARDIFF', 'GLASGOW', 'BELFAST', 'DERBY',
]);
const _us = _Region(['W', 'K', 'N', 'W'], [
  'BOSTON', 'DENVER', 'DALLAS', 'SEATTLE', 'CHICAGO', 'ATLANTA', 'PHOENIX', 'MIAMI',
]);
const _nz = _Region(['ZL'], [
  'AUCKLAND', 'WELLINGTON', 'DUNEDIN', 'NELSON', 'HAMILTON', 'NAPIER', 'TAUPO',
]);
const _in = _Region(['VU'], [
  'DELHI', 'MUMBAI', 'PUNE', 'CHENNAI', 'KOLKATA', 'BANGALORE', 'JAIPUR',
]);
const _any = _Region(['G', 'W', 'K', 'ZL', 'VU', 'M'], [
  'LONDON', 'BOSTON', 'AUCKLAND', 'DELHI', 'SYDNEY', 'TORONTO', 'DUBLIN',
]);

_Region _regionOf(String family) => switch (family) {
      'uk' => _uk,
      'us' => _us,
      'nz' => _nz,
      'in' => _in,
      _ => _any,
    };

T _pick<T>(Random r, List<T> l) => l[r.nextInt(l.length)];

String _call(_Region g, Random r) {
  final p = _pick(r, g.prefixes);
  final d = '${p == 'VU' ? 2 + r.nextInt(2) : r.nextInt(10)}';
  final n = 2 + r.nextInt(2);
  final l = String.fromCharCodes([for (var i = 0; i < n; i++) 65 + r.nextInt(26)]);
  return '$p$d$l';
}

const _kHz = ['3560', '7030', '7040', '10120', '14050', '14060', '18090', '21050'];
const _rst = ['599', '579', '559', '589', '449', '339', '569'];
const _ants = ['DIPOLE', 'VERTICAL', 'YAGI', 'LONG WIRE', 'LOOP'];

/// A QSO-style English line for the exams of [family], generated fresh for
/// each call so it never repeats: call signs, names, towns, reports,
/// frequencies.
String examTemplateEn(String family, Random r) {
  final g = _regionOf(family);
  return switch (r.nextInt(8)) {
    0 => 'HELLO ${_call(g, r)} THIS IS ${_call(g, r)} MY NAME IS ${_pick(r, _namesEn)}',
    1 => 'MY QTH IS ${_pick(r, g.towns)} AND YOUR REPORT IS ${_pick(r, _rst)}',
    2 => '${_call(g, r)} DE ${_call(g, r)} YOUR SIGNAL IS ${_pick(r, _rst)} IN ${_pick(r, g.towns)}',
    3 => 'I AM WORKING ON ${_pick(r, _kHz)} KHZ WITH ${5 + 5 * r.nextInt(20)} WATTS',
    4 => 'I HAVE A ${_pick(r, _ants)} ANTENNA AND ${10 + r.nextInt(90)} WATTS',
    5 => 'THANK YOU ${_pick(r, _namesEn)} FOR THE QSO WITH ${_call(g, r)} SEE YOU SOON',
    6 => 'THE STATION ${_call(g, r)} IS IN ${_pick(r, g.towns)} AND ACTIVE ON ${_pick(r, _kHz)} KHZ',
    _ => 'WE MEET ON THE ${1 + r.nextInt(28)} AT ${8 + r.nextInt(12)} IN ${_pick(r, g.towns)}',
  };
}
