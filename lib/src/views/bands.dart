import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/charts/band_cache.dart';
import 'package:muse_ml/src/charts/chart_controller.dart';
import 'package:muse_ml/src/connection_provider.dart';

class BandsView extends ConsumerWidget {
  const BandsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appStateProvider.notifier);
    return BandsDashboard(source: notifier.bandCache);
  }
}

class BandsDashboard extends StatefulWidget {
  final BandCache source;
  const BandsDashboard({super.key, required this.source});

  @override
  State<BandsDashboard> createState() => _BandsDashboardState();
}

class _BandsDashboardState extends State<BandsDashboard> with SingleTickerProviderStateMixin {
  final ChartController _controller = ChartController();
  final Set<int> _hiddenBands = {};
  Set<int> _activeElectrodes = {};
  List<int> _allElectrodes = const [];
  List<int> _lastChannels = const [];
  VoidCallback? _ctrlListener;
  bool _smooth = true;
  bool _realTime = false;

  Ticker? _scrollTicker;
  double _wallAtLastData = 0;
  double _dataAtLastData = 0;
  bool _hasData = false;
  static const double _futureOffset = 1.0;
  double get _offset => _realTime ? 0.0 : _futureOffset;

  @override
  void initState() {
    super.initState();
    _syncElectrodes();
    _lastChannels = widget.source.channels;
    _controller.timeWindowSecs = 30;
    _controller.snapToLive(widget.source);
    widget.source.addListener(_onSourceData);
    _ctrlListener = () {
      if (mounted) setState(() {});
    };
    _controller.addListener(_ctrlListener!);
  }

  @override
  void dispose() {
    widget.source.removeListener(_onSourceData);
    if (_ctrlListener != null) {
      _controller.removeListener(_ctrlListener!);
    }
    _scrollTicker?.dispose();
    super.dispose();
  }

  void _onSourceData() {
    final ch = widget.source.channels;
    if (!_listEquals(ch, _lastChannels)) {
      _lastChannels = ch;
      _syncElectrodes();
    }
    if (_controller.autoScroll) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final newData = widget.source.latestTimestamp;
      if (_hasData) {
        _wallAtLastData += (newData - _dataAtLastData);
        _dataAtLastData = newData;
      } else {
        _wallAtLastData = now;
        _dataAtLastData = newData;
        _hasData = true;
        _controller.visibleEnd = newData - _offset;
      }
      _scrollTicker ??= createTicker(_onTick);
      if (!_scrollTicker!.isActive) {
        _scrollTicker!.start();
      }
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (!_controller.autoScroll || !_hasData) {
      _scrollTicker?.stop();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final wallDelta = now - _wallAtLastData;
    _controller.visibleEnd = _dataAtLastData + wallDelta - _offset;
    _controller.forceNotify();
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _syncElectrodes() {
    final electrodes = <int>{};
    for (final ch in widget.source.channels) {
      electrodes.add(electrodeFromChannel(ch));
    }
    _allElectrodes = electrodes.toList()..sort();
    _activeElectrodes = Set.from(_allElectrodes);
  }

  void _toggleElectrode(int e) {
    setState(() {
      if (_activeElectrodes.contains(e)) {
        _activeElectrodes.remove(e);
      } else {
        _activeElectrodes.add(e);
      }
    });
  }

  void _toggleBand(int band) {
    setState(() {
      if (_hiddenBands.contains(band)) {
        _hiddenBands.remove(band);
      } else {
        _hiddenBands.add(band);
      }
    });
  }

  List<SeriesSlice> _buildSlices() {
    final ctrl = _controller;
    const queryPad = 5.0;
    final visibleStart = ctrl.visibleEnd - ctrl.timeWindowSecs;
    final source = widget.source;
    if (_activeElectrodes.isEmpty) return [];

    final result = <SeriesSlice>[];
    for (int b = 0; b < bandCountPerElectrode; b++) {
      if (_hiddenBands.contains(b)) continue;
      final perElectrode = <List<ChartSample>>[];
      for (final e in _activeElectrodes) {
        final id = bandChannelId(e, b);
        perElectrode.add(source.getRange(id, visibleStart - queryPad, ctrl.visibleEnd + queryPad));
      }
      final minLen = perElectrode.map((l) => l.length).reduce(math.min);
      if (minLen < 2) continue;
      final avgSamples = List<ChartSample>.generate(minLen, (i) {
        double sum = 0;
        for (final ch in perElectrode) {
          sum += ch[i].v;
        }
        return ChartSample(perElectrode[0][i].t, sum / perElectrode.length);
      });
      result.add(SeriesSlice(
        name: bandNames[b],
        color: bandColors[b % bandColors.length],
        unit: 'µV²/Hz',
        samples: avgSamples,
        visible: true,
      ));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!(_scrollTicker?.isActive ?? false) || !_controller.autoScroll) {
      _controller.ensureBounds(widget.source);
    }
    final visibleStart = _controller.visibleEnd - _controller.timeWindowSecs;
    final visibleEnd = _controller.visibleEnd;
    final slices = _buildSlices();

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _controller.onPointerSignal(event, widget.source.maxTimeWindowSecs);
                  }
                  if (_scrollTicker?.isActive ?? false) {
                    _scrollTicker?.stop();
                  }
                },
                child: GestureDetector(
                  onScaleUpdate: (d) {
                    _controller.onScaleUpdate(d, widget.source.maxTimeWindowSecs, context.size!.width);
                    if (_scrollTicker?.isActive ?? false) {
                      _scrollTicker?.stop();
                    }
                  },
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _EegChartPainter(
                        slices: slices,
                        visibleStart: visibleStart,
                        visibleEnd: visibleEnd,
                        autoScroll: _controller.autoScroll,
                        smooth: _smooth,
                      ),
                    ),
                  ),
                ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final itemH = 22.0;
    return Positioned(
      left: 8,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < bandCountPerElectrode; i++) ...[
              if (i > 0) SizedBox(height: itemH - 16),
              _LegendRow(
                color: bandColors[i % bandColors.length],
                label: bandNames[i],
                active: !_hiddenBands.contains(i),
                bold: true,
                onTap: () => _toggleBand(i),
              ),
            ],
            const SizedBox(height: 8),
            for (int i = 0; i < _allElectrodes.length; i++) ...[
              if (i > 0) const SizedBox(height: 3),
              _LegendRow(
                color: channelColor(_allElectrodes[i]),
                label: channelName(_allElectrodes[i]),
                active: _activeElectrodes.contains(_allElectrodes[i]),
                onTap: () => _toggleElectrode(_allElectrodes[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isLive = _controller.autoScroll;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2D37))),
      ),
      child: Row(
        children: [
          _headerBtn(Icons.remove, 'Zoom out', () => _controller.zoomOut(widget.source.maxTimeWindowSecs)),
          const SizedBox(width: 4),
          _headerBtn(Icons.add, 'Zoom in', () => _controller.zoomIn(widget.source.maxTimeWindowSecs)),
          const SizedBox(width: 8),
          Text(
            '${_controller.timeWindowSecs.toStringAsFixed(0)}s',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _smooth = !_smooth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _smooth ? const Color(0xFF0055FF).withAlpha(60) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _smooth ? const Color(0xFF0055FF) : const Color(0xFF4A4D57)),
              ),
              child: Text(
                'SMOOTH',
                style: TextStyle(
                  color: _smooth ? const Color(0xFF66AAFF) : const Color(0xFF4A4D57),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _realTime = !_realTime),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _realTime ? const Color(0xFF0055FF).withAlpha(60) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _realTime ? const Color(0xFF0055FF) : const Color(0xFF4A4D57)),
              ),
              child: Text(
                'REALTIME',
                style: TextStyle(
                  color: _realTime ? const Color(0xFF66AAFF) : const Color(0xFF4A4D57),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              _controller.autoScroll = true;
              final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
              final latest = widget.source.latestTimestamp;
              if (latest > 0) {
                if (_hasData) {
                  _wallAtLastData += (latest - _dataAtLastData);
                  _dataAtLastData = latest;
                } else {
                  _wallAtLastData = now;
                  _dataAtLastData = latest;
                  _hasData = true;
                  _controller.visibleEnd = latest - _offset;
                }
                _scrollTicker ??= createTicker(_onTick);
                if (!_scrollTicker!.isActive) _scrollTicker!.start();
              } else {
                _controller.snapToLive(widget.source);
              }
              _controller.forceNotify();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isLive ? const Color(0xFF00AA00).withAlpha(60) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isLive ? const Color(0xFF00AA00) : const Color(0xFF4A4D57)),
              ),
              child: Text(
                'LIVE',
                style: TextStyle(
                  color: isLive ? const Color(0xFF66FF66) : const Color(0xFF4A4D57),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _headerBtn(Icons.add_box_outlined, 'Add graph', () {}),
          const SizedBox(width: 4),
          _headerBtn(Icons.refresh, 'Reset defaults', () {
            _scrollTicker?.stop();
            _hasData = false;
            setState(() {
              _hiddenBands.clear();
              _syncElectrodes();
              _smooth = true;
              _realTime = false;
              _controller.autoScroll = true;
              _controller.timeWindowSecs = 30;
              _controller.snapToLive(widget.source);
              _controller.forceNotify();
            });
          }),
        ],
      ),
    );
  }

  Widget _headerBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white70, size: 18),
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
    required this.smooth,
  });

  final List<SeriesSlice> slices;
  final double visibleStart;
  final double visibleEnd;
  final bool autoScroll;
  final bool smooth;

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
    canvas.save();
    canvas.clipRect(_chartRect);
    for (final slice in slices) {
      _drawSlice(canvas, slice);
    }
    canvas.restore();
    _drawBorder(canvas);
    _drawAxisLabels(canvas);
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
      _yMin = -1;
      _yMax = 1;
    }
    final range = _yMax - _yMin;
    final padding = range > 0 ? range * 0.1 : 0.2;
    _niceMin = _yMin - padding;
    _niceMax = _yMax + padding;
    _yRange = _niceMax - _niceMin;
    _yScale = _chartRect.height / _yRange;
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

    // Find first on-screen index
    int firstVis = -1;
    for (int i = 0; i < samples.length; i += step) {
      if (samples[i].t >= visibleStart) {
        firstVis = i;
        break;
      }
    }
    if (firstVis < 0) return;

    // Build screen-coordinate points
    final pts = <Offset>[];

    // Interpolate left edge if there's a point before the first visible one
    if (firstVis > 0) {
      final prev = samples[firstVis - step];
      final next = samples[firstVis];
      final frac = (visibleStart - prev.t) / (next.t - prev.t);
      final v = prev.v + (next.v - prev.v) * frac;
      pts.add(Offset(
        _chartRect.left,
        _chartRect.top + (_niceMax - v) * _yScale,
      ));
    }

    // Include all points from first visible onward
    // (off-screen-right points extend beyond the right edge naturally)
    for (int i = firstVis; i < samples.length; i += step) {
      pts.add(Offset(
        _chartRect.left + (samples[i].t - visibleStart) * _xScale,
        _chartRect.top + (_niceMax - samples[i].v) * _yScale,
      ));
    }
    if (pts.length < 2) return;

    final path = Path();
    if (smooth) {
      _buildSmoothPath(path, pts);
    } else {
      path.moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _buildSmoothPath(Path path, List<Offset> pts) {
    // Catmull-Rom → Cubic Bezier
    // CP1 = P[i] + (P[i+1] - P[i-1]) / 6
    // CP2 = P[i+1] - (P[i+2] - P[i]) / 6
    path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
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
      String text;
      if (v.abs() < 10) {
        text = v.toStringAsFixed(2);
      } else if (v.abs() < 1000) {
        text = v.toStringAsFixed(1);
      } else {
        text = v.toInt().toString();
      }
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
      old.autoScroll != autoScroll ||
      old.smooth != smooth;
}
