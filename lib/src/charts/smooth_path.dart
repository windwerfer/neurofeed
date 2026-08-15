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
  if (n < 2) {
    return;
  }

  final slopes = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = pts[i + 1].dx - pts[i].dx;
    slopes[i] = dx == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx;
  }

  // Tangents in slope units, clamped so each segment's Hermite cubic is
  // monotone: the interior tangent is the sign-aware harmonic mean of the two
  // neighbouring segment slopes (≤ 3·min of either), and zero at a local
  // extremum or a flat neighbour.
  final tangents = List<double>.filled(n, 0);
  tangents[0] = slopes[0];
  tangents[n - 1] = slopes[n - 2];
  for (var i = 1; i < n - 1; i++) {
    final a = slopes[i - 1];
    final b = slopes[i];
    if (a == 0 || b == 0 || (a < 0) != (b < 0)) {
      tangents[i] = 0;
    } else {
      tangents[i] = 2 * a * b / (a + b);
    }
  }

  for (var i = 0; i < n - 1; i++) {
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final h = p2.dx - p1.dx;
    if (h == 0) {
      continue;
    }
    final cp1 = Offset(p1.dx + h / 3, p1.dy + tangents[i] * h / 3);
    final cp2 = Offset(p2.dx - h / 3, p2.dy - tangents[i + 1] * h / 3);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
}