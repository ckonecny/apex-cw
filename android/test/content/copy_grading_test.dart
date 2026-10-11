import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/copy_grading.dart';

void main() {
  test('exact copy is all right, case-insensitive', () {
    expect(gradeTyped('TQR5U', 'tqr5u'), [true, true, true, true, true]);
  });

  test('a missed char is one error, not every char after it', () {
    expect(gradeTyped('TQR5U', 'TQ5U'), [true, true, false, true, true]);
  });

  test('a wrong char is one error (substitution)', () {
    expect(gradeTyped('CD9AL', 'CB9AL'), [true, false, true, true, true]);
  });

  test('an extra typed char marks nothing wrong', () {
    expect(gradeTyped('ESNO0', 'ESNOO0'), [true, true, true, true, true]);
  });

  test('passed (empty) marks every char wrong', () {
    expect(gradeTyped('ABC', ''), [false, false, false]);
  });

  test('missed last char', () {
    expect(gradeTyped('CD9AL', 'CD9A'), [true, true, true, true, false]);
  });

  test('missed first char', () {
    expect(gradeTyped('CD9AL', 'D9AL'), [false, true, true, true, true]);
  });

  test('wholly different text marks all wrong', () {
    expect(gradeTyped('ABC', 'XYZ'), [false, false, false]);
  });

  group('isTypedRight', () {
    test('exact copy, case-insensitive', () {
      expect(isTypedRight('ABC', 'abc'), isTrue);
    });

    test('last key pressed twice or more is a slip, not an error', () {
      expect(isTypedRight('ABC', 'ABCC'), isTrue);
      expect(isTypedRight('ABC', 'ABCCC'), isTrue);
      expect(isTypedRight('ABB', 'ABBB'), isTrue);
    });

    test('other extra characters stay wrong', () {
      expect(isTypedRight('ABC', 'ABCE'), isFalse);
      expect(isTypedRight('ABC', 'ABBC'), isFalse);
      expect(isTypedRight('ABC', 'AABC'), isFalse);
      expect(isTypedRight('ABC', 'ABCCE'), isFalse);
    });

    test('missing or wrong characters stay wrong', () {
      expect(isTypedRight('ABC', 'AB'), isFalse);
      expect(isTypedRight('ABC', 'ABD'), isFalse);
      expect(isTypedRight('ABC', ''), isFalse);
      expect(isTypedRight('', 'A'), isFalse);
    });
  });
}
