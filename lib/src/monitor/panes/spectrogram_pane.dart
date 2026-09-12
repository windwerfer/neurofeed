import 'package:flutter/material.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

class SpectrogramPane extends StatelessWidget {
  const SpectrogramPane({
    super.key,
    required this.columns,
    required this.viewport,
    required this.newestElapsed,
    required this.magMin,
    required this.magMax,
    required this.connected,
  });

  final List<StftColumn> columns;
  final ViewportController viewport;
  final double newestElapsed;
  final double magMin;
  final double magMax;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: SpectrogramPanePainter(
        columns: columns,
        viewport: viewport,
        newestElapsed: newestElapsed,
        magMin: magMin,
        magMax: magMax,
        connected: connected,
        axisColor: theme.colorScheme.onSurfaceVariant,
        gridColor: theme.colorScheme.outlineVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class SpectrogramPanePainter extends CustomPainter {
  SpectrogramPanePainter({
    required this.columns,
    required this.viewport,
    required this.newestElapsed,
    required this.magMin,
    required this.magMax,
    required this.connected,
    required this.axisColor,
    required this.gridColor,
  });

  static const double yGutter = 36;
  static const double xGutter = 22;
  static const double topGutter = 10;
  static const double colorbarWidth = 12;
  static const double colorbarGutter = 40;
  static const double maxHz = 60;

  static const List<(double t, Color c)> _stops = [
    (0.0, Color(0xFF0D0887)),
    (0.25, Color(0xFF7E03A8)),
    (0.5, Color(0xFFCC4778)),
    (0.75, Color(0xFFF89540)),
    (1.0, Color(0xFFF0F921)),
  ];

  final List<StftColumn> columns;
  final ViewportController viewport;
  final double newestElapsed;
  final double magMin;
  final double magMax;
  final bool connected;
  final Color axisColor;
  final Color gridColor;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    yGutter,
    topGutter,
    (size.width - yGutter - colorbarGutter).clamp(8, double.infinity),
    (size.height - topGutter - xGutter).clamp(8, double.infinity),
  );

  static Color colorFor(double t) {
    final u = t.clamp(0.0, 1.0);
    for (var i = 1; i < _stops.length; i++) {
      if (u <= _stops[i].$1) {
        final a = _stops[i - 1];
        final b = _stops[i];
        final span = b.$1 - a.$1;
        final f = span <= 0 ? 1.0 : (u - a.$1) / span;
        return Color.lerp(a.$2, b.$2, f)!;
      }
    }
    return _stops.last.$2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chart = chartRect(size);
    if (chart.width <= 0 || chart.height <= 0) return;
    final visStart = viewport.stripVisibleStart(newestElapsed: newestElapsed);
    final visEnd = viewport.stripVisibleEnd(newestElapsed: newestElapsed);
    final span = visEnd - visStart;
    if (span <= 0) return;

    canvas.save();
    canvas.clipRect(chart);
    canvas.drawRect(chart, Paint()..color = _stops.first.$2);
    if (connected && columns.isNotEmpty) {
      _drawHeatmap(canvas, chart, visStart, span);
    }
    canvas.restore();
    _drawYLabels(canvas, chart);
    _drawXLabels(canvas, chart, visStart, visEnd);
    _drawColorbar(canvas, size, chart);
  }

  void _drawHeatmap(Canvas canvas, Rect chart, double visStart, double span) {
    if (columns.isEmpty) return;
    final magSpan = magMax - magMin;
    final hop = columns.length >= 2
        ? (columns[1].elapsed - columns[0].elapsed).abs()
        : 0.25;
    final colW = (hop / span * chart.width).clamp(1.0, chart.width);
    final n = columns.first.db.length;
    if (n < 2) return;
    final fftN = (n - 1) * 2;
    final hzBin = fftN > 0 ? kFftSampleRate / fftN : 1.0;

    for (final col in columns) {
      if (col.elapsed < visStart - hop || col.elapsed > visStart + span + hop) {
        continue;
      }
      final x = chart.left + (col.elapsed - visStart) / span * chart.width;
      if (x + colW < chart.left || x > chart.right) continue;
      final lastBin = (maxHz / hzBin).floor().clamp(0, col.db.length - 1);
      for (var k = 0; k <= lastBin; k++) {
        final hz0 = k * hzBin;
        final hz1 = (k + 1) * hzBin;
        if (hz0 >= maxHz) break;
        final y1 = chart.bottom - (hz0 / maxHz).clamp(0.0, 1.0) * chart.height;
        final y0 = chart.bottom - (hz1 / maxHz).clamp(0.0, 1.0) * chart.height;
        final t = magSpan.abs() < 1e-9 ? 0.0 : (col.db[k] - magMin) / magSpan;
        canvas.drawRect(
          Rect.fromLTRB(x, y0, x + colW, y1),
          Paint()..color = colorFor(t),
        );
      }
    }
  }

  void _drawYLabels(Canvas canvas, Rect chart) {
    final style = TextStyle(
      color: axisColor,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final title = TextPainter(
      text: TextSpan(text: 'Hz', style: style.copyWith(fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(8, chart.top - 2));
    for (final hz in const [0.0, 20.0, 40.0, 60.0]) {
      final y = chart.bottom - hz / maxHz * chart.height;
      final tp = TextPainter(
        text: TextSpan(text: hz.round().toString(), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 4, y - tp.height / 2));
    }
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

  void _drawColorbar(Canvas canvas, Size size, Rect chart) {
    final bar = Rect.fromLTWH(
      chart.right + 8,
      chart.top,
      colorbarWidth,
      chart.height,
    );
    if (bar.height <= 0) return;
    const n = 32;
    final h = bar.height / n;
    for (var i = 0; i < n; i++) {
      final t = 1 - i / (n - 1);
      canvas.drawRect(
        Rect.fromLTWH(bar.left, bar.top + i * h, bar.width, h + 0.5),
        Paint()..color = colorFor(t),
      );
    }
    final style = TextStyle(
      color: axisColor,
      fontSize: 9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final hi = TextPainter(
      text: TextSpan(text: magMax.round().toString(), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    hi.paint(canvas, Offset(bar.right + 2, bar.top));
    final lo = TextPainter(
      text: TextSpan(text: magMin.round().toString(), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    lo.paint(canvas, Offset(bar.right + 2, bar.bottom - lo.height));
  }

  @override
  bool shouldRepaint(covariant SpectrogramPanePainter old) {
    return old.columns != columns ||
        old.newestElapsed != newestElapsed ||
        old.magMin != magMin ||
        old.magMax != magMax ||
        old.connected != connected ||
        old.viewport.mode != viewport.mode ||
        old.viewport.windowSeconds != viewport.windowSeconds ||
        old.viewport.inspectStartElapsed != viewport.inspectStartElapsed;
  }
}
