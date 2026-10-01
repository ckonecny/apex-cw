import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/adaptive_copy_engine.dart';
import 'package:next_cw_trainer/content/char_stats.dart';
import 'package:next_cw_trainer/content/echo_suggestions.dart';

EchoSuggestionInput input({
  required List<bool> firstTry,
  int kochLevel = 0,
  int kochTotal = 0,
  List<String> active = const [],
  CharStatsStore? stats,
  int answerMax = 0,
  int ic = 10,
  int iw = 20,
  bool straight = false,
}) =>
    EchoSuggestionInput(
      firstTry: firstTry,
      wpm: 20,
      answerWpmMax: answerMax,
      interCharSpace: ic,
      interWordSpace: iw,
      maxInterCharSpace: 10,
      maxInterWordSpace: 20,
      kochLevel: kochLevel,
      kochTotal: kochTotal,
      activeChars: active,
      stats: stats ?? CharStatsStore(CharStatsStore.echo),
      straightKey: straight,
    );

final good = List.filled(10, true);
final bad = List.filled(10, false);

void main() {
  test('needs two good blocks in a row before tightening spacing', () {
    final e = AdaptiveCopyEngine();
    expect(evaluateEchoBlock(e, input(firstTry: good)).newInterChar, isNull);
    final s = evaluateEchoBlock(e, input(firstTry: good));
    expect(s.newInterChar, 9);
    expect(s.newInterWord, 19);
  });

  test('open Koch chars block tempo rise but not widening', () {
    final e = AdaptiveCopyEngine();
    evaluateEchoBlock(e, input(firstTry: good, kochLevel: 5, kochTotal: 40));
    final s = evaluateEchoBlock(e, input(firstTry: good, kochLevel: 5, kochTotal: 40));
    expect(s.newInterChar, isNull);
    expect(s.newWpm, isNull);
    final e2 = AdaptiveCopyEngine();
    evaluateEchoBlock(e2, input(firstTry: bad, ic: 8, iw: 15, kochLevel: 5, kochTotal: 40));
    final w = evaluateEchoBlock(e2, input(firstTry: bad, ic: 8, iw: 15, kochLevel: 5, kochTotal: 40));
    expect(w.newInterChar, 9);
  });

  test('no widening beyond the session start spacing', () {
    final e = AdaptiveCopyEngine();
    expect(evaluateEchoBlock(e, input(firstTry: bad)).newInterChar, isNull);
  });

  test('speed rises only at char speed and without open chars', () {
    final e = AdaptiveCopyEngine();
    evaluateEchoBlock(e, input(firstTry: good, ic: 3, iw: 7));
    final s = evaluateEchoBlock(e, input(firstTry: good, ic: 3, iw: 7));
    expect(s.newWpm, 21);
  });

  test('unlock when all active chars are solid, blocks tempo in that block', () {
    final st = CharStatsStore(CharStatsStore.echo);
    for (final c in ['K', 'M']) {
      for (var n = 0; n < 25; n++) { st.record(c, true); }
    }
    final e = AdaptiveCopyEngine();
    evaluateEchoBlock(e, input(firstTry: good, kochLevel: 2, kochTotal: 40, active: ['K', 'M'], stats: st));
    final s = evaluateEchoBlock(
        e, input(firstTry: good, kochLevel: 2, kochTotal: 40, active: ['K', 'M'], stats: st));
    expect(s.unlockNext, isTrue);
    expect(s.newWpm, isNull);
    expect(s.newInterChar, isNull);
  });

  test('no unlock without Koch content or when all chars are open', () {
    final st = CharStatsStore(CharStatsStore.echo);
    for (var n = 0; n < 25; n++) { st.record('K', true); }
    final e = AdaptiveCopyEngine();
    expect(evaluateEchoBlock(e, input(firstTry: good, active: ['K'], stats: st)).unlockNext, isFalse);
    expect(
        evaluateEchoBlock(e, input(firstTry: good, kochLevel: 40, kochTotal: 40, active: ['K'], stats: st))
            .unlockNext,
        isFalse);
  });

  test('Gebe-Tempo suggestion only below Hör-Tempo and with a good rate', () {
    final e = AdaptiveCopyEngine();
    expect(evaluateEchoBlock(e, input(firstTry: good, answerMax: 15)).newAnswerWpmMax, 16);
    expect(evaluateEchoBlock(e, input(firstTry: good, answerMax: 0)).newAnswerWpmMax, isNull);
    expect(evaluateEchoBlock(e, input(firstTry: good, answerMax: 20)).newAnswerWpmMax, isNull);
    expect(evaluateEchoBlock(e, input(firstTry: bad, answerMax: 15)).newAnswerWpmMax, isNull);
  });

  test('straight key: no Gebe-Tempo or spacing proposals', () {
    final e = AdaptiveCopyEngine();
    for (var n = 0; n < 4; n++) {
      final s = evaluateEchoBlock(e, input(firstTry: good, answerMax: 15, ic: 8, iw: 15, straight: true));
      expect(s.newAnswerWpmMax, isNull);
      expect(s.newInterChar, isNull);
      expect(s.newInterWord, isNull);
    }
  });

  test('weak chars come from the echo stats', () {
    final st = CharStatsStore(CharStatsStore.echo);
    for (var n = 0; n < 12; n++) { st.record('Q', false); st.record('E', true); }
    final s = evaluateEchoBlock(AdaptiveCopyEngine(),
        input(firstTry: good, kochLevel: 5, kochTotal: 40, active: ['Q', 'E'], stats: st));
    expect(s.weakChars.keys, ['Q']);
  });
}
