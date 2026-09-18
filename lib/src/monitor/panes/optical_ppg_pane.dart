import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

import 'package:muse_ml/src/monitor/cache/optical_cache.dart';

/// Sweep slot index in 0 .. slotCount-1 for an absolute elapsed time.
int ppgSweepSlot({
  required double elapsed,
  required double windowSeconds,
  double sampleRate = OpticalCache.ppgSampleRate,
}) {
  final n = (windowSeconds * sampleRate).round();
  if (n <= 0) return 0;
  final idx = (elapsed * sampleRate).floor();
  return ((idx % n) + n) % n;
}

/// Wipe cursor as a fraction of chart width (0..1) for Follow sweep.
double ppgSweepCursorFraction({
  required double newestElapsed,
  required double windowSeconds,
  double sampleRate = OpticalCache.ppgSampleRate,
}) {
  final n = (windowSeconds * sampleRate).round();
  if (n <= 0) return 0;
  return ppgSweepSlot(
        elapsed: newestElapsed,
        windowSeconds: windowSeconds,
        sampleRate: sampleRate,
      ) /
      n;
}


/// Raw IR PPG waveform for the bottom HR+SpO2 detail pane.
class OpticalPpgPane extends StatefulWidget {
  const OpticalPpgPane({
    super.key,
    required this.samples,
    required this.viewport,
    required this.newestElapsed,
    required this.connected,
    this.cursorElapsed,
    this.onTapElapsed,
  });

  final List<ChartSample> samples;
  final ViewportController viewport;
  final double newestElapsed;
  final bool connected;
  final double? cursorElapsed;
  final ValueChanged<double?>? onTapElapsed;

  @override
  State<OpticalPpgPane> createState() => _OpticalPpgPaneState();
}

class _OpticalPpgPaneState extends State<OpticalPpgPane>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _yMin = 0;
  double _yMax = 1;
  int? _yMs;
  bool _established = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    widget.viewport.addListener(_onViewport);
    _syncTicker();
  }

  @override
  void didUpdateWidget(OpticalPpgPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.removeListener(_onViewport);
      widget.viewport.addListener(_onViewport);
    }
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

  void _syncTicker() {
    final run =
        widget.connected && widget.viewport.mode == ViewportMode.follow;
    final ticker = _ticker;
    if (ticker == null) return;
    if (run) {
      if (!ticker.isActive) ticker.start();
    } else if (ticker.isActive) {
      ticker.stop();
    }
  }

  void _easeY(double visStart, double visEnd) {
    final raw = <double>[];
    for (final s in widget.samples) {
      if (s.t < visStart || s.t > visEnd) continue;
      if (s.v.isFinite) raw.add(s.v);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (raw.isEmpty) {
      _yMin = 0;
      _yMax = 1;
      _yMs = now;
      _established = false;
      return;
    }
    var lo = raw.first;
    var hi = raw.first;
    for (final v in raw) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi - lo;
    final pad = range > 0 ? range * 0.12 : 1.0;
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
    final tau = expanding ? 0.8 : 8.0;
    final a = 1 - math.exp(-dt / tau);
    return current + (target - current) * a;
  }

  void _onTapDown(TapDownDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final chart = OpticalPpgPainter.chartRect(size);
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final sweep = widget.viewport.mode == ViewportMode.follow;
    final window = widget.viewport.windowSeconds;
    final visStart = sweep
        ? widget.newestElapsed - window
        : widget.viewport.stripVisibleStart(
            newestElapsed: widget.newestElapsed,
            wallNow: wallNow,
          );
    final visEnd = sweep
        ? widget.newestElapsed
        : widget.viewport.stripVisibleEnd(
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
    if (sweep) {
      final frac = ((x - chart.left) / chart.width).clamp(0.0, 1.0);
      final slot = (frac * (window * OpticalCache.ppgSampleRate)).round();
      final cursor = ppgSweepSlot(
        elapsed: widget.newestElapsed,
        windowSeconds: window,
      );
      final age = (cursor - slot) % (window * OpticalCache.ppgSampleRate).round();
      final elapsed = widget.newestElapsed - age / OpticalCache.ppgSampleRate;
      widget.onTapElapsed?.call(elapsed.clamp(visStart, visEnd));
      return;
    }
    final elapsed = visStart + (x - chart.left) / chart.width * span;
    widget.onTapElapsed?.call(elapsed.clamp(visStart, visEnd));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final sweep = widget.viewport.mode == ViewportMode.follow;
    final window = widget.viewport.windowSeconds;
    final visStart = sweep
        ? widget.newestElapsed - window
        : widget.viewport.stripVisibleStart(
            newestElapsed: widget.newestElapsed,
            wallNow: wallNow,
          );
    final visEnd = sweep
        ? widget.newestElapsed
        : widget.viewport.stripVisibleEnd(
            newestElapsed: widget.newestElapsed,
            wallNow: wallNow,
          );
    _easeY(visStart, visEnd);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: OpticalPpgPainter(
            samples: widget.samples,
            viewport: widget.viewport,
            newestElapsed: widget.newestElapsed,
            wallNow: wallNow,
            yMin: _yMin,
            yMax: _yMax,
            connected: widget.connected,
            cursorElapsed: widget.cursorElapsed,
            axisColor: theme.colorScheme.onSurfaceVariant,
            gridColor: theme.colorScheme.outlineVariant,
            lineColor: theme.colorScheme.tertiary,
            onSurface: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class OpticalPpgPainter extends CustomPainter {
  OpticalPpgPainter({
    required this.samples,
    required this.viewport,
    required this.newestElapsed,
    required this.wallNow,
    required this.yMin,
    required this.yMax,
    required this.connected,
    required this.axisColor,
    required this.gridColor,
    required this.lineColor,
    required this.onSurface,
    this.cursorElapsed,
  });

  static const double leftGutter = 36;
  static const double rightGutter = 8;
  static const double xGutter = 22;
  static const double topGutter = 18;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    leftGutter,
    topGutter,
    (size.width - leftGutter - rightGutter).clamp(8, double.infinity),
    (size.height - topGutter - xGutter).clamp(8, double.infinity),
  );

  final List<ChartSample> samples;
  final ViewportController viewport;
  final double newestElapsed;
  final double wallNow;
  final double yMin;
  final double yMax;
  final bool connected;
  final double? cursorElapsed;
  final Color axisColor;
  final Color gridColor;
  final Color lineColor;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = chartRect(size);
    if (chart.width <= 0 || chart.height <= 0) return;
    final ySpan = yMax - yMin;
    if (ySpan <= 0) return;

    final sweep = viewport.mode == ViewportMode.follow;
    final window = viewport.windowSeconds;
    final visStart = sweep
        ? newestElapsed - window
        : viewport.stripVisibleStart(
            newestElapsed: newestElapsed,
            wallNow: wallNow,
          );
    final visEnd = sweep
        ? newestElapsed
        : viewport.stripVisibleEnd(
            newestElapsed: newestElapsed,
            wallNow: wallNow,
          );
    final span = visEnd - visStart;
    if (span <= 0) return;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    if (sweep) {
      // Fixed grid in sweep space (0..window).
      for (final t in elapsedTicks(
        start: 0,
        end: window,
        widthPx: chart.width,
      )) {
        final x = chart.left + t / window * chart.width;
        canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), grid);
      }
    } else {
      for (final t in elapsedTicks(
        start: visStart,
        end: visEnd,
        widthPx: chart.width,
      )) {
        final x = chart.left + (t - visStart) / span * chart.width;
        canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), grid);
      }
    }

    canvas.save();
    canvas.clipRect(chart);
    if (connected && samples.isNotEmpty) {
      if (sweep) {
        _drawSweep(canvas, chart, window, ySpan);
      } else if (samples.length <= chart.width.floor()) {
        final path = Path();
        var started = false;
        for (final s in samples) {
          if (!s.v.isFinite) {
            started = false;
            continue;
          }
          final x = chart.left + (s.t - visStart) / span * chart.width;
          final y = chart.bottom - ((s.v - yMin) / ySpan) * chart.height;
          if (!started) {
            path.moveTo(x, y);
            started = true;
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = lineColor
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      } else {
        final path = Path();
        _drawMinMax(path, chart, visStart, span, ySpan);
        canvas.drawPath(
          path,
          Paint()
            ..color = lineColor
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      }
    }

    final c = cursorElapsed;
    if (c != null && c >= visStart && c <= visEnd) {
      final x = sweep
          ? chart.left +
              ppgSweepSlot(
                    elapsed: c,
                    windowSeconds: window,
                  ) /
                  math.max(1, (window * OpticalCache.ppgSampleRate).round()) *
                  chart.width
          : chart.left + (c - visStart) / span * chart.width;
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        Paint()
          ..color = onSurface.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
    }
    canvas.restore();

    final style = TextStyle(color: axisColor, fontSize: 10);
    final title = TextPainter(
      text: TextSpan(text: 'IR PPG', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(chart.left, 2));

    if (sweep) {
      for (final t in elapsedTicks(
        start: 0,
        end: window,
        widthPx: chart.width,
      )) {
        final x = chart.left + t / window * chart.width;
        // Map sweep-local t to absolute elapsed near newest.
        final abs = newestElapsed - window + t;
        if (abs < 0) continue;
        final tp = TextPainter(
          text: TextSpan(text: formatElapsed(abs), style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 4));
      }
    } else {
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
  }

  void _drawSweep(Canvas canvas, Rect chart, double window, double ySpan) {
    final rate = OpticalCache.ppgSampleRate;
    final n = (window * rate).round();
    if (n <= 0) return;
    final display = List<double>.filled(n, double.nan);
    final cursor = ppgSweepSlot(
      elapsed: newestElapsed,
      windowSeconds: window,
      sampleRate: rate,
    );
    for (final s in samples) {
      if (!s.v.isFinite) continue;
      final age = (newestElapsed - s.t) * rate;
      if (age < 0 || age >= n) continue;
      var idx = (cursor - age.round()) % n;
      if (idx < 0) idx += n;
      display[idx] = s.v;
    }

    void strokeRange(int from, int to) {
      final path = Path();
      var started = false;
      for (var i = from; i < to; i++) {
        final v = display[i];
        if (!v.isFinite) {
          started = false;
          continue;
        }
        final x = chart.left + i / n * chart.width;
        final y = chart.bottom - ((v - yMin) / ySpan) * chart.height;
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      if (started) {
        canvas.drawPath(
          path,
          Paint()
            ..color = lineColor
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      }
    }

    // Newer samples sit in [0, cursor); older pass remains in (cursor, n).
    strokeRange(0, cursor);
    strokeRange(cursor + 1, n);

    final wipeX = chart.left + cursor / n * chart.width;
    canvas.drawLine(
      Offset(wipeX, chart.top),
      Offset(wipeX, chart.bottom),
      Paint()
        ..color = onSurface.withValues(alpha: 0.55)
        ..strokeWidth = 1.5,
    );
  }

  void _drawMinMax(
    Path path,
    Rect chart,
    double visStart,
    double span,
    double ySpan,
  ) {
    final cols = chart.width.floor();
    if (cols <= 0 || samples.isEmpty) return;
    var started = false;
    for (var col = 0; col < cols; col++) {
      final t0 = visStart + col / cols * span;
      final t1 = visStart + (col + 1) / cols * span;
      var lo = double.infinity;
      var hi = double.negativeInfinity;
      for (final s in samples) {
        if (s.t < t0 || s.t >= t1) continue;
        if (!s.v.isFinite) continue;
        if (s.v < lo) lo = s.v;
        if (s.v > hi) hi = s.v;
      }
      if (lo.isInfinite) {
        started = false;
        continue;
      }
      final x = chart.left + col.toDouble();
      final yLo = chart.bottom - ((lo - yMin) / ySpan) * chart.height;
      final yHi = chart.bottom - ((hi - yMin) / ySpan) * chart.height;
      if (!started) {
        path.moveTo(x, yLo);
        started = true;
      } else {
        path.lineTo(x, yLo);
      }
      path.lineTo(x, yHi);
    }
  }

  @override
  bool shouldRepaint(covariant OpticalPpgPainter old) =>
      old.samples != samples ||
      old.viewport != viewport ||
      old.viewport.mode != viewport.mode ||
      old.viewport.windowSeconds != viewport.windowSeconds ||
      old.newestElapsed != newestElapsed ||
      old.wallNow != wallNow ||
      old.yMin != yMin ||
      old.yMax != yMax ||
      old.connected != connected ||
      old.cursorElapsed != cursorElapsed ||
      old.axisColor != axisColor ||
      old.gridColor != gridColor ||
      old.lineColor != lineColor ||
      old.onSurface != onSurface;
}
