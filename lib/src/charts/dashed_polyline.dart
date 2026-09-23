import 'dart:ui';

/// Contiguous [draw, gap, draw, gap, ...] lengths that cover [totalLength].
///
/// Exposed for tests: dense polylines still leave gaps when the phase is
/// continuous along the whole path (not restarted per short segment).
List<({bool draw, double length})> dashedIntervals(
  double totalLength, {
  double dash = 6,
  double gap = 4,
}) {
  if (totalLength <= 0) return const [];
  final out = <({bool draw, double length})>[];
  var distance = 0.0;
  var draw = true;
  while (distance < totalLength) {
    final len = draw ? dash : gap;
    final next = distance + len > totalLength ? totalLength : distance + len;
    out.add((draw: draw, length: next - distance));
    draw = !draw;
    distance = next;
  }
  return out;
}

/// Dashed polyline with a **continuous** dash phase along the whole path.
///
/// Per-segment restarting looks solid when consecutive points are closer
/// than [dash] (common on flat hold-last-Y stretches at band sample rates).
void paintDashedPolyline(
  Canvas canvas,
  List<Offset> pts,
  Paint paint, {
  double dash = 6,
  double gap = 4,
}) {
  if (pts.length < 2) return;
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx, pts[i].dy);
  }
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    for (final part in dashedIntervals(
      metric.length,
      dash: dash,
      gap: gap,
    )) {
      final next = distance + part.length;
      if (part.draw) {
        canvas.drawPath(metric.extractPath(distance, next), paint);
      }
      distance = next;
    }
  }
}
