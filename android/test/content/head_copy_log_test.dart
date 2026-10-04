import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/head_copy_log.dart';

void main() {
  test('results survive an encode/parse round trip', () {
    final list = [const HcResult(1000, 2, 1, 3, 4), const HcResult(2000, 1, 0, 4, 4)];
    final back = hcParseResults(hcEncodeResults(list));
    expect(back.length, 2);
    expect(back.first.level, 2);
    expect(back.first.lang, 1);
    expect(back.first.rate, 0.75);
    expect(back.last.rate, 1.0);
  });

  test('broken or empty input gives an empty list', () {
    expect(hcParseResults(null), isEmpty);
    expect(hcParseResults(''), isEmpty);
    expect(hcParseResults('not json'), isEmpty);
    expect(hcParseResults('{"a":1}'), isEmpty);
  });

  test('only the newest results are kept', () {
    final list = [for (var i = 0; i < kKeepHcResults + 5; i++) HcResult(i, 1, 0, 1, 1)];
    final back = hcParseResults(hcEncodeResults(list));
    expect(back.length, kKeepHcResults);
    expect(back.first.time, 5);
  });

  test('recent rate weighs by question count and handles no data', () {
    expect(hcRecentRate([]), isNull);
    final list = [const HcResult(1, 1, 0, 0, 4), const HcResult(2, 3, 0, 6, 6)];
    expect(hcRecentRate(list), 0.6);
    expect(hcRecentRate(list, n: 1), 1.0);
  });
}
