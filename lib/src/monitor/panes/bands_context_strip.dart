import 'package:flutter/material.dart';
import 'package:muse_ml/src/monitor/empty_state.dart';
import 'package:muse_ml/src/monitor/graph_cinema.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

/// Histogram/PSD vs Bands strip height. Not a user setting.
const int kHistogramPsdPrimaryFlex = 7;
const int kBandsContextStripFlex = 3;

class HistogramPsdSplit extends StatelessWidget {
  const HistogramPsdSplit({
    super.key,
    required this.primary,
    required this.strip,
  });

  final Widget primary;
  final Widget strip;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: kHistogramPsdPrimaryFlex, child: primary),
        Expanded(flex: kBandsContextStripFlex, child: strip),
      ],
    );
  }
}

class BandsContextStrip extends StatefulWidget {
  const BandsContextStrip({
    super.key,
    required this.stripViewport,
    required this.epochViewport,
    required this.series,
    required this.stripNewestElapsed,
    required this.stripOldestElapsed,
    required this.highlightStartElapsed,
    required this.highlightEndElapsed,
    required this.connected,
    this.waiting = false,
  });

  final ViewportController stripViewport;
  final ViewportController epochViewport;
  final List<List<BandPoint>> series;
  final double stripNewestElapsed;
  final double stripOldestElapsed;
  final double highlightStartElapsed;
  final double highlightEndElapsed;
  final bool connected;
  final bool waiting;

  @override
  State<BandsContextStrip> createState() => _BandsContextStripState();
}

class _BandsContextStripState extends State<BandsContextStrip> {
  double _pinchWindowAtStart = ViewportController.bandsDefaultWindowSeconds;
  double _pinchFocalElapsed = 0;
  double _pinchFocalFraction = 0.5;

  ViewportController get _strip => widget.stripViewport;
  ViewportController get _epoch => widget.epochViewport;

  void _align() {
    alignEpochToContext(
      epoch: _epoch,
      context: _strip,
      contextNewestElapsed: widget.stripNewestElapsed,
      contextOldestElapsed: widget.stripOldestElapsed,
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    final newest = widget.stripNewestElapsed;
    if (_strip.mode == ViewportMode.follow) {
      _strip.enterInspectStrip(newestElapsed: newest);
    }
    _pinchWindowAtStart = _strip.windowSeconds;
    final w = context.size?.width ?? 1;
    final chartW =
        (w - TimeSeriesPanePainter.yGutter - TimeSeriesPanePainter.legendGutter)
            .clamp(1, w);
    final x = d.localFocalPoint.dx - TimeSeriesPanePainter.yGutter;
    _pinchFocalFraction = (x / chartW).clamp(0.0, 1.0);
    _pinchFocalElapsed =
        _strip.stripVisibleStart(newestElapsed: newest) +
        _pinchFocalFraction * _strip.windowSeconds;
    _align();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final newest = widget.stripNewestElapsed;
    if (d.pointerCount >= 2) {
      _strip.pinchX(
        scaleFromStart: d.scale,
        windowAtStart: _pinchWindowAtStart,
        focalElapsed: _pinchFocalElapsed,
        focalFraction: _pinchFocalFraction,
        newestElapsed: newest,
        elapsedCap: newest,
        oldestElapsed: widget.stripOldestElapsed,
        zoomFloor: bandsContextZoomFloor(_epoch.windowSeconds),
        zoomCap: ViewportController.bandsZoomCap,
      );
      _align();
      return;
    }
    if (d.pointerCount != 1) return;
    final w = context.size?.width ?? 1;
    if (w <= 0) return;
    _strip.panStrip(
      -d.focalPointDelta.dx / w * _strip.windowSeconds,
      newestElapsed: newest,
      oldestElapsed: widget.stripOldestElapsed,
    );
    _align();
  }

  void _setStripWindow(double seconds) {
    var next = seconds;
    final floor = bandsContextZoomFloor(_epoch.windowSeconds);
    if (next < floor) next = floor;
    _strip.setStripWindowSeconds(
      next,
      newestElapsed: widget.stripNewestElapsed,
    );
    _align();
  }

  @override
  Widget build(BuildContext context) {
    final cinema = GraphCinema.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: TimeSeriesPane(
              series: widget.series,
              viewport: _strip,
              newestElapsed: widget.stripNewestElapsed,
              connected: widget.connected,
              highlightStartElapsed: widget.highlightStartElapsed,
              highlightEndElapsed: widget.highlightEndElapsed,
            ),
          ),
        ),
        if (widget.waiting)
          const Positioned.fill(child: MonitorWaitingSignal()),
        if (!cinema)
          Positioned(
            left: TimeSeriesPanePainter.yGutter,
            top: 0,
            child: _StripWindowMenu(
              viewport: _strip,
              epochSeconds: _epoch.windowSeconds,
              onChanged: _setStripWindow,
            ),
          ),
      ],
    );
  }
}

class _StripWindowMenu extends StatelessWidget {
  const _StripWindowMenu({
    required this.viewport,
    required this.epochSeconds,
    required this.onChanged,
  });

  final ViewportController viewport;
  final double epochSeconds;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final floor = bandsContextZoomFloor(epochSeconds);
    final options = [
      for (final s in ViewportController.bandsWindowOptions)
        if (s + 1e-9 >= floor) s,
    ];
    return Tooltip(
      message: 'Bands window',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          key: const ValueKey('bands-context-window'),
          value: presetOrCustomValue(viewport.windowSeconds, options),
          isDense: true,
          items: [
            for (final s in options)
              DropdownMenuItem(value: s, child: Text(formatWindowSeconds(s))),
            if (!windowIsPreset(viewport.windowSeconds, options))
              DropdownMenuItem(
                value: viewport.windowSeconds,
                child: const Text('custom'),
              ),
          ],
          onChanged: (v) {
            if (v == null || v == viewport.windowSeconds) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}
