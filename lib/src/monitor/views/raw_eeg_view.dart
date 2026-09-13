import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/empty_state.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/monitor/panes/sweep_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';

class RawEegView extends ConsumerStatefulWidget {
  const RawEegView({super.key});

  @override
  ConsumerState<RawEegView> createState() => _RawEegViewState();
}

class _RawEegViewState extends ConsumerState<RawEegView> {
  final ViewportController _viewport = ViewportController();
  final SharedYScale _yScale = SharedYScale();

  double? _fileCacheStart;
  double? _fileCacheEnd;
  SessionData? _fileCache;

  @override
  void initState() {
    super.initState();
    final buf = ref.read(monitorControllerProvider.notifier).sweepBuffer;
    buf.setDisplayWindow(_viewport.windowSamples);
    if (buf.frozen) buf.resume();
    _viewport.addListener(_onChrome);
    _yScale.addListener(_onChrome);
  }

  void _onChrome() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewport.removeListener(_onChrome);
    _yScale.removeListener(_onChrome);
    _viewport.dispose();
    _yScale.dispose();
    super.dispose();
  }

  MonitorController get _mon => ref.read(monitorControllerProvider.notifier);

  void _follow() => _viewport.follow(_mon.sweepBuffer);

  void _inspect() {
    _viewport.enterInspectFromSweep(
      _mon.sweepBuffer,
      newestElapsed: _mon.ramNewestElapsed,
    );
  }

  void _onScaleStart(ScaleStartDetails _) {
    if (_viewport.mode == ViewportMode.follow) _inspect();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != 1) return;
    final w = context.size?.width ?? 1;
    if (w <= 0) return;
    _viewport.panSeconds(
      -d.focalPointDelta.dx / w * _viewport.windowSeconds,
      newestElapsed: _mon.ramNewestElapsed,
    );
  }

  SessionData? _fileData(MonitorState state) {
    if (_viewport.mode != ViewportMode.inspect) return null;
    final start = _viewport.inspectStartElapsed ?? 0;
    final end = start + _viewport.windowSeconds;
    final newest = _mon.ramNewestElapsed;
    if (!inspectNeedsFileBacked(
      startElapsed: start,
      ramCount: _mon.sweepBuffer.sampleCount,
      ramNewestElapsed: newest,
      captureStartedAtMs: state.captureStartedAtMs,
    )) {
      _fileCache = null;
      return null;
    }
    if (_fileCache != null &&
        _fileCacheStart == start &&
        _fileCacheEnd == end) {
      return _fileCache;
    }
    _fileCacheStart = start;
    _fileCacheEnd = end;
    _fileCache = inspectFileRange(
      startElapsed: start,
      endElapsed: end,
      ramCount: _mon.sweepBuffer.sampleCount,
      ramNewestElapsed: newest,
      captureStartedAtMs: state.captureStartedAtMs,
      getRange: (a, b) => _mon.fileBackedSource?.getRange(a, b),
    );
    return _fileCache;
  }

  Float64List? _channelFromFile(SessionData? data, int electrode) {
    if (data == null) return null;
    final start = _viewport.inspectStartElapsed ?? 0;
    final n = _viewport.windowSamples;
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = double.nan;
    }
    var any = false;
    for (final rec in data.eeg) {
      if (rec.electrode != electrode) continue;
      for (var i = 0; i < rec.samples.length; i++) {
        final t = rec.timestamp + i / SweepBuffer.sampleRate;
        final idx = ((t - start) * SweepBuffer.sampleRate).round();
        if (idx >= 0 && idx < n) {
          out[idx] = rec.samples[i];
          any = true;
        }
      }
    }
    return any ? out : null;
  }

  void _syncAutoY(SweepBuffer buffer) {
    if (_yScale.mode != YScaleMode.auto) return;
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    void acc(double s) {
      if (s.isNaN || s.abs() > 1e6) return;
      if (s < lo) lo = s;
      if (s > hi) hi = s;
    }

    final n = _viewport.windowSamples;
    final newest = _mon.ramNewestElapsed;
    if (_viewport.mode == ViewportMode.follow) {
      for (final ch in buffer.electrodes) {
        for (var i = 0; i < n; i++) {
          acc(buffer.displaySample(ch, i));
        }
      }
    } else {
      final start = _viewport.inspectStartElapsed ?? 0;
      for (final ch in buffer.electrodes) {
        final count = buffer.channelCount(ch);
        for (var i = 0; i < n; i++) {
          final idx = ramIndexForElapsed(
            elapsed: start + i / SweepBuffer.sampleRate,
            ramCount: count,
            ramNewestElapsed: newest,
          );
          if (idx != null) acc(buffer.sampleAt(ch, idx));
        }
      }
    }
    if (lo.isInfinite) {
      _yScale.setAutoHalfRange(200);
      return;
    }
    final range = hi - lo;
    final pad = range > 0 ? range * 0.15 : 20.0;
    _yScale.setAutoHalfRange(((range / 2) + pad).clamp(10.0, 10000.0));
  }

  Widget _yMenu(BuildContext context) {
    final label = _yScale.mode == YScaleMode.auto
        ? 'Auto'
        : '±${_yScale.halfRange.round()} µV';
    return PopupMenuButton<YScaleMode>(
      tooltip: 'Y scale',
      initialValue: _yScale.mode,
      onSelected: _yScale.setMode,
      itemBuilder: (context) => const [
        PopupMenuItem(value: YScaleMode.auto, child: Text('Auto')),
        PopupMenuItem(value: YScaleMode.fixed50, child: Text('±50 µV')),
        PopupMenuItem(value: YScaleMode.fixed100, child: Text('±100 µV')),
        PopupMenuItem(value: YScaleMode.fixed200, child: Text('±200 µV')),
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
    final connected = ref.watch(
      appStateProvider.select((s) => s.status.connected),
    );
    ref.listen(appStateProvider.select((s) => s.status.connected), (
      prev,
      next,
    ) {
      if (next != true) _follow();
    });
    final names = state.electrodeNames;
    final mon = _mon;
    final buffer = mon.sweepBuffer;
    final theme = Theme.of(context);
    final trace = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final wipe = theme.colorScheme.onSurface;

    return GraphShell(
      title: 'Raw EEG',
      showRecord: true,
      viewport: _viewport,
      windowOptions: ViewportController.eegWindowOptions,
      onFollow: _follow,
      onInspect: _inspect,
      onWindowChanged: (s) => _viewport.setWindowSeconds(s, buffer),
      toolbarExtras: _yMenu(context),
      body: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent &&
              _viewport.mode == ViewportMode.inspect) {
            _viewport.panSeconds(
              e.scrollDelta.dy / 120 * _viewport.windowSeconds * 0.1,
              newestElapsed: mon.ramNewestElapsed,
            );
          }
        },
        child: GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: ListenableBuilder(
            listenable: buffer,
            builder: (context, _) {
              _syncAutoY(buffer);
              final file = _fileData(state);
              final newest = mon.ramNewestElapsed;
              return Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const minH = 160.0;
                        final n = names.length;
                        Widget pane(int i) => SweepPane(
                          electrode: i,
                          label: names[i],
                          buffer: buffer,
                          viewport: _viewport,
                          yScale: _yScale,
                          showXAxis: i == n - 1,
                          traceColor: trace,
                          wipeColor: wipe,
                          fileSamples: _channelFromFile(file, i),
                          newestElapsed: newest,
                          captureStartedAtMs: state.captureStartedAtMs,
                        );
                        if (n * minH >= constraints.maxHeight) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                for (var i = 0; i < n; i++)
                                  SizedBox(height: minH, child: pane(i)),
                              ],
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(child: pane(i)),
                          ],
                        );
                      },
                    ),
                  ),
                  if (connected && !buffer.hasData)
                    const Positioned.fill(child: MonitorWaitingSignal()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
