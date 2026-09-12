import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';
import 'package:muse_ml/src/monitor/empty_state.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/panes/psd_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

enum PsdHzRange { hz60, hz100 }

class PsdView extends ConsumerStatefulWidget {
  const PsdView({super.key});

  @override
  ConsumerState<PsdView> createState() => _PsdViewState();
}

class _PsdViewState extends ConsumerState<PsdView> {
  final ViewportController _viewport = ViewportController()
    ..windowSeconds = ViewportController.psdDefaultWindowSeconds;

  Set<int> _selected = {};
  int _montageLen = 0;
  PsdHzRange _hz = PsdHzRange.hz60;
  double? _hairlineHz;

  @override
  void initState() {
    super.initState();
    ref
        .read(monitorControllerProvider.notifier)
        .sweepBuffer
        .addListener(_onTick);
    _viewport.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mon.sweepBuffer.removeListener(_onTick);
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

  double get _maxHz => _hz == PsdHzRange.hz100 ? 100 : 60;

  void _follow() => _viewport.followStrip();

  void _inspect() =>
      _viewport.enterInspectStrip(newestElapsed: _newestElapsed());

  Widget _hzMenu(BuildContext context) {
    final label = _hz == PsdHzRange.hz100 ? '0–100 Hz' : '0–60 Hz';
    return PopupMenuButton<PsdHzRange>(
      tooltip: 'Hz range',
      initialValue: _hz,
      onSelected: (v) => setState(() => _hz = v),
      itemBuilder: (context) => const [
        PopupMenuItem(value: PsdHzRange.hz60, child: Text('0–60 Hz')),
        PopupMenuItem(value: PsdHzRange.hz100, child: Text('0–100 Hz')),
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
    Spectrum? spectrum;
    double? peak;
    if (connected && buffer.hasData) {
      final samples = meanEegWindow(
        buffer: buffer,
        electrodes: _selected,
        startElapsed: start,
        endElapsed: end,
        newestElapsed: _mon.ramNewestElapsed ?? newest,
      );
      spectrum = welch(samples);
      peak = alphaPeakHz(spectrum);
    }
    final inspectLabel = _viewport.mode == ViewportMode.inspect
        ? '${formatElapsed(start)}–${formatElapsed(end)}'
        : null;

    return GraphShell(
      title: 'Power Spectral Density',
      showRecord: true,
      viewport: _viewport,
      windowOptions: ViewportController.histogramPsdWindowOptions,
      onFollow: _follow,
      onInspect: _inspect,
      onWindowChanged: (s) =>
          _viewport.setStripWindowSeconds(s, newestElapsed: newest),
      inspectRangeLabel: inspectLabel,
      toolbarMiddle: _hzMenu(context),
      toolbarExtras: ElectrodeToggles(
        names: names,
        selected: _selected,
        onToggle: (i) {
          setState(() {
            _selected = toggleAverageElectrode(_selected, i);
          });
        },
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: PsdPane(
                    spectrum: spectrum,
                    maxHz: _maxHz,
                    connected: connected,
                    peakHz: peak,
                    hairlineHz: _hairlineHz,
                    onTapHz: (hz) => setState(() => _hairlineHz = hz),
                  ),
                ),
                if (connected && !buffer.hasData)
                  const Positioned.fill(child: MonitorWaitingSignal()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
