import 'dart:math';

import 'mini_qso_data.dart';

// Mini-QSO stage (issue #40): builds a short on-air exchange between two
// stations from building blocks, and the multiple-choice questions about it.
// UI-free and driven by an injectable Random and a given callsign list, so
// every rule is unit-testable.
//
// Questions go in the order the facts are heard. A question names the stations
// by their role ("the calling station", "the answering station"), never by a
// fact asked later, so nothing is given away.

enum MqFact { call, rst, qth, name, extra }

/// Which side speaks: 0 = the calling station (A), 1 = the answering one (B).
class MqTurn {
  final int station;
  final String text;
  const MqTurn(this.station, this.text);
}

class MqQuestion {
  final int station;
  final MqFact fact;
  /// Which extra it is (RIG, PWR, ANT, WX); null for the other facts.
  final String? extraKey;
  final List<String> options;
  final int correct;
  /// The callsign to name the station by, once an earlier question has made it
  /// known (level 3); null means the question says "the calling / answering
  /// station".
  final String? byCall;
  const MqQuestion(this.station, this.fact, this.extraKey, this.options, this.correct, [this.byCall]);

  String get answer => options[correct];
}

class MqRound {
  final List<MqTurn> turns;
  final List<MqQuestion> questions;
  const MqRound(this.turns, this.questions);
}

const mqOptionCount = 4;
const mqLevels = 3;
/// Callsigns a round needs: two stations plus wrong options for two call questions.
const mqCallsNeeded = 8;
/// Facts asked at level 3 besides the two callsigns, drawn at random.
const mqLevel3Facts = 4;

class _Station {
  final String call, name, qth, rst; // rst = the report this station gives
  final String extraKey, extra;
  const _Station(this.call, this.name, this.qth, this.rst, this.extraKey, this.extra);
}

class MiniQsoEngine {
  final Random _rng;
  MiniQsoEngine({Random? rng}) : _rng = rng ?? Random();

  T _pick<T>(List<T> l) => l[_rng.nextInt(l.length)];

  static const _extras = <String, List<String>>{
    'RIG': mqRigs,
    'PWR': mqPowers,
    'ANT': mqAntennas,
    'WX': mqWeather,
  };

  /// A round of [level] 1..3. [calls] needs [mqCallsNeeded] distinct entries.
  MqRound newRound(int level, List<String> calls) {
    final lv = level.clamp(1, mqLevels);
    assert(calls.toSet().length >= mqCallsNeeded);
    final names = [...mqNames]..shuffle(_rng);
    final cities = [...mqCities]..shuffle(_rng);
    final keys = _extras.keys.toList()..shuffle(_rng);
    final a = _station(calls[0], names[0], cities[0], keys[0]);
    final b = _station(calls[1], names[1], cities[1], keys[1]);

    final turns = <MqTurn>[
      MqTurn(0, 'CQ CQ DE ${a.call} ${a.call} K'),
      MqTurn(1, switch (lv) {
        1 => '${a.call} DE ${b.call} ${b.call} QTH ${b.qth} NAME ${b.name} BK',
        _ => '${a.call} DE ${b.call} ${b.call} UR ${b.rst} ${b.rst} QTH ${b.qth} NAME ${b.name} ${b.extraKey} ${b.extra} BK',
      }),
      if (lv < 3) MqTurn(0, 'R TNX ${b.name} 73 EE') else ...[
        MqTurn(0, '${b.call} DE ${a.call} R TNX ${b.name} UR ${a.rst} ${a.rst} QTH ${a.qth} NAME ${a.name} ${a.extraKey} ${a.extra} BK'),
        MqTurn(1, 'R TNX ${a.name} 73 TU ${a.call} DE ${b.call} SK'),
        MqTurn(0, 'TU 73 EE'),
      ],
    ];

    final q = <MqQuestion>[];
    if (lv == 3) q.add(_call(0, a.call, calls));
    q.add(_call(1, b.call, calls));
    // Candidates in the order they are heard; at level 3 only a random few of
    // them are asked, and by then both callsigns are known.
    final cands = <MqQuestion Function(String? by)>[];
    void side(_Station s, int who, {required bool rst, required bool extra}) {
      if (rst) cands.add((by) => _pool(who, MqFact.rst, null, s.rst, mqRsts, by));
      cands.add((by) => _pool(who, MqFact.qth, null, s.qth, mqCities, by));
      cands.add((by) => _pool(who, MqFact.name, null, s.name, mqNames, by));
      if (extra) cands.add((by) => _pool(who, MqFact.extra, s.extraKey, s.extra, _extras[s.extraKey]!, by));
    }

    side(b, 1, rst: lv >= 2, extra: lv >= 2);
    var chosen = List<int>.generate(cands.length, (i) => i);
    if (lv == 3) {
      side(a, 0, rst: true, extra: true);
      chosen = ([for (var i = 0; i < cands.length; i++) i]..shuffle(_rng)).take(mqLevel3Facts).toList()..sort();
    }
    // Candidates 0..n-1 belong to B first, then A: the order of the dialogue is
    // B's turn before A's second turn, as built above.
    for (final i in chosen) {
      final isA = lv == 3 && i >= cands.length - 4;
      q.add(cands[i](lv == 3 ? (isA ? a.call : b.call) : null));
    }
    return MqRound(turns, q);
  }

  _Station _station(String call, String name, String qth, String extraKey) => _Station(
        call, name, qth, _pick(mqRsts), extraKey, _pick(_extras[extraKey]!),
      );

  MqQuestion _call(int station, String correct, List<String> calls) {
    // Wrong calls: from the spare ones, then any other.
    final wrong = [for (final c in calls.skip(2)) if (c != correct) c];
    return _make(station, MqFact.call, null, correct, wrong);
  }

  MqQuestion _pool(int station, MqFact fact, String? key, String correct, List<String> pool, String? by) {
    // Neither the right answer nor the other station's value as a wrong one.
    return _make(station, fact, key, correct, [for (final v in pool.toSet()) if (v != correct) v], by);
  }

  MqQuestion _make(int station, MqFact fact, String? key, String correct, List<String> wrong, [String? by]) {
    final distractors = ([...wrong.toSet()]..shuffle(_rng)).take(mqOptionCount - 1).toList();
    final options = [correct, ...distractors]..shuffle(_rng);
    return MqQuestion(station, fact, key, options, options.indexOf(correct), by);
  }
}

/// Problems with the building blocks; empty when sound. Used by the tests.
List<String> mqValidate() {
  final problems = <String>[];
  void need(String what, List<String> l, int n) {
    if (l.toSet().length < n) problems.add('$what: fewer than $n different values');
    for (final v in l) {
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(v)) problems.add('$what: "$v" is not plain CW text');
    }
  }
  need('names', mqNames, 4);
  need('cities', mqCities, 4);
  need('rst', mqRsts, 4);
  need('rig', mqRigs, 4);
  need('power', mqPowers, 4);
  need('antenna', mqAntennas, 4);
  need('weather', mqWeather, 4);
  return problems;
}
