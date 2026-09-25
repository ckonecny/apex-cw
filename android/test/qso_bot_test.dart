import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/qso_bot.dart';

class _Sim {
  int t = 1000;
  final tx = <String>[];
  final infos = <String>[];
  late QsoBot bot;
  _Sim(QsoType type, {QsoLevel level = QsoLevel.beginner, int contest = 0}) {
    bot = QsoBot(
      type: type, level: level, contestType: contest, userCall: 'OE1ABC',
      userWpm: 20, interWordDits: 7,
      nextCall: () => const QsoCall('DL1XYZ', contEU, 14),
      play: (s, w) => tx.add(s), stopPlay: () {}, info: infos.add,
      random: Random(1), clock: () => t);
  }
  void run(int ms) { for (var i = 0; i < ms ~/ 20; i++) { t += 20; bot.tick(); } }
  void key(String text) {
    for (final ch in text.toLowerCase().split('')) { bot.feed(ch); t += 150; }
    bot.feed(' ');
  }
  void botDone() { run(100); bot.txDone(); }
}

void main() {
  test('matcher primitives', () {
    expect(QsoMatch.looksLikeCallsign('OE1ABC'), isTrue);
    expect(QsoMatch.looksLikeCallsign('2E0ABC'), isTrue);
    expect(QsoMatch.looksLikeCallsign('5NN'), isFalse);
    expect(QsoMatch.looksLikeCallsign('599'), isFalse);
    expect(QsoMatch.looksLikeCallsign('DL1XYZ/P'), isTrue);
    expect(QsoMatch.matchRST('5NN'), isTrue);
    expect(QsoMatch.matchRST('579'), isTrue);
    expect(QsoMatch.matchRST('699'), isFalse);
    expect(QsoMatch.matchZone('14'), isTrue);
    expect(QsoMatch.matchZone('41'), isFalse);
  });

  test('SOTA: bot calls CQ, user answers', () {
    final s = _Sim(QsoType.sotaPota);
    s.bot.start();
    s.run(5200);                          // silence -> bot calls CQ
    expect(s.tx.last, startsWith('cq '));
    s.botDone();
    s.key('OE1ABC'); s.key('K');
    expect(s.tx.last, startsWith('oe1abc de dl1xyz ur 599'));
    s.botDone();
    s.key('R'); s.key('599'); s.key('BK');
    expect(s.tx.last, startsWith('r qth '));
    s.botDone();
    s.run(4200);                          // optional ack times out
    expect(s.tx.last, 'tu 73 e e de dl1xyz <sk>');
    s.botDone();
    expect(s.bot.phase, QsoPhase.done);
    expect(s.infos.last, 'QSO complete');
  });

  test('SOTA: user calls CQ, bot answers as chaser', () {
    final s = _Sim(QsoType.sotaPota);
    s.bot.start();
    s.key('CQ'); s.key('SOTA'); s.key('DE'); s.key('OE9QRP'); s.key('K');
    expect(s.tx.last, 'dl1xyz dl1xyz');
    s.botDone();
    s.key('DL1XYZ'); s.key('559'); s.key('K');
    expect(s.tx.last, contains('tu 73 e e <sk>'));
    s.botDone();
    expect(s.infos.last, 'QSO complete');
  });

  test('<err> retracts, letter r does not', () {
    final s = _Sim(QsoType.sotaPota);
    s.bot.start();
    s.run(5200);
    s.botDone();
    s.key('OE1ABC'); s.bot.feed('R'); s.key('OE1RRR'); s.key('K');
    expect(s.tx.last, startsWith('oe1rrr de dl1xyz'));
  });

  test('repeat request and recovery', () {
    final s = _Sim(QsoType.sotaPota);
    s.bot.start();
    s.run(5200);
    s.botDone();
    s.key('AGN');
    s.run(3500);                          // silence ends the over
    expect(s.tx.last, startsWith('cq '));   // full repeat
    s.botDone();
    s.run(16100);                         // no reply -> recovery prompt
    expect(['qrz?', 'pse agn', 'ur call agn?'], contains(s.tx.last));
  });

  test('Standard: bot runs, info over with name', () {
    final s = _Sim(QsoType.standard);
    s.bot.start();
    s.run(5200);
    expect(s.tx.last, 'cq cq de dl1xyz dl1xyz k');
    s.botDone();
    s.key('DL1XYZ'); s.key('DE'); s.key('OE1ABC'); s.key('K');
    s.botDone();
    for (final w in ['UR', 'RST', '579', '=', 'NAME', 'CHRIS', 'CHRIS', '=', 'QTH', 'VIENNA', 'K']) { s.key(w); }
    expect(s.tx.last, contains('fb dr chris'));
  });

  test('Contest CQ WW: user runs, two QSOs then idle end', () {
    final s = _Sim(QsoType.contest);
    s.bot.start();
    s.key('CQ'); s.key('TEST'); s.key('OE1ABC');
    s.run(2000);
    expect(s.tx.last, 'dl1xyz');
    s.botDone();
    s.key('DL1XYZ'); s.key('5NN'); s.key('15');
    s.run(3300);
    expect(s.tx.last, '599 14');           // Beginner spells out 5nn
    s.botDone();
    s.key('CQ'); s.key('TEST'); s.key('OE1ABC'); s.key('K');
    expect(s.tx.last, 'dl1xyz');           // fresh station answers the next CQ
    s.botDone();
    s.run(16200);                          // nobody sends the exchange -> recovery
    expect(s.tx.last, isNot('dl1xyz'));
  });

  test('Contest: bot runs, idle ends session', () {
    final s = _Sim(QsoType.contest);
    s.bot.start();
    s.run(15200);
    expect(s.tx.last, 'cq test de dl1xyz dl1xyz test');
    s.botDone();
    s.run(15200);
    expect(s.infos.last, 'session end');
  });
}
