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
}
