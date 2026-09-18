import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/charts/smooth_path.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

const Color kHrColor = Color(0xFFEC407A);
const Color kSpo2Color = Color(0xFF26C6DA);

const double kHrYMin = 40;
const double kHrYMax = 200;
const double kSpo2YMin = 50;
const double kSpo2YMax = 100;

class OpticalOverviewPane extends StatefulWidget {
  const OpticalOverviewPane({
    super.key,
    required this.hr,
    required this.spo2,
    required this.viewport,
    required this.newestElapsed,
    required this.connected,
    this.avgHr,
    this.highlightStartElapsed,
    this.highlightEndElapsed,
    this.cursorElapsed,
    this.onTapElapsed,
  });

  final List<ChartSample> hr;
  final List<ChartSample> spo2;
  final ViewportController viewport;
  final double newestElapsed;
  final bool connected;
  final double? avgHr;
  final double? highlightStartElapsed;
  final double? highlightEndElapsed;
  final double? cursorElapsed;
  final ValueChanged<double?>? onTapElapsed;

  @override
  State<OpticalOverviewPane> createState() => _OpticalOverviewPaneState();
}

class _OpticalOverviewPaneState extends State<OpticalOverviewPane>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    widget.viewport.addListener(_onViewport);
    _maybeNoteSample();
    _syncTicker();
  }

  @override
  void didUpdateWidget(OpticalOverviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.removeListener(_onViewport);
      widget.viewport.addListener(_onViewport);
    }
    _maybeNoteSample();
    _syncTicker();
  }

  @override
  void dispose() {
    widget.viewport.removeListener(_onViewport);
    _ticker?.dispose();
    super.dispose();
  }

  void _onViewport() {
    _syncTicker();
    if (mounted) setState(() {});
  }

  bool get _hasSamples => widget.hr.isNotEmpty || widget.spo2.isNotEmpty;

  void _maybeNoteSample() {
    if (!widget.connected || !_hasSamples) {
      if (!widget.connected) widget.viewport.resetFollowAnchors();
      return;
    }
    widget.viewport.noteStripSample(widget.newestElapsed);
  }

  void _syncTicker() {
    final run =
        widget.connected &&
        widget.viewport.mode == ViewportMode.follow &&
        widget.viewport.followLeadSeconds > 0;
    final ticker = _ticker;
    if (ticker == null) return;
    if (run) {
      if (!ticker.isActive) ticker.start();
    } else if (ticker.isActive) {
      ticker.stop();
    }
  }

  void _onTapDown(TapDownDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final chart = OpticalOverviewPainter.chartRect(size);
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final visStart = widget.viewport.stripVisibleStart(
      newestElapsed: widget.newestElapsed,
      wallNow: wallNow,
    );
    final visEnd = widget.viewport.stripVisibleEnd(
      newestElapsed: widget.newestElapsed,
      wallNow: wallNow,
    );
    final span = visEnd - visStart;
    if (span <= 0 || chart.width <= 0) return;
    final x = d.localPosition.dx;
    if (x < chart.left || x > chart.right) {
      widget.onTapElapsed?.call(null);
      return;
    }
    final elapsed = visStart + (x - chart.left) / chart.width * span;
    widget.onTapElapsed?.call(elapsed.clamp(visStart, visEnd));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: OpticalOverviewPainter(
            hr: widget.hr,
            spo2: widget.spo2,
            viewport: widget.viewport,
            newestElapsed: widget.newestElapsed,
            wallNow: wallNow,
            connected: widget.connected,
            avgHr: widget.avgHr,
            highlightStartElapsed: widget.highlightStartElapsed,
            highlightEndElapsed: widget.highlightEndElapsed,
            cursorElapsed: widget.cursorElapsed,
            axisColor: theme.colorScheme.onSurfaceVariant,
            gridColor: theme.colorScheme.outlineVariant,
            highlightColor: theme.colorScheme.primary,
            onSurface: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class OpticalOverviewPainter extends CustomPainter {
  OpticalOverviewPainter({
    required this.hr,
    required this.spo2,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.connected,
    required this.axisColor,
    required this.gridColor,
    required this.highlightColor,
    required this.onSurface,
    this.avgHr,
    this.highlightStartElapsed,
    this.highlightEndElapsed,
    this.cursorElapsed,
  });

  static const double leftGutter = 36;
  static const double rightGutter = 36;
  static const double xGutter = 22;
  static const double topGutter = 28;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    leftGutter,
    topGutter,
    (size.width - leftGutter - rightGutter).clamp(8, double.infinity),
    (size.height - topGutter - xGutter).clamp(8, double.infinity),
  );

  final List<ChartSample> hr;
  final List<ChartSample> spo2;
  final ViewportController viewport;
  final double newestElapsed;
  final double wallNow;
  final bool connected;
  final double? avgHr;
  final double? highlightStartElapsed;
  final double? highlightEndElapsed;
  final double? cursorElapsed;
  final Color axisColor;
  final Color gridColor;
  final Color highlightColor;
  final Color onSurface;

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
    _drawHighlight(canvas, chart, visStart, visEnd);
    if (connected) {
      _drawSeries(canvas, chart, hr, kHrColor, visStart, span, kHrYMin, kHrYMax);
      _drawSeries(
        canvas,
        chart,
        spo2,
        kSpo2Color,
        visStart,
        span,
        kSpo2YMin,
        kSpo2YMax,
      );
      _drawAvgHr(canvas, chart);
    }
    _drawCursor(canvas, chart, visStart, span);
    canvas.restore();
    _drawYLabels(canvas, chart);
    _drawXLabels(canvas, chart, visStart, visEnd);
    _drawCursorReadout(canvas, chart, visStart, span);
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

  void _drawHighlight(
    Canvas canvas,
    Rect chart,
    double visStart,
    double visEnd,
  ) {
    final start = highlightStartElapsed;
    final end = highlightEndElapsed;
    if (start == null || end == null) return;
    final frac = highlightFractions(
      visStart: visStart,
      visEnd: visEnd,
      highlightStart: start,
      highlightEnd: end,
    );
    if (frac == null) return;
    final x0 = chart.left + frac.$1 * chart.width;
    final x1 = chart.left + frac.$2 * chart.width;
    final rect = Rect.fromLTRB(x0, chart.top, x1, chart.bottom);
    canvas.drawRect(
      rect,
      Paint()..color = highlightColor.withValues(alpha: 0.18),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = highlightColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawSeries(
    Canvas canvas,
    Rect chart,
    List<ChartSample> samples,
    Color color,
    double visStart,
    double span,
    double yMin,
    double yMax,
  ) {
    if (samples.length < 2) return;
    final ySpan = yMax - yMin;
    if (ySpan <= 0) return;
    final pts = <Offset>[];
    for (final s in samples) {
      final x = chart.left + (s.t - visStart) / span * chart.width;
      final y = chart.bottom - ((s.v - yMin) / ySpan) * chart.height;
      pts.add(Offset(x, y));
    }
    final path = Path();
    buildSmoothPath(path, pts);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _drawAvgHr(Canvas canvas, Rect chart) {
    final avg = avgHr;
    if (avg == null || !avg.isFinite) return;
    if (avg < kHrYMin || avg > kHrYMax) return;
    final y =
        chart.bottom - ((avg - kHrYMin) / (kHrYMax - kHrYMin)) * chart.height;
    final paint = Paint()
      ..color = kHrColor.withValues(alpha: 0.85)
      ..strokeWidth = 0.9;
    const dash = 8.0;
    const gap = 4.0;
    var x = chart.left;
    while (x < chart.right) {
      final x1 = math.min(x + dash, chart.right);
      canvas.drawLine(Offset(x, y), Offset(x1, y), paint);
      x += dash + gap;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: 'avg HR',
        style: TextStyle(color: kHrColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(chart.left + 4, y - tp.height - 2));
  }

  void _drawCursor(Canvas canvas, Rect chart, double visStart, double span) {
    final c = cursorElapsed;
    if (c == null) return;
    if (c < visStart || c > visStart + span) return;
    final x = chart.left + (c - visStart) / span * chart.width;
    canvas.drawLine(
      Offset(x, chart.top),
      Offset(x, chart.bottom),
      Paint()
        ..color = onSurface.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
  }

  void _drawCursorReadout(
    Canvas canvas,
    Rect chart,
    double visStart,
    double span,
  ) {
    final c = cursorElapsed;
    if (c == null) return;
    if (c < visStart || c > visStart + span) return;
    final hrV = _nearest(hr, c);
    final spo2V = _nearest(spo2, c);
    final parts = <String>[];
    if (hrV != null) parts.add('${hrV.round()} bpm');
    if (spo2V != null) parts.add('${spo2V.round()}% SpO₂');
    if (parts.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: parts.join('  ·  '),
        style: TextStyle(color: onSurface, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: chart.width);
    final x = chart.left + (c - visStart) / span * chart.width;
    var left = x - tp.width / 2;
    if (left < chart.left) left = chart.left;
    if (left + tp.width > chart.right) left = chart.right - tp.width;
    tp.paint(canvas, Offset(left, 4));
  }

  double? _nearest(List<ChartSample> samples, double elapsed) {
    if (samples.isEmpty) return null;
    ChartSample? best;
    var bestD = double.infinity;
    for (final s in samples) {
      final d = (s.t - elapsed).abs();
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    if (best == null || bestD > 2.0) return null;
    return best.v;
  }

  void _drawYLabels(Canvas canvas, Rect chart) {
    final style = TextStyle(color: axisColor, fontSize: 10);
    void label(String text, double y, {required bool left}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = left ? chart.left - tp.width - 4 : chart.right + 4;
      tp.paint(canvas, Offset(dx, y - tp.height / 2));
    }

    label('${kHrYMax.round()}', chart.top, left: true);
    label('${kHrYMin.round()}', chart.bottom, left: true);
    label('bpm', chart.top + 14, left: true);
    label('${kSpo2YMax.round()}', chart.top, left: false);
    label('${kSpo2YMin.round()}', chart.bottom, left: false);
    label('%', chart.top + 14, left: false);
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
  bool shouldRepaint(covariant OpticalOverviewPainter old) =>
      old.hr != hr ||
      old.spo2 != spo2 ||
      old.viewport != viewport ||
      old.newestElapsed != newestElapsed ||
      old.wallNow != wallNow ||
      old.connected != connected ||
      old.avgHr != avgHr ||
      old.highlightStartElapsed != highlightStartElapsed ||
      old.highlightEndElapsed != highlightEndElapsed ||
      old.cursorElapsed != cursorElapsed ||
      old.axisColor != axisColor ||
      old.gridColor != gridColor ||
      old.highlightColor != highlightColor ||
      old.onSurface != onSurface;
}
