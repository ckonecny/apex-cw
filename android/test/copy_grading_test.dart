import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/copy_grading.dart';

void main() {
  group('gradeTyped', () {
    test('substitution and deletion are wrong, insertion is ignored', () {
      expect(gradeTyped('KARL', 'KARL'), [true, true, true, true]);
      expect(gradeTyped('KARL', 'KXRL'), [true, false, true, true]);
      expect(gradeTyped('KARL', 'KRL'), [true, false, true, true]);
      expect(gradeTyped('KARL', 'KAXRL'), [true, true, true, true]);
    });

    test('empty answer marks everything wrong, case does not matter', () {
      expect(gradeTyped('AB', ''), [false, false]);
      expect(gradeTyped('ab', 'AB'), [true, true]);
    });
  });

  group('gradeSent (Geben, per character)', () {
    test('one wrong character costs only that character', () {
      expect(gradeSent('KARL', 'KARL'), [true, true, true, true]);
      expect(gradeSent('KARL', 'KXRL'), [true, false, true, true]);
      expect(gradeSent('KARL', 'KRL'), [true, false, true, true]);
    });

    test('an extra keyed character is an error', () {
      expect(gradeSent('KARL', 'KAXRL'), [true, true, true, false]);
      expect(gradeSent('CQ', 'CQQQ'), [false, false]);
    });

    test('empty answer is all wrong, blanks and case do not count', () {
      expect(gradeSent('AB', ''), [false, false]);
      expect(gradeSent('ab c', 'ABC'), [true, true, true]);
    });
  });

  group('firstMixup (#92)', () {
    test('substitution reads played>typed', () {
      expect(firstMixup('KARL', 'RARL'), 'K>R');
      expect(firstMixup('cbnl', 'cdnl'), 'B>D');
    });

    test('a missing character reads played>–', () {
      expect(firstMixup('KARL', 'KRL'), 'A>–');
      expect(firstMixup('KARL', ''), 'K>–');
    });

    test('only the first wrong character counts', () {
      expect(firstMixup('KARL', 'RAXL'), 'K>R');
    });

    test('right copy and extra typed characters give no mix-up', () {
      expect(firstMixup('KARL', 'KARL'), isNull);
      expect(firstMixup('KARL', 'kArl'), isNull);
      expect(firstMixup('KARL', 'KAXRL'), isNull);
    });

    test('blanks in the played text never count', () {
      expect(firstMixup('A B', 'AB'), isNull);
      expect(firstMixup('A B', 'AX'), 'B>X');
    });
  });
}
