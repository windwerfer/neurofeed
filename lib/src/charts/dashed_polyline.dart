import 'dart:ui';

/// Segment-wise dashed polyline. Independent of Bands Y-overshoot dash.
void paintDashedPolyline(
  Canvas canvas,
  List<Offset> pts,
  Paint paint, {
  double dash = 5,
  double gap = 4,
}) {
  if (pts.length < 2) return;
  for (var i = 0; i < pts.length - 1; i++) {
    _dashSegment(canvas, pts[i], pts[i + 1], paint, dash, gap);
  }
}

void _dashSegment(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint,
  double dash,
  double gap,
) {
  final d = b - a;
  final len = d.distance;
  if (len <= 0) return;
  final dir = Offset(d.dx / len, d.dy / len);
  var t = 0.0;
  var draw = true;
  while (t < len) {
    final step = draw ? dash : gap;
    final next = t + step > len ? len : t + step;
    if (draw) {
      canvas.drawLine(a + dir * t, a + dir * next, paint);
    }
    draw = !draw;
    t = next;
  }
}
