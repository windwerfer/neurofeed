import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/dashed_polyline.dart';
import 'package:muse_ml/src/charts/smooth_path.dart';
import 'package:muse_ml/src/feedback/trust/trust_runs.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';
import 'package:muse_ml/src/feedback/trust/trust_viewport.dart';

const double kTrustYGutter = 28;
const double kTrustXGutter = 16;
const double kTrustTopGutter = 18;

class RewardTrustPane extends StatelessWidget {
  const RewardTrustPane({
    super.key,
    required this.samples,
    required this.marks,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.label,
    required this.seriesColor,
    this.heldBackFill = kTrustHeldBackFill,
  });

  final List<TrustRewardSample> samples;
  final List<TrustGestureMark> marks;
  final TrustViewport viewport;
  final double newestElapsed;
  final double wallNow;
  final String label;
  final Color seriesColor;
  final bool heldBackFill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: RewardTrustPainter(
          samples: samples,
          marks: marks,
          visStart: viewport.visibleStart(newestElapsed, wallNow: wallNow),
          visEnd: viewport.visibleEnd(newestElapsed, wallNow: wallNow),
          windowSeconds: viewport.windowSeconds,
          label: label,
          seriesColor: seriesColor,
          axisColor: theme.colorScheme.onSurfaceVariant,
          onSurface: theme.colorScheme.onSurface,
          heldBackFill: heldBackFill,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class GuardWarnPane extends StatelessWidget {
  const GuardWarnPane({
    super.key,
    required this.samples,
    required this.marks,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.label,
    required this.seriesColor,
  });

  final List<TrustGuardSample> samples;
  final List<TrustGestureMark> marks;
  final TrustViewport viewport;
  final double newestElapsed;
  final double wallNow;
  final String label;
  final Color seriesColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: GuardWarnPainter(
          samples: samples,
          marks: marks,
          visStart: viewport.visibleStart(newestElapsed, wallNow: wallNow),
          visEnd: viewport.visibleEnd(newestElapsed, wallNow: wallNow),
          windowSeconds: viewport.windowSeconds,
          label: label,
          seriesColor: seriesColor,
          axisColor: theme.colorScheme.onSurfaceVariant,
          onSurface: theme.colorScheme.onSurface,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class GuardCeilingPane extends StatelessWidget {
  const GuardCeilingPane({
    super.key,
    required this.samples,
    required this.marks,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.seriesColor,
    required this.ceiling,
  });

  final List<TrustGuardSample> samples;
  final List<TrustGestureMark> marks;
  final TrustViewport viewport;
  final double newestElapsed;
  final double wallNow;
  final Color seriesColor;
  final double ceiling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = samples.isEmpty ? 0.0 : samples.last.lastDelta;
    return RepaintBoundary(
      child: CustomPaint(
        painter: GuardCeilingPainter(
          samples: samples,
          marks: marks,
          visStart: viewport.visibleStart(newestElapsed, wallNow: wallNow),
          visEnd: viewport.visibleEnd(newestElapsed, wallNow: wallNow),
          windowSeconds: viewport.windowSeconds,
          seriesColor: seriesColor,
          axisColor: theme.colorScheme.onSurfaceVariant,
          onSurface: theme.colorScheme.onSurface,
          ceiling: ceiling,
          liveDelta: live,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

Rect _chartRect(Size size) => Rect.fromLTWH(
  kTrustYGutter,
  kTrustTopGutter,
  (size.width - kTrustYGutter - 8).clamp(8, double.infinity),
  (size.height - kTrustTopGutter - kTrustXGutter).clamp(8, double.infinity),
);

double _x(double t, Rect plot, double visStart, double span) =>
    plot.left + ((t - visStart) / span) * plot.width;

double _y(double v, Rect plot, double yMin, double yMax) {
  final span = yMax - yMin;
  if (span <= 0) return plot.bottom;
  return plot.bottom - ((v - yMin) / span) * plot.height;
}

void _paintMarks(
  Canvas canvas,
  Rect plot, {
  required List<TrustGestureMark> marks,
  required double visStart,
  required double span,
  required Color color,
}) {
  final paint = Paint()
    ..color = color.withValues(alpha: 0.45)
    ..strokeWidth = 1;
  for (final m in marks) {
    if (m.label.isEmpty) continue;
    if (m.t < visStart || m.t > visStart + span) continue;
    final x = _x(m.t, plot, visStart, span);
    canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), paint);
    _paintText(
      canvas,
      m.label,
      Offset(x + 2, plot.bottom - 12),
      color.withValues(alpha: 0.7),
      10,
    );
  }
}

void _paintText(
  Canvas canvas,
  String text,
  Offset at,
  Color color,
  double size,
) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}

void _paintHeader(
  Canvas canvas,
  Size size, {
  required String left,
  required String right,
  required Color color,
}) {
  _paintText(canvas, left, const Offset(4, 2), color, 11);
  final tp = TextPainter(
    text: TextSpan(
      text: right,
      style: TextStyle(color: color, fontSize: 11),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(size.width - tp.width - 4, 2));
}

void _paintHLine(Canvas canvas, Rect plot, double y, {required Color color}) {
  canvas.drawLine(
    Offset(plot.left, y),
    Offset(plot.right, y),
    Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1,
  );
}

class RewardTrustPainter extends CustomPainter {
  RewardTrustPainter({
    required this.samples,
    required this.marks,
    required this.visStart,
    required this.visEnd,
    required this.windowSeconds,
    required this.label,
    required this.seriesColor,
    required this.axisColor,
    required this.onSurface,
    this.heldBackFill = kTrustHeldBackFill,
  });

  final List<TrustRewardSample> samples;
  final List<TrustGestureMark> marks;
  final double visStart;
  final double visEnd;
  final double windowSeconds;
  final String label;
  final Color seriesColor;
  final Color axisColor;
  final Color onSurface;
  final bool heldBackFill;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _chartRect(size);
    if (plot.width <= 0 || plot.height <= 0) return;
    final span = visEnd - visStart;
    if (span <= 0) return;
    const yMin = 0.0;
    const yMax = 100.0;
    _paintHeader(
      canvas,
      size,
      left: label,
      right: '${windowSeconds.round()}s',
      color: axisColor,
    );
    _paintText(
      canvas,
      '100',
      Offset(2, _y(100, plot, yMin, yMax) - 6),
      axisColor,
      9,
    );
    _paintText(
      canvas,
      '0',
      Offset(2, _y(0, plot, yMin, yMax) - 6),
      axisColor,
      9,
    );

    canvas.save();
    canvas.clipRect(plot);

    final vis = [
      for (final s in samples)
        if (s.t >= visStart - 1 && s.t <= visEnd + 1) s,
    ];
    final runs = rewardRuns(vis);
    final gray = onSurface.withValues(alpha: 0.45);
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      if (!shouldPaintHeldBackFill(gate: heldBackFill, kind: run.kind)) {
        continue;
      }
      final nextT = i + 1 < runs.length ? runs[i + 1].tStart : null;
      final rightT = heldBackFillEnd(
        tEnd: run.tEnd,
        nextT: nextT,
        visEnd: visEnd,
      );
      final left = _x(run.tStart, plot, visStart, span);
      final right = _x(rightT, plot, visStart, span);
      canvas.drawRect(
        Rect.fromLTRB(
          math.max(left, plot.left),
          plot.top,
          math.min(right, plot.right),
          plot.bottom,
        ),
        Paint()..color = onSurface.withValues(alpha: 0.10),
      );
    }

    final thr = vis.isEmpty ? 40.0 : vis.last.thresholdPercentile;
    _paintHLine(canvas, plot, _y(thr, plot, yMin, yMax), color: axisColor);
    _paintText(
      canvas,
      thr.round().toString(),
      Offset(2, _y(thr, plot, yMin, yMax) - 6),
      axisColor,
      9,
    );

    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final next = i + 1 < runs.length ? runs[i + 1].samples.first : null;
      final stroke = runStrokeSamples(run.samples, next);
      final pts = [
        for (final s in stroke)
          Offset(
            _x(s.t, plot, visStart, span),
            _y(s.plotPercentile ?? s.percentile, plot, yMin, yMax),
          ),
      ];
      final color = run.kind == TrustStrokeKind.heldBack ? gray : seriesColor;
      _paintRunStroke(
        canvas,
        pts,
        color: color,
        dashed: run.kind == TrustStrokeKind.dirty,
      );
      final tag = rewardRunLabel(run);
      if (tag != null) {
        _paintText(
          canvas,
          tag,
          Offset(_x(run.tStart, plot, visStart, span) + 2, plot.top + 2),
          color,
          10,
        );
      }
    }

    _paintMarks(
      canvas,
      plot,
      marks: marks,
      visStart: visStart,
      span: span,
      color: onSurface,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RewardTrustPainter old) =>
      old.samples.length != samples.length ||
      old.samples != samples ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.t != samples.last.t) ||
      old.marks != marks ||
      old.visStart != visStart ||
      old.visEnd != visEnd ||
      old.windowSeconds != windowSeconds ||
      old.label != label ||
      old.seriesColor != seriesColor ||
      old.heldBackFill != heldBackFill;
}

class GuardWarnPainter extends CustomPainter {
  GuardWarnPainter({
    required this.samples,
    required this.marks,
    required this.visStart,
    required this.visEnd,
    required this.windowSeconds,
    required this.label,
    required this.seriesColor,
    required this.axisColor,
    required this.onSurface,
  });

  final List<TrustGuardSample> samples;
  final List<TrustGestureMark> marks;
  final double visStart;
  final double visEnd;
  final double windowSeconds;
  final String label;
  final Color seriesColor;
  final Color axisColor;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _chartRect(size);
    if (plot.width <= 0 || plot.height <= 0) return;
    final span = visEnd - visStart;
    if (span <= 0) return;
    _paintHeader(canvas, size, left: label, right: 'warn', color: axisColor);
    const yMin = 0.0;
    const yMax = 100.0;
    canvas.save();
    canvas.clipRect(plot);
    _paintHLine(canvas, plot, _y(75, plot, yMin, yMax), color: axisColor);
    _paintGuardSeries(
      canvas,
      plot,
      samples: samples,
      visStart: visStart,
      span: visEnd - visStart,
      yOf: (s) =>
          (s.plotFeaturePercentile ?? s.featurePercentile).clamp(0, 100),
      yMin: yMin,
      yMax: yMax,
      seriesColor: seriesColor,
    );
    _paintMarks(
      canvas,
      plot,
      marks: marks,
      visStart: visStart,
      span: span,
      color: onSurface,
    );
    canvas.restore();
    _paintText(canvas, '100', Offset(2, plot.top - 6), axisColor, 9);
    _paintText(canvas, '0', Offset(2, plot.bottom - 6), axisColor, 9);
  }

  @override
  bool shouldRepaint(covariant GuardWarnPainter old) =>
      old.samples.length != samples.length ||
      old.samples != samples ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.t != samples.last.t) ||
      old.marks != marks ||
      old.visStart != visStart ||
      old.visEnd != visEnd ||
      old.label != label ||
      old.seriesColor != seriesColor;
}

class GuardCeilingPainter extends CustomPainter {
  GuardCeilingPainter({
    required this.samples,
    required this.marks,
    required this.visStart,
    required this.visEnd,
    required this.windowSeconds,
    required this.seriesColor,
    required this.axisColor,
    required this.onSurface,
    required this.ceiling,
    required this.liveDelta,
  });

  final List<TrustGuardSample> samples;
  final List<TrustGestureMark> marks;
  final double visStart;
  final double visEnd;
  final double windowSeconds;
  final Color seriesColor;
  final Color axisColor;
  final Color onSurface;
  final double ceiling;
  final double liveDelta;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _chartRect(size);
    if (plot.width <= 0 || plot.height <= 0) return;
    final span = visEnd - visStart;
    if (span <= 0) return;
    final over = liveDelta > 0.5;
    _paintHeader(
      canvas,
      size,
      left: 'δ ceiling',
      right: over ? liveDelta.toStringAsFixed(2) : ceiling.toStringAsFixed(2),
      color: axisColor,
    );
    const yMin = 0.0;
    const yMax = 0.5;
    canvas.save();
    canvas.clipRect(plot);
    _paintHLine(canvas, plot, _y(ceiling, plot, yMin, yMax), color: axisColor);
    _paintGuardSeries(
      canvas,
      plot,
      samples: samples,
      visStart: visStart,
      span: span,
      yOf: (s) => (s.plotDelta ?? s.lastDelta).clamp(0.0, 0.5),
      yMin: yMin,
      yMax: yMax,
      seriesColor: seriesColor,
    );
    _paintMarks(
      canvas,
      plot,
      marks: marks,
      visStart: visStart,
      span: span,
      color: onSurface,
    );
    canvas.restore();
    _paintText(canvas, '0.50', Offset(0, plot.top - 6), axisColor, 9);
    _paintText(canvas, '0.00', Offset(0, plot.bottom - 6), axisColor, 9);
  }

  @override
  bool shouldRepaint(covariant GuardCeilingPainter old) =>
      old.samples.length != samples.length ||
      old.samples != samples ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.t != samples.last.t) ||
      old.marks != marks ||
      old.visStart != visStart ||
      old.visEnd != visEnd ||
      old.liveDelta != liveDelta ||
      old.ceiling != ceiling;
}

void _paintRunStroke(
  Canvas canvas,
  List<Offset> pts, {
  required Color color,
  required bool dashed,
}) {
  if (pts.isEmpty) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.6
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  if (dashed) {
    paintDashedPolyline(canvas, pts, paint);
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, 1.5, paint..style = PaintingStyle.fill);
    }
    return;
  }
  if (pts.length == 1) {
    canvas.drawCircle(pts.first, 1.5, paint..style = PaintingStyle.fill);
    return;
  }
  final path = Path();
  buildSmoothPath(path, pts);
  canvas.drawPath(path, paint);
}

void _paintGuardSeries(
  Canvas canvas,
  Rect plot, {
  required List<TrustGuardSample> samples,
  required double visStart,
  required double span,
  required double Function(TrustGuardSample) yOf,
  required double yMin,
  required double yMax,
  required Color seriesColor,
}) {
  final vis = [
    for (final s in samples)
      if (s.t >= visStart - 1 && s.t <= visStart + span + 1) s,
  ];
  if (vis.isEmpty) return;
  var dirty = !vis.first.clean;
  var buf = <TrustGuardSample>[vis.first];
  void flush(bool asDirty, TrustGuardSample? next) {
    final stroke = runStrokeSamples(buf, next);
    final pts = [
      for (final s in stroke)
        Offset(_x(s.t, plot, visStart, span), _y(yOf(s), plot, yMin, yMax)),
    ];
    _paintRunStroke(canvas, pts, color: seriesColor, dashed: asDirty);
  }

  for (var i = 1; i < vis.length; i++) {
    final d = !vis[i].clean;
    if (d == dirty) {
      buf.add(vis[i]);
    } else {
      flush(dirty, vis[i]);
      dirty = d;
      buf = [vis[i]];
    }
  }
  flush(dirty, null);
}
