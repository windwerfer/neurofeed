import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

bool sweepSampleOk(double s) => !s.isNaN && s.abs() <= 1e6;

/// Min/max envelope of [n] samples into at most one vertical tick per pixel
/// column when [n] > [widthPx]. Returns the number of move/line vertices.
int emitSweepTrace({
  required int n,
  required double widthPx,
  required double Function(int i) sampleAt,
  required void Function(double x, double y) moveTo,
  required void Function(double x, double y) lineTo,
}) {
  if (n <= 0 || widthPx <= 0) return 0;
  final cols = widthPx.floor();
  if (cols <= 0) return 0;

  var points = 0;
  var started = false;
  void move(double x, double y) {
    moveTo(x, y);
    points++;
    started = true;
  }

  void line(double x, double y) {
    lineTo(x, y);
    points++;
  }

  if (n <= cols) {
    for (var i = 0; i < n; i++) {
      final s = sampleAt(i);
      if (!sweepSampleOk(s)) {
        started = false;
        continue;
      }
      if (!started) {
        move(i.toDouble(), s);
      } else {
        line(i.toDouble(), s);
      }
    }
    return points;
  }

  for (var col = 0; col < cols; col++) {
    var i0 = (col * n) ~/ cols;
    var i1 = ((col + 1) * n) ~/ cols;
    if (i1 <= i0) i1 = i0 + 1;
    if (i0 >= n) break;
    if (i1 > n) i1 = n;
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (var i = i0; i < i1; i++) {
      final s = sampleAt(i);
      if (!sweepSampleOk(s)) continue;
      if (s < lo) lo = s;
      if (s > hi) hi = s;
    }
    if (lo.isInfinite) {
      started = false;
      continue;
    }
    final x = i0.toDouble();
    if (!started) {
      move(x, lo);
    } else {
      line(x, lo);
    }
    line(x, hi);
  }
  return points;
}

class _AxisLabelCache {
  static const int _cap = 64;
  static final Map<String, TextPainter> _cache = {};

  static TextPainter painter(String text, TextStyle style) {
    final key = '$text#${style.color?.toARGB32()}#${style.fontSize}';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    if (_cache.length >= _cap) {
      _cache.remove(_cache.keys.first)?.dispose();
    }
    _cache[key] = tp;
    return tp;
  }
}

enum YScaleMode { auto, fixed50, fixed100, fixed200 }

class SharedYScale extends ChangeNotifier {
  YScaleMode mode = YScaleMode.auto;
  double autoHalfRange = 200;

  double get halfRange {
    switch (mode) {
      case YScaleMode.auto:
        return autoHalfRange;
      case YScaleMode.fixed50:
        return 50;
      case YScaleMode.fixed100:
        return 100;
      case YScaleMode.fixed200:
        return 200;
    }
  }

  void setMode(YScaleMode next) {
    if (mode == next) return;
    mode = next;
    notifyListeners();
  }

  void setAutoHalfRange(double v) {
    autoHalfRange = v;
  }
}

class SweepPane extends StatelessWidget {
  const SweepPane({
    super.key,
    required this.electrode,
    required this.label,
    required this.buffer,
    required this.viewport,
    required this.yScale,
    required this.showXAxis,
    required this.traceColor,
    required this.wipeColor,
    this.fileSamples,
    this.newestElapsed,
    this.captureStartedAtMs,
  });

  final int electrode;
  final String label;
  final SweepBuffer buffer;
  final ViewportController viewport;
  final SharedYScale yScale;
  final bool showXAxis;
  final Color traceColor;
  final Color wipeColor;
  final Float64List? fileSamples;
  final double? newestElapsed;
  final int? captureStartedAtMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisColor = theme.colorScheme.onSurfaceVariant;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: SweepPanePainter(
                    electrode: electrode,
                    buffer: buffer,
                    viewport: viewport,
                    yScale: yScale,
                    showXAxis: showXAxis,
                    traceColor: traceColor,
                    wipeColor: wipeColor,
                    axisColor: axisColor,
                    gridColor: theme.colorScheme.outlineVariant,
                    fileSamples: fileSamples,
                    newestElapsed: newestElapsed,
                    captureStartedAtMs: captureStartedAtMs,
                    generation: buffer.generation,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: SweepPanePainter.yGutter + 8,
                child: Text(
                  label,
                  style: TextStyle(
                    color: traceColor,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SweepPanePainter extends CustomPainter {
  SweepPanePainter({
    required this.electrode,
    required this.buffer,
    required this.viewport,
    required this.yScale,
    required this.showXAxis,
    required this.traceColor,
    required this.wipeColor,
    required this.axisColor,
    required this.gridColor,
    required this.fileSamples,
    required this.newestElapsed,
    required this.captureStartedAtMs,
    required this.generation,
  });

  static const double yGutter = 44;
  static const double xGutter = 22;
  static const double stroke = 1;

  final int electrode;
  final SweepBuffer buffer;
  final ViewportController viewport;
  final SharedYScale yScale;
  final bool showXAxis;
  final Color traceColor;
  final Color wipeColor;
  final Color axisColor;
  final Color gridColor;
  final Float64List? fileSamples;
  final double? newestElapsed;
  final int? captureStartedAtMs;
  final int generation;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(
      8,
      4,
      (size.width - 8 - yGutter).clamp(8, double.infinity),
      (size.height - 4 - (showXAxis ? xGutter : 4)).clamp(8, double.infinity),
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    final half = yScale.halfRange;
    final yScalePx = chart.height / (2 * half);
    final n = viewport.windowSamples;
    final xScale = chart.width / n;

    _drawGrid(canvas, chart, half, yScalePx, n, xScale);
    _drawTrace(canvas, chart, half, yScalePx, n, xScale);
    if (viewport.mode == ViewportMode.follow && buffer.hasData) {
      _drawWipe(canvas, chart, n, xScale);
    }
    _drawYLabels(canvas, chart, half, yScalePx);
    if (showXAxis) {
      _drawXLabels(canvas, chart, n, xScale);
    }
  }

  void _drawGrid(
    Canvas canvas,
    Rect chart,
    double half,
    double yScalePx,
    int n,
    double xScale,
  ) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(chart.left, chart.center.dy),
      Offset(chart.right, chart.center.dy),
      paint,
    );
    final xTicks = elapsedTicks(
      start: 0,
      end: viewport.windowSeconds,
      widthPx: chart.width,
    );
    for (final t in xTicks) {
      final i = t * SweepBuffer.sampleRate;
      final x = chart.left + i * xScale;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
    }
  }

  void _drawTrace(
    Canvas canvas,
    Rect chart,
    double half,
    double yScalePx,
    int n,
    double xScale,
  ) {
    if (!buffer.hasChannel(electrode) && fileSamples == null) return;
    final paint = Paint()
      ..color = traceColor
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final path = Path();
    emitSweepTrace(
      n: n,
      widthPx: chart.width,
      sampleAt: (i) => _sampleAt(i, n),
      moveTo: (x, y) {
        path.moveTo(chart.left + x * xScale, chart.center.dy - y * yScalePx);
      },
      lineTo: (x, y) {
        path.lineTo(chart.left + x * xScale, chart.center.dy - y * yScalePx);
      },
    );
    canvas.drawPath(path, paint);
  }

  double _sampleAt(int i, int n) {
    if (fileSamples != null && i < fileSamples!.length) {
      final v = fileSamples![i];
      if (!v.isNaN) return v;
    }
    if (viewport.mode == ViewportMode.follow) {
      return buffer.displaySample(electrode, i);
    }
    final start = viewport.inspectStartElapsed ?? 0;
    final elapsed = start + i / SweepBuffer.sampleRate;
    final idx = ramIndexForElapsed(
      elapsed: elapsed,
      ramCount: buffer.channelCount(electrode),
      ramNewestElapsed: newestElapsed,
    );
    if (idx == null) return double.nan;
    return buffer.sampleAt(electrode, idx);
  }

  void _drawWipe(Canvas canvas, Rect chart, int n, double xScale) {
    if (n <= 0) return;
    final pos = buffer.cursor % n;
    final x = chart.left + pos * xScale;
    final paint = Paint()
      ..color = wipeColor
      ..strokeWidth = stroke;
    canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
  }

  void _drawYLabels(Canvas canvas, Rect chart, double half, double yScalePx) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    void label(double v) {
      final py = chart.center.dy - v * yScalePx;
      final text = v == 0 ? '0' : v.toStringAsFixed(0);
      final tp = _AxisLabelCache.painter(text, style);
      tp.paint(canvas, Offset(chart.right + 4, py - tp.height / 2));
    }

    label(half);
    label(0);
    label(-half);
  }

  void _drawXLabels(Canvas canvas, Rect chart, int n, double xScale) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final follow = viewport.mode == ViewportMode.follow;
    final now =
        newestElapsed ??
        (captureStartedAtMs == null
            ? buffer.sampleCount / SweepBuffer.sampleRate
            : 0.0);
    final start = follow
        ? now - viewport.windowSeconds
        : (viewport.inspectStartElapsed ?? 0);
    final end = follow ? now : start + viewport.windowSeconds;
    final ticks = elapsedTicks(
      start: follow ? 0 : start,
      end: follow ? viewport.windowSeconds : end,
      widthPx: chart.width,
    );

    for (final t in ticks) {
      late final double elapsed;
      late final double x;
      if (follow) {
        // t is seconds from the left of the pane (0..window). Wrap at wipe.
        final sample = (t * SweepBuffer.sampleRate).round().clamp(0, n);
        final cursor = n <= 0 ? 0 : buffer.cursor % n;
        if (sample < cursor) {
          elapsed = now - (cursor - sample) / SweepBuffer.sampleRate;
        } else {
          elapsed = now - (cursor + n - sample) / SweepBuffer.sampleRate;
        }
        x = chart.left + sample * xScale;
      } else {
        elapsed = t;
        final i = (t - start) * SweepBuffer.sampleRate;
        x = chart.left + i * xScale;
      }
      if (elapsed < 0) continue;
      final tp = _AxisLabelCache.painter(formatElapsed(elapsed), style);
      var dx = x - tp.width / 2;
      if (dx < chart.left) dx = chart.left;
      if (dx + tp.width > chart.right) dx = chart.right - tp.width;
      tp.paint(canvas, Offset(dx, chart.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant SweepPanePainter old) {
    return old.generation != generation ||
        old.viewport.mode != viewport.mode ||
        old.viewport.windowSeconds != viewport.windowSeconds ||
        old.viewport.inspectStartElapsed != viewport.inspectStartElapsed ||
        old.yScale.halfRange != yScale.halfRange ||
        old.traceColor != traceColor ||
        old.wipeColor != wipeColor ||
        old.fileSamples != fileSamples ||
        old.newestElapsed != newestElapsed ||
        old.showXAxis != showXAxis;
  }
}
