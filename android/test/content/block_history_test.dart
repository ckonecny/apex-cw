import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/block_history.dart';

void main() {
  test('kein Trend unter 6 Blöcken', () {
    expect(trendOf(List.filled(5, 0.8)), isNull);
  });
  test('besser, schlechter, gleich', () {
    expect(trendOf([...List.filled(5, 0.7), ...List.filled(5, 0.9)])!.direction, 1);
    expect(trendOf([...List.filled(5, 0.9), ...List.filled(5, 0.7)])!.direction, -1);
    expect(trendOf(List.filled(10, 0.8))!.direction, 0);
  });
  test('sechs Blöcke: Vergleich mit dem einen früheren', () {
    final t = trendOf([0.5, 0.9, 0.9, 0.9, 0.9, 0.9])!;
    expect(t.percent, 90);
    expect(t.direction, 1);
  });
}
