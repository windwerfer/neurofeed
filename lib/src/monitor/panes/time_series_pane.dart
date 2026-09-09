import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/panes/overshoot_hold.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

const double kBandsLogEpsilon = 1e-12;

class BandPoint {
  const BandPoint(this.elapsed, this.db);
  final double elapsed;
  final double db;
}

double linearToDb(double linear) {
  final v = linear.isFinite && linear > kBandsLogEpsilon
      ? linear
      : kBandsLogEpsilon;
  return 10.0 * math.log(v) / math.ln10;
}

double bandOriginUnix(BandCache cache, int? captureStartedAtMs) {
  if (captureStartedAtMs != null) {
    return captureStartedAtMs / 1000.0;
  }
  if (cache.hasData) return cache.oldestTimestamp;
  return 0;
}

List<List<BandPoint>> buildBandSeries({
  required BandCache cache,
  required Iterable<int> electrodes,
  required double startElapsed,
  required double endElapsed,
  required int? captureStartedAtMs,
}) {
  final origin = bandOriginUnix(cache, captureStartedAtMs);
  final startUnix = startElapsed + origin;
  final endUnix = endElapsed + origin;
  const pad = 1.0;
  final selected = electrodes.toList();
  final series = <List<BandPoint>>[];
  for (var b = 0; b < bandNames.length; b++) {
    final byT = <int, List<double>>{};
    for (final e in selected) {
      final samples = cache.getRange(
        bandChannelId(e, b),
        startUnix - pad,
        endUnix + pad,
      );
      for (final s in samples) {
        final key = (s.t * 1000).round();
        (byT[key] ??= []).add(linearToDb(s.v));
      }
    }
    final keys = byT.keys.toList()..sort();
    series.add([
      for (final k in keys)
        BandPoint(
          k / 1000.0 - origin,
          byT[k]!.reduce((a, b) => a + b) / byT[k]!.length,
        ),
    ]);
  }
  return series;
}

class TimeSeriesPane extends StatefulWidget {
  const TimeSeriesPane({
    super.key,
    required this.series,
    required this.viewport,
    required this.newestElapsed,
    required this.connected,
  });

  final List<List<BandPoint>> series;
  final ViewportController viewport;
  final double newestElapsed;
  final bool connected;

  @override
  State<TimeSeriesPane> createState() => _TimeSeriesPaneState();
}

class _TimeSeriesPaneState extends State<TimeSeriesPane> {
  double _yMin = -10;
  double _yMax = 20;
  int? _yMs;
  bool _established = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _easeY();
    return CustomPaint(
      painter: TimeSeriesPanePainter(
        series: widget.series,
        viewport: widget.viewport,
        newestElapsed: widget.newestElapsed,
        yMin: _yMin,
        yMax: _yMax,
        axisColor: theme.colorScheme.onSurfaceVariant,
        gridColor: theme.colorScheme.outlineVariant,
        connected: widget.connected,
      ),
    );
  }

  void _easeY() {
    final start = widget.viewport.stripVisibleStart(
      newestElapsed: widget.newestElapsed,
    );
    final end = widget.viewport.stripVisibleEnd(
      newestElapsed: widget.newestElapsed,
    );
    final raw = <double>[];
    for (final series in widget.series) {
      for (final p in series) {
        if (p.elapsed < start || p.elapsed > end) continue;
        raw.add(p.db);
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final forScale = overshootScaleValues(
      raw,
      currentMax: _established ? _yMax : null,
    ).toList();
    if (forScale.isEmpty) {
      _yMin = -10;
      _yMax = 20;
      _yMs = now;
      _established = false;
      return;
    }
    var lo = forScale.first;
    var hi = forScale.first;
    for (final v in forScale) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi - lo;
    final pad = range > 0 ? range * 0.15 : 1.0;
    final targetMin = lo - pad;
    final targetMax = hi + pad;
    if (_yMs == null || !_established) {
      _yMin = targetMin;
      _yMax = targetMax;
      _yMs = now;
      _established = true;
      return;
    }
    final dt = (now - _yMs!) / 1000.0;
    _yMs = now;
    _yMin = _easeToward(_yMin, targetMin, dt, expanding: targetMin < _yMin);
    _yMax = _easeToward(_yMax, targetMax, dt, expanding: targetMax > _yMax);
  }

  double _easeToward(
    double current,
    double target,
    double dt, {
    required bool expanding,
  }) {
    if (dt <= 0) return current;
    final tau = expanding ? 1.5 : 12.0;
    final a = 1 - math.exp(-dt / tau);
    return current + (target - current) * a;
  }
}

class TimeSeriesPanePainter extends CustomPainter {
  TimeSeriesPanePainter({
    required this.series,
    required this.viewport,
    required this.newestElapsed,
    required this.yMin,
    required this.yMax,
    required this.axisColor,
    required this.gridColor,
    required this.connected,
  });

  static const double yGutter = 44;
  static const double legendGutter = 56;
  static const double xGutter = 22;
  static const double topGutter = 18;

  final List<List<BandPoint>> series;
  final ViewportController viewport;
  final double newestElapsed;
  final double yMin;
  final double yMax;
  final Color axisColor;
  final Color gridColor;
  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(
      yGutter,
      topGutter,
      (size.width - yGutter - legendGutter).clamp(8, double.infinity),
      (size.height - topGutter - xGutter).clamp(8, double.infinity),
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    final visStart = viewport.stripVisibleStart(newestElapsed: newestElapsed);
    final visEnd = viewport.stripVisibleEnd(newestElapsed: newestElapsed);
    final span = visEnd - visStart;
    if (span <= 0) return;
    final ySpan = yMax - yMin;
    if (ySpan <= 0) return;

    _drawGrid(canvas, chart, visStart, visEnd, span);
    canvas.save();
    canvas.clipRect(chart);
    if (connected) {
      for (var i = 0; i < series.length && i < bandColors.length; i++) {
        _drawSeries(canvas, chart, series[i], bandColors[i], visStart, span);
      }
    }
    canvas.restore();
    _drawYLabels(canvas, chart);
    _drawXLabels(canvas, chart, visStart, visEnd);
    _drawLegend(canvas, chart);
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
    if (yMin <= 0 && yMax >= 0) {
      final y = _yToPx(chart, 0);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
    }
    for (final t in elapsedTicks(
      start: visStart,
      end: visEnd,
      widthPx: chart.width,
    )) {
      final x = chart.left + (t - visStart) / span * chart.width;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
    }
  }

  void _drawSeries(
    Canvas canvas,
    Rect chart,
    List<BandPoint> points,
    Color color,
    double visStart,
    double span,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    var lastInRange = yMin;
    var haveInRange = false;
    final solid = <Offset>[];
    final dashed = <Offset>[];

    void flushSolid() {
      if (solid.length < 2) {
        solid.clear();
        return;
      }
      final path = Path()..moveTo(solid.first.dx, solid.first.dy);
      for (var i = 1; i < solid.length; i++) {
        path.lineTo(solid[i].dx, solid[i].dy);
      }
      canvas.drawPath(path, paint);
      solid.clear();
    }

    void flushDashed() {
      if (dashed.length >= 2) {
        paintDashedPolyline(canvas, List<Offset>.from(dashed), paint);
      }
      dashed.clear();
    }

    Offset pt(double elapsed, double db) {
      final x = chart.left + (elapsed - visStart) / span * chart.width;
      final y = _yToPx(chart, db);
      return Offset(x, y);
    }

    var prevDashed = false;
    for (final p in points) {
      final hold = overshootPaintY(
        value: p.db,
        yMax: yMax,
        lastInRangeY: haveInRange ? lastInRange : yMax,
      );
      if (!hold.dashed) {
        lastInRange = p.db;
        haveInRange = true;
      }
      final o = pt(p.elapsed, hold.y);
      if (hold.dashed != prevDashed &&
          (solid.isNotEmpty || dashed.isNotEmpty)) {
        final join = o;
        if (prevDashed) {
          dashed.add(join);
          flushDashed();
          solid.add(join);
        } else {
          solid.add(join);
          flushSolid();
          dashed.add(join);
        }
      }
      if (hold.dashed) {
        dashed.add(o);
      } else {
        solid.add(o);
      }
      prevDashed = hold.dashed;
    }
    flushSolid();
    flushDashed();
  }

  double _yToPx(Rect chart, double v) =>
      chart.top + (yMax - v) / (yMax - yMin) * chart.height;

  void _drawYLabels(Canvas canvas, Rect chart) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final title = TextPainter(
      text: TextSpan(text: 'dB', style: style.copyWith(fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(8, chart.top - title.height - 2));

    for (final v in _yTicks(chart.height)) {
      final py = _yToPx(chart, v);
      final text = v.abs() >= 10 || v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 4, py - tp.height / 2));
    }
  }

  List<double> _yTicks(double height) {
    final range = yMax - yMin;
    if (range <= 0 || height <= 0) return const [];
    final ideal = (height / 40).clamp(2, 8);
    final rough = range / ideal;
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
    final first = (yMin / step).ceil() * step;
    final ticks = <double>[];
    for (var v = first; v <= yMax + 1e-9; v += step) {
      ticks.add(v);
    }
    return ticks;
  }

  void _drawXLabels(Canvas canvas, Rect chart, double visStart, double visEnd) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final span = visEnd - visStart;
    for (final t in elapsedTicks(
      start: visStart,
      end: visEnd,
      widthPx: chart.width,
    )) {
      if (t < 0) continue;
      final x = chart.left + (t - visStart) / span * chart.width;
      final tp = TextPainter(
        text: TextSpan(text: formatElapsed(t), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = x - tp.width / 2;
      if (dx < chart.left) dx = chart.left;
      if (dx + tp.width > chart.right) dx = chart.right - tp.width;
      tp.paint(canvas, Offset(dx, chart.bottom + 4));
    }
  }

  void _drawLegend(Canvas canvas, Rect chart) {
    final x = chart.right + 8;
    var y = chart.top;
    for (var i = 0; i < bandNames.length && i < bandColors.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: bandNames[i],
          style: TextStyle(color: bandColors[i], fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
      y += tp.height + 4;
    }
  }

  @override
  bool shouldRepaint(covariant TimeSeriesPanePainter old) {
    return old.yMin != yMin ||
        old.yMax != yMax ||
        old.newestElapsed != newestElapsed ||
        old.viewport.mode != viewport.mode ||
        old.viewport.windowSeconds != viewport.windowSeconds ||
        old.viewport.inspectStartElapsed != viewport.inspectStartElapsed ||
        old.connected != connected ||
        old.series != series;
  }
}
