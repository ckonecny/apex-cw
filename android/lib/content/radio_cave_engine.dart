// Game logic of Radio Cave, ported from MorseRadioCave.cpp: a Colossal-Cave
// style text adventure in an abandoned radio station (12 rooms, 6 items, a
// few puzzles and two death traps). Every command is keyed in Morse; the CW
// clues (wall scribbles, the station log, IR7's calls) are played as audio.
// Pure Dart: [dispatch] takes one keyed command and updates the state, so the
// whole game is unit-testable without audio or UI.
//
// Command strings keep the firmware's case convention: letters are lower
// case, prosign letters upper case (SK -> 'K', AS -> 'S', KA -> 'A', KN ->
// 'N', VE -> 'E', BK -> 'B'). The final-QSO phrases rely on it ("... qsl K").
// Texts are English only, as in the firmware.
import 'dart:convert';

const rcNumRooms = 12;
const rcInvMax = 2;
const rcClueWpm = 30;
const rcClueQrsDivisor = 2;
const rcCluePitchHz = 696;
const rcInputMax = 32;

const _carried = 100;
const _gone = 101;
const _ambiguous = 255;
const _saveVersion = 1;

enum RcPhase { playing, dead, won }

/// A CW clue to play: [text] uses `<SK>` for the prosign, [wpm] is its speed.
class RcClue {
  final String text;
  final int wpm;
  const RcClue(this.text, this.wpm);
}

class _Item {
  final String name, takeName, examine;
  const _Item(this.name, this.takeName, this.examine);
}

const _items = <_Item>[
  _Item('', '', ''),
  _Item('FUEL', 'fuel canister', 'A red metal fuel canister. Sloshes when shaken.'),
  _Item('MANUAL', 'operating manual', 'The RC0 station operating manual. Thick, dusty.'),
  _Item('MIC', 'microphone',
      'A vintage desk microphone. The connector is incompatible with anything in this station.'),
  _Item('KEY', 'brass key', 'A small, heavy brass key. Warm to the touch.'),
  _Item('CHOKE', 'choke coil',
      'A wire-wound RF choke. Its solder joint is blackened and cracked. Needs repair.'),
  _Item('TUBE', '6146 tube',
      'A pristine 6146 power tetrode wrapped in oilcloth. Its getter flash is a silver mirror.'),
];

const rcNumItems = 6;
const _fuel = 1, _manual = 2, _mic = 3, _key = 4, _choke = 5, _tube = 6;

// Exits per room, indexed N, E, S, W; -1 = none. Index 0 unused.
const rcRoomNames = [
  '', 'Forest Path', 'Cave Entrance', 'Main Corridor', 'Generator Room',
  'Storage Room', 'Workshop', 'Operating Room', 'Receiver Alcove',
  'Antenna Tunnel', 'Antenna Platform', "Captain's Office", 'The Safe',
];
const _exits = <List<int>>[
  [-1, -1, -1, -1],
  [2, -1, -1, -1],
  [3, -1, 1, -1],
  [9, 7, 2, 4],
  [-1, 3, 5, -1],
  [4, 3, 6, -1],
  [5, 3, -1, -1],
  [8, 11, -1, 3],
  [-1, -1, 7, -1],
  [10, -1, 3, -1],
  [-1, -1, 9, -1],
  [-1, -1, -1, 7],
  [-1, -1, -1, -1],
];
const _dirLetters = ['N', 'E', 'S', 'W'];

const _wallText = '88   CQ DX   6HKE   0ULP   W3DZZ\n'
    'QRZ?   XYZZY   DE RC0 QSL <SK>\n'
    'QTH?   QLF G5RV   RST 577  55';

class RadioCaveEngine {
  // ── Persistent game state ────────────────────────────────────────────────
  int room = 1;
  int steps = 0;
  int visited = 0;     // bit r set = room r visited
  bool generator = false, antennaGrounded = true, officeOpen = false, safeOpen = false;
  bool chokeRepaired = false, chokeInstalled = false, tubeInstalled = false;
  bool masterPower = false, txMode = false;
  int wallLookCount = 0, qsoStage = 0, spareTubes = 2;
  final List<int> itemLoc = List.filled(rcNumItems + 1, 0);

  // ── Transient state (not saved) ──────────────────────────────────────────
  RcPhase phase = RcPhase.playing;
  String body = '';        // main text area
  String message = '';     // result line under the text
  RcClue? clue;            // set by a command that wants CW played; the UI takes it
  bool pendingNewConfirm = false;
  String lastClue = '';
  int lastClueWpm = rcClueWpm;
  int bodyVersion = 0;     // bumped whenever the main text is replaced (scroll reset)

  RadioCaveEngine() {
    newGame();
  }

  void newGame() {
    room = 1;
    steps = 0;
    visited = 0;
    generator = false;
    antennaGrounded = true;
    officeOpen = safeOpen = false;
    chokeRepaired = chokeInstalled = tubeInstalled = false;
    masterPower = txMode = false;
    wallLookCount = 0;
    qsoStage = 0;
    spareTubes = 2;
    itemLoc[_fuel] = 5;
    itemLoc[_manual] = 5;
    itemLoc[_mic] = 5;
    itemLoc[_key] = 4;      // hidden until the generator runs
    itemLoc[_choke] = 7;
    itemLoc[_tube] = 12;    // inside the safe
  }

  /// Starts a play session: resumes [save] if it is valid, otherwise a new
  /// game. Returns true when resumed.
  bool begin(String? save) {
    final resumed = save != null && _load(save);
    if (!resumed) newGame();
    _markVisited(room);
    phase = RcPhase.playing;
    message = resumed ? 'Welcome back.' : '';
    clue = null;
    lastClue = '';
    lastClueWpm = rcClueWpm;
    pendingNewConfirm = false;
    _refreshRoom(!resumed);
    return resumed;
  }

  // ── Save / load ──────────────────────────────────────────────────────────

  String toSave() => jsonEncode({
        'v': _saveVersion,
        'room': room, 'steps': steps, 'visited': visited,
        'gen': generator, 'ground': antennaGrounded, 'office': officeOpen,
        'safe': safeOpen, 'repaired': chokeRepaired, 'chokeIn': chokeInstalled,
        'tubeIn': tubeInstalled, 'power': masterPower, 'tx': txMode,
        'wall': wallLookCount, 'qso': qsoStage, 'spare': spareTubes,
        'items': itemLoc,
      });

  bool _load(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['v'] != _saveVersion) return false;
      final r = m['room'] as int;
      final it = (m['items'] as List).cast<int>();
      if (r < 1 || r > rcNumRooms || it.length != rcNumItems + 1) return false;
      room = r;
      steps = m['steps'] as int;
      visited = m['visited'] as int;
      generator = m['gen'] as bool;
      antennaGrounded = m['ground'] as bool;
      officeOpen = m['office'] as bool;
      safeOpen = m['safe'] as bool;
      chokeRepaired = m['repaired'] as bool;
      chokeInstalled = m['chokeIn'] as bool;
      tubeInstalled = m['tubeIn'] as bool;
      masterPower = m['power'] as bool;
      txMode = m['tx'] as bool;
      wallLookCount = m['wall'] as int;
      qsoStage = m['qso'] as int;
      spareTubes = m['spare'] as int;
      for (var i = 0; i < it.length; i++) {
        itemLoc[i] = it[i];
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── World queries ────────────────────────────────────────────────────────

  bool _roomVisited(int r) => (visited & (1 << r)) != 0;
  void _markVisited(int r) => visited |= 1 << r;
  bool _isCarried(int it) => it >= 1 && it <= rcNumItems && itemLoc[it] == _carried;
  bool _inRoom(int it, int r) => it >= 1 && it <= rcNumItems && itemLoc[it] == r;

  bool _visibleIn(int it, int r) {
    if (!_inRoom(it, r)) return false;
    if (it == _key && r == 4) return generator;   // hangs behind the generator
    return true;
  }

  /// Items carried, in item order.
  List<int> get inventory => [
        for (var it = 1; it <= rcNumItems; it++)
          if (itemLoc[it] == _carried) it
      ].take(rcInvMax).toList();

  int get invCount => inventory.length;
  static String itemTakeName(int it) => _items[it].takeName;

  /// Exit letters shown in the hint line ("N", "E", ...).
  List<String> get exitLetters => [
        for (var d = 0; d < 4; d++)
          if (_exit(room, d) > 0) _dirLetters[d]
      ];

  int _exit(int r, int dir) {
    final dest = _exits[r][dir];
    if (dest <= 0) return -1;
    if (r == 7 && dir == 1 && !officeOpen) return -1;   // Captain's door
    return dest;
  }

  // Prefix match of [arg] among the items in [mask] (bit i = item i).
  int _resolveAmong(String arg, int mask) {
    if (arg.isEmpty) return 0;
    final up = arg.toUpperCase();
    var match = 0, hits = 0;
    for (var it = 1; it <= rcNumItems; it++) {
      if ((mask & (1 << it)) == 0) continue;
      if (_items[it].name.startsWith(up)) {
        match = it;
        hits++;
      }
    }
    return hits == 0 ? 0 : hits > 1 ? _ambiguous : match;
  }

  int _resolveAny(String arg) => _resolveAmong(arg, 0xFF);

  int get _takeableMask {
    var m = 0;
    for (var it = 1; it <= rcNumItems; it++) {
      if (_visibleIn(it, room)) m |= 1 << it;
    }
    return m;
  }

  int get _carriedMask {
    var m = 0;
    for (var it = 1; it <= rcNumItems; it++) {
      if (_isCarried(it)) m |= 1 << it;
    }
    return m;
  }

  static bool _argIs(String a, String target) => a.isNotEmpty && target.startsWith(a);

  // ── Room text ────────────────────────────────────────────────────────────

  String roomDescription(int r, bool full) {
    final v = _roomVisited(r) && !full;
    switch (r) {
      case 1:
        return v
            ? 'Forest trail. A squeaking metal door leads north into the mountain.'
            : 'A narrow forest trail. The wind pushes an old metal door back and forth '
                'on its rusty hinges — it squeaks with every gust. Behind it, a dark '
                'passage leads into the mountainside.';
      case 2:
        return v
            ? 'Cave entrance. "RC0" stenciled above the door. Corridor leads north.'
            : 'A heavy steel door, rusted but ajar, leads deeper into the mountain. Cold '
                'air flows from inside. Above the door, faded stenciled letters read: RC0. '
                'Beyond the door, a corridor stretches into darkness.';
      case 3:
        return v
            ? 'Main corridor. Doors lead in all directions.'
            : 'A long concrete corridor lit by emergency strips that barely glow. Doors '
                'line both sides. Signs on the walls point to various rooms. The air '
                'smells of dust and old electronics. A faded poster on the wall shows '
                'radio operating procedures.';
      case 4:
        if (!generator) {
          return v
              ? 'Generator room. The generator is silent. Fuel gauge reads empty.'
              : 'A large diesel generator dominates this room. The fuel gauge reads empty. '
                  'A thick power cable runs from the generator through the wall. The room '
                  'smells of old oil. It is dim in here.';
        }
        return v
            ? 'Generator room. The generator hums steadily.'
            : 'The generator hums steadily, powering the station.';
      case 5:
        return v
            ? 'Storage room. Shelves with equipment.'
            : 'Metal shelves line the walls, stacked with dusty boxes and old equipment.';
      case 6:
        if (!generator) {
          return v
              ? 'Workshop. Soldering iron is cold — no power.'
              : 'A sturdy workbench with a soldering iron plugged into an outlet, wire '
                  'cutters, and various tools. A magnifying lamp hangs over the bench. '
                  'Without power, the soldering iron is cold and useless.';
        }
        return v
            ? 'Workshop. Soldering iron ready.'
            : 'The workbench is brightly lit. The soldering iron is hot, ready for use. '
                'Wire cutters, solder, and various tools are neatly arranged.';
      case 7:
        if (!tubeInstalled) {
          if (v) {
            return officeOpen
                ? "Operating room. Tube dead, choke disconnected. Captain's door is open."
                : "Operating room. Tube dead, choke disconnected. Captain's door is locked.";
          }
          final door = officeOpen ? '— it stands open.' : '— it is locked.';
          final head = _inRoom(_choke, 7)
              ? 'The heart of the station. A large transmitter rack fills one wall, '
                  "dominated by a 6146 power tube. The tube's getter flash has turned "
                  'milky white — it\'s clearly dead. A choke coil is disconnected from a '
                  'wire going to the plate connector and obviously needs repair. A '
                  'straight key is bolted to the operating desk. On the wall: a master '
                  'power switch (OFF position) and a TX/RX toggle switch. The walls are '
                  'covered in scribbled notes, callsigns, and doodles. On the east wall, '
                  'a heavy door is marked "Captain" '
              : 'The heart of the station. A large transmitter rack fills one wall, '
                  'dominated by a 6146 power tube — its getter flash is milky white, '
                  'clearly dead. The plate connector wire hangs loose where a choke coil '
                  'was removed. A straight key is bolted to the operating desk. On the '
                  'wall: a master power switch and TX/RX toggle. The walls are covered in '
                  'scribbled notes. On the east wall, a heavy door marked "Captain" ';
          return head + door;
        }
        if (v) {
          return officeOpen
              ? "Operating room. All equipment ready. Captain's door is open."
              : 'Operating room. All equipment ready.';
        }
        return officeOpen
            ? 'The transmitter rack gleams with the new 6146 — its getter flash a '
                "pristine silver mirror. The Captain's door stands open to the east."
            : 'The transmitter rack gleams with the new 6146 — its getter flash a '
                'pristine silver mirror.';
      case 8:
        if (!generator) {
          return v
              ? 'Receiver alcove. No power.'
              : 'A small alcove with a receiver setup. A pair of old headphones hangs '
                  'from a hook. The receiver is dark and silent.';
        }
        if (antennaGrounded) {
          return v
              ? 'Receiver alcove. Static only.'
              : 'The receiver hums with power, but produces only static.';
        }
        return v
            ? 'Receiver alcove. A CW signal is coming in!'
            : 'The receiver crackles to life. Through the headphones you hear a clear CW '
                'signal — someone is calling!';
      case 9:
        return v
            ? 'Antenna tunnel. Ground switch on the wall.'
            : 'A long, sloping tunnel leading upward. A ladder-wire feed line runs along '
                'the ceiling toward daylight. Halfway through, a heavy double knife '
                'switch is mounted on the wall, labeled "ANTENNA GROUND".';
      case 10:
        return v
            ? 'Antenna platform. Mast towers above.'
            : 'Daylight! You emerge onto a rocky platform high on the mountainside. A '
                'tall antenna mast rises above you, its guy wires creaking in the wind. '
                'The view across the valley is breathtaking.';
      case 11:
        if (v) {
          return safeOpen
              ? "Captain's office. Logbook on desk. Safe is open."
              : "Captain's office. Logbook on desk. Safe in the corner.";
        }
        return safeOpen
            ? 'A small office with a wooden desk and a leather chair. A framed sign '
                'reading "RC0" hangs on the wall. On the desk lies a thick logbook, its '
                'pages yellowed with age. The heavy safe in the corner stands open.'
            : 'A small office with a wooden desk and a leather chair. A framed sign '
                'reading "RC0" hangs on the wall. On the desk lies a thick logbook, its '
                'pages yellowed with age. A heavy safe sits in the corner, its door '
                'closed.';
      case 12:
        return 'Inside the safe: a spare 6146 tube wrapped in oilcloth. A card reads: '
            '"Spare 6146. Handle with care."';
    }
    return '';
  }

  String _itemsSuffix(int r) {
    final here = [
      for (var it = 1; it <= rcNumItems; it++)
        if (_visibleIn(it, r)) _items[it].takeName
    ];
    if (here.isEmpty) return '';
    final b = StringBuffer('\n\nYou see: ');
    for (var i = 0; i < here.length; i++) {
      if (i > 0) b.write(i == here.length - 1 ? ' and ' : ', ');
      b.write(here[i]);
    }
    b.write('.');
    return b.toString();
  }

  void _setBody(String text) {
    body = text;
    bodyVersion++;
  }

  void _refreshRoom(bool full) =>
      _setBody(roomDescription(room, full) + _itemsSuffix(room));

  void _startClue(String text, int wpm) {
    lastClue = text;
    lastClueWpm = wpm;
    clue = RcClue(text, wpm);
  }

  // ── Movement ─────────────────────────────────────────────────────────────

  void _move(int dir) {
    final dest = _exit(room, dir);
    if (dest < 0) {
      message = "You can't go that way.";
      return;
    }
    room = dest;
    final first = !_roomVisited(dest);
    _markVisited(dest);
    _refreshRoom(first);
    message = '';
    if (dest == 8 && generator && !antennaGrounded && qsoStage == 0) {
      _startClue('rc0 rc0 de ir7 ir7 k', 30);   // IR7 calling
    }
  }

  // ── Key phrases (magic words, locators, the final QSO) ───────────────────

  bool _tryKeyPhrase(String phraseCase, String lc) {
    if (lc == 'xyzzy') {
      if (room == 7 && !officeOpen) {
        officeOpen = true;
        _setBody("You key X-Y-Z-Z-Y on the straight key. From the east, you hear a "
            "click — the Captain's Office door swings open!");
        message = '';
        return true;
      }
      message = room == 11 ? "You're already inside." : 'Nothing happens.';
      return true;
    }

    if (lc == 'jn78dh') {
      if (room == 11 && !safeOpen) {
        safeOpen = true;
        if (itemLoc[_tube] == 12) itemLoc[_tube] = 11;
        // The firmware shows the keyed message first, then immediately
        // replaces it by the refreshed room text.
        _refreshRoom(false);
        message = '';
        return true;
      }
      message = room == 11 && safeOpen ? 'The safe is already open.' : 'Nothing happens.';
      return true;
    }

    final qsoReady = room == 7 && masterPower && txMode && tubeInstalled && !antennaGrounded;
    final single = phraseCase == 'de rc0 qsl K' || lc == 'de rc0 qsl k' || lc == 'de rc0 qsl sk';
    final double = phraseCase == 'de de rc0 rc0 qsl qsl K K' ||
        lc == 'de de rc0 rc0 qsl qsl k k' ||
        lc == 'de de rc0 rc0 qsl qsl sk sk';

    if (qsoReady && (single || double)) {
      if (single && qsoStage == 0) {
        qsoStage = 2;
        _setBody('You key: DE RC0 QSL <SK>\n\n'
            'A pause... then the receiver comes alive!\n\n'
            'IR7 responds: RC0 DE IR7 PSE QSZ');
        _startClue('rc0 de ir7 pse qsz', 30);
        message = '';
        return true;
      }
      if (single && qsoStage == 2) {
        _setBody('IR7 patiently repeats: RC0 DE IR7 PSE QSZ\n\n'
            '(Hint: QSZ means send each word twice.)');
        _startClue('rc0 de ir7 pse qsz', 30);
        message = '';
        return true;
      }
      if (double && qsoStage == 2) {
        qsoStage = 3;
        phase = RcPhase.won;
        return true;
      }
      _setBody('You key the message. No response.');
      message = '';
      return true;
    }

    if (single || double) {
      if (room != 7) {
        message = "You're not at the transmitter.";
      } else if (!masterPower) {
        message = 'Master power is off.';
      } else if (!txMode) {
        message = 'Not in TX mode.';
      } else if (!tubeInstalled) {
        message = 'The tube is dead.';
      } else if (antennaGrounded) {
        message = 'Antenna is grounded.';
      } else {
        message = 'Nothing happens.';
      }
      return true;
    }
    return false;
  }

  void _die() => phase = RcPhase.dead;

  // ── Command dispatcher ───────────────────────────────────────────────────

  void dispatch(String cmd) {
    final trimmed = cmd.replaceFirst(RegExp(r'[ \t]+$'), '');
    if (trimmed.isEmpty) return;
    steps++;
    clue = null;
    message = trimmed.toUpperCase();

    final lc = trimmed.toLowerCase();
    final sp = lc.indexOf(' ');
    final verb = sp < 0 ? lc : lc.substring(0, sp);
    final arg = sp < 0 ? '' : lc.substring(sp + 1);
    final argCase = sp < 0 ? '' : trimmed.substring(sp + 1);

    switch (verb) {
      case 'n': return _move(0);
      case 'e': return _move(1);
      case 's': return _move(2);
      case 'w': return _move(3);
    }

    if (verb == 'l' || verb == 'look') return _look(arg);

    if (verb == 'i' || verb == 'inv') {
      final inv = inventory;
      if (inv.isEmpty) {
        message = "You're carrying nothing.";
      } else if (inv.length == 1) {
        message = 'Carrying: ${_items[inv[0]].takeName}.';
      } else {
        _setBody('Carrying:\n${[for (final it in inv) '• ${_items[it].takeName}\n'].join()}');
        message = '';
      }
      return;
    }

    if (verb == 'h' || verb == 'help') {
      _setBody('Commands:\n'
          'N/S/E/W — move\n'
          'L <obj> — look / examine\n'
          'I — inventory\n'
          'TAKE, DROP <item>\n'
          'USE <item/thing>\n'
          'USE TX / USE RX\n'
          'FIX <item> — repair\n'
          'READ MANUAL, READ LOG\n'
          'KEY <word> — send CW\n'
          'QRS — replay slower\n'
          'NEW — restart game\n'
          'H — this help');
      message = '';
      return;
    }

    if (lc == 'qrs' || lc == 'pse qrs') {
      if (lastClue.isNotEmpty) {
        final wpm = lastClueWpm ~/ rcClueQrsDivisor;
        clue = RcClue(lastClue, wpm < 5 ? 5 : wpm);
        message = 'QRS (replay)';
      } else {
        message = 'QRS — nothing to replay yet';
      }
      return;
    }

    if (verb == 'new') {
      // The firmware's "Already a fresh game." check runs after the step
      // counter was raised, so it can never apply: NEW always asks.
      pendingNewConfirm = true;
      message = 'Wipe save? Key Y to confirm.';
      return;
    }
    if (pendingNewConfirm) {
      pendingNewConfirm = false;
      if (verb == 'y' || verb == 'yes') {
        newGame();
        _markVisited(room);
        _refreshRoom(true);
        message = 'Game restarted.';
        return;
      }
      message = 'Cancelled.';
      return;
    }

    if (verb == 't' || verb == 'take') return _take(arg);
    if (verb == 'd' || verb == 'dr' || verb == 'drop') return _drop(arg);
    if (verb == 'u' || verb == 'use') return _use(arg);

    if (verb == 'f' || verb == 'fix' || verb == 'solder') {
      if (arg.isEmpty) {
        message = 'Fix what?';
      } else if (_argIs(arg, 'choke')) {
        if (!_isCarried(_choke)) {
          message = "You don't have that.";
        } else if (room != 6) {
          message = 'Nothing happens.';
        } else if (!generator) {
          message = 'Soldering iron is cold. No power.';
        } else if (chokeRepaired) {
          message = 'The choke coil is already repaired.';
        } else {
          chokeRepaired = true;
          message = 'Choke coil resoldered.';
        }
      } else {
        message = 'Nothing to fix like that.';
      }
      return;
    }

    if (verb == 'r' || verb == 'read') return _read(arg);

    if (verb == 'k' || verb == 'key') {
      if (arg.isEmpty) {
        message = 'Key what?';
      } else if (!_tryKeyPhrase(argCase, arg)) {
        message = 'Nothing happens.';
      }
      return;
    }

    // Bare text: a magic word keyed directly, as a CW operator would.
    if (_tryKeyPhrase(trimmed, lc)) return;

    message = 'What? Key H for help.';
  }

  void _look(String a) {
    if (a.isEmpty) {
      _refreshRoom(true);
      message = '';
      return;
    }
    // Items that are really here (room or inventory) come first.
    final it = _resolveAmong(a, _takeableMask | _carriedMask);
    if (it == _ambiguous) {
      message = 'Which one?';
      return;
    }
    if (it > 0) {
      _setBody(_items[it].examine);
      message = '';
      return;
    }

    String? text;
    switch (room) {
      case 1:
        if (_argIs(a, 'door') || _argIs(a, 'sign')) {
          text = 'An old metal door hanging off one hinge, squeaking in the wind.';
        }
      case 2:
        if (_argIs(a, 'door') || _argIs(a, 'sign')) {
          text = 'Faded stenciled letters above the door: "RC0".';
        }
      case 3:
        if (_argIs(a, 'poster') || _argIs(a, 'sign')) {
          text = 'A faded poster with radio operating procedures.';
        }
      case 4:
        if (_argIs(a, 'generator')) {
          text = generator
              ? 'The generator rumbles steadily.'
              : 'A large diesel generator. Fuel gauge reads empty.';
        }
      case 5:
        if (_argIs(a, 'shelf') || _argIs(a, 'shelves')) {
          text = 'Metal shelves lined with dusty boxes and old equipment.';
        }
      case 6:
        if (_argIs(a, 'bench') || _argIs(a, 'iron')) {
          text = generator
              ? 'The soldering iron is hot and ready.'
              : 'The soldering iron is cold — no power.';
        }
      case 7:
        if (_argIs(a, 'door')) {
          text = officeOpen
              ? "The Captain's door stands open. The office is to the east."
              : 'A heavy door marked "Captain". It is locked. There is a keyhole below the handle.';
        } else if (_argIs(a, 'switch')) {
          text = 'Master power: ${masterPower ? 'ON' : 'OFF'}. Mode: ${txMode ? 'TX' : 'RX'}.';
        } else if (_argIs(a, 'tube')) {
          text = tubeInstalled
              ? 'The new 6146 gleams with a pristine silver getter flash.'
              : "The 6146's getter flash has turned milky white. The vacuum seal is "
                  'broken. This tube is dead.';
        } else if (_argIs(a, 'wall')) {
          _wall();
          message = wallLookCount == 1
              ? 'Scribbles on the wall. CW...'
              : 'Scribbles. CW replaying...';
          return;
        }
      case 8:
        if (_argIs(a, 'receiver') || _argIs(a, 'phones')) {
          text = !generator
              ? 'Receiver is dead. No power.'
              : antennaGrounded
                  ? 'Only static through the phones.'
                  : 'A clear CW signal comes through!';
        }
      case 9:
        if (_argIs(a, 'switch')) {
          text = 'Antenna ground switch: ${antennaGrounded ? 'GROUND' : 'OPERATE'}.';
        } else if (_argIs(a, 'cable') || _argIs(a, 'feedline')) {
          text = 'Ladder-wire feed line running up to the antenna platform.';
        }
      case 10:
        if (_argIs(a, 'antenna') || _argIs(a, 'mast')) {
          text = 'Tall antenna mast. Guy wires creak. Looks functional.';
        }
      case 11:
        if (_argIs(a, 'desk') || _argIs(a, 'log') || _argIs(a, 'logbook')) {
          text = 'A thick logbook lies on the desk. Use READ LOG to examine it.';
        } else if (_argIs(a, 'safe')) {
          text = safeOpen
              ? 'The safe stands open.'
              : 'A heavy safe. The door is closed. There is a combination lock.';
        }
    }
    if (text == null) {
      message = "You don't see anything special.";
      return;
    }
    _setBody(text);
    message = '';
  }

  // The wall scribbles: the first look plays XYZZY, later ones the QSO opener.
  void _wall() {
    _setBody(_wallText);
    wallLookCount++;
    if (wallLookCount == 1) {
      _startClue('xyzzy', 16);
    } else {
      _startClue('de rc0 qsl <SK>', 16);
    }
  }

  void _take(String arg) {
    if (arg.isEmpty) {
      message = 'Take what?';
      return;
    }
    final it = _resolveAmong(arg, _takeableMask);
    if (it == 0) {
      final any = _resolveAny(arg);
      if (any == _ambiguous) {
        message = 'Which one?';
      } else if (any > 0 && _isCarried(any)) {
        message = 'You already have that.';
      } else {
        message = "There's nothing like that here.";
      }
      return;
    }
    if (it == _ambiguous) {
      message = 'Which one?';
      return;
    }
    if (invCount >= rcInvMax) {
      message = 'Your hands are full. Drop something.';
      return;
    }
    // Reaching for the choke next to the live plate connector is fatal.
    if (it == _choke && room == 7 && masterPower) {
      _die();
      return;
    }
    itemLoc[it] = _carried;
    _refreshRoom(false);
    message = 'You take the ${_items[it].takeName}.';
  }

  void _drop(String arg) {
    if (arg.isEmpty) {
      message = 'Drop what?';
      return;
    }
    final it = _resolveAmong(arg, _carriedMask);
    if (it == 0) {
      message = "You don't have that.";
      return;
    }
    if (it == _ambiguous) {
      message = 'Which one?';
      return;
    }
    itemLoc[it] = room;
    _refreshRoom(false);
    message = 'You drop the ${_items[it].takeName}.';
  }

  void _use(String arg) {
    if (arg.isEmpty) {
      message = 'Use what?';
      return;
    }

    if (_argIs(arg, 'fuel')) {
      if (!_isCarried(_fuel)) {
        message = "You don't have that.";
      } else if (room != 4) {
        message = 'Nothing happens.';
      } else if (generator) {
        message = 'Generator already runs.';
      } else {
        generator = true;
        itemLoc[_fuel] = _gone;
        _setBody('You pour the fuel into the tank. The generator coughs, sputters... '
            'and rumbles to life! Lights flicker on throughout the station. In the '
            'light, you notice a small brass key hanging on a nail behind the generator.');
        message = '';
      }
      return;
    }

    if (_argIs(arg, 'key')) {
      if (!_isCarried(_key)) {
        message = "You don't have that.";
      } else if ((room == 7 || room == 11) && !officeOpen) {
        officeOpen = true;
        message = 'Click! The door swings open.';
        _refreshRoom(false);
      } else if (officeOpen && (room == 7 || room == 11)) {
        message = 'The door is already open.';
      } else {
        message = "The key doesn't fit anything here.";
      }
      return;
    }

    if (_argIs(arg, 'switch')) {
      if (room == 9) {
        antennaGrounded = !antennaGrounded;
        message = antennaGrounded ? 'Switch → GROUND.' : 'Switch → OPERATE. Antenna live.';
        _refreshRoom(false);
      } else if (room == 7) {
        masterPower = !masterPower;
        if (masterPower) {
          _setBody(tubeInstalled && chokeInstalled
              ? 'You flip the master power switch ON. The transmitter hums to life. '
                  'Meters flicker. The station is operational!'
              : 'You flip the master power switch ON. Nothing much happens — the '
                  'transmitter section seems dead.');
        } else {
          _setBody('You flip the master power switch OFF. The transmitter goes silent.');
        }
        message = '';
      } else {
        message = "There's no switch here.";
      }
      return;
    }

    // Two letters at least, so that "t" stays the tube.
    if (arg.length >= 2 && _argIs(arg, 'tx')) {
      if (room != 7) {
        message = 'Nothing happens.';
        return;
      }
      if (!masterPower) {
        message = 'Master power is off.';
        return;
      }
      if (antennaGrounded && tubeInstalled) {
        // Keying into a grounded antenna destroys the tube and the choke joint.
        tubeInstalled = false;
        chokeInstalled = false;
        chokeRepaired = false;
        itemLoc[_choke] = 7;
        _refreshRoom(false);
        _setBody('A loud POP from the transmitter and a puff of smoke! The 6146 now '
            'looks milky white — the tube is dead. The choke\'s solder joint has '
            'cracked open. There are no spare tubes left. The station cannot be '
            'revived.');
        message = 'Station dead. Key NEW to restart.';
        return;
      }
      txMode = true;
      if (tubeInstalled && !antennaGrounded && qsoStage == 0) {
        _setBody('Switched to TX mode.\n\n'
            'The frequency is clear. You can key your message now.');
        message = '';
      } else {
        message = 'Switched to TX mode.';
      }
      return;
    }

    if (arg.length >= 2 && _argIs(arg, 'rx')) {
      if (room != 7) {
        message = 'Nothing happens.';
        return;
      }
      txMode = false;
      if (masterPower && tubeInstalled && !antennaGrounded && qsoStage == 0) {
        _startClue('rc0 rc0 de ir7 ir7 k', 30);
      }
      message = 'Switched to RX mode.';
      return;
    }

    if (_argIs(arg, 'choke')) {
      if (!_isCarried(_choke)) {
        message = room == 7 && chokeInstalled
            ? 'The choke coil is already installed.'
            : "You don't have that.";
      } else if (room == 6) {
        if (!generator) {
          message = 'Soldering iron is cold. No power.';
        } else if (chokeRepaired) {
          message = 'The choke coil is already repaired.';
        } else {
          chokeRepaired = true;
          message = 'Choke coil resoldered.';
        }
      } else if (room == 7) {
        if (masterPower) {
          _die();
        } else if (!chokeRepaired) {
          message = 'Joint still cracked. Fix it first.';
        } else {
          chokeInstalled = true;
          itemLoc[_choke] = _gone;
          _refreshRoom(false);
          message = 'Choke coil reattached.';
        }
      } else {
        message = 'Nothing happens.';
      }
      return;
    }

    if (_argIs(arg, 'tube')) {
      if (!_isCarried(_tube)) {
        message = "You don't have that.";
      } else if (room == 6) {
        message = 'Install the tube in Operating Room.';
      } else if (room == 7) {
        if (masterPower) {
          _die();
        } else if (!chokeInstalled) {
          message = "Choke isn't installed yet.";
        } else {
          tubeInstalled = true;
          itemLoc[_tube] = _gone;
          _refreshRoom(false);
          message = '6146 installed. Transmitter ready!';
        }
      } else {
        message = 'Nothing happens.';
      }
      return;
    }

    // "m" alone is ambiguous between manual and mic; decide by what is carried.
    if (_argIs(arg, 'manual')) {
      if (!_argIs(arg, 'mic') || arg.length >= 2) {
        message = _isCarried(_manual) ? 'Use READ MANUAL to read it.' : "You don't have that.";
        return;
      }
      final hasManual = _isCarried(_manual), hasMic = _isCarried(_mic);
      if (hasManual && !hasMic) {
        message = 'Use READ MANUAL to read it.';
      } else if (hasMic && !hasManual) {
        message = 'Connector incompatible. CW-only.';
      } else if (!hasManual && !hasMic) {
        message = "You don't have that.";
      } else {
        message = 'Which one?';
      }
      return;
    }
    if (_argIs(arg, 'mic')) {
      message = 'Connector incompatible. CW-only.';
      return;
    }

    message = 'Nothing happens.';
  }

  void _read(String arg) {
    if (arg.isEmpty) {
      message = 'Read what?';
      return;
    }
    if (_argIs(arg, 'manual')) {
      if (!_isCarried(_manual)) {
        message = "You don't have that.";
        return;
      }
      _setBody('STATION RC0 — OPERATING PROCEDURES\n\n'
          '! Danger! High Voltage!\n'
          'Check tubes before powering on!\n\n'
          'Always verify all tubes are seated and functional before engaging the '
          'master power switch.');
      _startClue('danger', 12);
      message = 'CW playing: DANGER';
      return;
    }
    if (_argIs(arg, 'log') || _argIs(arg, 'logbook')) {
      if (room != 11) {
        message = "There's nothing to read here.";
        return;
      }
      _setBody('STATION LOG\n\n'
          '19510901 23:15  IR5    LOC BK29??\n'
          '19510917 04:45  XYZZY  LOC JN78DH\n'
          '19540430 05:05  K666?  LOC CM87VK');
      _startClue('19510917', 36);
      message = 'CW playing...';
      return;
    }
    if (_argIs(arg, 'wall') && room == 7) {
      _wall();
      message = '';
      return;
    }
    message = "There's nothing to read.";
  }

  // ── Won / dead texts ─────────────────────────────────────────────────────

  static const deathText = 'A blinding arc of high voltage leaps through your hand. '
      'Everything goes dark.\n\n'
      'You suffered a painful death by high voltage.\n\n'
      'IR7 continues to call... waiting.';

  String get wonText => 'After 50 years of silence, station RC0 has returned to the air. '
      'Your message has been received.\n\n'
      '73 de IR7\n\n'
      'Steps taken: $steps';

  /// IR7's closing greeting, played on the victory screen.
  static const wonClue = RcClue('r r tu 73 <SK> <SK> <SK>', 16);
}

// ── Command buffer rules (shared with the screen and the tests) ─────────────

/// The firmware maps decoder output to buffer characters: letters stay
/// lower case, prosigns become single upper-case letters. Returns null for
/// characters that must not enter the buffer.
String? rcBufferChar(String decoded) {
  switch (decoded) {
    case 'SK': return 'K';
    case 'AS': return 'S';
    case 'KA': return 'A';
    case 'KN': return 'N';
    case 'VE': return 'E';
    case 'BK': return 'B';
  }
  if (decoded.length != 1 || decoded == '*') return null;
  return decoded.toLowerCase();
}

/// Single letters that dispatch immediately, without waiting for silence.
bool rcIsInstantCommand(String buf, {required bool pendingNewConfirm}) {
  if (buf.length != 1) return false;
  if ('sewih'.contains(buf)) return true;      // lower case only
  return buf == 'y' && pendingNewConfirm;
}
