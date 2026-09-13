import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:muse_ml/src/monitor/dsp.dart';

class HistogramPane extends StatelessWidget {
  const HistogramPane({
    super.key,
    required this.counts,
    required this.halfRange,
    required this.connected,
    this.hairlineUv,
    this.onTapUv,
  });

  final List<int> counts;
  final double halfRange;
  final bool connected;
  final double? hairlineUv;
  final ValueChanged<double>? onTapUv;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTapUv == null
            ? null
            : (d) {
                final size = context.size;
                if (size == null) return;
                onTapUv!(
                  HistogramPanePainter.uvForX(
                    d.localPosition.dx,
                    size,
                    halfRange,
                  ),
                );
              },
        child: CustomPaint(
          painter: HistogramPanePainter(
            counts: counts,
            halfRange: halfRange,
            connected: connected,
            hairlineUv: hairlineUv,
            axisColor: theme.colorScheme.onSurfaceVariant,
            gridColor: theme.colorScheme.outlineVariant,
            barColor: theme.colorScheme.primary,
            hairlineColor: theme.colorScheme.onSurface,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class HistogramPanePainter extends CustomPainter {
  HistogramPanePainter({
    required this.counts,
    required this.halfRange,
    required this.connected,
    required this.hairlineUv,
    required this.axisColor,
    required this.gridColor,
    required this.barColor,
    required this.hairlineColor,
  });

  static const double yGutter = 44;
  static const double xGutter = 22;
  static const double topGutter = 22;
  static const double rightGutter = 12;

  final List<int> counts;
  final double halfRange;
  final bool connected;
  final double? hairlineUv;
  final Color axisColor;
  final Color gridColor;
  final Color barColor;
  final Color hairlineColor;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    yGutter,
    topGutter,
    (size.width - yGutter - rightGutter).clamp(8, double.infinity),
    (size.height - topGutter - xGutter).clamp(8, double.infinity),
  );

  static double uvForX(double x, Size size, double halfRange) {
    final chart = chartRect(size);
    if (chart.width <= 0) return 0;
    final t = ((x - chart.left) / chart.width).clamp(0.0, 1.0);
    return -halfRange + t * 2 * halfRange;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chart = chartRect(size);
    if (chart.width <= 0 || chart.height <= 0) return;
    var maxCount = 1;
    if (connected) {
      for (final c in counts) {
        if (c > maxCount) maxCount = c;
      }
    }
    final yMax = maxCount * 1.1;
    _drawGrid(canvas, chart, yMax);
    if (connected && counts.isNotEmpty) {
      _drawBars(canvas, chart, yMax);
    }
    _drawYLabels(canvas, chart, yMax);
    _drawXLabels(canvas, chart);
    final uv = hairlineUv;
    if (uv != null && connected) {
      _drawHairline(canvas, chart, uv);
    }
  }

  void _drawGrid(Canvas canvas, Rect chart, double yMax) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(chart.left + chart.width / 2, chart.top),
      Offset(chart.left + chart.width / 2, chart.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      paint,
    );
  }

  void _drawBars(Canvas canvas, Rect chart, double yMax) {
    final n = counts.length;
    if (n == 0 || yMax <= 0) return;
    final bw = chart.width / n;
    final paint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final h = counts[i] / yMax * chart.height;
      if (h <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(chart.left + i * bw, chart.bottom - h, bw - 0.5, h),
        paint,
      );
    }
  }

  void _drawYLabels(Canvas canvas, Rect chart, double yMax) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final title = TextPainter(
      text: TextSpan(text: 'count', style: style.copyWith(fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(8, chart.top - title.height - 2));
    for (final v in _yTicks(yMax, chart.height)) {
      final py = chart.bottom - v / yMax * chart.height;
      final tp = TextPainter(
        text: TextSpan(text: v.round().toString(), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 4, py - tp.height / 2));
    }
  }

  List<double> _yTicks(double yMax, double height) {
    if (yMax <= 0 || height <= 0) return const [];
    final ideal = (height / 40).clamp(2, 6);
    final rough = yMax / ideal;
    final exp = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final frac = rough / exp;
    final step =
        exp *
        (frac <= 1.5
            ? 1
            : frac <= 3.5
            ? 2
            : frac <= 7.5
            ? 5
            : 10);
    if (step <= 0) return const [];
    final ticks = <double>[];
    for (var v = 0.0; v <= yMax + 1e-9; v += step) {
      ticks.add(v);
    }
    return ticks;
  }

  void _drawXLabels(Canvas canvas, Rect chart) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    void label(double uv, double x) {
      final text = uv == 0 ? '0' : '${uv.round()}';
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = x - tp.width / 2;
      if (dx < chart.left) dx = chart.left;
      if (dx + tp.width > chart.right) dx = chart.right - tp.width;
      tp.paint(canvas, Offset(dx, chart.bottom + 4));
    }

    label(-halfRange, chart.left);
    label(0, chart.left + chart.width / 2);
    label(halfRange, chart.right);
    final unit = TextPainter(
      text: TextSpan(text: 'µV', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    unit.paint(
      canvas,
      Offset(chart.right - unit.width, chart.bottom + xGutter - unit.height),
    );
  }

  void _drawHairline(Canvas canvas, Rect chart, double uv) {
    final t = ((uv + halfRange) / (2 * halfRange)).clamp(0.0, 1.0);
    final x = chart.left + t * chart.width;
    final paint = Paint()
      ..color = hairlineColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
    final bin = histogramBinFor(
      uv,
      halfRange: halfRange,
      binCount: counts.isEmpty ? kHistogramBins : counts.length,
    );
    final count = bin >= 0 && bin < counts.length ? counts[bin] : 0;
    final label = '${uv.round()} µV   $count';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: hairlineColor,
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = x - tp.width / 2;
    if (dx < chart.left) dx = chart.left;
    if (dx + tp.width > chart.right) dx = chart.right - tp.width;
    tp.paint(canvas, Offset(dx, chart.top - tp.height - 2));
  }

  @override
  bool shouldRepaint(covariant HistogramPanePainter old) {
    return old.halfRange != halfRange ||
        old.connected != connected ||
        old.hairlineUv != hairlineUv ||
        old.counts != counts;
  }
}
