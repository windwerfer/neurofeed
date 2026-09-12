import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';
import 'package:muse_ml/src/monitor/empty_state.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

class BandsView extends ConsumerStatefulWidget {
  const BandsView({super.key});

  @override
  ConsumerState<BandsView> createState() => _BandsViewState();
}

class _BandsViewState extends ConsumerState<BandsView> {
  final ViewportController _viewport = ViewportController()
    ..windowSeconds = ViewportController.bandsDefaultWindowSeconds;

  Set<int> _selected = {};
  int _montageLen = 0;
  double _pinchWindowAtStart = ViewportController.bandsDefaultWindowSeconds;
  double _pinchFocalElapsed = 0;
  double _pinchFocalFraction = 0.5;

  @override
  void initState() {
    super.initState();
    ref.read(monitorControllerProvider.notifier).bandCache.addListener(_onTick);
    _viewport.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mon.bandCache.removeListener(_onTick);
    _viewport.removeListener(_onTick);
    _viewport.dispose();
    super.dispose();
  }

  MonitorController get _mon => ref.read(monitorControllerProvider.notifier);

  void _syncMontage(List<String> names) {
    if (names.length == _montageLen &&
        _selected.isNotEmpty &&
        _selected.every((i) => i >= 0 && i < names.length)) {
      return;
    }
    _montageLen = names.length;
    _selected = allElectrodeIndices(names.length);
  }

  double _newestElapsed() {
    final cache = _mon.bandCache;
    final startMs = ref.read(monitorControllerProvider).captureStartedAtMs;
    if (!cache.hasData) return 0;
    return cache.latestTimestamp - bandOriginUnix(cache, startMs);
  }

  double _oldestElapsed() {
    final cache = _mon.bandCache;
    final startMs = ref.read(monitorControllerProvider).captureStartedAtMs;
    if (!cache.hasData) return 0;
    final origin = bandOriginUnix(cache, startMs);
    var oldest = cache.oldestTimestamp - origin;
    if (oldest < 0) oldest = 0;
    return oldest;
  }

  void _follow() => _viewport.followStrip();

  void _inspect() =>
      _viewport.enterInspectStrip(newestElapsed: _newestElapsed());

  void _onScaleStart(ScaleStartDetails d) {
    final newest = _newestElapsed();
    if (_viewport.mode == ViewportMode.follow) {
      _viewport.enterInspectStrip(newestElapsed: newest);
    }
    _pinchWindowAtStart = _viewport.windowSeconds;
    final w = context.size?.width ?? 1;
    final chartW =
        (w - TimeSeriesPanePainter.yGutter - TimeSeriesPanePainter.legendGutter)
            .clamp(1, w);
    final x = d.localFocalPoint.dx - TimeSeriesPanePainter.yGutter;
    _pinchFocalFraction = (x / chartW).clamp(0.0, 1.0);
    _pinchFocalElapsed =
        _viewport.stripVisibleStart(newestElapsed: newest) +
        _pinchFocalFraction * _viewport.windowSeconds;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final newest = _newestElapsed();
    if (d.pointerCount >= 2) {
      _viewport.pinchX(
        scaleFromStart: d.scale,
        windowAtStart: _pinchWindowAtStart,
        focalElapsed: _pinchFocalElapsed,
        focalFraction: _pinchFocalFraction,
        newestElapsed: newest,
        elapsedCap: newest,
        oldestElapsed: _oldestElapsed(),
      );
      return;
    }
    if (d.pointerCount != 1) return;
    final w = context.size?.width ?? 1;
    if (w <= 0) return;
    _viewport.panStrip(
      -d.focalPointDelta.dx / w * _viewport.windowSeconds,
      newestElapsed: newest,
      oldestElapsed: _oldestElapsed(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorControllerProvider);
    final app = ref.watch(appStateProvider);
    ref.listen(appStateProvider.select((s) => s.status.connected), (
      prev,
      next,
    ) {
      if (next != true) _follow();
    });
    final connected = app.status.connected;
    final names = state.electrodeNames;
    _syncMontage(names);
    final cache = _mon.bandCache;
    final newest = _newestElapsed();
    final start = _viewport.stripVisibleStart(newestElapsed: newest);
    final end = _viewport.stripVisibleEnd(newestElapsed: newest);
    final series = connected
        ? buildBandSeries(
            cache: cache,
            electrodes: _selected,
            startElapsed: start,
            endElapsed: end,
            captureStartedAtMs: state.captureStartedAtMs,
          )
        : [for (var i = 0; i < bandNames.length; i++) <BandPoint>[]];

    return GraphShell(
      title: 'Bands',
      showRecord: true,
      viewport: _viewport,
      windowOptions: ViewportController.bandsWindowOptions,
      onFollow: _follow,
      onInspect: _inspect,
      onWindowChanged: (s) =>
          _viewport.setStripWindowSeconds(s, newestElapsed: newest),
      toolbarExtras: ElectrodeToggles(
        names: names,
        selected: _selected,
        onToggle: (i) {
          setState(() {
            _selected = toggleAverageElectrode(_selected, i);
          });
        },
      ),
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: Stack(
          children: [
            Positioned.fill(
              child: TimeSeriesPane(
                series: series,
                viewport: _viewport,
                newestElapsed: newest,
                connected: connected,
              ),
            ),
            if (connected && !cache.hasData)
              const Positioned.fill(child: MonitorWaitingSignal()),
          ],
        ),
      ),
    );
  }
}
