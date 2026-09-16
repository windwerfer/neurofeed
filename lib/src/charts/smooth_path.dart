import 'dart:ui';

/// Trace a monotone cubic spline (Fritsch–Carlson / PCHIP) through [pts] onto
/// [path].
///
/// The curve passes through every point and never overshoots the data:
/// locally-monotonic stretches stay monotonic, so a simple up/down wave keeps
/// its shape instead of developing the caved-in / bulged-out loops that
/// uniform Catmull-Rom produces around steep vertices. Handles non-uniform
/// x-spacing (gaps where buckets had no data).
void buildSmoothPath(Path path, List<Offset> pts) {
  final n = pts.length;
  if (n == 0) {
    return;
  }
  path.moveTo(pts[0].dx, pts[0].dy);
  if (n == 1) {
    return;
  }
  for (final c in pchipCubics(pts)) {
    if ((c.p3.dx - c.p0.dx).abs() < 1e-12) {
      path.lineTo(c.p3.dx, c.p3.dy);
    } else {
      path.cubicTo(c.p1.dx, c.p1.dy, c.p2.dx, c.p2.dy, c.p3.dx, c.p3.dy);
    }
  }
}

/// Cubic Bézier for each PCHIP segment (`p0` → `p1`/`p2` → `p3`).
List<({Offset p0, Offset p1, Offset p2, Offset p3})> pchipCubics(
  List<Offset> pts,
) {
  final n = pts.length;
  if (n < 2) return const [];
  if (n == 2) {
    final a = pts[0];
    final b = pts[1];
    return [
      (
        p0: a,
        p1: Offset(a.dx + (b.dx - a.dx) / 3, a.dy + (b.dy - a.dy) / 3),
        p2: Offset(a.dx + 2 * (b.dx - a.dx) / 3, a.dy + 2 * (b.dy - a.dy) / 3),
        p3: b,
      ),
    ];
  }

  final h = List<double>.filled(n - 1, 0);
  final delta = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    h[i] = pts[i + 1].dx - pts[i].dx;
    delta[i] = h[i] == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / h[i];
  }

  final m = List<double>.filled(n, 0);
  m[0] = _pchipEndSlope(delta[0], delta[1], h[0], h[1]);
  m[n - 1] = _pchipEndSlope(delta[n - 2], delta[n - 3], h[n - 2], h[n - 3]);
  for (var i = 1; i < n - 1; i++) {
    final d0 = delta[i - 1];
    final d1 = delta[i];
    if (d0 == 0 || d1 == 0 || (d0 < 0) != (d1 < 0)) {
      m[i] = 0;
    } else {
      final w1 = 2 * h[i] + h[i - 1];
      final w2 = h[i] + 2 * h[i - 1];
      m[i] = (w1 + w2) / (w1 / d0 + w2 / d1);
    }
  }

  final out = <({Offset p0, Offset p1, Offset p2, Offset p3})>[];
  for (var i = 0; i < n - 1; i++) {
    final p0 = pts[i];
    final p3 = pts[i + 1];
    final hi = h[i];
    if (hi.abs() < 1e-12) {
      out.add((p0: p0, p1: p0, p2: p3, p3: p3));
      continue;
    }
    out.add((
      p0: p0,
      p1: Offset(p0.dx + hi / 3, p0.dy + m[i] * hi / 3),
      p2: Offset(p3.dx - hi / 3, p3.dy - m[i + 1] * hi / 3),
      p3: p3,
    ));
  }
  return out;
}

double _pchipEndSlope(double d0, double d1, double h0, double h1) {
  final denom = h0 + h1;
  if (denom == 0) return 0;
  var d = ((2 * h0 + h1) * d0 - h0 * d1) / denom;
  if (d == 0 || d0 == 0 || (d < 0) != (d0 < 0)) return 0;
  if ((d0 < 0) != (d1 < 0) && d.abs() > 3 * d0.abs()) {
    return 3 * d0;
  }
  return d;
}

Offset bezierCubic(({Offset p0, Offset p1, Offset p2, Offset p3}) c, double t) {
  final u = 1 - t;
  final uu = u * u;
  final tt = t * t;
  return Offset(
    uu * u * c.p0.dx +
        3 * uu * t * c.p1.dx +
        3 * u * tt * c.p2.dx +
        tt * t * c.p3.dx,
    uu * u * c.p0.dy +
        3 * uu * t * c.p1.dy +
        3 * u * tt * c.p2.dy +
        tt * t * c.p3.dy,
  );
}
