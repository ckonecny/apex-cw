// Building blocks for the mini-QSO stage (issue #40, DECISIONS.md "Mini-QSO
// stage"). Radio style as on the air: the abbreviations are the same in every
// language, only the questions are translated. Plain ASCII, as the CW engine
// plays it; fictional values only. Own lists, written for this app.

const mqNames = <String>[
  'TOM', 'ANNA', 'MAX', 'EVA', 'PAUL', 'LENA', 'KARL', 'NINA', 'JACK', 'SUE',
  'PETER', 'MIA', 'FRANZ', 'LISA', 'BEN', 'JOHN',
];

const mqCities = <String>[
  'WIEN', 'GRAZ', 'LINZ', 'SALZBURG', 'BERLIN', 'HAMBURG', 'BONN', 'BERN',
  'BASEL', 'LONDON', 'PARIS', 'ROMA', 'OSLO', 'MADRID', 'BOSTON', 'DENVER',
];

/// Reports as sent in CW, digits only (readability, strength, tone).
const mqRsts = <String>['599', '589', '579', '569', '559', '449', '339'];

const mqRigs = <String>['IC7300', 'FT991', 'K3', 'TS590', 'FT817', 'KX3', 'IC705', 'QCX'];
const mqPowers = <String>['5W', '10W', '25W', '50W', '100W', '400W'];
const mqAntennas = <String>['DIPOLE', 'VERTICAL', 'YAGI', 'LONGWIRE', 'EFHW', 'LOOP'];
const mqWeather = <String>['SUNNY', 'CLOUDY', 'RAIN', 'SNOW', 'WINDY', 'FOG'];
