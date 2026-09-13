import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/panes/sweep_pane.dart';

int _countPoints({
  required int n,
  required double widthPx,
  required double Function(int i) sampleAt,
}) {
  return emitSweepTrace(
    n: n,
    widthPx: widthPx,
    sampleAt: sampleAt,
    moveTo: (x, y) {},
    lineTo: (x, y) {},
  );
}

void main() {
  test('2560 samples at width 100 emit at most 200 path points', () {
    final points = _countPoints(
      n: 2560,
      widthPx: 100,
      sampleAt: (i) => i.toDouble(),
    );
    expect(points, lessThanOrEqualTo(200));
    expect(points, 200);
  });

  test('n at or below width is one vertex per sample', () {
    expect(
      _countPoints(n: 50, widthPx: 100, sampleAt: (i) => i.toDouble()),
      50,
    );
    expect(
      _countPoints(n: 100, widthPx: 100, sampleAt: (i) => i.toDouble()),
      100,
    );
  });

  test('minmax per pixel keeps a peak inside a dense column', () {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    emitSweepTrace(
      n: 1000,
      widthPx: 10,
      sampleAt: (i) => i == 500 ? 99.0 : 0.0,
      moveTo: (x, y) {
        lo = math.min(lo, y);
        hi = math.max(hi, y);
      },
      lineTo: (x, y) {
        lo = math.min(lo, y);
        hi = math.max(hi, y);
      },
    );
    expect(hi, 99.0);
    expect(lo, 0.0);
  });

  test('NaN columns break the path', () {
    var moves = 0;
    var lines = 0;
    emitSweepTrace(
      n: 8,
      widthPx: 8,
      sampleAt: (i) => i == 3 ? double.nan : i.toDouble(),
      moveTo: (x, y) => moves++,
      lineTo: (x, y) => lines++,
    );
    expect(moves, 2);
    expect(lines, 5);
  });
}
