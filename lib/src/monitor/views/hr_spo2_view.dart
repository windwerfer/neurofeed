import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/charts/eeg_data_source.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/monitor/cache/optical_cache.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/monitor/empty_state.dart';
import 'package:neurofeed/src/monitor/graph_cinema.dart';
import 'package:neurofeed/src/monitor/graph_shell.dart';
import 'package:neurofeed/src/monitor/monitor_controller.dart';
import 'package:neurofeed/src/monitor/monitor_providers.dart';
import 'package:neurofeed/src/monitor/panes/optical_overview_pane.dart';
import 'package:neurofeed/src/monitor/panes/optical_ppg_pane.dart';
import 'package:neurofeed/src/monitor/panes/time_series_pane.dart';
import 'package:neurofeed/src/monitor/viewport_controller.dart';
import 'package:neurofeed/src/settings.dart';

const String kHrSpo2WindowKey = 'hrSpo2';
const String kHrSpo2DetailWindowKey = 'hrSpo2';

const int kOpticalOverviewFlex = 6;
const int kOpticalDetailFlex = 4;

class HrSpo2View extends ConsumerStatefulWidget {
  const HrSpo2View({super.key});

  @override
  ConsumerState<HrSpo2View> createState() => _HrSpo2ViewState();
}

class _HrSpo2ViewState extends ConsumerState<HrSpo2View> {
  final ViewportController _overview = ViewportController()
    ..windowSeconds = ViewportController.opticalOverviewDefaultWindowSeconds
    ..followLeadSeconds = ViewportController.bandsFollowLeadSeconds;
  final ViewportController _detail = ViewportController()
    ..windowSeconds = ViewportController.opticalDetailDefaultWindowSeconds;

  double _pinchWindowAtStart =
      ViewportController.opticalOverviewDefaultWindowSeconds;
  double _pinchFocalElapsed = 0;
  double _pinchFocalFraction = 0.5;
  bool _pinchOnDetail = false;
  bool _draggingHighlight = false;
  double? _cursorElapsed;
  late final MonitorController _mon;

  @override
  void initState() {
    super.initState();
    _mon = ref.read(monitorControllerProvider.notifier);
    _hydrateWindows();
    _overview.addListener(_onViewport);
    _detail.addListener(_onViewport);
  }

  void _hydrateWindows() {
    final settings = ref.read(settingsProvider);
    final top = settings.monitorWindowSeconds(kHrSpo2WindowKey);
    if (top != null && top > 0) {
      _overview.windowSeconds = top;
    }
    final bottom = settings.monitorDetailWindowSeconds(kHrSpo2DetailWindowKey);
    if (bottom != null && bottom > 0) {
      _detail.windowSeconds = bottom;
    }
    clampDetailToOverview(
      detail: _detail,
      overview: _overview,
      newestElapsed: 0,
    );
  }

  void _persistOverviewWindow() {
    ref
        .read(settingsProvider)
        .setMonitorWindowSeconds(kHrSpo2WindowKey, _overview.windowSeconds);
  }

  void _persistDetailWindow() {
    ref
        .read(settingsProvider)
        .setMonitorDetailWindowSeconds(
          kHrSpo2DetailWindowKey,
          _detail.windowSeconds,
        );
  }

  void _onViewport() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overview.removeListener(_onViewport);
    _detail.removeListener(_onViewport);
    _overview.dispose();
    _detail.dispose();
    super.dispose();
  }

  double _newestElapsed() {
    final cache = _mon.opticalCache;
    final startMs = ref.read(monitorControllerProvider).captureStartedAtMs;
    if (!cache.hasData) return 0;
    return cache.latestTimestamp - opticalOriginUnix(cache, startMs);
  }

  double _oldestElapsed() {
    final cache = _mon.opticalCache;
    final startMs = ref.read(monitorControllerProvider).captureStartedAtMs;
    if (!cache.hasData) return 0;
    final origin = opticalOriginUnix(cache, startMs);
    var oldest = cache.oldestTimestamp - origin;
    if (oldest < 0) oldest = 0;
    return oldest;
  }

  void _follow() {
    _overview.followStrip();
    _detail.followStrip();
  }

  void _inspect() {
    final newest = _newestElapsed();
    _overview.enterInspectStrip(newestElapsed: newest);
    alignDetailToOverview(
      detail: _detail,
      overview: _overview,
      newestElapsed: newest,
      oldestElapsed: _oldestElapsed(),
    );
  }

  void _onOverviewWindowChanged(double seconds) {
    final newest = _newestElapsed();
    _overview.setStripWindowSeconds(seconds, newestElapsed: newest);
    clampDetailToOverview(
      detail: _detail,
      overview: _overview,
      newestElapsed: newest,
    );
    if (_overview.mode == ViewportMode.inspect) {
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: _oldestElapsed(),
      );
    }
    _persistOverviewWindow();
    _persistDetailWindow();
  }

  void _onDetailWindowChanged(double seconds) {
    final newest = _newestElapsed();
    var next = seconds;
    if (next > _overview.windowSeconds) next = _overview.windowSeconds;
    _detail.setStripWindowSeconds(next, newestElapsed: newest);
    ensureOverviewCoversDetail(
      overview: _overview,
      detailSeconds: next,
      newestElapsed: newest,
    );
    if (_overview.mode == ViewportMode.inspect) {
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: _oldestElapsed(),
      );
    }
    _persistDetailWindow();
    _persistOverviewWindow();
  }

  void _beginPinch(ScaleStartDetails d, {required bool detail}) {
    final newest = _newestElapsed();
    final oldest = _oldestElapsed();
    _pinchOnDetail = detail;
    _draggingHighlight = false;
    final vp = detail ? _detail : _overview;
    final w = context.size?.width ?? 1;
    final gutter = detail
        ? OpticalPpgPainter.leftGutter
        : OpticalOverviewPainter.leftGutter;
    final right = detail
        ? OpticalPpgPainter.rightGutter
        : OpticalOverviewPainter.rightGutter;
    final chartW = (w - gutter - right).clamp(1.0, w);
    final x = d.localFocalPoint.dx - gutter;

    if (!detail && _overview.mode == ViewportMode.inspect) {
      final ovStart = _overview.stripVisibleStart(newestElapsed: newest);
      final ovEnd = _overview.stripVisibleEnd(newestElapsed: newest);
      final hiStart = _detail.stripVisibleStart(newestElapsed: newest);
      final hiEnd = _detail.stripVisibleEnd(newestElapsed: newest);
      if (highlightHitTest(
        localX: d.localFocalPoint.dx,
        chartLeft: gutter,
        chartWidth: chartW,
        visStart: ovStart,
        visEnd: ovEnd,
        highlightStart: hiStart,
        highlightEnd: hiEnd,
      )) {
        _draggingHighlight = true;
        panDetailWithinOverview(
          detail: _detail,
          overview: _overview,
          deltaSeconds: 0,
          newestElapsed: newest,
          oldestElapsed: oldest,
          highlightEndElapsed: hiEnd,
        );
        _pinchWindowAtStart = _detail.windowSeconds;
        _pinchFocalFraction = (x / chartW).clamp(0.0, 1.0);
        _pinchFocalElapsed =
            hiStart + _pinchFocalFraction * _detail.windowSeconds;
        return;
      }
    }

    if (_overview.mode == ViewportMode.follow) {
      _overview.enterInspectStrip(newestElapsed: newest);
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: oldest,
      );
    }
    _pinchWindowAtStart = vp.windowSeconds;
    _pinchFocalFraction = (x / chartW).clamp(0.0, 1.0);
    _pinchFocalElapsed =
        vp.stripVisibleStart(newestElapsed: newest) +
        _pinchFocalFraction * vp.windowSeconds;
  }

  void _updatePinch(ScaleUpdateDetails d) {
    final newest = _newestElapsed();
    final oldest = _oldestElapsed();
    if (d.pointerCount >= 2) {
      _draggingHighlight = false;
      if (_pinchOnDetail) {
        _detail.pinchX(
          scaleFromStart: d.scale,
          windowAtStart: _pinchWindowAtStart,
          focalElapsed: _pinchFocalElapsed,
          focalFraction: _pinchFocalFraction,
          newestElapsed: newest,
          elapsedCap: math.min(newest, _overview.windowSeconds),
          oldestElapsed: oldest,
          zoomFloor: ViewportController.opticalDetailZoomFloor,
          zoomCap: math.min(
            ViewportController.opticalDetailZoomCap,
            _overview.windowSeconds,
          ),
        );
        ensureOverviewCoversDetail(
          overview: _overview,
          detailSeconds: _detail.windowSeconds,
          newestElapsed: newest,
        );
        _persistDetailWindow();
      } else {
        _overview.pinchX(
          scaleFromStart: d.scale,
          windowAtStart: _pinchWindowAtStart,
          focalElapsed: _pinchFocalElapsed,
          focalFraction: _pinchFocalFraction,
          newestElapsed: newest,
          elapsedCap: newest,
          oldestElapsed: oldest,
          zoomFloor: ViewportController.bandsZoomFloor,
          zoomCap: ViewportController.bandsZoomCap,
        );
        clampDetailToOverview(
          detail: _detail,
          overview: _overview,
          newestElapsed: newest,
        );
        alignDetailToOverview(
          detail: _detail,
          overview: _overview,
          newestElapsed: newest,
          oldestElapsed: oldest,
        );
        _persistOverviewWindow();
        _persistDetailWindow();
      }
      return;
    }
    if (d.pointerCount != 1) return;
    final w = context.size?.width ?? 1;
    if (w <= 0) return;
    if (_draggingHighlight) {
      final chartW =
          (w -
                  OpticalOverviewPainter.leftGutter -
                  OpticalOverviewPainter.rightGutter)
              .clamp(1.0, w);
      final delta = d.focalPointDelta.dx / chartW * _overview.windowSeconds;
      panDetailWithinOverview(
        detail: _detail,
        overview: _overview,
        deltaSeconds: delta,
        newestElapsed: newest,
        oldestElapsed: oldest,
      );
      return;
    }
    final vp = _pinchOnDetail ? _detail : _overview;
    final delta = -d.focalPointDelta.dx / w * vp.windowSeconds;
    if (_pinchOnDetail) {
      if (_overview.mode == ViewportMode.follow) {
        _overview.enterInspectStrip(newestElapsed: newest);
      }
      // Pan overview so detail stays locked to its right edge.
      _overview.panStrip(delta, newestElapsed: newest, oldestElapsed: oldest);
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: oldest,
      );
    } else {
      _overview.panStrip(delta, newestElapsed: newest, oldestElapsed: oldest);
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: oldest,
      );
    }
  }

  void _onPointerSignal(PointerSignalEvent e, {required bool detail}) {
    final kb = HardwareKeyboard.instance;
    if (e is! PointerScrollEvent) return;
    if (!kb.isControlPressed && !kb.isMetaPressed) return;
    final newest = _newestElapsed();
    final oldest = _oldestElapsed();
    final vp = detail ? _detail : _overview;
    if (_overview.mode == ViewportMode.follow) {
      _overview.enterInspectStrip(newestElapsed: newest);
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: oldest,
      );
    }
    final factor = math.exp(e.scrollDelta.dy * 0.002);
    final box = context.findRenderObject() as RenderBox?;
    final w = box?.size.width ?? 1.0;
    final gutter = detail
        ? OpticalPpgPainter.leftGutter
        : OpticalOverviewPainter.leftGutter;
    final right = detail
        ? OpticalPpgPainter.rightGutter
        : OpticalOverviewPainter.rightGutter;
    final chartW = (w - gutter - right).clamp(1.0, w);
    final local = box?.globalToLocal(e.position);
    final x = (local?.dx ?? w / 2) - gutter;
    final focalFraction = (x / chartW).clamp(0.0, 1.0);
    final focalElapsed =
        vp.stripVisibleStart(newestElapsed: newest) +
        focalFraction * vp.windowSeconds;
    if (detail) {
      _detail.pinchX(
        scaleFromStart: 1 / factor,
        windowAtStart: _detail.windowSeconds,
        focalElapsed: focalElapsed,
        focalFraction: focalFraction,
        newestElapsed: newest,
        elapsedCap: math.min(newest, _overview.windowSeconds),
        oldestElapsed: oldest,
        zoomFloor: ViewportController.opticalDetailZoomFloor,
        zoomCap: math.min(
          ViewportController.opticalDetailZoomCap,
          _overview.windowSeconds,
        ),
      );
      ensureOverviewCoversDetail(
        overview: _overview,
        detailSeconds: _detail.windowSeconds,
        newestElapsed: newest,
      );
      _persistDetailWindow();
    } else {
      _overview.pinchX(
        scaleFromStart: 1 / factor,
        windowAtStart: _overview.windowSeconds,
        focalElapsed: focalElapsed,
        focalFraction: focalFraction,
        newestElapsed: newest,
        elapsedCap: newest,
        oldestElapsed: oldest,
        zoomFloor: ViewportController.bandsZoomFloor,
        zoomCap: ViewportController.bandsZoomCap,
      );
      clampDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
      );
      alignDetailToOverview(
        detail: _detail,
        overview: _overview,
        newestElapsed: newest,
        oldestElapsed: oldest,
      );
      _persistOverviewWindow();
      _persistDetailWindow();
    }
  }

  List<ChartSample> _elapsedSeries(
    List<ChartSample> unixSamples,
    double origin,
  ) => [for (final s in unixSamples) ChartSample(s.t - origin, s.v)];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorControllerProvider);
    final connected = ref.watch(
      appStateProvider.select((s) => s.status.connected),
    );
    final kind = ref.watch(appStateProvider.select((s) => s.lastConnectedKind));
    ref.listen(appStateProvider.select((s) => s.status.connected), (
      prev,
      next,
    ) {
      if (next != true) _follow();
    });
    listenLiveGraphBoundary(
      ref,
      resetAnchors: () {
        _overview.resetFollowAnchors();
        _detail.resetFollowAnchors();
      },
      resumeFollow: _follow,
    );

    final hasPpg = deviceHasPpg(kind);
    final newest = _newestElapsed();
    final inspectLabel = _overview.mode == ViewportMode.inspect
        ? '${formatElapsed(_overview.stripVisibleStart(newestElapsed: newest))}–${formatElapsed(_overview.stripVisibleEnd(newestElapsed: newest))}'
        : null;

    return GraphShell(
      title: 'HR+SpO2',
      showRecord: true,
      viewport: _overview,
      windowOptions: ViewportController.opticalOverviewWindowOptions,
      onFollow: _follow,
      onInspect: _inspect,
      onWindowChanged: _onOverviewWindowChanged,
      inspectRangeLabel: inspectLabel,
      body: !hasPpg
          ? const MonitorNoPpg()
          : Column(
              children: [
                Expanded(
                  flex: kOpticalOverviewFlex,
                  child: Listener(
                    onPointerSignal: (e) => _onPointerSignal(e, detail: false),
                    child: GestureDetector(
                      onScaleStart: (d) => _beginPinch(d, detail: false),
                      onScaleUpdate: _updatePinch,
                      child: ListenableBuilder(
                        listenable: _mon.opticalCache,
                        builder: (context, _) {
                          final cache = _mon.opticalCache;
                          final origin = opticalOriginUnix(
                            cache,
                            state.captureStartedAtMs,
                          );
                          final n = _newestElapsed();
                          final start = _overview.stripVisibleStart(
                            newestElapsed: n,
                          );
                          final end = _overview.stripVisibleEnd(
                            newestElapsed: n,
                          );
                          const pad = 1.0;
                          final hr = connected
                              ? _elapsedSeries(
                                  cache.pulseRange(
                                    origin + start - pad,
                                    origin + end + pad,
                                  ),
                                  origin,
                                )
                              : const <ChartSample>[];
                          final spo2 = connected
                              ? _elapsedSeries(
                                  cache.spo2Range(
                                    origin + start - pad,
                                    origin + end + pad,
                                  ),
                                  origin,
                                )
                              : const <ChartSample>[];
                          final detailStart = _detail.stripVisibleStart(
                            newestElapsed: n,
                          );
                          final detailEnd = _detail.stripVisibleEnd(
                            newestElapsed: n,
                          );
                          final showHighlight =
                              _overview.mode == ViewportMode.inspect;
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: OpticalOverviewPane(
                                  hr: hr,
                                  spo2: spo2,
                                  viewport: _overview,
                                  newestElapsed: n,
                                  connected: connected,
                                  avgHr: cache.avgHr,
                                  highlightStartElapsed: showHighlight
                                      ? detailStart
                                      : null,
                                  highlightEndElapsed: showHighlight
                                      ? detailEnd
                                      : null,
                                  cursorElapsed: _cursorElapsed,
                                  onTapElapsed: (t) =>
                                      setState(() => _cursorElapsed = t),
                                ),
                              ),
                              if (connected && !cache.hasData)
                                const Positioned.fill(
                                  child: MonitorWaitingSignal(),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: kOpticalDetailFlex,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Listener(
                          onPointerSignal: (e) =>
                              _onPointerSignal(e, detail: true),
                          child: GestureDetector(
                            onScaleStart: (d) => _beginPinch(d, detail: true),
                            onScaleUpdate: _updatePinch,
                            child: ListenableBuilder(
                              listenable: _mon.opticalCache,
                              builder: (context, _) {
                                final cache = _mon.opticalCache;
                                final origin = opticalOriginUnix(
                                  cache,
                                  state.captureStartedAtMs,
                                );
                                final n = _newestElapsed();
                                final sweep =
                                    _detail.mode == ViewportMode.follow &&
                                    _overview.mode == ViewportMode.follow;
                                final start = sweep
                                    ? n - _detail.windowSeconds
                                    : _detail.stripVisibleStart(
                                        newestElapsed: n,
                                      );
                                final end = sweep
                                    ? n
                                    : _detail.stripVisibleEnd(newestElapsed: n);
                                const pad = 0.25;
                                final ppg = connected
                                    ? _elapsedSeries(
                                        cache.ppgIrRange(
                                          origin + start - pad,
                                          origin + end + pad,
                                        ),
                                        origin,
                                      )
                                    : const <ChartSample>[];
                                return OpticalPpgPane(
                                  samples: ppg,
                                  viewport: _detail,
                                  newestElapsed: n,
                                  connected: connected,
                                  cursorElapsed: _cursorElapsed,
                                  onTapElapsed: (t) =>
                                      setState(() => _cursorElapsed = t),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (!GraphCinema.of(context))
                        Positioned(
                          left: 8,
                          top: 0,
                          child: _DetailWindowMenu(
                            viewport: _detail,
                            overviewSeconds: _overview.windowSeconds,
                            onChanged: _onDetailWindowChanged,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _DetailWindowMenu extends StatelessWidget {
  const _DetailWindowMenu({
    required this.viewport,
    required this.overviewSeconds,
    required this.onChanged,
  });

  final ViewportController viewport;
  final double overviewSeconds;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <double>[
      for (final s in ViewportController.opticalDetailWindowOptions)
        if (s <= overviewSeconds + 1e-9) s,
    ];
    if (options.isEmpty) {
      options.add(
        math.min(
          ViewportController.opticalDetailDefaultWindowSeconds,
          overviewSeconds,
        ),
      );
    }
    return Tooltip(
      message: 'IR PPG window',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          key: const ValueKey('hr-spo2-detail-window'),
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
