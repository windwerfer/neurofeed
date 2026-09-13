import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';
import 'package:muse_ml/src/monitor/empty_state.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/panes/bands_context_strip.dart';
import 'package:muse_ml/src/monitor/panes/histogram_pane.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

enum HistogramUvRange { uv50, uv100, uv200 }

class HistogramView extends ConsumerStatefulWidget {
  const HistogramView({super.key});

  @override
  ConsumerState<HistogramView> createState() => _HistogramViewState();
}

class _HistogramViewState extends ConsumerState<HistogramView> {
  final ViewportController _viewport = ViewportController()
    ..windowSeconds = ViewportController.histogramDefaultWindowSeconds;
  final ViewportController _strip = ViewportController()
    ..windowSeconds = ViewportController.bandsDefaultWindowSeconds
    ..followLeadSeconds = ViewportController.bandsFollowLeadSeconds;

  Set<int> _selected = {};
  int _montageLen = 0;
  HistogramUvRange _uv = HistogramUvRange.uv100;
  double? _hairlineUv;

  @override
  void initState() {
    super.initState();
    final mon = ref.read(monitorControllerProvider.notifier);
    mon.sweepBuffer.addListener(_onTick);
    mon.bandCache.addListener(_onTick);
    _viewport.addListener(_onTick);
    _strip.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mon.sweepBuffer.removeListener(_onTick);
    _mon.bandCache.removeListener(_onTick);
    _viewport.removeListener(_onTick);
    _strip.removeListener(_onTick);
    _viewport.dispose();
    _strip.dispose();
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

  double _newestElapsed() =>
      sweepNewestElapsed(_mon.sweepBuffer, _mon.ramNewestElapsed);

  double _bandNewest() {
    final cache = _mon.bandCache;
    final startMs = ref.read(monitorControllerProvider).captureStartedAtMs;
    if (!cache.hasData) return _newestElapsed();
    return cache.latestTimestamp - bandOriginUnix(cache, startMs);
  }

  double _bandOldest() {
    final cache = _mon.bandCache;
    final startMs = ref.read(monitorControllerProvider).captureStartedAtMs;
    if (!cache.hasData) return 0;
    final origin = bandOriginUnix(cache, startMs);
    var oldest = cache.oldestTimestamp - origin;
    if (oldest < 0) oldest = 0;
    return oldest;
  }

  double get _halfRange {
    switch (_uv) {
      case HistogramUvRange.uv50:
        return 50;
      case HistogramUvRange.uv100:
        return 100;
      case HistogramUvRange.uv200:
        return 200;
    }
  }

  void _follow() {
    _strip.followStrip();
    _viewport.followStrip();
  }

  void _inspect() {
    _strip.enterInspectStrip(newestElapsed: _bandNewest());
    alignEpochToContext(
      epoch: _viewport,
      context: _strip,
      contextNewestElapsed: _bandNewest(),
      contextOldestElapsed: _bandOldest(),
    );
  }

  void _onWindowChanged(double seconds) {
    final newest = _newestElapsed();
    _viewport.setStripWindowSeconds(seconds, newestElapsed: newest);
    ensureContextCoversEpoch(
      context: _strip,
      epochSeconds: seconds,
      newestElapsed: _bandNewest(),
    );
    if (_strip.mode == ViewportMode.inspect) {
      alignEpochToContext(
        epoch: _viewport,
        context: _strip,
        contextNewestElapsed: _bandNewest(),
        contextOldestElapsed: _bandOldest(),
      );
    }
  }

  Widget _uvMenu(BuildContext context) {
    final label = '±${_halfRange.round()} µV';
    return PopupMenuButton<HistogramUvRange>(
      tooltip: 'µV range',
      initialValue: _uv,
      onSelected: (v) => setState(() => _uv = v),
      itemBuilder: (context) => const [
        PopupMenuItem(value: HistogramUvRange.uv50, child: Text('±50 µV')),
        PopupMenuItem(value: HistogramUvRange.uv100, child: Text('±100 µV')),
        PopupMenuItem(value: HistogramUvRange.uv200, child: Text('±200 µV')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
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
    final buffer = _mon.sweepBuffer;
    final newest = _newestElapsed();
    final start = _viewport.stripVisibleStart(newestElapsed: newest);
    final end = _viewport.stripVisibleEnd(newestElapsed: newest);
    final samples = connected
        ? meanEegWindow(
            buffer: buffer,
            electrodes: _selected,
            startElapsed: start,
            endElapsed: end,
            newestElapsed: _mon.ramNewestElapsed ?? newest,
          )
        : const <double>[];
    final counts = histogramCounts(samples, halfRange: _halfRange);
    final inspectLabel = _viewport.mode == ViewportMode.inspect
        ? '${formatElapsed(start)}–${formatElapsed(end)}'
        : null;
    final bandNewest = _bandNewest();
    final bandOldest = _bandOldest();
    final stripStart = _strip.stripVisibleStart(newestElapsed: bandNewest);
    final stripEnd = _strip.stripVisibleEnd(newestElapsed: bandNewest);
    final series = connected
        ? buildBandSeries(
            cache: _mon.bandCache,
            electrodes: _selected,
            startElapsed: stripStart,
            endElapsed: stripEnd,
            captureStartedAtMs: state.captureStartedAtMs,
          )
        : [for (var i = 0; i < bandNames.length; i++) <BandPoint>[]];

    return GraphShell(
      title: 'Histogram',
      showRecord: true,
      viewport: _viewport,
      windowOptions: ViewportController.histogramPsdWindowOptions,
      onFollow: _follow,
      onInspect: _inspect,
      onWindowChanged: _onWindowChanged,
      inspectRangeLabel: inspectLabel,
      toolbarMiddle: _uvMenu(context),
      toolbarExtras: ElectrodeToggles(
        names: names,
        selected: _selected,
        onToggle: (i) {
          setState(() {
            _selected = toggleAverageElectrode(_selected, i);
          });
        },
      ),
      body: HistogramPsdSplit(
        primary: Stack(
          children: [
            Positioned.fill(
              child: HistogramPane(
                counts: counts,
                halfRange: _halfRange,
                connected: connected,
                hairlineUv: _hairlineUv,
                onTapUv: (uv) => setState(() => _hairlineUv = uv),
              ),
            ),
            if (connected && !buffer.hasData)
              const Positioned.fill(child: MonitorWaitingSignal()),
          ],
        ),
        strip: BandsContextStrip(
          stripViewport: _strip,
          epochViewport: _viewport,
          series: series,
          stripNewestElapsed: bandNewest,
          stripOldestElapsed: bandOldest,
          highlightStartElapsed: start,
          highlightEndElapsed: end,
          connected: connected,
          waiting: connected && !_mon.bandCache.hasData,
        ),
      ),
    );
  }
}
