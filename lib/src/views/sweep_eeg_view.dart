import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(appStateProvider.notifier);
    _sub = notifier.eventStream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _buffer.dispose();
    super.dispose();
  }

  void _onEvent(MuseEventDto event) {
    if (event is MuseEventDto_Eeg) {
      _buffer.append(event.field0);
    }
  }

  void _onDragStart(DragStartDetails _) {
    if (!_buffer.frozen) _buffer.freeze();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_buffer.frozen) return;
    final pixelsPerSample = context.size!.width / _buffer.capacity;
    _buffer.panBy(-(d.delta.dx / pixelsPerSample).round());
  }

  void _resume() => _buffer.resume();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _buffer,
      builder: (_, _) {
        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SweepPainter(
                    buffer: _buffer,
                    frozen: _buffer.frozen,
                    panOffset: _buffer.panOffset,
                  ),
                ),
              ),
              if (_buffer.frozen)
                Positioned(
                  top: 8,
                  right: 12,
                  child: GestureDetector(
                    onTap: _resume,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00AA00).withAlpha(60),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF00AA00)),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Color(0xFF66FF66),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.buffer,
    required this.frozen,
    required this.panOffset,
  });

  final SweepBuffer buffer;
  final bool frozen;
  final int panOffset;

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

  @override
  void paint(Canvas canvas, Size size) {
    _chartRect = Rect.fromLTWH(
      _kMarginL, _kMarginT,
      (size.width - _kMarginL - _kMarginR).clamp(100, double.infinity),
      (size.height - _kMarginT - _kMarginB).clamp(50, double.infinity),
    );
    _xScale = _chartRect.width / buffer.capacity;

    _drawBackground(canvas);
    _drawGrid(canvas);

    for (final ch in buffer.electrodes) {
      _drawChannel(canvas, ch);
    }

    _drawCursor(canvas);
    _drawBorder(canvas);
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

    final yLines = _niceGridValues(-100, 100, _chartRect.height, 40);
    for (final v in yLines) {
      final py = _chartRect.center.dy - v / 200 * _chartRect.height;
      canvas.drawLine(
        Offset(_chartRect.left, py),
        Offset(_chartRect.right, py),
        paint,
      );
    }

    final xLines = _niceGridValues(0, buffer.capacity.toDouble(), _chartRect.width, 60);
    for (final v in xLines) {
      final px = _chartRect.left + v * _xScale;
      canvas.drawLine(
        Offset(px, _chartRect.top),
        Offset(px, _chartRect.bottom),
        paint,
      );
    }
  }

  void _drawChannel(Canvas canvas, int electrode) {
    final buf = buffer.getChannel(electrode);
    if (buf == null || buf.isEmpty) return;

    final color = _kChannelColors[electrode % _kChannelColors.length];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    bool visibleSamples = false;
    final path = Path();
    final visibleStart = frozen ? panOffset : 0;
    final visibleEnd = frozen
        ? (visibleStart + (_chartRect.width / _xScale).ceil()).toInt()
        : buffer.cursor;

    for (int i = visibleStart; i < visibleEnd && i < buffer.capacity; i++) {
      final s = buf[i];
      if (!_sampleValid(s)) continue;
      final x = _chartRect.left + (i - visibleStart) * _xScale;
      final y = _chartRect.center.dy - s / 200 * _chartRect.height;
      if (!visibleSamples) {
        visibleSamples = true;
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (visibleSamples) canvas.drawPath(path, paint);
  }

  void _drawCursor(Canvas canvas) {
    final cursorPos = frozen ? 0 : buffer.cursor;
    final cx = _chartRect.left + cursorPos * _xScale;

    final paint = Paint()
      ..color = frozen
          ? const Color(0xFF555555)
          : const Color(0xFF88FF88)
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

  bool _sampleValid(double v) => v.abs() < 1e6;

  @override
  bool shouldRepaint(_SweepPainter old) => true;

  List<double> _niceGridValues(double min, double max, double pxSpan, double minPx) {
    final range = max - min;
    if (range <= 0 || pxSpan <= 0) return [];
    final ideal = pxSpan / minPx;
    final rough = range / ideal;
    final step = _niceStep(rough);
    if (step <= 0) return [];
    final start = (min / step).ceil() * step;
    final result = <double>[];
    for (double v = start; v <= max; v += step) { result.add(v); }
    return result;
  }

  double _niceStep(double r) {
    final exp = math.pow(10, (math.log(r) / math.ln10).floor()).toDouble();
    final frac = r / exp;
    return exp * (frac <= 1.5 ? 1 : frac <= 3.5 ? 2 : frac <= 7.5 ? 5 : 10);
  }
}
