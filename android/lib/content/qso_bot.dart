import 'dart:math';

// QSO Bot: a simulated CW QSO partner, ported from the firmware's
// MorseQsoBot.cpp (state machine + descriptors), MorseQsoBotMatch.h (token
// classifiers) and qso_content.h (content pools), reference tag V9.0.
//
// The engine is UI-free: the screen feeds decoded characters in the
// firmware's encodeProSigns() form (letters lowercase, <sk> -> 'K', <kn> -> 'N',
// <ka> -> 'A', <as> -> 'S', <ve> -> 'E', <bk> -> 'B', <err> -> 'R',
// unknown -> 'U'), calls tick() periodically and txDone() when the bot's
// transmission has finished playing. Bot text uses this app's convention:
// ordinary letters lowercase, prosigns as explicit <xx> tokens.

// ── Matcher primitives (MorseQsoBotMatch.h) ─────────────────────────────

class QsoMatch {
  static bool _isUpper(String c) => c.compareTo('A') >= 0 && c.compareTo('Z') <= 0 && c.length == 1;
  static bool _isDigit(String c) => c.length == 1 && c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

  /// Callsign shape: [prefix 1..2, ≥1 letter][area digit][suffix 1..4 letters](/TAIL).
  static bool looksLikeCallsign(String tok) {
    final len = tok.length;
    if (len < 3 || len > 10) return false;
    var coreLen = len;
    for (var i = 0; i < len; i++) {
      if (tok[i] == '/') {
        coreLen = i;
        if (i + 1 >= len) return false;
        for (var t = i + 1; t < len; t++) {
          if (!(_isUpper(tok[t]) || _isDigit(tok[t]))) return false;
        }
        break;
      }
    }
    if (coreLen < 3) return false;
    var sufStart = coreLen;
    while (sufStart > 0 && _isUpper(tok[sufStart - 1])) {
      sufStart--;
    }
    final sufLen = coreLen - sufStart;
    if (sufLen < 1 || sufLen > 4) return false;
    final areaPos = sufStart - 1;
    if (areaPos < 1) return false;
    if (!_isDigit(tok[areaPos])) return false;
    final preLen = areaPos;
    if (preLen < 1 || preLen > 2) return false;
    var preHasLetter = false;
    for (var j = 0; j < areaPos; j++) {
      final c = tok[j];
      if (_isUpper(c)) {
        preHasLetter = true;
      } else if (!_isDigit(c)) {
        return false;
      }
    }
    return preHasLetter;
  }

  static bool matchCallsign(String tok, String botCall) =>
      looksLikeCallsign(tok) && tok != botCall.toUpperCase();

  /// Cut numbers: T->0, A->1, N->9.
  static String normalizeCutNumbers(String tok) {
    final sb = StringBuffer();
    for (final c in tok.toUpperCase().split('')) {
      sb.write(switch (c) { 'T' => '0', 'A' => '1', 'N' => '9', _ => c });
    }
    return sb.toString();
  }

  static bool matchRST(String tok) {
    final n = normalizeCutNumbers(tok);
    if (n.length != 3) return false;
    if (n.codeUnitAt(0) < 0x33 || n.codeUnitAt(0) > 0x35) return false;
    return _isDigit(n[1]) && _isDigit(n[2]);
  }

  static bool allDigits(String s) => s.isNotEmpty && s.split('').every(_isDigit);

  static bool matchZone(String tok) {
    final n = normalizeCutNumbers(tok);
    if (!allDigits(n) || n.isEmpty || n.length > 2) return false;
    final v = int.parse(n);
    return v >= 1 && v <= 40;
  }

  static bool matchSerial(String tok) {
    final n = normalizeCutNumbers(tok);
    return allDigits(n) && n.isNotEmpty && n.length <= 4;
  }

  static bool matchExchange(String tok, int contestType) =>
      contestType == 0 ? matchZone(tok) : matchSerial(tok);

  static bool matchRef(String tok, String botRef) => tok.toUpperCase() == botRef.toUpperCase();

  static bool matchProsignTok(String tok, String expected) =>
      expected.isNotEmpty && tok.toUpperCase() == expected.toUpperCase();

  static const commonNoise = ['de', 'dr', 'pse', 'qsl', 'tnx', 'tu', 'ok', 'fb', 'es',
    'qrl', 'om', 'oc', 'dx', 'hr', 'gm', 'ga', 'ge', 'gd', 'cfm', 'cpy', 'ant', 'rig'];
  // "k" deliberately not noise: see the firmware comment (a split-off
  // callsign prefix "K" must reach the concat buffer).
  static const callsignNoise = ['bk', 'qrz', 'qrz?', 'cq', 'sota', 'pota'];
  static const rstNoise      = ['r', 'rr', 'ur', 'qsa', 'qrk', 'bk', 'rst'];
  static const refNoise      = ['qth', 'loc', 'ref', 'r', 'rr', 'bk'];
  static const prosignNoise  = <String>[];
  static const exchangeNoise = ['5nn', '599', 'ur', 'r', 'rr', 'nr', 'bk', 'tu'];

  static bool isNoiseToken(String tok, List<String> extraNoise, String expected) {
    final u = tok.toUpperCase();
    if (expected.isNotEmpty && u == expected.toUpperCase()) return false;
    return commonNoise.any((n) => n.toUpperCase() == u) ||
        extraNoise.any((n) => n.toUpperCase() == u);
  }

  static bool isEndOfOver(String upper) =>
      upper == 'K' || upper == '+' || upper == 'AR' || upper == '73' ||
      upper == '72' || upper == 'BK' || upper == 'KK';

  static bool isSlotKeyword(String tok) => const {
    'rst', 'call', 'cl', 'ur', 'qth', 'loc', 'ref', 'sota', 'pota', 'summit',
    'name', 'op', 'nm'}.contains(tok.toLowerCase());

  static bool isRepeatTrigger(String upper) => upper == 'AGN' || upper == 'RPT' || upper == '?';
}

enum FieldCur { none, name, qth, rst, other }

/// Standard-QSO keyword-field parser (SLOT_INFO).
class InfoParser {
  FieldCur cur = FieldCur.none;
  bool rst = false, other = false, framed = false;
  String name = '', qth = '';

  void reset() {
    cur = FieldCur.none; rst = false; other = false; framed = false; name = ''; qth = '';
  }

  void feed(String token) {
    if (QsoMatch.looksLikeCallsign(token)) framed = true;
    final low = token.toLowerCase();
    if (low == 'de') { framed = true; cur = FieldCur.none; return; }
    if (low == 'name' || low == 'op' || low == 'nm') { cur = FieldCur.name; return; }
    if (low == 'qth' || low == 'loc' || low == 'qra') { cur = FieldCur.qth; return; }
    if (const {'rig', 'tcvr', 'radio', 'trx', 'ant', 'antenna', 'aerial', 'wx', 'temp',
        'age', 'yrs'}.contains(low)) { cur = FieldCur.other; other = true; return; }
    if (low == 'rst' || low == 'ur' || low == 'urs') { cur = FieldCur.rst; return; }
    if (const {'=', 'es', 'bt', 'hw', 'hw?', 'pse'}.contains(low)) { cur = FieldCur.none; return; }
    if (QsoMatch.matchRST(token)) { rst = true; cur = FieldCur.none; return; }
    if (cur == FieldCur.name) {
      name = _appendDedup(name, token);
    } else if (cur == FieldCur.qth) {
      qth = _appendDedup(qth, token);
    }
  }

  static String _appendDedup(String field, String tok) {
    final sp = field.lastIndexOf(' ');
    final last = sp < 0 ? field : field.substring(sp + 1);
    if (last.toLowerCase() == tok.toLowerCase()) return field;
    return field.isEmpty ? tok : '$field $tok';
  }
}

// ── Content pools (qso_content.h) ───────────────────────────────────────

const contEU = 0x01, contNA = 0x02, contSA = 0x04, contAF = 0x08,
    contAS = 0x10, contOC = 0x20, contAll = 0x7F;

class _CV {
  final String value;
  final int continent;
  const _CV(this.value, this.continent);
}

String _pickByContinent(Random rnd, List<_CV> arr, int want) {
  final matches = arr.where((v) => v.continent & want != 0).toList();
  if (matches.isEmpty) return arr[rnd.nextInt(arr.length)].value;
  return matches[rnd.nextInt(matches.length)].value;
}

const _naEuOcAf = contNA | contEU | contOC | contAF;
const _naEuOc = contNA | contEU | contOC;
const _names = [
  _CV('JOHN', _naEuOcAf), _CV('MIKE', _naEuOcAf), _CV('DAVE', _naEuOcAf), _CV('PETER', _naEuOcAf),
  _CV('BOB', contNA | contOC), _CV('TOM', _naEuOc), _CV('JAMES', _naEuOc), _CV('MARK', _naEuOc),
  _CV('TIM', _naEuOc), _CV('STEVE', _naEuOc), _CV('ALEX', _naEuOc), _CV('PAT', contNA | contEU),
  _CV('KEN', contNA | contOC), _CV('BILL', contNA | contOC), _CV('JIM', contNA | contOC),
  _CV('RON', contNA | contOC), _CV('ED', contNA), _CV('RAY', contNA), _CV('AL', contNA),
  _CV('ANNA', contEU | contNA | contAF), _CV('HANS', contEU), _CV('WERNER', contEU),
  _CV('SVEN', contEU), _CV('LARS', contEU), _CV('NILS', contEU), _CV('ERIK', contEU),
  _CV('JAN', contEU), _CV('OLEG', contEU), _CV('IGOR', contEU), _CV('PAVEL', contEU),
  _CV('HIRO', contAS), _CV('YUKI', contAS), _CV('KENJI', contAS), _CV('TAK', contAS),
  _CV('LEO', contEU | contSA), _CV('LUIS', contSA | contEU), _CV('PEDRO', contSA | contEU),
  _CV('CARLOS', contSA | contEU), _CV('JUAN', contSA | contEU), _CV('ANDRE', contSA | contEU | contAF),
];

const _qths = [
  _CV('VIENNA', contEU), _CV('LONDON', contEU), _CV('BERLIN', contEU), _CV('ROME', contEU),
  _CV('MADRID', contEU), _CV('OSLO', contEU), _CV('PRAGUE', contEU), _CV('PARIS', contEU),
  _CV('BERN', contEU), _CV('WARSAW', contEU), _CV('BUDAPEST', contEU), _CV('DUBLIN', contEU),
  _CV('LISBON', contEU), _CV('ATHENS', contEU), _CV('ZURICH', contEU), _CV('HELSINKI', contEU),
  _CV('DENVER', contNA), _CV('BOSTON', contNA), _CV('DALLAS', contNA), _CV('MIAMI', contNA),
  _CV('OTTAWA', contNA), _CV('TORONTO', contNA), _CV('CHICAGO', contNA), _CV('SEATTLE', contNA),
  _CV('TOKYO', contAS), _CV('OSAKA', contAS), _CV('NAGOYA', contAS), _CV('SEOUL', contAS),
  _CV('MANILA', contAS),
  _CV('SYDNEY', contOC), _CV('MELBOURNE', contOC), _CV('PERTH', contOC), _CV('AUCKLAND', contOC),
  _CV('RIO', contSA), _CV('LIMA', contSA), _CV('BOGOTA', contSA), _CV('SANTIAGO', contSA),
  _CV('CORDOBA', contSA),
  _CV('CAIRO', contAF), _CV('NAIROBI', contAF), _CV('CAPETOWN', contAF), _CV('DURBAN', contAF),
  _CV('TUNIS', contAF),
];

const _rigs = ['IC7300', 'FT991', 'K3', 'KX3', 'KX2', 'TS590', 'FT817', 'IC705',
  'FTDX10', 'K4', 'ELECRAFT', 'FT710',
  'QCX', 'QMX', 'MTR', 'KX1', 'ATS', 'HB1B', 'HOMEBREW',
  'FT101', 'TS520', 'IC756', 'TS850', 'YAESU', 'ICOM', 'KENWOOD'];
const _ants = ['DIPOLE', 'EFHW', 'VERT', 'BEAM', 'HEXBEAM', 'GP', 'G5RV', 'LOOP',
  'ENDFED', 'INVV', 'YAGI', 'DELTA', 'SLOPER', 'MAGLOOP', 'JPOLE', 'FAN', 'LONGWIRE', 'W3DZZ'];
const _wxs = ['SUNNY', 'CLOUDY', 'RAIN', 'SNOW', 'CLEAR', 'FOG', 'WINDY', 'COLD',
  'WARM', 'HOT', 'MILD', 'STORM', 'DRIZZLE', 'HUMID', 'FROST', 'ICE', 'HAIL', 'OVERCAST', 'BREEZY'];
const _ages = ['25', '32', '41', '55', '63', '70', '45', '38', '52', '29', '47', '60'];

const _sotaRefs = [
  _CV('oe/at-001', contEU), _CV('oe/st-002', contEU), _CV('oe/sb-005', contEU), _CV('oe/kt-010', contEU),
  _CV('g/ld-001', contEU), _CV('g/ld-003', contEU), _CV('g/sp-001', contEU), _CV('g/wb-002', contEU),
  _CV('dl/al-001', contEU), _CV('dl/bw-021', contEU), _CV('dl/am-006', contEU), _CV('dl/sx-001', contEU),
  _CV('f/vo-001', contEU), _CV('hb/vs-001', contEU), _CV('sp/bz-001', contEU), _CV('i/ra-001', contEU),
  _CV('w6/ss-001', contNA), _CV('w6/ct-001', contNA), _CV('w2/cr-003', contNA), _CV('w4/cm-005', contNA),
  _CV('w7/wa-005', contNA), _CV('ve7/vc-001', contNA),
  _CV('ja/nn-001', contAS), _CV('ja/so-004', contAS), _CV('hl/gd-001', contAS), _CV('bv/tp-001', contAS),
  _CV('vk1/ac-014', contOC), _CV('vk3/vs-001', contOC), _CV('vk5/se-001', contOC), _CV('zl1/wk-001', contOC),
  _CV('lu/ic-001', contSA), _CV('py/sp-001', contSA), _CV('ce/ms-001', contSA),
  _CV('zs/wc-001', contAF), _CV('cn/mo-001', contAF), _CV('ea8/lp-001', contAF),
];

const _potaRefs = [
  _CV('oe-0012', contEU), _CV('oe-0044', contEU), _CV('dl-0021', contEU), _CV('dl-0103', contEU),
  _CV('g-0001', contEU), _CV('g-0034', contEU), _CV('f-1002', contEU), _CV('i-0150', contEU),
  _CV('us-0001', contNA), _CV('us-1234', contNA), _CV('us-4567', contNA), _CV('us-7777', contNA),
  _CV('ve-0099', contNA), _CV('ve-0050', contNA),
  _CV('ja-0007', contAS), _CV('ja-0210', contAS), _CV('hl-0003', contAS), _CV('bv-0001', contAS),
  _CV('vk-0042', contOC), _CV('vk-0301', contOC), _CV('vk-0500', contOC), _CV('zl-0004', contOC),
  _CV('lu-0001', contSA), _CV('py-0010', contSA), _CV('ce-0005', contSA),
  _CV('zs-0007', contAF), _CV('cn-0003', contAF),
];

// ── Sequence descriptors (MorseQsoBot.cpp) ──────────────────────────────

enum _K { end, botTx, expect, expectOpt, waitUserCq, waitCqLoop, loop, pauseMs }

enum QsoSlot { none, callsign, rst, ref, prosign, exchange, info }

class _Step {
  final _K kind;
  final String? tmpl;
  final QsoSlot slot;
  final int arg;
  const _Step(this.kind, this.tmpl, this.slot, this.arg);
}

// The firmware's uppercase K (= <sk>) sign-offs are written as <sk> here
// (CLAUDE.md rule 3). Everything else is verbatim.
const _sotaPotaSteps = [
  /* 0 */ _Step(_K.waitUserCq, null, QsoSlot.none, 5),
  /* 1 */ _Step(_K.botTx, '[BOTCALL] [BOTCALL]', QsoSlot.none, 0),
  /* 2 */ _Step(_K.expect, '5NN', QsoSlot.rst, 0),
  /* 3 */ _Step(_K.botTx, 'r ur 5nn 5nn[S2SREF] tu 73 e e <sk>', QsoSlot.none, 0),
  /* 4 */ _Step(_K.end, null, QsoSlot.none, 0),
  /* 5 */ _Step(_K.botTx, 'cq [ACT] cq [ACT] de [BOTCALL] [BOTCALL] k', QsoSlot.none, 0),
  /* 6 */ _Step(_K.expect, '[USERCALL]', QsoSlot.callsign, 4),
  /* 7 */ _Step(_K.botTx, '[USERCALL] de [BOTCALL] ur 5nn 5nn bk', QsoSlot.none, 0),
  /* 8 */ _Step(_K.expect, '5NN', QsoSlot.rst, 0),
  /* 9 */ _Step(_K.botTx, 'r qth [BOTREF] [BOTREF] bk', QsoSlot.none, 0),
  /* 10*/ _Step(_K.expectOpt, 'r', QsoSlot.prosign, 0),
  /* 11*/ _Step(_K.botTx, 'tu 73 e e de [BOTCALL] <sk>', QsoSlot.none, 0),
  /* 12*/ _Step(_K.end, null, QsoSlot.none, 0),
];

const _contestSteps = [
  /* 0 */ _Step(_K.waitUserCq, null, QsoSlot.none, 5),
  /* 1 */ _Step(_K.botTx, '[BOTCALL]', QsoSlot.none, 0),
  /* 2 */ _Step(_K.expect, '', QsoSlot.exchange, 3),
  /* 3 */ _Step(_K.botTx, '5nn [BOTEXCH]', QsoSlot.none, 0),
  /* 4 */ _Step(_K.waitCqLoop, null, QsoSlot.none, 1),
  /* 5 */ _Step(_K.botTx, 'cq test de [BOTCALL] [BOTCALL] test', QsoSlot.none, 0),
  /* 6 */ _Step(_K.expect, '', QsoSlot.callsign, 4),
  /* 7 */ _Step(_K.botTx, '[USERCALL] 5nn [BOTEXCH]', QsoSlot.none, 0),
  /* 8 */ _Step(_K.expect, '', QsoSlot.exchange, 3),
  /* 9 */ _Step(_K.botTx, 'tu', QsoSlot.none, 0),
  /* 10*/ _Step(_K.loop, null, QsoSlot.none, 5),
];

const _standardSteps = [
  /* 0 */ _Step(_K.waitUserCq, null, QsoSlot.none, 9),
  /* 1 */ _Step(_K.botTx, '[USERCALL] de [BOTCALL] [BOTCALL] k', QsoSlot.none, 0),
  /* 2 */ _Step(_K.expect, '', QsoSlot.info, 3),
  /* 3 */ _Step(_K.botTx, '[USERCALL] de [BOTCALL] = fb dr [USERNAME] = ur rst 599 599 = name [BOTNAME] [BOTNAME] = qth [BOTQTH] [BOTQTH] = hw? k', QsoSlot.none, 0),
  /* 4 */ _Step(_K.expectOpt, '', QsoSlot.info, 0),
  /* 5 */ _Step(_K.botTx, '= all copy fb = rig [BOTRIG] = ant [BOTANT] = wx [BOTWX] = age [BOTAGE] = hw? bk', QsoSlot.none, 0),
  /* 6 */ _Step(_K.expectOpt, '73', QsoSlot.prosign, 0),
  /* 7 */ _Step(_K.botTx, 'tnx fb qso dr [USERNAME] = 73 73 = [USERCALL] de [BOTCALL] <sk>', QsoSlot.none, 0),
  /* 8 */ _Step(_K.end, null, QsoSlot.none, 0),
  /* 9 */ _Step(_K.botTx, 'cq cq de [BOTCALL] [BOTCALL] k', QsoSlot.none, 0),
  /* 10*/ _Step(_K.expect, '', QsoSlot.callsign, 4),
  /* 11*/ _Step(_K.botTx, '[USERCALL] de [BOTCALL] = gm dr om = ur rst 599 599 = name [BOTNAME] [BOTNAME] = qth [BOTQTH] [BOTQTH] = hw? k', QsoSlot.none, 0),
  /* 12*/ _Step(_K.expect, '', QsoSlot.info, 3),
  /* 13*/ _Step(_K.botTx, '[USERCALL] de [BOTCALL] = fb dr [USERNAME] = rig [BOTRIG] = ant [BOTANT] = wx [BOTWX] = age [BOTAGE] = hw? bk', QsoSlot.none, 0),
  /* 14*/ _Step(_K.expectOpt, '', QsoSlot.info, 0),
  /* 15*/ _Step(_K.botTx, 'tnx fb qso dr [USERNAME] = 73 73 = [USERCALL] de [BOTCALL] <sk>', QsoSlot.none, 0),
  /* 16*/ _Step(_K.expectOpt, '73', QsoSlot.prosign, 0),
  /* 17*/ _Step(_K.end, null, QsoSlot.none, 0),
];

// ── Engine ──────────────────────────────────────────────────────────────

enum QsoType { sotaPota, standard, contest }

/// Firmware posQsoBotLevel.
enum QsoLevel { beginner, intermediate, advanced }

/// What the bot is doing, for the screen's status line.
enum QsoPhase { opening, botTx, expect, pause, done }

class QsoCall {
  final String call;
  final int continent, zone;
  const QsoCall(this.call, this.continent, this.zone);
}

class QsoBot {
  final QsoType type;
  final QsoLevel level;
  final int contestType;          // 0 = CQ WW (zone), 1 = WPX/Sprint (serial)
  final QsoCall Function() nextCall;
  final void Function(String text, int wpm) play;
  final void Function() stopPlay;
  final void Function(String text) info;
  final Random _rnd;
  final int Function() _clock;

  /// The user's keyer speed (firmware MorsePreferences::wpm), live.
  int userWpm;
  /// Keyer word gap in dits (firmware interWordSpace / ditLength).
  int interWordDits;

  static const wpmMin = 5, wpmMax = 60;

  QsoBot({
    required this.type,
    required this.level,
    required this.contestType,
    required String userCall,
    required this.userWpm,
    required this.interWordDits,
    required this.nextCall,
    required this.play,
    required this.stopPlay,
    required this.info,
    Random? random,
    int Function()? clock,
  })  : _rnd = random ?? Random(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _steps = switch (type) {
          QsoType.contest => _contestSteps,
          QsoType.standard => _standardSteps,
          QsoType.sotaPota => _sotaPotaSteps,
        },
        _sessionMode = type == QsoType.contest {
    _userCall = userCall.isEmpty ? 'OE1XXX' : userCall.toUpperCase();
  }

  int _rand(int n) => _rnd.nextInt(n);
  int _randRange(int a, int b) => a + _rnd.nextInt(b - a);
  int _now() => _clock();

  // ---- Input accumulator ----
  static const _inputMax = 31;
  String _inputBuf = '';
  int _lastCharTime = 0;          // 0 = submit pending or idle
  bool _eeeeDetected = false;

  void _inputReset() { _inputBuf = ''; _lastCharTime = 0; }

  /// Feeds one decoded character (encodeProSigns form, see the file header),
  /// or ' ' at a word gap.
  void feed(String c) {
    if (_state == QsoPhase.done) return;
    _inputFeed(c);
    tick();          // consume a completed word before the next char arrives
  }

  void _inputFeed(String c) {
    _stateStart = _now();
    if (c == ' ') {
      if (_inputBuf.isNotEmpty) _lastCharTime = 0;
      return;
    }
    if (c == 'R') {                       // <err>: disregard the current word
      _inputBuf = ''; _lastCharTime = 0; _eeeeDetected = true;
      return;
    }
    c = c.toUpperCase();
    if (_inputBuf.length < _inputMax) _inputBuf += c;
    _lastCharTime = _now();
    if (_inputBuf.endsWith('EEEE')) {
      _inputBuf = ''; _lastCharTime = 0; _eeeeDetected = true;
    }
  }

  bool get _inputMidToken => _inputBuf.isNotEmpty && _lastCharTime > 0;

  bool get _inputSubmitReady {
    if (_inputBuf.isEmpty) return false;
    if (_lastCharTime == 0) return true;
    final dit = (1200 / userWpm).round();
    var wordGap = interWordDits * dit + dit;
    if (wordGap < 1200) wordGap = 1200;
    return _now() - _lastCharTime > wordGap;
  }

  // ---- Actors ----
  String _botCall = '', _botRef = '', _botName = '', _botQth = '';
  String _botRig = '', _botAnt = '', _botWx = '', _botAge = '';
  late String _userCall;
  String _userName = '';
  int _activity = 0;              // 0 = SOTA, 1 = POTA
  bool _botAlsoActivator = false;
  int _botZone = 14;
  int _botSerial = 1;
  int _botWpm = 0;
  static const _qrsStep = 3;

  String get botCall => _botCall;
  String get userCall => _userCall;
  int get botWpm => _botWpm;

  void _pickBotIdentity() {
    final c = nextCall();
    final cont = c.continent;
    _botZone = c.zone;
    if (_botZone < 1 || _botZone > 40) _botZone = _randRange(1, 41);
    _botCall = c.call.toUpperCase();
    _activity = _rand(2);
    _botRef = _pickByContinent(_rnd, _activity == 0 ? _sotaRefs : _potaRefs, cont);
    _botName = _pickByContinent(_rnd, _names, cont);
    _botQth = _pickByContinent(_rnd, _qths, cont);
    _botRig = _rigs[_rand(_rigs.length)];
    _botAnt = _ants[_rand(_ants.length)];
    _botWx = _wxs[_rand(_wxs.length)];
    _botAge = _ages[_rand(_ages.length)];
    _botAlsoActivator = _rand(100) < 15;
    _botSerial = _randRange(1, 600);

    _botWpm = userWpm;
    if (level != QsoLevel.beginner) {
      final chance = level == QsoLevel.advanced ? 50 : 30;
      if (_rand(100) < chance) {
        final delta = level == QsoLevel.advanced ? _randRange(4, 9) : 4;
        final dir = _rand(2) == 1 ? 1 : -1;
        var w = (userWpm + dir * delta).clamp(wpmMin, wpmMax);
        if (w == userWpm) w = (userWpm - dir * delta).clamp(wpmMin, wpmMax);
        _botWpm = w;
      }
    }
  }

  void _adjustBotSpeed(int dir) {
    final w = (_botWpm > 0 ? _botWpm : userWpm) + dir * _qrsStep;
    _botWpm = w.clamp(wpmMin, wpmMax);
  }

  String _expand(String tmpl) {
    var out = tmpl;
    out = out.replaceAll('[ACT]', _activity == 0 ? 'sota' : 'pota');
    out = out.replaceAll('[S2SREF]', _botAlsoActivator ? ' = qth [BOTREF] [BOTREF]' : '');
    final exch = contestType == 0 ? '$_botZone' : _botSerial.toString().padLeft(3, '0');
    out = out.replaceAll('[BOTEXCH]', exch);
    out = out
        .replaceAll('[BOTCALL]', _botCall.toLowerCase())
        .replaceAll('[BOTREF]', _botRef.toLowerCase())
        .replaceAll('[BOTNAME]', _botName.toLowerCase())
        .replaceAll('[BOTQTH]', _botQth.toLowerCase())
        .replaceAll('[BOTRIG]', _botRig.toLowerCase())
        .replaceAll('[BOTANT]', _botAnt.toLowerCase())
        .replaceAll('[BOTWX]', _botWx.toLowerCase())
        .replaceAll('[BOTAGE]', _botAge.toLowerCase())
        .replaceAll('[USERCALL]', _userCall.toLowerCase())
        .replaceAll('[USERNAME]', (_userName.isNotEmpty ? _userName : 'om').toLowerCase());
    return out;
  }

  // ---- Runtime state ----
  final List<_Step> _steps;
  final bool _sessionMode;
  int _pc = 0;
  QsoPhase _state = QsoPhase.done;
  int _stateStart = 0;
  int _retriesLeft = 0;
  bool _recoveryActive = false;
  String _concatBuf = '';

  QsoPhase get phase => _state;
  /// The current step waits for the user (EXPECT or the CQ opening).
  bool get listening => _state == QsoPhase.expect || _state == QsoPhase.opening;
  /// ms since the current wait started (status countdowns).
  int get waitingMs => _now() - (_state == QsoPhase.opening ? _openingStart : _stateStart);

  bool _userStartedCalling = false;
  bool _openingCallSeen = false;
  int _openingStart = 0;
  int _openingActivity = 0;
  static const _openingWaitMs = 5000;
  static const _callEndSilenceMs = 1800;
  static const _sessionIdleMs = 15000;

  bool _waitTimeoutEndsSession = false;
  int _waitTimeoutTarget = 0;
  int _waitUserCqTarget = 0xFF;

  bool _overStarted = false;
  bool _overMatched = false;
  String _overMatchedValue = '';
  bool _overRepeat = false;
  String _overRepeatSlot = '';
  int _overActivity = 0;
  static const _optNoReplyMs = 4000;

  int get _overEndSilenceMs => switch (level) {
    QsoLevel.beginner => 3200, QsoLevel.advanced => 2000, _ => 2500 };
  int get _noReplyMs => switch (level) {
    QsoLevel.beginner => 16000, QsoLevel.advanced => 9000, _ => 12000 };

  String _lastBotTx = '';
  String _repeatSlot = '';
  bool _rstReceived = false;
  bool _qsoWarm = false;
  bool _userInformal = false;
  final _info = InfoParser();

  // ---- Slot grammar ----
  List<String> _noiseFor(QsoSlot s) => switch (s) {
    QsoSlot.callsign => QsoMatch.callsignNoise,
    QsoSlot.rst => QsoMatch.rstNoise,
    QsoSlot.ref => QsoMatch.refNoise,
    QsoSlot.exchange => QsoMatch.exchangeNoise,
    _ => QsoMatch.prosignNoise,
  };

  bool _allowConcat(QsoSlot s) =>
      s == QsoSlot.callsign || s == QsoSlot.rst || s == QsoSlot.ref || s == QsoSlot.exchange;

  bool _matchSlot(QsoSlot kind, String tok, String expected) => switch (kind) {
    QsoSlot.callsign => QsoMatch.matchCallsign(tok, _botCall),
    QsoSlot.rst => QsoMatch.matchRST(tok),
    QsoSlot.ref => QsoMatch.matchRef(tok, _botRef),
    QsoSlot.prosign => QsoMatch.matchProsignTok(tok, expected),
    QsoSlot.exchange => QsoMatch.matchExchange(tok, contestType),
    _ => false,
  };

  // ---- State transitions ----

  String _maybeDropPreamble(String text) {
    if (level == QsoLevel.beginner || !_qsoWarm) return text;
    final drop = _userInformal || level == QsoLevel.advanced;
    if (!drop) return text;
    final pre = '${_userCall.toLowerCase()} de ${_botCall.toLowerCase()}';
    if (!text.startsWith(pre)) return text;
    var rest = text.substring(pre.length).trim();
    if (rest.startsWith('=')) rest = rest.substring(1).trim();
    return rest;
  }

  void _startBotTx(String text) {
    var tx = _maybeDropPreamble(text);
    if (level == QsoLevel.beginner) tx = tx.replaceAll('5nn', '599');
    _state = QsoPhase.botTx;
    _stateStart = _now();
    play(tx, _botWpm > 0 ? _botWpm : userWpm);
  }

  void _resetOverAccumulators() {
    _overStarted = false;
    _overMatched = false;
    _overMatchedValue = '';
    _overRepeat = false;
    _overRepeatSlot = '';
    _overActivity = _now();
    _concatBuf = '';
    _eeeeDetected = false;
    _info.reset();
  }

  void _startExpect(int budget) {
    _inputReset();
    _resetOverAccumulators();
    final base = budget == 0 ? (_steps[_pc].slot == QsoSlot.callsign ? 4 : 2) : budget;
    final adj = base + (level == QsoLevel.beginner ? 1 : level == QsoLevel.advanced ? -1 : 0);
    _retriesLeft = adj < 1 ? 1 : adj;
    _state = QsoPhase.expect;
    _stateStart = _now();
  }

  void _reEnterExpect() {
    _inputReset();
    _resetOverAccumulators();
    _state = QsoPhase.expect;
    _stateStart = _now();
  }

  void _startOpening() {
    _inputReset();
    _concatBuf = '';
    _userStartedCalling = false;
    _openingCallSeen = false;
    _openingStart = _now();
    _openingActivity = _now();
    _state = QsoPhase.opening;
  }

  void _enterStep() {
    if (_pc >= _steps.length) { info('QSO complete'); _state = QsoPhase.done; return; }
    final step = _steps[_pc];
    switch (step.kind) {
      case _K.end:
        info(_rstReceived ? 'QSO complete' : 'QSO complete (no RST)');
        _state = QsoPhase.done;
      case _K.botTx:
        _lastBotTx = _expand(step.tmpl!);
        _startBotTx(_lastBotTx);
      case _K.expect:
      case _K.expectOpt:
        _startExpect(step.arg);
      case _K.waitUserCq:
        _waitTimeoutEndsSession = false;
        _waitTimeoutTarget = step.arg;
        _waitUserCqTarget = 0xFF;
        _startOpening();
      case _K.waitCqLoop:
        _waitTimeoutEndsSession = true;
        _waitUserCqTarget = step.arg;
        _startOpening();
      case _K.loop:
        _pickBotIdentity();
        _pc = step.arg;
        _enterStep();
      case _K.pauseMs:
        _state = QsoPhase.pause;
        _stateStart = _now();
    }
  }

  void _advance() { _pc++; _enterStep(); }

  void _finishOpening() {
    if (_waitUserCqTarget != 0xFF) {
      _pickBotIdentity();
      _pc = _waitUserCqTarget;
      _enterStep();
    } else {
      _advance();
    }
  }

  static const _callRecovery    = ['qrz?', 'agn agn', 'call?', 'pse agn'];
  static const _callRecoveryBeg = ['qrz?', 'pse agn', 'ur call agn?'];
  static const _callRecoveryAdv = ['qrz?', 'agn', 'call?'];
  static const _genRecovery     = ['agn agn', 'agn?', 'pse rpt', 'hw?'];
  static const _genRecoveryBeg  = ['pse agn', 'agn agn', 'pse rpt'];
  static const _genRecoveryAdv  = ['agn', 'agn?', '?'];
  static const _rstRecovery     = ['pse ur rst?', 'rst?', 'ur rst agn?', 'pse rpt rst'];
  static const _rstRecoveryBeg  = ['pse ur rst?', 'ur rst agn?'];
  static const _rstRecoveryAdv  = ['rst?', 'rst pse'];

  String _pick(List<String> pool) => pool[_rand(pool.length)];

  String _recoveryPrompt(QsoSlot slot) {
    if (slot == QsoSlot.callsign) {
      return _pick(switch (level) {
        QsoLevel.beginner => _callRecoveryBeg,
        QsoLevel.advanced => _callRecoveryAdv,
        _ => _callRecovery });
    }
    return _pick(switch (level) {
      QsoLevel.beginner => _genRecoveryBeg,
      QsoLevel.advanced => _genRecoveryAdv,
      _ => _genRecovery });
  }

  String _rstRecoveryPrompt() => _pick(switch (level) {
    QsoLevel.beginner => _rstRecoveryBeg,
    QsoLevel.advanced => _rstRecoveryAdv,
    _ => _rstRecovery });

  void _enterRecovery(String prompt) {
    _recoveryActive = true;
    _startBotTx(prompt);
  }

  String _repeatSnippetFor(String kw) {
    final k = kw.toLowerCase();
    if (k == 'rst') return 'ur 5nn 5nn';
    if (k == 'call' || k == 'cl' || k == 'ur') {
      final c = _botCall.toLowerCase();
      return '$c $c';
    }
    if (const {'qth', 'loc', 'ref', 'sota', 'pota', 'summit'}.contains(k)) {
      final r = _botRef.toLowerCase();
      return 'qth $r $r';
    }
    if (k == 'name' || k == 'op' || k == 'nm') return 'name ${_botName.toLowerCase()}';
    return '';
  }

  void _executePendingRepeat() {
    var snippet = _repeatSlot.isNotEmpty ? _repeatSnippetFor(_repeatSlot) : '';
    if (snippet.isEmpty) snippet = _lastBotTx;
    if (snippet.isEmpty) snippet = 'agn';
    _repeatSlot = '';
    _enterRecovery(snippet);
  }

  void _processOver(_Step step) {
    if (_overRepeat) {
      _repeatSlot = _overRepeatSlot;
      _executePendingRepeat();
      return;
    }
    if (step.slot == QsoSlot.info) {
      if (_info.name.isNotEmpty) _userName = _info.name;
      _qsoWarm = true;
      _userInformal = !_info.framed;
      if (step.kind == _K.expectOpt) { _advance(); return; }
      if (_info.rst) { _rstReceived = true; _advance(); return; }
      if (_retriesLeft > 0) { _retriesLeft--; _enterRecovery(_rstRecoveryPrompt()); return; }
      _advance();
      return;
    }
    if (_overMatched) {
      if (step.slot == QsoSlot.callsign) _userCall = _overMatchedValue;
      if (step.slot == QsoSlot.rst) _rstReceived = true;
      _advance();
      return;
    }
    if (step.kind == _K.expectOpt) { _advance(); return; }
    if (_retriesLeft > 0) {
      _retriesLeft--;
      _enterRecovery(_recoveryPrompt(step.slot));
    } else {
      info('Giving up');
      _state = QsoPhase.done;
    }
  }

  // ---- Public control ----

  void start() {
    _pickBotIdentity();
    _inputReset();
    _pc = 0;
    _recoveryActive = false;
    _concatBuf = '';
    _eeeeDetected = false;
    _rstReceived = false;
    _qsoWarm = false;
    _userInformal = false;
    _lastBotTx = '';
    _repeatSlot = '';
    _resetOverAccumulators();
    _enterStep();
  }

  void abort() {
    if (_state == QsoPhase.done) return;
    stopPlay();
    _state = QsoPhase.done;
    info('Aborted');
  }

  /// The bot's transmission has finished playing.
  void txDone() {
    if (_state != QsoPhase.botTx) return;
    if (_recoveryActive) {
      _recoveryActive = false;
      _reEnterExpect();
    } else {
      _advance();
    }
  }

  /// One pass of the firmware's main-loop state machine (call every ~20 ms).
  void tick() {
    if (_state == QsoPhase.opening) {
      if (_inputSubmitReady) {
        final token = _inputBuf;
        final upper = token.toUpperCase();
        _inputReset();
        if (token.isNotEmpty) {
          _userStartedCalling = true;
          _openingActivity = _now();
          if (QsoMatch.looksLikeCallsign(token)) {
            if (upper != _botCall.toUpperCase()) _userCall = token;
            _openingCallSeen = true;
          }
          if (QsoMatch.isEndOfOver(upper) && _openingCallSeen) _finishOpening();
        }
      }
      if (_state == QsoPhase.opening) {
        if (_userStartedCalling) {
          if (!_inputMidToken && _now() - _openingActivity > _callEndSilenceMs) {
            _finishOpening();
          }
        } else {
          final to = _sessionMode ? _sessionIdleMs : _openingWaitMs;
          if (_now() - _openingStart > to) {
            if (_waitTimeoutEndsSession) {
              info('session end');
              _state = QsoPhase.done;
            } else {
              _pc = _waitTimeoutTarget;
              _enterStep();
            }
          }
        }
      }
    } else if (_state == QsoPhase.expect) {
      final step = _steps[_pc];
      final noise = _noiseFor(step.slot);
      final expected = step.tmpl ?? '';

      if (_inputSubmitReady) {
        final token = _inputBuf;
        final upper = token.toUpperCase();
        _inputReset();
        if (token.isNotEmpty) {
          _overStarted = true;
          _overActivity = _now();

          var consumed = false;
          if (upper == 'QRS' || upper == 'QRQ') {
            _adjustBotSpeed(upper == 'QRS' ? -1 : 1);
            consumed = true;
          } else if (QsoMatch.isRepeatTrigger(upper)) {
            _overRepeat = true; _overRepeatSlot = ''; consumed = true;
          } else if (_overRepeat && _overRepeatSlot.isEmpty && QsoMatch.isSlotKeyword(token)) {
            _overRepeatSlot = token; consumed = true;
          }

          if (!consumed) {
            if (QsoMatch.looksLikeCallsign(token)) {
              if (upper != _botCall.toUpperCase()) _userCall = token;
            }
            if (step.slot == QsoSlot.info) {
              _info.feed(token);
              if (_info.rst) _overMatched = true;
            } else if (step.slot == QsoSlot.exchange) {
              if (_matchSlot(QsoSlot.exchange, token, expected)) {
                _overMatched = true; _overMatchedValue = token;
              }
              final norm = QsoMatch.normalizeCutNumbers(token);
              if (QsoMatch.allDigits(norm)) {
                _concatBuf += norm;
                if (_concatBuf.length > 8) _concatBuf = _concatBuf.substring(_concatBuf.length - 8);
                if (_matchSlot(QsoSlot.exchange, _concatBuf, expected)) {
                  _overMatched = true; _overMatchedValue = _concatBuf;
                }
              }
            } else {
              if (_matchSlot(step.slot, token, expected)) {
                _overMatched = true; _overMatchedValue = token;
                _concatBuf = '';
              } else if (QsoMatch.isNoiseToken(token, noise, expected)) {
                // drop, keep listening
              } else if (!_overMatched && _allowConcat(step.slot)) {
                _concatBuf += token;
                if (_concatBuf.length > 16) _concatBuf = _concatBuf.substring(_concatBuf.length - 16);
                if (_matchSlot(step.slot, _concatBuf, expected)) {
                  _overMatched = true; _overMatchedValue = _concatBuf;
                }
              }
            }
          }

          if (QsoMatch.isEndOfOver(upper) && _overMatched) _processOver(step);
        }
      }

      if (_state == QsoPhase.expect && _eeeeDetected) {
        _eeeeDetected = false;
        if (step.slot == QsoSlot.info) {
          if (_info.cur == FieldCur.qth || _info.cur == FieldCur.name) {
            final f = _info.cur == FieldCur.qth ? _info.qth : _info.name;
            final sp = f.lastIndexOf(' ');
            final cut = sp < 0 ? '' : f.substring(0, sp);
            if (_info.cur == FieldCur.qth) { _info.qth = cut; } else { _info.name = cut; }
          } else if (_info.cur == FieldCur.rst) {
            _info.rst = false;
          }
        } else {
          _overMatched = false; _overMatchedValue = '';
          _overRepeat = false; _overRepeatSlot = '';
          _concatBuf = '';
        }
        _overActivity = _now();
      }

      if (_state == QsoPhase.expect && _overStarted && !_inputMidToken &&
          _now() - _overActivity > _overEndSilenceMs) {
        _processOver(step);
      }

      if (_state == QsoPhase.expect && !_overStarted && !_inputMidToken) {
        final sessionGate = _sessionMode && step.slot == QsoSlot.callsign;
        final to = step.kind == _K.expectOpt
            ? _optNoReplyMs
            : sessionGate ? _sessionIdleMs : _noReplyMs;
        if (_now() - _stateStart > to) {
          if (step.kind == _K.expectOpt) {
            _advance();
          } else if (sessionGate) {
            info('session end');
            _state = QsoPhase.done;
          } else if (_retriesLeft > 0) {
            _retriesLeft--;
            _enterRecovery(_recoveryPrompt(step.slot));
          } else {
            info('Giving up');
            _state = QsoPhase.done;
          }
        }
      }
    } else if (_state == QsoPhase.pause) {
      if (_now() - _stateStart >= _steps[_pc].arg) _advance();
    }
  }
}
