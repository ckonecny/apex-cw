import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/echo_timing.dart';

// Expected values worked out by hand from m32_v6.ino (V9.0):
// generateCW() SEND_WORD: genTimer = 1400 + interCharacterSpace
//   + interWordSpace / 3 + think * 1000; interWordSpace = max(IW, IC + 4) dits.
// doPaddleIambic(): interWordTimer = 2 * interCharacterSpace + ditLength
//   + interWordSpace / 8.
void main() {
  test('start deadline at the default spacing, 20 WPM (dit 60 ms)', () {
    // 1400 + 3*60 + 7*60/3 = 1720
    expect(
        echoStartDeadlineMs(
            promptWpm: 20, interChar: 3, interWord: 7, thinkSeconds: 0),
        1720);
  });

  test('start deadline adds the think time', () {
    expect(
        echoStartDeadlineMs(
            promptWpm: 20, interChar: 3, interWord: 7, thinkSeconds: 2),
        3720);
  });

  test('a small InterWord Spc is lifted to Interchar Spc + 4', () {
    // IC 9, IW 5 -> word space 13 dits: 1400 + 9*60 + 13*60/3 = 2200
    expect(
        echoStartDeadlineMs(
            promptWpm: 20, interChar: 9, interWord: 5, thinkSeconds: 0),
        2200);
  });

  test('answer end in dits', () {
    // 2*3 + 1 + 7/8 = 7.875 -> 8
    expect(echoAnswerEndDits(3, 7), 8);
    // IC 9, IW 5: 2*9 + 1 + 13/8 = 20.6 -> 21
    expect(echoAnswerEndDits(9, 5), 21);
  });
}
