import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/monitor/dsp.dart';

class PsdPane extends StatelessWidget {
  const PsdPane({
    super.key,
    required this.spectrum,
    required this.maxHz,
    required this.connected,
    this.peakHz,
    this.hairlineHz,
    this.onTapHz,
  });

  final Spectrum? spectrum;
  final double maxHz;
  final bool connected;
  final double? peakHz;
  final double? hairlineHz;
  final ValueChanged<double>? onTapHz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTapHz == null
            ? null
            : (d) {
                final size = context.size;
                if (size == null) return;
                onTapHz!(
                  PsdPanePainter.hzForX(d.localPosition.dx, size, maxHz),
                );
              },
        child: CustomPaint(
          painter: PsdPanePainter(
            spectrum: spectrum,
            maxHz: maxHz,
            connected: connected,
            peakHz: peakHz,
            hairlineHz: hairlineHz,
            axisColor: theme.colorScheme.onSurfaceVariant,
            gridColor: theme.colorScheme.outlineVariant,
            lineColor: theme.colorScheme.onSurface,
            hairlineColor: theme.colorScheme.onSurface,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class PsdPanePainter extends CustomPainter {
  PsdPanePainter({
    required this.spectrum,
    required this.maxHz,
    required this.connected,
    required this.peakHz,
    required this.hairlineHz,
    required this.axisColor,
    required this.gridColor,
    required this.lineColor,
    required this.hairlineColor,
  });

  static const double yGutter = 44;
  static const double xGutter = 22;
  static const double topGutter = 22;
  static const double rightGutter = 12;

  static const List<(double lo, double hi)> bandEdges = [
    (kBandDeltaLoHz, kBandDeltaHiHz),
    (kBandThetaLoHz, kBandThetaHiHz),
    (kBandAlphaLoHz, kBandAlphaHiHz),
    (kBandBetaLoHz, kBandBetaHiHz),
    (kBandGammaLoHz, kBandGammaHiHz),
  ];

  final Spectrum? spectrum;
  final double maxHz;
  final bool connected;
  final double? peakHz;
  final double? hairlineHz;
  final Color axisColor;
  final Color gridColor;
  final Color lineColor;
  final Color hairlineColor;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    yGutter,
    topGutter,
    (size.width - yGutter - rightGutter).clamp(8, double.infinity),
    (size.height - topGutter - xGutter).clamp(8, double.infinity),
  );

  static double hzForX(double x, Size size, double maxHz) {
    final chart = chartRect(size);
    if (chart.width <= 0) return 0;
    final t = ((x - chart.left) / chart.width).clamp(0.0, 1.0);
    return t * maxHz;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chart = chartRect(size);
    if (chart.width <= 0 || chart.height <= 0 || maxHz <= 0) return;
    final spec = spectrum;
    var yMin = -40.0;
    var yMax = 10.0;
    if (connected && spec != null) {
      final range = _visibleDb(spec);
      if (range != null) {
        yMin = range.$1;
        yMax = range.$2;
      }
    }
    final ySpan = yMax - yMin;
    if (ySpan <= 0) return;

    _drawBandShading(canvas, chart);
    _drawGrid(canvas, chart, yMin, yMax);
    if (connected && spec != null) {
      _drawSpectrum(canvas, chart, spec, yMin, ySpan);
      final peak = peakHz;
      if (peak != null) {
        _drawPeak(canvas, chart, spec, peak, yMin, ySpan);
      }
    }
    _drawYLabels(canvas, chart, yMin, yMax);
    _drawXLabels(canvas, chart);
    final hz = hairlineHz;
    if (hz != null && connected && spec != null) {
      _drawHairline(canvas, chart, spec, hz, yMin, ySpan);
    }
  }

  (double, double)? _visibleDb(Spectrum spec) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    final last = math.min(
      spec.power.length - 1,
      freqBin(maxHz, spec.n, sampleRate: spec.sampleRate),
    );
    for (var k = 1; k <= last; k++) {
      final db = powerToDb(spec.power[k]);
      if (db < lo) lo = db;
      if (db > hi) hi = db;
    }
    if (lo.isInfinite) return null;
    final pad = (hi - lo) > 0 ? (hi - lo) * 0.15 : 1.0;
    return (lo - pad, hi + pad);
  }

  void _drawBandShading(Canvas canvas, Rect chart) {
    for (var i = 0; i < bandEdges.length && i < bandColors.length; i++) {
      final lo = bandEdges[i].$1;
      final hi = bandEdges[i].$2;
      final x0 = chart.left + (lo / maxHz).clamp(0.0, 1.0) * chart.width;
      final x1 = chart.left + (hi / maxHz).clamp(0.0, 1.0) * chart.width;
      if (x1 <= x0) continue;
      canvas.drawRect(
        Rect.fromLTRB(x0, chart.top, x1, chart.bottom),
        Paint()..color = bandColors[i].withValues(alpha: 0.16),
      );
    }
  }

  void _drawGrid(Canvas canvas, Rect chart, double yMin, double yMax) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    if (yMin <= 0 && yMax >= 0) {
      final y = chart.top + (yMax - 0) / (yMax - yMin) * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
    }
    const ticks = [0.0, 4.0, 8.0, 13.0, 30.0, 50.0, 60.0, 100.0];
    for (final hz in ticks) {
      if (hz < 0 || hz > maxHz) continue;
      final x = chart.left + hz / maxHz * chart.width;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
    }
  }

  void _drawSpectrum(
    Canvas canvas,
    Rect chart,
    Spectrum spec,
    double yMin,
    double ySpan,
  ) {
    final last = math.min(
      spec.power.length - 1,
      freqBin(maxHz, spec.n, sampleRate: spec.sampleRate),
    );
    if (last < 1) return;
    final path = Path();
    var started = false;
    for (var k = 0; k <= last; k++) {
      final hz = spec.freqAt(k);
      if (hz > maxHz) break;
      final x = chart.left + hz / maxHz * chart.width;
      final db = powerToDb(spec.power[k]);
      final y = chart.top + (yMin + ySpan - db) / ySpan * chart.height;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (!started) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _drawPeak(
    Canvas canvas,
    Rect chart,
    Spectrum spec,
    double peak,
    double yMin,
    double ySpan,
  ) {
    if (peak < 0 || peak > maxHz) return;
    final k = freqBin(
      peak,
      spec.n,
      sampleRate: spec.sampleRate,
    ).clamp(0, spec.power.length - 1);
    final db = powerToDb(spec.power[k]);
    final x = chart.left + peak / maxHz * chart.width;
    final y = chart.top + (yMin + ySpan - db) / ySpan * chart.height;
    canvas.drawCircle(Offset(x, y), 3, Paint()..color = bandColors[2]);
    final tp = TextPainter(
      text: TextSpan(
        text: '${peak.toStringAsFixed(1)} Hz',
        style: TextStyle(color: bandColors[2], fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = x + 6;
    if (dx + tp.width > chart.right) dx = x - tp.width - 6;
    tp.paint(canvas, Offset(dx, y - tp.height - 2));
  }

  void _drawYLabels(Canvas canvas, Rect chart, double yMin, double yMax) {
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
    final range = yMax - yMin;
    final ideal = (chart.height / 40).clamp(2, 8);
    final rough = range / ideal;
    final exp = math
        .pow(10, (math.log(rough.abs()) / math.ln10).floor())
        .toDouble();
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
    if (step <= 0) return;
    final first = (yMin / step).ceil() * step;
    for (var v = first; v <= yMax + 1e-9; v += step) {
      final py = chart.top + (yMax - v) / range * chart.height;
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

  void _drawXLabels(Canvas canvas, Rect chart) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final ticks = <double>[0, 4, 8, 13, 30, 50];
    if (maxHz >= 60) ticks.add(60);
    if (maxHz >= 100) ticks.add(100);
    for (final hz in ticks) {
      if (hz > maxHz) continue;
      final x = chart.left + hz / maxHz * chart.width;
      final tp = TextPainter(
        text: TextSpan(
          text: hz == 0 ? '0' : hz.round().toString(),
          style: style,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = x - tp.width / 2;
      if (dx < chart.left) dx = chart.left;
      if (dx + tp.width > chart.right) dx = chart.right - tp.width;
      tp.paint(canvas, Offset(dx, chart.bottom + 4));
    }
    final unit = TextPainter(
      text: TextSpan(text: 'Hz', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    unit.paint(
      canvas,
      Offset(chart.right - unit.width, chart.bottom + xGutter - unit.height),
    );
  }

  void _drawHairline(
    Canvas canvas,
    Rect chart,
    Spectrum spec,
    double hz,
    double yMin,
    double ySpan,
  ) {
    final clamped = hz.clamp(0.0, maxHz);
    final x = chart.left + clamped / maxHz * chart.width;
    canvas.drawLine(
      Offset(x, chart.top),
      Offset(x, chart.bottom),
      Paint()
        ..color = hairlineColor
        ..strokeWidth = 1,
    );
    final k = freqBin(
      clamped,
      spec.n,
      sampleRate: spec.sampleRate,
    ).clamp(0, spec.power.length - 1);
    final db = powerToDb(spec.power[k]);
    final label =
        '${clamped.toStringAsFixed(1)} Hz   ${db.toStringAsFixed(1)} dB';
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
  bool shouldRepaint(covariant PsdPanePainter old) {
    return old.spectrum != spectrum ||
        old.maxHz != maxHz ||
        old.connected != connected ||
        old.peakHz != peakHz ||
        old.hairlineHz != hairlineHz;
  }
}
