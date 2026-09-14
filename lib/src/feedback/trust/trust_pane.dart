import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/dashed_polyline.dart';
import 'package:muse_ml/src/charts/smooth_path.dart';
import 'package:muse_ml/src/feedback/trust/trust_inhibit.dart';
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
    this.inhibitWash = kTrustInhibitWash,
  });

  final List<TrustRewardSample> samples;
  final List<TrustGestureMark> marks;
  final TrustViewport viewport;
  final double newestElapsed;
  final double wallNow;
  final String label;
  final Color seriesColor;
  final bool inhibitWash;

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
          inhibitWash: inhibitWash,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class InhibitTrustPane extends StatelessWidget {
  const InhibitTrustPane({
    super.key,
    required this.samples,
    required this.marks,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.specs,
  });

  final List<TrustRewardSample> samples;
  final List<TrustGestureMark> marks;
  final TrustViewport viewport;
  final double newestElapsed;
  final double wallNow;
  final List<TrustInhibitSpec> specs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: InhibitTrustPainter(
          samples: samples,
          marks: marks,
          visStart: viewport.visibleStart(newestElapsed, wallNow: wallNow),
          visEnd: viewport.visibleEnd(newestElapsed, wallNow: wallNow),
          windowSeconds: viewport.windowSeconds,
          specs: specs,
          axisColor: theme.colorScheme.onSurfaceVariant,
          onSurface: theme.colorScheme.onSurface,
          errorColor: theme.colorScheme.error,
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

void _paintHLine(
  Canvas canvas,
  Rect plot,
  double y, {
  required Color color,
  double alpha = 0.55,
  double strokeWidth = 1,
}) {
  canvas.drawLine(
    Offset(plot.left, y),
    Offset(plot.right, y),
    Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = strokeWidth,
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
    this.inhibitWash = kTrustInhibitWash,
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
  final bool inhibitWash;

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
    if (inhibitWash) {
      final wash = Paint()..color = onSurface.withValues(alpha: 0.10);
      for (final spanT in inhibitWashSpans(vis, visEnd: visEnd)) {
        final left = _x(spanT.tStart, plot, visStart, span);
        final right = _x(spanT.tEnd, plot, visStart, span);
        canvas.drawRect(
          Rect.fromLTRB(
            math.max(left, plot.left),
            plot.top,
            math.min(right, plot.right),
            plot.bottom,
          ),
          wash,
        );
      }
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

    final runs = rewardRuns(vis);
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
      _paintRunStroke(
        canvas,
        pts,
        color: seriesColor,
        dashed: run.kind == TrustStrokeKind.dirty,
      );
      if (run.kind == TrustStrokeKind.dirty) {
        final tag = rewardRunLabel(run);
        if (tag != null) {
          _paintText(
            canvas,
            tag,
            Offset(_x(run.tStart, plot, visStart, span) + 2, plot.top + 2),
            seriesColor,
            10,
          );
        }
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
      old.inhibitWash != inhibitWash;
}

class InhibitTrustPainter extends CustomPainter {
  InhibitTrustPainter({
    required this.samples,
    required this.marks,
    required this.visStart,
    required this.visEnd,
    required this.windowSeconds,
    required this.specs,
    required this.axisColor,
    required this.onSurface,
    required this.errorColor,
  });

  final List<TrustRewardSample> samples;
  final List<TrustGestureMark> marks;
  final double visStart;
  final double visEnd;
  final double windowSeconds;
  final List<TrustInhibitSpec> specs;
  final Color axisColor;
  final Color onSurface;
  final Color errorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _chartRect(size);
    if (plot.width <= 0 || plot.height <= 0) return;
    final span = visEnd - visStart;
    if (span <= 0 || specs.isEmpty) return;
    const yMin = 0.0;
    final yMax = inhibitAxisMax(specs);
    _paintHeader(
      canvas,
      size,
      left: inhibitPaneLabel(specs),
      right: 'inhibit',
      color: axisColor,
    );
    _paintText(
      canvas,
      yMax >= 1 ? '1.0' : yMax.toStringAsFixed(2),
      Offset(0, _y(yMax, plot, yMin, yMax) - 6),
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

    final byCeiling = [...specs]
      ..sort((a, b) => b.ceiling.compareTo(a.ceiling));
    for (final spec in byCeiling) {
      final top = _y(spec.ceiling.clamp(yMin, yMax), plot, yMin, yMax);
      canvas.drawRect(
        Rect.fromLTRB(plot.left, top, plot.right, plot.bottom),
        Paint()..color = inhibitSeriesColor(spec.id).withValues(alpha: 0.08),
      );
    }

    for (final spec in specs) {
      final series = inhibitSeriesColor(spec.id);
      final y = _y(spec.ceiling.clamp(yMin, yMax), plot, yMin, yMax);
      _paintHLine(canvas, plot, y, color: series, alpha: 0.9, strokeWidth: 1.2);
      _paintText(
        canvas,
        spec.ceiling.toStringAsFixed(2),
        Offset(plot.left + 2, y - 12),
        series,
        9,
      );
    }

    final queued = <_InhibitStroke>[];
    for (final spec in specs) {
      final series = inhibitSeriesColor(spec.id);
      final overshoot = inhibitOvershootColor(spec.id, errorColor);
      final runs = inhibitRuns(vis, spec);
      for (var i = 0; i < runs.length; i++) {
        queued.add(
          _InhibitStroke(
            spec: spec,
            run: runs[i],
            next: i + 1 < runs.length ? runs[i + 1].samples.first : null,
            color: inhibitRunColor(
              runs[i].kind,
              series: series,
              overshoot: overshoot,
            ),
          ),
        );
      }
    }
    for (final stroke in queued) {
      if (stroke.run.kind == TrustInhibitKind.overshoot) continue;
      _paintInhibitRun(
        canvas,
        plot,
        run: stroke.run,
        next: stroke.next,
        spec: stroke.spec,
        visStart: visStart,
        span: span,
        yMin: yMin,
        yMax: yMax,
        color: stroke.color,
        dashed: stroke.run.kind == TrustInhibitKind.dirty,
      );
    }
    var overshootLabelSlot = 0;
    for (final stroke in queued) {
      if (stroke.run.kind != TrustInhibitKind.overshoot) continue;
      _paintInhibitRun(
        canvas,
        plot,
        run: stroke.run,
        next: stroke.next,
        spec: stroke.spec,
        visStart: visStart,
        span: span,
        yMin: yMin,
        yMax: yMax,
        color: stroke.color,
        dashed: false,
      );
      _paintText(
        canvas,
        stroke.spec.overshootLabel,
        Offset(
          _x(stroke.run.tStart, plot, visStart, span) + 2,
          plot.top + 2 + overshootLabelSlot * 12,
        ),
        stroke.color,
        10,
      );
      overshootLabelSlot++;
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
  bool shouldRepaint(covariant InhibitTrustPainter old) =>
      old.samples.length != samples.length ||
      old.samples != samples ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.t != samples.last.t) ||
      old.marks != marks ||
      old.visStart != visStart ||
      old.visEnd != visEnd ||
      old.windowSeconds != windowSeconds ||
      old.specs != specs ||
      old.errorColor != errorColor;
}

class _InhibitStroke {
  const _InhibitStroke({
    required this.spec,
    required this.run,
    required this.next,
    required this.color,
  });

  final TrustInhibitSpec spec;
  final TrustInhibitRun run;
  final TrustRewardSample? next;
  final Color color;
}

void _paintInhibitRun(
  Canvas canvas,
  Rect plot, {
  required TrustInhibitRun run,
  required TrustRewardSample? next,
  required TrustInhibitSpec spec,
  required double visStart,
  required double span,
  required double yMin,
  required double yMax,
  required Color color,
  required bool dashed,
}) {
  final stroke = runStrokeSamples(run.samples, next);
  final pts = <Offset>[];
  for (final s in stroke) {
    final y = inhibitPlotY(s, spec);
    if (y == null) continue;
    pts.add(
      Offset(
        _x(s.t, plot, visStart, span),
        _y(y.clamp(yMin, yMax), plot, yMin, yMax),
      ),
    );
  }
  _paintRunStroke(canvas, pts, color: color, dashed: dashed);
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
