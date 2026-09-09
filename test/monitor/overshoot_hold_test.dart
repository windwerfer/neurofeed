import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/panes/overshoot_hold.dart';

void main() {
  test('value above Y-max does not feed auto scale', () {
    expect(kBandsOvershootHold, isTrue);
    final scaled = overshootScaleValues([10, 20, 100], currentMax: 25).toList();
    expect(scaled, [10, 20]);
  });

  test('null currentMax includes all finite values', () {
    final scaled = overshootScaleValues([10, double.nan, 100]).toList();
    expect(scaled, [10, 100]);
  });

  test('overshoot paints dashed at last in-range Y', () {
    final hold = overshootPaintY(value: 100, yMax: 25, lastInRangeY: 20);
    expect(hold.y, 20);
    expect(hold.dashed, isTrue);

    final inRange = overshootPaintY(value: 18, yMax: 25, lastInRangeY: 20);
    expect(inRange.y, 18);
    expect(inRange.dashed, isFalse);
  });
}
