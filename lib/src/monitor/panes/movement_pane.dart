import 'package:flutter/material.dart';
import 'package:neurofeed/src/charts/eeg_data_source.dart';
import 'package:neurofeed/src/charts/smooth_path.dart';
import 'package:neurofeed/src/monitor/viewport_controller.dart';

const Color kMovementColor = Color(0xFFFFA726);
const double kMovementYMin = 0;
const double kMovementYMax = 1.5;

class MovementPane extends StatelessWidget {
  const MovementPane({
    super.key,
    required this.samples,
    required this.viewport,
    required this.newestElapsed,
  });

  final List<ChartSample> samples;
  final ViewportController viewport;
  final double newestElapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return RepaintBoundary(
      child: CustomPaint(
        painter: MovementPainter(
          samples: samples,
          viewport: viewport,
          newestElapsed: newestElapsed,
          wallNow: wallNow,
          axisColor: theme.colorScheme.onSurfaceVariant,
          gridColor: theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class MovementPainter extends CustomPainter {
  MovementPainter({
    required this.samples,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.axisColor,
    required this.gridColor,
  });

  static const double leftGutter = 36;
  static const double rightGutter = 12;
  static const double xGutter = 22;
  static const double topGutter = 28;

  final List<ChartSample> samples;
  final ViewportController viewport;
  final double newestElapsed;
  final double wallNow;
  final Color axisColor;
  final Color gridColor;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    leftGutter,
    topGutter,
    (size.width - leftGutter - rightGutter).clamp(8, double.infinity),
    (size.height - topGutter - xGutter).clamp(8, double.infinity),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final chart = chartRect(size);
    if (chart.width <= 0 || chart.height <= 0) return;
    final visStart = viewport.stripVisibleStart(
      newestElapsed: newestElapsed,
      wallNow: wallNow,
    );
    final visEnd = viewport.stripVisibleEnd(
      newestElapsed: newestElapsed,
      wallNow: wallNow,
    );
    final span = visEnd - visStart;
    if (span <= 0) return;

    _drawGrid(canvas, chart, visStart, visEnd, span);
    canvas.save();
    canvas.clipRect(chart);
    _drawSeries(canvas, chart, visStart, span);
    canvas.restore();
    _drawYLabels(canvas, chart);
    _drawXLabels(canvas, chart, visStart, visEnd);
  }

  void _drawGrid(
    Canvas canvas,
    Rect chart,
    double visStart,
    double visEnd,
    double span,
  ) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final t in elapsedTicks(
      start: visStart,
      end: visEnd,
      widthPx: chart.width,
    )) {
      final x = chart.left + (t - visStart) / span * chart.width;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
    }
  }

  void _drawSeries(Canvas canvas, Rect chart, double visStart, double span) {
    if (samples.length < 2) return;
    final ySpan = kMovementYMax - kMovementYMin;
    final pts = <Offset>[];
    for (final s in samples) {
      final x = chart.left + (s.t - visStart) / span * chart.width;
      final y = chart.bottom - ((s.v - kMovementYMin) / ySpan) * chart.height;
      pts.add(Offset(x, y));
    }
    final path = Path();
    buildSmoothPath(path, pts);
    canvas.drawPath(
      path,
      Paint()
        ..color = kMovementColor
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _drawYLabels(Canvas canvas, Rect chart) {
    final style = TextStyle(color: axisColor, fontSize: 10);
    void label(String text, double y) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 4, y - tp.height / 2));
    }

    label('1.5', chart.top);
    label('0', chart.bottom);
    label('g', chart.top + 14);
  }

  void _drawXLabels(Canvas canvas, Rect chart, double visStart, double visEnd) {
    final style = TextStyle(color: axisColor, fontSize: 10);
    final span = visEnd - visStart;
    for (final t in elapsedTicks(
      start: visStart,
      end: visEnd,
      widthPx: chart.width,
    )) {
      final x = chart.left + (t - visStart) / span * chart.width;
      final tp = TextPainter(
        text: TextSpan(text: formatElapsed(t), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant MovementPainter old) =>
      old.samples != samples ||
      old.viewport != viewport ||
      old.newestElapsed != newestElapsed ||
      old.wallNow != wallNow ||
      old.axisColor != axisColor ||
      old.gridColor != gridColor;
}
