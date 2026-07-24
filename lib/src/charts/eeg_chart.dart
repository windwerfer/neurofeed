import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/charts/chart_controller.dart';
import 'package:muse_ml/src/charts/graph_config.dart';

class EegChartWidget extends StatefulWidget {
  final EegDataSource source;
  final ChartController controller;
  final GraphConfig config;
  final VoidCallback? onToggleAvg;
  final ValueChanged<int>? onToggleElectrode;
  final VoidCallback? onRemove;

  const EegChartWidget({
    super.key,
    required this.source,
    required this.controller,
    required this.config,
    this.onToggleAvg,
    this.onToggleElectrode,
    this.onRemove,
  });

  @override
  State<EegChartWidget> createState() => _EegChartWidgetState();
}

class _EegChartWidgetState extends State<EegChartWidget> {
  @override
  void initState() {
    super.initState();
    widget.source.addListener(_requestRepaint);
    widget.controller.addListener(_requestRepaint);
    widget.controller.snapToLive(widget.source);
  }

  @override
  void didUpdateWidget(EegChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_requestRepaint);
      widget.source.addListener(_requestRepaint);
      widget.controller.snapToLive(widget.source);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_requestRepaint);
      widget.controller.addListener(_requestRepaint);
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_requestRepaint);
    widget.controller.removeListener(_requestRepaint);
    super.dispose();
  }

  void _requestRepaint() {
    if (mounted) setState(() {});
  }

  List<SeriesSlice> _buildSlices() {
    final ctrl = widget.controller;
    final visibleStart = ctrl.visibleEnd - ctrl.timeWindowSecs;
    final source = widget.source;
    final config = widget.config;
    final active = config.activeElectrodes.toList()..sort();

    if (config.avgMode && active.length > 1) {
      final perChannel = <List<ChartSample>>[];
      for (final ch in active) {
        perChannel.add(source.getRange(ch, visibleStart, ctrl.visibleEnd));
      }
      final minLen = perChannel.map((l) => l.length).reduce(math.min);
      if (minLen < 2) return [];
      final avgSamples = List<ChartSample>.generate(minLen, (i) {
        double sum = 0;
        for (final ch in perChannel) {
          sum += ch[i].v;
        }
        return ChartSample(perChannel[0][i].t, sum / perChannel.length);
      });
      return [
        SeriesSlice(
          name: 'avg',
          color: const Color(0xFF4FC3F7),
          unit: 'µV',
          samples: avgSamples,
          visible: true,
        ),
      ];
    }

    final result = <SeriesSlice>[];
    for (final ch in active) {
      result.add(SeriesSlice(
        name: channelName(ch),
        color: channelColor(ch),
        unit: 'µV',
        samples: source.getRange(ch, visibleStart, ctrl.visibleEnd),
        visible: true,
      ));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    ctrl.ensureBounds(widget.source);
    final visibleStart = ctrl.visibleEnd - ctrl.timeWindowSecs;
    final visibleEnd = ctrl.visibleEnd;
    final slices = _buildSlices();

    return ClipRect(
      child: Stack(
        children: [
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                ctrl.onPointerSignal(event, widget.source.maxTimeWindowSecs);
              }
            },
            child: GestureDetector(
              onScaleUpdate: (d) {
                ctrl.onScaleUpdate(d, widget.source.maxTimeWindowSecs, context.size!.width);
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _EegChartPainter(
                    slices: slices,
                    visibleStart: visibleStart,
                    visibleEnd: visibleEnd,
                    autoScroll: ctrl.autoScroll,
                  ),
                ),
              ),
            ),
          ),
          if (widget.onToggleAvg != null) _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final config = widget.config;
    final activeList = config.allElectrodes;
    final itemH = 22.0;
    return Positioned(
      right: 8,
      bottom: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xBB111218),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2A2D37)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < activeList.length; i++) ...[
              if (i > 0) SizedBox(height: itemH - 16),
              _LegendRow(
                color: channelColor(activeList[i]),
                label: channelName(activeList[i]),
                active: config.activeElectrodes.contains(activeList[i]),
                onTap: widget.onToggleElectrode != null
                    ? () => widget.onToggleElectrode!(activeList[i])
                    : null,
              ),
            ],
            SizedBox(height: itemH - 14),
            _LegendRow(
              color: const Color(0xFF4FC3F7),
              label: 'avg',
              active: config.avgMode,
              bold: true,
              onTap: widget.onToggleAvg,
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: widget.onRemove,
                child: const Icon(Icons.remove_circle_outline, color: Color(0xFF6B7280), size: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final bool active;
  final bool bold;
  final VoidCallback? onTap;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.active,
    this.bold = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 11,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 5),
            SizedBox(
              width: 8,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active ? color : color.withAlpha(60),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
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
    _drawLiveIndicator(canvas);
  }

  void _computeLayout() {
    const marginL = 60.0, marginR = 16.0;
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
    final x = _chartRect.right - 52;
    final y = _chartRect.top - 20;
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

  @override
  bool shouldRepaint(_EegChartPainter old) =>
      old.visibleStart != visibleStart ||
      old.visibleEnd != visibleEnd ||
      old.slices != slices ||
      old.autoScroll != autoScroll;
}
