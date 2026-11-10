import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/effective_wpm.dart';

void main() {
  test('normal gaps give the character speed back', () {
    expect(effectiveWpm(20, 3, 7), 20);
    expect(effectiveWpm(20, 3, 7, typing: true), 20);
  });

  test('paper mode counts both gaps', () {
    // 50 * 20 / (31 + 4 * 28 + 40) = 5.46 -> 5
    expect(effectiveWpm(20, 28, 40), 5);
    // a wider word gap alone lowers it
    expect(effectiveWpm(20, 3, 40), lessThan(effectiveWpm(20, 3, 7)));
  });

  test('typing mode ignores the word gap', () {
    expect(effectiveWpm(20, 28, 40, typing: true),
        effectiveWpm(20, 28, 7, typing: true));
    // 50 * 20 / (31 + 112 + 7) = 6.67 -> 7
    expect(effectiveWpm(20, 28, 40, typing: true), 7);
    // the character gap still counts
    expect(effectiveWpm(20, 28, 40, typing: true),
        lessThan(effectiveWpm(20, 3, 40, typing: true)));
  });

  // m32_v6.ino updateTimings(): interWordSpace = max(InterWord Spc, Interchar Spc + 4)
  test('played word gap is at least the character gap + 4', () {
    expect(minWordSpaceDits(3), 7);
    expect(playedWordSpaceDits(3, 6), 7);
    expect(playedWordSpaceDits(3, 9), 9);
    expect(playedWordSpaceDits(9, 7), 13);
    // eff. counts what is played: 50 * 20 / (31 + 36 + 13) = 12.5 -> 13
    expect(effectiveWpm(20, 9, 7), 13);
    expect(effectiveWpm(20, 3, 6), 20);
  });
}
