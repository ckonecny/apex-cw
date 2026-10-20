import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/theme/theme_controller.dart';

MediaQueryData _mq(double w, List<Rect> holes) => MediaQueryData(
      size: Size(w, 800),
      displayFeatures: [
        for (final h in holes)
          DisplayFeature(
              bounds: h,
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown),
      ],
    );

void main() {
  test('off when not wanted', () {
    expect(CompactTop.evaluate(_mq(411, const []), wanted: false).applied, false);
  });

  test('no cut-out: applied, no limits', () {
    final i = CompactTop.evaluate(_mq(411, const []), wanted: true);
    expect(i.applied, true);
    expect(i.holeLeft, isNull);
    expect(i.fits(6), true);
  });

  test('centred hole (Pixel 9a): applied, title limit, five buttons fit', () {
    final i = CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(184, 0, 227, 58)]), wanted: true);
    expect(i.applied, true);
    expect(i.holeLeft, 184);
    expect(i.fits(5), true);
    expect(i.fits(6), false);
  });

  test('narrow phone: four buttons fit, five do not', () {
    final i = CompactTop.evaluate(
        _mq(360, [const Rect.fromLTRB(160, 0, 202, 40)]), wanted: true);
    expect(i.applied, true);
    expect(i.fits(4), true);
    expect(i.fits(5), false);
  });

  test('corner hole, wide notch and too little room: normal layout', () {
    expect(CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(20, 0, 60, 40)]), wanted: true).applied, false);
    // a hole in the very corner touches the screen edge
    expect(CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(0, 0, 40, 40)]), wanted: true).applied, false);
    expect(CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(371, 0, 411, 40)]), wanted: true).applied, false);
    expect(CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(120, 0, 290, 40)]), wanted: true).applied, false);
    expect(CompactTop.evaluate(
        _mq(320, [const Rect.fromLTRB(140, 0, 240, 40)]), wanted: true).applied, false);
  });

  test('two cut-outs: any bad one disables, otherwise the nearest limits', () {
    expect(CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(184, 0, 227, 40), const Rect.fromLTRB(10, 0, 40, 30)]),
        wanted: true).applied, false);
    final i = CompactTop.evaluate(
        _mq(411, [const Rect.fromLTRB(170, 0, 190, 40), const Rect.fromLTRB(210, 0, 230, 40)]),
        wanted: true);
    expect(i.applied, true);
    expect(i.holeLeft, 170);
  });
}
