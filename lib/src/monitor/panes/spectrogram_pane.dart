import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

class SpectrogramHeatmapBgra {
  const SpectrogramHeatmapBgra({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  int pixelOffset(int x, int y) => (y * width + x) * 4;
}

SpectrogramHeatmapBgra? rasterizeSpectrogramBgra(
  List<StftColumn> columns, {
  required double magMin,
  required double magMax,
  double maxHz = SpectrogramPanePainter.maxHz,
}) {
  if (columns.isEmpty) return null;
  final width = columns.length;
  final n = columns.first.db.length;
  if (n < 2) return null;
  final fftN = (n - 1) * 2;
  final hzBin = fftN > 0 ? kFftSampleRate / fftN : 1.0;
  var height = 0;
  for (var k = 0; k < n; k++) {
    if (k * hzBin >= maxHz) break;
    height++;
  }
  if (height < 1) return null;

  final bytes = Uint8List(width * height * 4);
  final magSpan = magMax - magMin;
  for (var x = 0; x < columns.length; x++) {
    final db = columns[x].db;
    final limit = height < db.length ? height : db.length;
    for (var k = 0; k < limit; k++) {
      final t = magSpan.abs() < 1e-9 ? 0.0 : (db[k] - magMin) / magSpan;
      final argb = SpectrogramPanePainter.colorFor(t).toARGB32();
      final offset = ((height - 1 - k) * width + x) * 4;
      bytes[offset] = argb & 0xFF;
      bytes[offset + 1] = (argb >> 8) & 0xFF;
      bytes[offset + 2] = (argb >> 16) & 0xFF;
      bytes[offset + 3] = (argb >> 24) & 0xFF;
    }
  }
  return SpectrogramHeatmapBgra(bytes: bytes, width: width, height: height);
}

class SpectrogramPane extends StatefulWidget {
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
  State<SpectrogramPane> createState() => _SpectrogramPaneState();
}

class _SpectrogramPaneState extends State<SpectrogramPane> {
  ui.Image? _heatmap;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scheduleRaster();
  }

  @override
  void didUpdateWidget(SpectrogramPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns != widget.columns ||
        oldWidget.magMin != widget.magMin ||
        oldWidget.magMax != widget.magMax ||
        oldWidget.connected != widget.connected) {
      _scheduleRaster();
    }
  }

  @override
  void dispose() {
    _generation++;
    _heatmap?.dispose();
    _heatmap = null;
    super.dispose();
  }

  void _scheduleRaster() {
    _generation++;
    final gen = _generation;
    if (!widget.connected || widget.columns.isEmpty) {
      _dropHeatmap();
      return;
    }
    final bmp = rasterizeSpectrogramBgra(
      widget.columns,
      magMin: widget.magMin,
      magMax: widget.magMax,
    );
    if (bmp == null) {
      _dropHeatmap();
      return;
    }
    ui.decodeImageFromPixels(
      bmp.bytes,
      bmp.width,
      bmp.height,
      ui.PixelFormat.bgra8888,
      (image) {
        if (!mounted || gen != _generation) {
          image.dispose();
          return;
        }
        final previous = _heatmap;
        setState(() {
          _heatmap = image;
        });
        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            previous.dispose();
          });
        }
      },
    );
  }

  void _dropHeatmap() {
    final previous = _heatmap;
    if (previous == null) return;
    _heatmap = null;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: SpectrogramPanePainter(
        columns: widget.columns,
        viewport: widget.viewport,
        newestElapsed: widget.newestElapsed,
        magMin: widget.magMin,
        magMax: widget.magMax,
        connected: widget.connected,
        heatmap: _heatmap,
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
    required this.heatmap,
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
  final ui.Image? heatmap;
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
    if (connected && columns.isNotEmpty && heatmap != null) {
      _drawHeatmap(canvas, chart, visStart, span, heatmap!);
    }
    canvas.restore();
    _drawYLabels(canvas, chart);
    _drawXLabels(canvas, chart, visStart, visEnd);
    _drawColorbar(canvas, size, chart);
  }

  void _drawHeatmap(
    Canvas canvas,
    Rect chart,
    double visStart,
    double span,
    ui.Image image,
  ) {
    if (columns.isEmpty) return;
    final hop = columns.length >= 2
        ? (columns[1].elapsed - columns[0].elapsed).abs()
        : 0.25;
    final hopSec = hop > 1e-12 ? hop : 0.25;
    final x0 =
        chart.left + (columns.first.elapsed - visStart) / span * chart.width;
    final dest = Rect.fromLTWH(
      x0,
      chart.top,
      hopSec / span * chart.width * columns.length,
      chart.height,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.none,
    );
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
        old.heatmap != heatmap ||
        old.viewport.mode != viewport.mode ||
        old.viewport.windowSeconds != viewport.windowSeconds ||
        old.viewport.inspectStartElapsed != viewport.inspectStartElapsed;
  }
}
