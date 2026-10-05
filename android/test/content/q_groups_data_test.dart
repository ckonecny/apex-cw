import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/q_groups_data.dart';

void main() {
  test('Q-group list is sound', () {
    expect(qgValidate(qGroups), isEmpty);
  });

  test('every group is a real Q-code and in uppercase', () {
    for (final g in qGroups) {
      expect(RegExp(r'^Q[A-Z]{2}$').hasMatch(g.code), isTrue, reason: g.code);
    }
  });

  test('the validator catches a level with too few wrong options', () {
    const a = QGroup('QAA', 1, 'x', QText('a', 'b'), QText('a', 'b'));
    expect(qgValidate(const [a]), isNotEmpty);
  });
}
