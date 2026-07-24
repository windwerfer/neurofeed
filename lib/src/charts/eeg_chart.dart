import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';

class EegChartWidget extends StatefulWidget {
  final EegDataSource source;
  const EegChartWidget({super.key, required this.source});

  @override
  State<EegChartWidget> createState() => _EegChartWidgetState();
}

class _EegChartWidgetState extends State<EegChartWidget> {
  double _timeWindowSecs = 10;
  double _visibleEnd = 0;
  final Set<int> _hiddenChannels = {};
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onData);
    _snapToLive();
  }

  @override
  void didUpdateWidget(EegChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_onData);
      widget.source.addListener(_onData);
      _snapToLive();
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_onData);
    super.dispose();
  }

  void _onData() {
    if (mounted) setState(() {});
  }

  void _snapToLive() {
    final latest = widget.source.latestTimestamp;
    if (latest > 0) _visibleEnd = latest;
  }

  double get _maxTimeWindowSecs => widget.source.maxTimeWindowSecs;

  void _ensureBounds() {
    final latest = widget.source.latestTimestamp;
    final oldest = widget.source.oldestTimestamp;
    _timeWindowSecs = _timeWindowSecs.clamp(2.0, _maxTimeWindowSecs);

    if (_autoScroll) {
      _visibleEnd = latest;
    }
    if (latest <= 0 || oldest <= 0) return;
    final minEnd = oldest + _timeWindowSecs;
    final maxEnd = latest;
    if (minEnd < maxEnd) {
      _visibleEnd = _visibleEnd.clamp(minEnd, maxEnd);
    } else {
      _visibleEnd = latest;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      final prevWindow = _timeWindowSecs;
      _timeWindowSecs = (prevWindow / d.scale).clamp(2.0, _maxTimeWindowSecs);
      if (d.focalPointDelta.dx.abs() > 0.5) {
        final effectiveDelta =
            d.focalPointDelta.dx * _timeWindowSecs / context.size!.width;
        _visibleEnd -= effectiveDelta;
        _autoScroll = false;
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    setState(() {
      final factor = event.scrollDelta.dy < 0 ? 1.0 / 1.2 : 1.2;
      _timeWindowSecs = (_timeWindowSecs * factor).clamp(2.0, _maxTimeWindowSecs);
    });
  }

  void _zoomIn() {
    setState(() {
      _timeWindowSecs = (_timeWindowSecs / 1.5).clamp(2.0, _maxTimeWindowSecs);
    });
  }

  void _zoomOut() {
    setState(() {
      _timeWindowSecs = (_timeWindowSecs * 1.5).clamp(2.0, _maxTimeWindowSecs);
    });
  }

  void _enableAutoScroll() {
    setState(() {
      _autoScroll = true;
      _snapToLive();
    });
  }

  static const _legendPad = 12.0;
  static const _legendItemHeight = 28.0;

  void _onTapUp(TapUpDetails d) {
    final size = context.size!;
    final slices = _currentSlices;
    if (slices.isEmpty) return;
    final legendRect = _legendRect(size, slices.length);
    if (!legendRect.contains(d.localPosition)) {
      final liveRect = _liveRect(size);
      if (liveRect.contains(d.localPosition) && !_autoScroll) {
        _enableAutoScroll();
      }
      return;
    }
    final dy = d.localPosition.dy - legendRect.top - _legendPad;
    final index = dy ~/ _legendItemHeight;
    if (index < 0 || index >= slices.length) return;

    final channels = widget.source.channels;
    if (index >= channels.length) return;
    final ch = channels[index];
    setState(() {
      if (_hiddenChannels.contains(ch)) {
        _hiddenChannels.remove(ch);
      } else {
        _hiddenChannels.add(ch);
      }
    });
  }

  List<SeriesSlice> get _currentSlices {
    final visibleStart = _visibleEnd - _timeWindowSecs;
    return widget.source.slices(
      startT: visibleStart,
      endT: _visibleEnd,
      hiddenChannels: _hiddenChannels,
    );
  }

  Rect _legendRect(Size size, int count) {
    final w = 90.0;
    final h = _legendPad * 2 + count * _legendItemHeight;
    return Rect.fromLTWH(size.width - w - 8, size.height - h - 8, w, h);
  }

  Rect _liveRect(Size size) {
    return Rect.fromLTWH(size.width - 60, 8, 52, 20);
  }

  @override
  Widget build(BuildContext context) {
    _ensureBounds();
    final visibleStart = _visibleEnd - _timeWindowSecs;
    final visibleEnd = _visibleEnd;
    final slices = widget.source.slices(
      startT: visibleStart,
      endT: visibleEnd,
      hiddenChannels: _hiddenChannels,
    );

    return Stack(
      children: [
        Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            onScaleUpdate: _onScaleUpdate,
            onTapUp: _onTapUp,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _EegChartPainter(
                  slices: slices,
                  visibleStart: visibleStart,
                  visibleEnd: visibleEnd,
                  autoScroll: _autoScroll,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 64,
          bottom: 8,
          child: _ZoomControls(
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            autoScroll: _autoScroll,
            onToggleLive: _enableAutoScroll,
          ),
        ),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.autoScroll,
    required this.onToggleLive,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool autoScroll;
  final VoidCallback onToggleLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xCC111218),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(Icons.remove, onZoomOut),
          Container(width: 1, height: 16, color: const Color(0xFF2A2D37)),
          _Btn(Icons.add, onZoomIn),
          if (!autoScroll) ...[
            Container(width: 1, height: 16, color: const Color(0xFF2A2D37)),
            GestureDetector(
              onTap: onToggleLive,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(icon, color: Colors.white70, size: 16),
      ),
    );
  }
}

class _EegChartPainter extends CustomPainter {
  _EegChartPainter({
    required this.slices,
    required this.visibleStart,
    required this.visibleEnd,
    required this.autoScroll,
  });

  final List<SeriesSlice> slices;
  final double visibleStart;
  final double visibleEnd;
  final bool autoScroll;

  late Size _size;
  late Rect _chartRect;
  late double _xScale;
  late double _yMin;
  late double _yMax;
  late double _niceMin;
  late double _niceMax;
  late double _yRange;
  late double _yScale;

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    _computeLayout();
    _drawBackground(canvas);
    _drawGrid(canvas);
    for (final slice in slices) {
      _drawSlice(canvas, slice);
    }
    _drawBorder(canvas);
    _drawAxisLabels(canvas);
    _drawLegend(canvas);
    _drawLiveIndicator(canvas);
  }

  void _computeLayout() {
    const marginL = 60.0, marginR = 100.0;
    const marginT = 24.0, marginB = 32.0;
    _chartRect = Rect.fromLTWH(
      marginL,
      marginT,
      (_size.width - marginL - marginR).clamp(100, double.infinity),
      (_size.height - marginT - marginB).clamp(50, double.infinity),
    );
    _xScale = _chartRect.width / (visibleEnd - visibleStart);

    _yMin = double.infinity;
    _yMax = double.negativeInfinity;
    for (final slice in slices) {
      for (final s in slice.samples) {
        if (s.v < _yMin) _yMin = s.v;
        if (s.v > _yMax) _yMax = s.v;
      }
    }
    if (_yMin.isInfinite || _yMax.isInfinite) {
      _yMin = -100;
      _yMax = 100;
    }
    final range = _yMax - _yMin;
    final padding = range > 0 ? range * 0.1 : 20.0;
    _niceMin = _yMin - padding;
    _niceMax = _yMax + padding;
    _yRange = _niceMax - _niceMin;
    _yScale = _chartRect.height / _yRange;
  }

  void _drawLiveIndicator(Canvas canvas) {
    final x = _size.width - 60;
    final y = 8.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, 52, 20),
      const Radius.circular(4),
    );

    canvas.drawRRect(
      r,
      Paint()..color = autoScroll ? const Color(0xCC00AA00) : const Color(0xCC444444),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: 'LIVE',
        style: TextStyle(
          color: autoScroll ? const Color(0xFF66FF66) : const Color(0xFF888888),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x + (52 - tp.width) / 2, y + (20 - tp.height) / 2));
  }

  void _drawBackground(Canvas canvas) {
    final bg = Offset.zero & _size;
    canvas.drawRect(bg, Paint()..color = const Color(0xFF111218));
  }

  void _drawBorder(Canvas canvas) {
    canvas.drawRect(
      _chartRect,
      Paint()
        ..color = const Color(0xFF2A2D37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E212A)
      ..strokeWidth = 1;

    final yLines =
        _niceGridValues(_niceMin, _niceMax, _chartRect.height, 40);
    for (final v in yLines) {
      final y = _niceMax - v;
      final py = _chartRect.top + y * _yScale;
      canvas.drawLine(
        Offset(_chartRect.left, py),
        Offset(_chartRect.right, py),
        gridPaint,
      );
    }

    final xLines =
        _niceGridValues(visibleStart, visibleEnd, _chartRect.width, 60);
    for (final v in xLines) {
      final px = _chartRect.left + (v - visibleStart) * _xScale;
      canvas.drawLine(
        Offset(px, _chartRect.top),
        Offset(px, _chartRect.bottom),
        gridPaint,
      );
    }
  }

  List<double> _niceGridValues(
      double min, double max, double pixelSpan, double minPxGap) {
    final range = max - min;
    if (range <= 0 || pixelSpan <= 0) return [];
    final idealCount = pixelSpan / minPxGap;
    final roughStep = range / idealCount;
    final step = _niceStep(roughStep);
    if (step <= 0) return [];
    final start = (min / step).ceil() * step;
    final result = <double>[];
    for (double v = start; v <= max; v += step) {
      result.add(v);
    }
    return result;
  }

  double _niceStep(double rough) {
    final exp =
        math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final frac = rough / exp;
    return exp * (frac <= 1.5 ? 1 : frac <= 3.5 ? 2 : frac <= 7.5 ? 5 : 10);
  }

  void _drawSlice(Canvas canvas, SeriesSlice slice) {
    if (!slice.visible) return;
    final samples = slice.samples;
    if (samples.length < 2) return;

    final targetCount = (_chartRect.width * 2).toInt();
    final step = samples.length > targetCount
        ? (samples.length / targetCount).ceil()
        : 1;

    final paint = Paint()
      ..color = slice.color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < samples.length; i += step) {
      final x =
          _chartRect.left + (samples[i].t - visibleStart) * _xScale;
      final y = _chartRect.top + (_niceMax - samples[i].v) * _yScale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawAxisLabels(Canvas canvas) {
    final labelStyle = TextStyle(
      color: const Color(0xFF6B7280),
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final yLines = _niceGridValues(_niceMin, _niceMax, _chartRect.height, 40);
    for (final v in yLines) {
      final y = _niceMax - v;
      final py = _chartRect.top + y * _yScale;
      final text = v.toStringAsFixed(v.abs() < 10 ? 1 : 0);
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _chartRect.left - 8);
      tp.paint(
        canvas,
        Offset(_chartRect.left - tp.width - 4, py - tp.height / 2),
      );
    }

    final windowSecs = visibleEnd - visibleStart;
    final offsetLines =
        _niceGridValues(-windowSecs, 0, _chartRect.width, 60);
    var lastLabelEnd = double.negativeInfinity;
    const labelGap = 8.0;
    for (final offset in offsetLines) {
      final px = _chartRect.left + (offset + windowSecs) * _xScale;
      final text = autoScroll
          ? _formatTimeOffset(offset)
          : _formatTimestamp(visibleEnd + offset);
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final half = tp.width / 2;
      if (px - half < lastLabelEnd) continue;
      lastLabelEnd = px + half + labelGap;
      tp.paint(canvas, Offset(px - half, _chartRect.bottom + 6));
    }
  }

  String _formatTimeOffset(double offset) {
    if (offset.abs() < 0.5) return '0s';
    final abs = offset.abs();
    final label = abs < 60
        ? '${abs.toStringAsFixed(abs < 10 ? 1 : 0)}s'
        : '${(abs / 60).floor()}m${(abs % 60).toInt()}s';
    return offset < 0 ? '-$label' : '+$label';
  }

  String _formatTimestamp(double t) {
    final dt = DateTime.fromMillisecondsSinceEpoch((t * 1000).toInt());
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  void _drawLegend(Canvas canvas) {
    if (slices.isEmpty) return;

    const pad = _EegChartWidgetState._legendPad;
    const itemH = _EegChartWidgetState._legendItemHeight;
    final count = slices.length;
    const w = 90.0;
    final h = pad * 2 + count * itemH;
    final rect =
        Rect.fromLTWH(_size.width - w - 8, _size.height - h - 8, w, h);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xBB111218),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFF2A2D37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (int i = 0; i < count; i++) {
      final slice = slices[i];
      final y = rect.top + pad + i * itemH;

      canvas.drawCircle(
        Offset(rect.left + 10, y + itemH / 2),
        4,
        Paint()
          ..color =
              slice.visible ? slice.color : slice.color.withAlpha(60)
          ..style = PaintingStyle.fill,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: slice.name,
          style: TextStyle(
            color: slice.visible ? Colors.white : Colors.white38,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(rect.left + 20, y + itemH / 2 - tp.height / 2),
      );

      if (!slice.visible) {
        final cx = rect.right - pad;
        canvas.drawLine(
          Offset(cx - 5, y + itemH / 2 - 5),
          Offset(cx + 5, y + itemH / 2 + 5),
          Paint()..color = Colors.white38..strokeWidth = 1.5,
        );
        canvas.drawLine(
          Offset(cx + 5, y + itemH / 2 - 5),
          Offset(cx - 5, y + itemH / 2 + 5),
          Paint()..color = Colors.white38..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EegChartPainter old) =>
      old.visibleStart != visibleStart ||
      old.visibleEnd != visibleEnd ||
      old.slices != slices ||
      old.autoScroll != autoScroll;
}
