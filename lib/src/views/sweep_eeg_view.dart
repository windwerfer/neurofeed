import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/sweep_buffer.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class SweepEegView extends ConsumerStatefulWidget {
  const SweepEegView({super.key});

  @override
  ConsumerState<SweepEegView> createState() => _SweepEegViewState();
}

class _SweepEegViewState extends ConsumerState<SweepEegView> {
  final SweepBuffer _buffer = SweepBuffer();
  StreamSubscription<MuseEventDto>? _sub;
  bool _drawerOpen = false;
  final Set<int> _activeElectrodes = {};
  final Set<int> _discoveredElectrodes = {};
  bool _avgMode = false;
  int _xZoomSamples = 0;
  int? _xZoomAtPinchStart;
  int _panOffset = 0;
  bool _yAutoZoom = true;
  double _yZoomFactor = 1.0;
  double? _yZoomAtPinchStart;

  static const _initialXZoomSamples = 1536; // 6s at 256 Hz

  @override
  void initState() {
    super.initState();
    _xZoomSamples = _initialXZoomSamples;
    _buffer.setDisplayWindow(_xZoomSamples);
    _buffer.addListener(_onBufferChanged);
    final notifier = ref.read(appStateProvider.notifier);
    _sub = notifier.eventStream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _buffer.removeListener(_onBufferChanged);
    _buffer.dispose();
    super.dispose();
  }

  void _onBufferChanged() {
    if (mounted) setState(() {});
  }

  void _onEvent(MuseEventDto event) {
    if (event is MuseEventDto_Eeg) {
      _buffer.append(event.field0);
      if (!_discoveredElectrodes.contains(event.field0.electrode)) {
        setState(() {
          _discoveredElectrodes.add(event.field0.electrode);
          _activeElectrodes.add(event.field0.electrode);
        });
      }
    }
  }

  void _onScaleStart(ScaleStartDetails _) {
    _xZoomAtPinchStart = _xZoomSamples;
    _yZoomAtPinchStart = _yZoomFactor;
    if (!_buffer.frozen) _buffer.freeze();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount == 1) {
      if (!_buffer.frozen) _buffer.freeze();
      final pixelsPerSample = context.size!.width / _xZoomSamples;
      _panBy(-(d.focalPointDelta.dx / pixelsPerSample).round());
    } else if (d.pointerCount >= 2) {
      final hz = d.horizontalScale;
      final vz = d.verticalScale;
      final hDev = (hz - 1.0).abs();
      final vDev = (vz - 1.0).abs();
      if (hDev > vDev && _xZoomAtPinchStart != null) {
        setState(() {
          _xZoomSamples = (_xZoomAtPinchStart! / hz).round().clamp(
            128,
            _buffer.capacity,
          );
          _buffer.setDisplayWindow(_xZoomSamples);
        });
      } else if (vDev > hDev && _yZoomAtPinchStart != null) {
        setState(() {
          _yAutoZoom = false;
          _yZoomFactor = _yZoomAtPinchStart! / vz;
        });
      }
    }
  }

  void _panBy(int delta) {
    setState(() {
      final maxPan = math.max(0, _buffer.cursor - _xZoomSamples);
      _panOffset = (_panOffset + delta).clamp(0, maxPan);
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    setState(() {
      if (delta < 0) {
        _xZoomSamples = (_xZoomSamples ~/ 1.2).clamp(128, _buffer.capacity);
      } else {
        _xZoomSamples = (_xZoomSamples * 1.2).round().clamp(
          128,
          _buffer.capacity,
        );
      }
      _buffer.setDisplayWindow(_xZoomSamples);
    });
  }

  void _xZoomOut() {
    setState(() {
      _xZoomSamples = (_xZoomSamples * 1.5).round().clamp(
        128,
        _buffer.capacity,
      );
      _buffer.setDisplayWindow(_xZoomSamples);
    });
  }

  void _xZoomIn() {
    setState(() {
      _xZoomSamples = (_xZoomSamples ~/ 1.5).clamp(128, _buffer.capacity);
      _buffer.setDisplayWindow(_xZoomSamples);
    });
  }

  double _computeAutoYHalfRange() {
    double yMin = double.infinity;
    double yMax = double.negativeInfinity;
    for (final ch in _activeElectrodes) {
      final data = _buffer.frozen ? _buffer.getChannel(ch) : _buffer.getDisplay(ch);
      if (data == null) continue;
      final start = _buffer.frozen ? _panOffset : 0;
      final end = start + _xZoomSamples;
      for (int i = start; i < end; i++) {
        final s = _buffer.frozen ? data[i % _buffer.capacity] : data[i];
        if (s.abs() < 1e6) {
          if (s < yMin) yMin = s;
          if (s > yMax) yMax = s;
        }
      }
    }
    if (yMin.isInfinite || yMax.isInfinite) return 200.0;
    final range = yMax - yMin;
    final padding = range > 0 ? range * 0.15 : 20.0;
    return ((range / 2) + padding).clamp(10.0, 10000.0);
  }

  void _enterManualMode() {
    if (!_yAutoZoom) return;
    final autoRange = _computeAutoYHalfRange();
    _yAutoZoom = false;
    _yZoomFactor = 200.0 / autoRange;
  }

  void _yZoomOut() {
    setState(() {
      _enterManualMode();
      _yZoomFactor *= 1.5;
    });
  }

  void _yZoomIn() {
    setState(() {
      _enterManualMode();
      _yZoomFactor /= 1.5;
    });
  }

  void _toggleYAutoZoom() {
    if (_yAutoZoom) {
      final autoRange = _computeAutoYHalfRange();
      setState(() {
        _yAutoZoom = false;
        _yZoomFactor = 200.0 / autoRange;
      });
    } else {
      setState(() => _yAutoZoom = true);
    }
  }

  void _resume() {
    _buffer.resume();
    _panOffset = 0;
  }

  void _toggleDrawer() => setState(() => _drawerOpen = !_drawerOpen);

  void _reset() {
    _buffer.freeze();
    _buffer.resume();
    setState(() {
      _xZoomSamples = _initialXZoomSamples;
      _yAutoZoom = true;
      _yZoomFactor = 1.0;
    });
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

  static const _kDrawerWidth = 180.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeaderBar(
          onXZoomOut: _xZoomOut,
          onXZoomIn: _xZoomIn,
          xZoomLabel: '${(_xZoomSamples / 256).round()}s',
          onYZoomOut: _yZoomOut,
          onYZoomIn: _yZoomIn,
          yAutoZoom: _yAutoZoom,
          onToggleYAutoZoom: _toggleYAutoZoom,
          onGear: _toggleDrawer,
          gearActive: _drawerOpen,
          isLive: !_buffer.frozen,
          onLive: _resume,
          onReset: _reset,
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: ClipRect(
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SweepPainter(
                            buffer: _buffer,
                            frozen: _buffer.frozen,
                            panOffset: _panOffset,
                            activeElectrodes: _activeElectrodes,
                            avgMode: _avgMode,
                            xZoomSamples: _xZoomSamples,
                            yAutoZoom: _yAutoZoom,
                            yZoomFactor: _yZoomFactor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_drawerOpen)
                _SettingsDrawer(
                  width: _kDrawerWidth,
                  electrodes: _buffer.electrodes,
                  activeElectrodes: _activeElectrodes,
                  avgMode: _avgMode,
                  onToggleElectrode: _toggleElectrode,
                  onToggleAvg: () => setState(() => _avgMode = !_avgMode),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.onXZoomOut,
    required this.onXZoomIn,
    required this.xZoomLabel,
    required this.onYZoomOut,
    required this.onYZoomIn,
    required this.yAutoZoom,
    required this.onToggleYAutoZoom,
    required this.onGear,
    required this.gearActive,
    required this.isLive,
    required this.onLive,
    required this.onReset,
  });

  final VoidCallback onXZoomOut;
  final VoidCallback onXZoomIn;
  final String xZoomLabel;
  final VoidCallback onYZoomOut;
  final VoidCallback onYZoomIn;
  final bool yAutoZoom;
  final VoidCallback onToggleYAutoZoom;
  final VoidCallback onGear;
  final bool gearActive;
  final bool isLive;
  final VoidCallback onLive;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2D37))),
      ),
      child: Row(
        children: [
          _headerBtn(Icons.remove, 'X zoom out', onXZoomOut),
          const SizedBox(width: 4),
          _headerBtn(Icons.add, 'X zoom in', onXZoomIn),
          const SizedBox(width: 6),
          Text(
            xZoomLabel,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          _headerBtn(Icons.vertical_align_bottom, 'Y zoom out', onYZoomOut),
          const SizedBox(width: 4),
          _headerBtn(Icons.vertical_align_top, 'Y zoom in', onYZoomIn),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onToggleYAutoZoom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: yAutoZoom
                    ? const Color(0xFF00AA00).withAlpha(60)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: yAutoZoom
                      ? const Color(0xFF00AA00)
                      : const Color(0xFF4A4D57),
                ),
              ),
              child: Text(
                'AUTO',
                style: TextStyle(
                  color: yAutoZoom
                      ? const Color(0xFF66FF66)
                      : const Color(0xFF4A4D57),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _headerBtn(Icons.settings, 'Settings', onGear, active: gearActive),
          const Spacer(),
          GestureDetector(
            onTap: isLive ? null : onLive,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isLive
                    ? const Color(0xFF00AA00).withAlpha(60)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isLive
                      ? const Color(0xFF00AA00)
                      : const Color(0xFF4A4D57),
                ),
              ),
              child: Text(
                'LIVE',
                style: TextStyle(
                  color: isLive
                      ? const Color(0xFF66FF66)
                      : const Color(0xFF4A4D57),
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
          _headerBtn(Icons.refresh, 'Reset', onReset),
        ],
      ),
    );
  }

  Widget _headerBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: active ? const Color(0xFF66FF66) : Colors.white70,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _SettingsDrawer extends StatelessWidget {
  const _SettingsDrawer({
    required this.width,
    required this.electrodes,
    required this.activeElectrodes,
    required this.avgMode,
    required this.onToggleElectrode,
    required this.onToggleAvg,
  });

  final double width;
  final List<int> electrodes;
  final Set<int> activeElectrodes;
  final bool avgMode;
  final ValueChanged<int> onToggleElectrode;
  final VoidCallback onToggleAvg;

  static const _kChannelNames = ['TP9', 'AF7', 'AF8', 'TP10'];
  static const _kChannelColors = [
    Color(0xFF4FC3F7),
    Color(0xFFFF7043),
    Color(0xFF66BB6A),
    Color(0xFFAB47BC),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xBB111218),
        border: const Border(left: BorderSide(color: Color(0xFF2A2D37))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Text(
              'SENSORS',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          for (int i = 0; i < electrodes.length; i++) ...[
            _SensorRow(
              color: _kChannelColors[i % _kChannelColors.length],
              label: i < _kChannelNames.length
                  ? _kChannelNames[i]
                  : 'CH${i + 1}',
              active: activeElectrodes.contains(electrodes[i]),
              onTap: () => onToggleElectrode(electrodes[i]),
            ),
          ],
          const Divider(color: Color(0xFF2A2D37), height: 20),
          _SensorRow(
            color: const Color(0xFF4FC3F7),
            label: 'avg',
            active: avgMode,
            bold: true,
            onTap: onToggleAvg,
          ),
        ],
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  final Color color;
  final String label;
  final bool active;
  final bool bold;
  final VoidCallback onTap;

  const _SensorRow({
    required this.color,
    required this.label,
    required this.active,
    this.bold = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 11,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 6),
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

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.buffer,
    required this.frozen,
    required this.panOffset,
    required this.activeElectrodes,
    required this.avgMode,
    required this.xZoomSamples,
    required this.yAutoZoom,
    required this.yZoomFactor,
  });

  final SweepBuffer buffer;
  final bool frozen;
  final int panOffset;
  final Set<int> activeElectrodes;
  final bool avgMode;
  final int xZoomSamples;
  final bool yAutoZoom;
  final double yZoomFactor;

  static const _kMarginL = 50.0;
  static const _kMarginR = 16.0;
  static const _kMarginT = 24.0;
  static const _kMarginB = 28.0;
  static const _kChannelColors = [
    Color(0xFF4FC3F7),
    Color(0xFFFF7043),
    Color(0xFF66BB6A),
    Color(0xFFAB47BC),
    Color(0xFFFFA726),
    Color(0xFF26C6DA),
    Color(0xFFEC407A),
    Color(0xFF8D6E63),
  ];

  late Rect _chartRect;
  late double _xScale;
  late int _visibleStart;
  late int _visibleEnd;
  late double _yHalfRange;
  late double _yScale;

  @override
  void paint(Canvas canvas, Size size) {
    _chartRect = Rect.fromLTWH(
      _kMarginL,
      _kMarginT,
      (size.width - _kMarginL - _kMarginR).clamp(100, double.infinity),
      (size.height - _kMarginT - _kMarginB).clamp(50, double.infinity),
    );
    _xScale = _chartRect.width / xZoomSamples;

    if (frozen) {
      _visibleStart = panOffset;
      _visibleEnd = panOffset + xZoomSamples;
    } else {
      _visibleStart = 0;
      _visibleEnd = xZoomSamples;
    }

    _computeYRange();
    _drawBackground(canvas);
    _drawGrid(canvas);

    if (avgMode && activeElectrodes.length > 1) {
      _drawAvgTrace(canvas);
    } else {
      final sorted = activeElectrodes.toList()..sort();
      for (final ch in sorted) {
        if (buffer.getChannel(ch) != null) {
          _drawChannel(canvas, ch);
        }
      }
    }

    _drawCursor(canvas);
    _drawBorder(canvas);
    _drawYLabels(canvas);
  }

  void _computeYRange() {
    if (yAutoZoom) {
      double yMin = double.infinity;
      double yMax = double.negativeInfinity;
      final sorted = activeElectrodes.toList()..sort();
      for (final ch in sorted) {
        final data = frozen ? buffer.getChannel(ch) : buffer.getDisplay(ch);
        if (data == null) continue;
        for (int i = _visibleStart; i < _visibleEnd; i++) {
          final s = frozen ? data[i % buffer.capacity] : data[i];
          if (s.abs() < 1e6) {
            if (s < yMin) yMin = s;
            if (s > yMax) yMax = s;
          }
        }
      }
      if (yMin.isInfinite || yMax.isInfinite) {
        _yHalfRange = 200.0;
      } else {
        final range = yMax - yMin;
        final padding = range > 0 ? range * 0.15 : 20.0;
        _yHalfRange = ((range / 2) + padding).clamp(10.0, 10000.0);
      }
    } else {
      _yHalfRange = 200.0 / yZoomFactor;
    }
    _yScale = _chartRect.height / (2 * _yHalfRange);
  }

  void _drawBackground(Canvas canvas) {
    canvas.drawRect(_chartRect, Paint()..color = const Color(0xFF111218));
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
    final paint = Paint()
      ..color = const Color(0xFF1E212A)
      ..strokeWidth = 1;

    final yLines = _niceGridValues(
      -_yHalfRange,
      _yHalfRange,
      _chartRect.height,
      40,
    );
    for (final v in yLines) {
      if (v.abs() < 0.001) continue;
      final py = _chartRect.center.dy - v * _yScale;
      canvas.drawLine(
        Offset(_chartRect.left, py),
        Offset(_chartRect.right, py),
        paint,
      );
    }

    final xLines = _niceGridValues(
      0,
      xZoomSamples.toDouble(),
      _chartRect.width,
      60,
    );
    for (final v in xLines) {
      final px = _chartRect.left + v * _xScale;
      canvas.drawLine(
        Offset(px, _chartRect.top),
        Offset(px, _chartRect.bottom),
        paint,
      );
    }
  }

  void _drawYLabels(Canvas canvas) {
    final style = TextStyle(
      color: const Color(0xFF6B7280),
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final yLines = _niceGridValues(
      -_yHalfRange,
      _yHalfRange,
      _chartRect.height,
      40,
    );
    for (final v in yLines) {
      final py = _chartRect.center.dy - v * _yScale;
      final text = v.toStringAsFixed(v.abs() < 10 ? 1 : 0);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _chartRect.left - 8);
      tp.paint(
        canvas,
        Offset(_chartRect.left - tp.width - 4, py - tp.height / 2),
      );
    }
  }

  void _drawAvgTrace(Canvas canvas) {
    final sorted = activeElectrodes.toList()..sort();
    final channels = <List<double>>[];
    for (final ch in sorted) {
      final data = frozen ? buffer.getChannel(ch) : buffer.getDisplay(ch);
      if (data != null) channels.add(frozen ? data.toList() : data.toList());
    }
    if (channels.isEmpty || channels.any((c) => c.isEmpty)) return;

    final paint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final cap = buffer.capacity;
    bool started = false;
    final path = Path();
    for (int i = _visibleStart; i < _visibleEnd; i++) {
      double sum = 0;
      int count = 0;
      for (final c in channels) {
        final idx = frozen ? i % cap : i;
        if (idx < c.length && c[idx].abs() < 1e6) {
          sum += c[idx];
          count++;
        }
      }
      if (count == 0) continue;
      final avg = sum / count;
      final x = _chartRect.left + (i - _visibleStart) * _xScale;
      final y = _chartRect.center.dy - avg * _yScale;
      if (!started) {
        started = true;
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (started) canvas.drawPath(path, paint);
  }

  void _drawChannel(Canvas canvas, int electrode) {
    final data = frozen ? buffer.getChannel(electrode) : buffer.getDisplay(electrode);
    if (data == null || data.isEmpty) return;

    final color = _kChannelColors[electrode % _kChannelColors.length];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final cap = buffer.capacity;
    bool started = false;
    final path = Path();
    for (int i = _visibleStart; i < _visibleEnd; i++) {
      final s = frozen ? data[i % cap] : data[i];
      if (s.abs() > 1e6) continue;
      final x = _chartRect.left + (i - _visibleStart) * _xScale;
      final y = _chartRect.center.dy - s * _yScale;
      if (!started) {
        started = true;
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (started) canvas.drawPath(path, paint);
  }

  void _drawCursor(Canvas canvas) {
    final cursorPos = frozen ? buffer.cursor - _visibleStart : buffer.cursor % xZoomSamples;
    if (cursorPos < 0 || cursorPos > xZoomSamples) return;
    final cx = _chartRect.left + cursorPos * _xScale;

    final paint = Paint()
      ..color = frozen ? const Color(0xFF555555) : const Color(0xFF88FF88)
      ..strokeWidth = frozen ? 1.5 : 2.0;

    canvas.drawLine(
      Offset(cx, _chartRect.top),
      Offset(cx, _chartRect.bottom),
      paint,
    );

    if (!frozen) {
      canvas.drawLine(
        Offset(cx, _chartRect.top),
        Offset(cx, _chartRect.top + 8),
        Paint()
          ..color = const Color(0xFF88FF88)
          ..strokeWidth = 3,
      );
      canvas.drawLine(
        Offset(cx, _chartRect.bottom - 8),
        Offset(cx, _chartRect.bottom),
        Paint()
          ..color = const Color(0xFF88FF88)
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_SweepPainter old) => true;

  List<double> _niceGridValues(
    double min,
    double max,
    double pxSpan,
    double minPx,
  ) {
    final range = max - min;
    if (range <= 0 || pxSpan <= 0) return [];
    final ideal = pxSpan / minPx;
    final rough = range / ideal;
    final step = _niceStep(rough);
    if (step <= 0) return [];
    final start = (min / step).ceil() * step;
    final result = <double>[];
    for (double v = start; v <= max; v += step) {
      result.add(v);
    }
    return result;
  }

  double _niceStep(double r) {
    final exp = math.pow(10, (math.log(r) / math.ln10).floor()).toDouble();
    final frac = r / exp;
    return exp *
        (frac <= 1.5
            ? 1
            : frac <= 3.5
            ? 2
            : frac <= 7.5
            ? 5
            : 10);
  }
}
