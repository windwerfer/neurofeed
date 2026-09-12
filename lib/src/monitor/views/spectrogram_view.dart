import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';
import 'package:muse_ml/src/monitor/empty_state.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/panes/spectrogram_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

class SpectrogramView extends ConsumerStatefulWidget {
  const SpectrogramView({super.key});

  @override
  ConsumerState<SpectrogramView> createState() => _SpectrogramViewState();
}

class _SpectrogramViewState extends ConsumerState<SpectrogramView> {
  final ViewportController _viewport = ViewportController()
    ..windowSeconds = ViewportController.spectrogramDefaultWindowSeconds;

  Set<int> _selected = {};
  int _montageLen = 0;
  double _pinchWindowAtStart =
      ViewportController.spectrogramDefaultWindowSeconds;
  double _pinchFocalElapsed = 0;
  double _pinchFocalFraction = 0.5;
  double _magMin = -40;
  double _magMax = 0;
  bool _magLocked = false;
  int _lastHop = -1;
  List<StftColumn> _columns = const [];
  Set<int> _cachedElectrodes = const {};
  double _cachedStart = 0;
  double _cachedEnd = 0;

  @override
  void initState() {
    super.initState();
    ref
        .read(monitorControllerProvider.notifier)
        .sweepBuffer
        .addListener(_onBuffer);
    _viewport.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _onBuffer() {
    if (!mounted) return;
    if (_viewport.mode == ViewportMode.inspect) return;
    final hop = _mon.sweepBuffer.sampleCount ~/ kStftHopSamples;
    if (hop == _lastHop) return;
    _lastHop = hop;
    setState(() {});
  }

  @override
  void dispose() {
    _mon.sweepBuffer.removeListener(_onBuffer);
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

  double _newestElapsed() =>
      sweepNewestElapsed(_mon.sweepBuffer, _mon.ramNewestElapsed);

  double _oldestElapsed() {
    final n = _mon.sweepBuffer.sampleCount;
    if (n <= 0) return 0;
    final newest = _newestElapsed();
    var oldest = newest - (n - 1) / SweepBuffer.sampleRate;
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
        (w -
                SpectrogramPanePainter.yGutter -
                SpectrogramPanePainter.colorbarGutter)
            .clamp(1, w);
    final x = d.localFocalPoint.dx - SpectrogramPanePainter.yGutter;
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
        zoomFloor: ViewportController.spectrogramZoomFloor,
        zoomCap: ViewportController.spectrogramZoomCap,
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

  List<StftColumn> _stft(double start, double end) {
    final sameElectrodes =
        _cachedElectrodes.length == _selected.length &&
        _cachedElectrodes.containsAll(_selected);
    if (sameElectrodes &&
        (start - _cachedStart).abs() < 1e-6 &&
        (end - _cachedEnd).abs() < 1e-6 &&
        _columns.isNotEmpty &&
        _viewport.mode == ViewportMode.inspect) {
      return _columns;
    }
    final pad = kDefaultFftN / SweepBuffer.sampleRate;
    final samples = meanEegWindow(
      buffer: _mon.sweepBuffer,
      electrodes: _selected,
      startElapsed: start - pad,
      endElapsed: end,
      newestElapsed: _mon.ramNewestElapsed ?? _newestElapsed(),
    );
    final cols = stftColumns(samples, startElapsed: start - pad);
    _columns = cols;
    _cachedElectrodes = Set<int>.from(_selected);
    _cachedStart = start;
    _cachedEnd = end;
    return cols;
  }

  (double, double)? _magFrom(List<StftColumn> cols) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final c in cols) {
      for (final db in c.db) {
        if (!db.isFinite) continue;
        if (db < lo) lo = db;
        if (db > hi) hi = db;
      }
    }
    if (lo.isInfinite) return null;
    if (hi - lo < 1) hi = lo + 1;
    return (lo, hi);
  }

  Widget _magMenu(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'mag ▾',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        );
      },
      menuChildren: [
        SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_magMin.round()} … ${_magMax.round()} dB',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                RangeSlider(
                  min: -80,
                  max: 40,
                  values: RangeValues(
                    _magMin.clamp(-80, 39),
                    _magMax.clamp(_magMin + 1, 40),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _magMin = v.start;
                      _magMax = v.end;
                      _magLocked = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ],
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
    final columns = connected && buffer.hasData
        ? _stft(start, end)
        : const <StftColumn>[];
    var magMin = _magMin;
    var magMax = _magMax;
    if (!_magLocked) {
      final m = _magFrom(columns);
      if (m != null) {
        magMin = m.$1;
        magMax = m.$2;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _magLocked) return;
          setState(() {
            _magMin = magMin;
            _magMax = magMax;
            _magLocked = true;
          });
        });
      }
    }

    return GraphShell(
      title: 'Spectrogram',
      viewport: _viewport,
      windowOptions: ViewportController.spectrogramWindowOptions,
      formatWindow: formatSpectrogramWindow,
      onFollow: _follow,
      onInspect: _inspect,
      onWindowChanged: (s) =>
          _viewport.setStripWindowSeconds(s, newestElapsed: newest),
      toolbarMiddle: _magMenu(context),
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
              child: SpectrogramPane(
                columns: columns,
                viewport: _viewport,
                newestElapsed: newest,
                magMin: magMin,
                magMax: magMax,
                connected: connected,
              ),
            ),
            if (connected && !buffer.hasData)
              const Positioned.fill(child: MonitorWaitingSignal()),
          ],
        ),
      ),
    );
  }
}
