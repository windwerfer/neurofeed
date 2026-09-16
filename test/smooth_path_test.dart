import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/charts/smooth_path.dart';

void main() {
  test('two points is a straight segment', () {
    final cubics = pchipCubics(const [Offset(0, 0), Offset(10, 5)]);
    expect(cubics, hasLength(1));
    for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final p = bezierCubic(cubics.first, t);
      expect(p.dx, closeTo(10 * t, 1e-9));
      expect(p.dy, closeTo(5 * t, 1e-9));
    }
  });

  test('same-x points stay connected (no skipped vertex)', () {
    final path = Path();
    buildSmoothPath(path, const [Offset(0, 0), Offset(0, 10), Offset(10, 10)]);
    final bounds = path.getBounds();
    expect(bounds.top, closeTo(0, 1e-6));
    expect(bounds.bottom, closeTo(10, 1e-6));
    expect(bounds.left, closeTo(0, 1e-6));
    expect(bounds.right, closeTo(10, 1e-6));
  });

  test('PCHIP stays inside each segment y-range (no overshoot bar)', () {
    final pts = [
      const Offset(0, 0),
      const Offset(10, 8),
      const Offset(20, 3),
      const Offset(30, 9),
      const Offset(40, 4),
    ];
    for (final c in pchipCubics(pts)) {
      final lo = c.p0.dy < c.p3.dy ? c.p0.dy : c.p3.dy;
      final hi = c.p0.dy > c.p3.dy ? c.p0.dy : c.p3.dy;
      for (var i = 0; i <= 16; i++) {
        final y = bezierCubic(c, i / 16).dy;
        expect(y, greaterThanOrEqualTo(lo - 1e-6));
        expect(y, lessThanOrEqualTo(hi + 1e-6));
      }
    }
  });

  test('steep peak then drop does not overshoot the vertex', () {
    final pts = [
      const Offset(0, 0),
      const Offset(10, 20),
      const Offset(20, 2),
      const Offset(30, 4),
    ];
    for (final c in pchipCubics(pts)) {
      final lo = c.p0.dy < c.p3.dy ? c.p0.dy : c.p3.dy;
      final hi = c.p0.dy > c.p3.dy ? c.p0.dy : c.p3.dy;
      for (var i = 0; i <= 20; i++) {
        final y = bezierCubic(c, i / 20).dy;
        expect(y, inInclusiveRange(lo - 1e-6, hi + 1e-6));
      }
    }
  });
}
