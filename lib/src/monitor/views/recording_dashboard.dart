import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/device_montage.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/band_toggles.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/panes/histogram_pane.dart';
import 'package:muse_ml/src/monitor/panes/psd_pane.dart';
import 'package:muse_ml/src/monitor/panes/spectrogram_pane.dart';
import 'package:muse_ml/src/monitor/panes/sweep_pane.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';
import 'package:muse_ml/src/monitor/views/histogram_view.dart';
import 'package:muse_ml/src/monitor/views/psd_view.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';

enum RecordingDashGraph { rawEeg, bands, histogram, psd, spectrogram }

class _LoadedRecording {
  const _LoadedRecording({
    required this.data,
    required this.originMs,
    required this.newestElapsed,
    required this.labels,
    this.meta,
  });

  final SessionData data;
  final int originMs;
  final double newestElapsed;
  final List<String> labels;
  final RecordingMetadata? meta;
}

/// History row for `kind = recording`. Follow is disabled; Inspect uses
/// in-memory `v5ExtractRaw` (body already includes the 12-byte header).
class RecordingDashboardView extends ConsumerStatefulWidget {
  const RecordingDashboardView({super.key, required this.sessionId, this.path});

  final String sessionId;
  final String? path;

  @override
  ConsumerState<RecordingDashboardView> createState() =>
      _RecordingDashboardViewState();
}

class _RecordingDashboardViewState
    extends ConsumerState<RecordingDashboardView> {
  final ViewportController _viewport = ViewportController()
    ..mode = ViewportMode.inspect
    ..inspectStartElapsed = 0
    ..windowSeconds = ViewportController.defaultWindowSeconds;
  final SweepBuffer _buffer = SweepBuffer();
  final SharedYScale _yScale = SharedYScale();

  RecordingDashGraph _graph = RecordingDashGraph.rawEeg;
  Set<int> _selected = {};
  Set<int> _visibleBands = allBandIndices();
  int _montageLen = 0;
  HistogramUvRange _uv = HistogramUvRange.uv100;
  PsdHzRange _hz = PsdHzRange.hz60;
  double? _hairlineUv;
  double? _hairlineHz;
  double _magMin = -40;
  double _magMax = 0;
  bool _magLocked = false;
  double _pinchWindowAtStart = ViewportController.defaultWindowSeconds;
  double _pinchFocalElapsed = 0;
  double _pinchFocalFraction = 0.5;

  Future<_LoadedRecording>? _load;
  _LoadedRecording? _loaded;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _buffer.setDisplayWindow(_viewport.windowSamples);
    _buffer.freeze();
    _viewport.addListener(_onTick);
    _yScale.addListener(_onTick);
    _load = _open();
    _load!
        .then((loaded) {
          if (!mounted) return;
          setState(() {
            _loaded = loaded;
            _error = null;
            _syncMontage(loaded.labels);
          });
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => _error = e);
        });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewport.removeListener(_onTick);
    _yScale.removeListener(_onTick);
    _viewport.dispose();
    _yScale.dispose();
    _buffer.dispose();
    super.dispose();
  }

  Future<_LoadedRecording> _open() async {
    final storage = await ref.read(sessionStorageProvider.future);
    final name = widget.path ?? 'recording_${widget.sessionId}.muse.feedback';
    final bytes = await storage.readFile(name);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Recording file not found ($name)');
    }
    final full = Uint8List.fromList(bytes);
    RecordingMetadata? meta;
    try {
      final head = v5ParseHead(bytes: full);
      final decoded = jsonDecode(utf8.decode(head.metadataJson));
      if (decoded is Map<String, dynamic>) {
        meta = RecordingMetadata.fromJson(decoded);
      }
    } catch (_) {}
    final raw = v5ExtractRaw(bytes: full);
    final data = sessionParseBody(bytes: raw);
    final origin = _originMs(data, meta);
    final newest = _newestElapsed(data, origin, meta);
    final n = _channelCount(data, meta);
    final labels = _labelsFor(n, meta);
    return _LoadedRecording(
      data: data,
      originMs: origin,
      newestElapsed: newest,
      labels: labels,
      meta: meta,
    );
  }

  void _syncMontage(List<String> names) {
    if (names.length == _montageLen &&
        _selected.isNotEmpty &&
        _selected.every((i) => i >= 0 && i < names.length)) {
      return;
    }
    _montageLen = names.length;
    _selected = allElectrodeIndices(names.length);
  }

  void _setGraph(RecordingDashGraph next) {
    if (_graph == next) return;
    final newest = _loaded?.newestElapsed ?? 0;
    final def = switch (next) {
      RecordingDashGraph.rawEeg => ViewportController.defaultWindowSeconds,
      RecordingDashGraph.bands => ViewportController.bandsDefaultWindowSeconds,
      RecordingDashGraph.histogram =>
        ViewportController.histogramDefaultWindowSeconds,
      RecordingDashGraph.psd => ViewportController.psdDefaultWindowSeconds,
      RecordingDashGraph.spectrogram =>
        ViewportController.spectrogramDefaultWindowSeconds,
    };
    setState(() {
      _graph = next;
      _hairlineUv = null;
      _hairlineHz = null;
      _magLocked = false;
      if (next == RecordingDashGraph.rawEeg) {
        _viewport.setWindowSeconds(def, _buffer);
      } else {
        _viewport.setStripWindowSeconds(def, newestElapsed: newest);
      }
    });
  }

  List<double> get _windowOptions => switch (_graph) {
    RecordingDashGraph.rawEeg => ViewportController.eegWindowOptions,
    RecordingDashGraph.bands => ViewportController.bandsWindowOptions,
    RecordingDashGraph.histogram ||
    RecordingDashGraph.psd => ViewportController.histogramPsdWindowOptions,
    RecordingDashGraph.spectrogram =>
      ViewportController.spectrogramWindowOptions,
  };

  void _onWindowChanged(double s) {
    final newest = _loaded?.newestElapsed ?? 0;
    if (_graph == RecordingDashGraph.rawEeg) {
      _viewport.setWindowSeconds(s, _buffer);
    } else {
      _viewport.setStripWindowSeconds(s, newestElapsed: newest);
    }
  }

  bool get _panEnabled =>
      _graph == RecordingDashGraph.rawEeg ||
      _graph == RecordingDashGraph.bands ||
      _graph == RecordingDashGraph.spectrogram;

  void _onScaleStart(ScaleStartDetails d) {
    if (!_panEnabled) return;
    final newest = _loaded?.newestElapsed ?? 0;
    _pinchWindowAtStart = _viewport.windowSeconds;
    final w = context.size?.width ?? 1;
    final x = d.localFocalPoint.dx;
    _pinchFocalFraction = w <= 0 ? 0.5 : (x / w).clamp(0.0, 1.0);
    _pinchFocalElapsed =
        _viewport.stripVisibleStart(newestElapsed: newest) +
        _pinchFocalFraction * _viewport.windowSeconds;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_panEnabled) return;
    final newest = _loaded?.newestElapsed ?? 0;
    if (d.pointerCount >= 2 &&
        (_graph == RecordingDashGraph.bands ||
            _graph == RecordingDashGraph.spectrogram)) {
      _viewport.pinchX(
        scaleFromStart: d.scale,
        windowAtStart: _pinchWindowAtStart,
        focalElapsed: _pinchFocalElapsed,
        focalFraction: _pinchFocalFraction,
        newestElapsed: newest,
        elapsedCap: newest,
        oldestElapsed: 0,
        zoomFloor: _graph == RecordingDashGraph.spectrogram
            ? ViewportController.spectrogramZoomFloor
            : ViewportController.bandsZoomFloor,
        zoomCap: _graph == RecordingDashGraph.spectrogram
            ? ViewportController.spectrogramZoomCap
            : ViewportController.bandsZoomCap,
      );
      return;
    }
    if (d.pointerCount != 1) return;
    final w = context.size?.width ?? 1;
    if (w <= 0) return;
    final delta = -d.focalPointDelta.dx / w * _viewport.windowSeconds;
    if (_graph == RecordingDashGraph.rawEeg) {
      _viewport.panSeconds(delta, newestElapsed: newest);
    } else {
      _viewport.panStrip(delta, newestElapsed: newest, oldestElapsed: 0);
    }
  }

  Widget _graphKindBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SegmentedButton<RecordingDashGraph>(
        segments: const [
          ButtonSegment(
            value: RecordingDashGraph.rawEeg,
            label: Text('Raw EEG'),
          ),
          ButtonSegment(value: RecordingDashGraph.bands, label: Text('Bands')),
          ButtonSegment(
            value: RecordingDashGraph.histogram,
            label: Text('Histogram'),
          ),
          ButtonSegment(value: RecordingDashGraph.psd, label: Text('PSD')),
          ButtonSegment(
            value: RecordingDashGraph.spectrogram,
            label: Text('Spectrogram'),
          ),
        ],
        selected: {_graph},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelectionChanged: (s) {
          if (s.isEmpty) return;
          _setGraph(s.first);
        },
      ),
    );
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

  Widget _uvMenu(BuildContext context) {
    final half = switch (_uv) {
      HistogramUvRange.uv50 => 50,
      HistogramUvRange.uv100 => 100,
      HistogramUvRange.uv200 => 200,
    };
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
        child: Text(
          '±$half µV',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }

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

  Widget? _toolbarMiddle(BuildContext context) {
    return switch (_graph) {
      RecordingDashGraph.rawEeg => _yMenu(context),
      RecordingDashGraph.histogram => _uvMenu(context),
      RecordingDashGraph.psd => _hzMenu(context),
      RecordingDashGraph.spectrogram => _magMenu(context),
      RecordingDashGraph.bands => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = _loaded;
    final title = loaded?.meta?.device.name.isNotEmpty == true
        ? loaded!.meta!.device.name
        : 'Recording';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _error != null
          ? Center(child: Text('Could not load recording: $_error'))
          : loaded == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _graphKindBar(context),
                Expanded(child: _shell(theme, loaded)),
              ],
            ),
    );
  }

  Widget _shell(ThemeData theme, _LoadedRecording loaded) {
    _syncMontage(loaded.labels);
    final newest = loaded.newestElapsed;
    final start = _viewport.stripVisibleStart(newestElapsed: newest);
    final end = _viewport.stripVisibleEnd(newestElapsed: newest);
    final inspectLabel = '${formatElapsed(start)}–${formatElapsed(end)}';
    final extras = _graph == RecordingDashGraph.rawEeg
        ? null
        : ElectrodeToggles(
            names: loaded.labels,
            selected: _selected,
            onToggle: (i) {
              setState(() {
                _selected = toggleAverageElectrode(_selected, i);
              });
            },
          );

    return GraphShell(
      title: switch (_graph) {
        RecordingDashGraph.rawEeg => 'Raw EEG',
        RecordingDashGraph.bands => 'Bands',
        RecordingDashGraph.histogram => 'Histogram',
        RecordingDashGraph.psd => 'Power Spectral Density',
        RecordingDashGraph.spectrogram => 'Spectrogram',
      },
      followEnabled: false,
      showRecord: false,
      viewport: _viewport,
      windowOptions: _windowOptions,
      formatWindow: _graph == RecordingDashGraph.spectrogram
          ? formatSpectrogramWindow
          : null,
      onFollow: () {},
      onInspect: () {},
      onWindowChanged: _onWindowChanged,
      inspectRangeLabel: inspectLabel,
      toolbarMiddle: _toolbarMiddle(context),
      toolbarExtras: extras,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && _panEnabled) {
                  final delta =
                      e.scrollDelta.dy / 120 * _viewport.windowSeconds * 0.1;
                  if (_graph == RecordingDashGraph.rawEeg) {
                    _viewport.panSeconds(delta, newestElapsed: newest);
                  } else {
                    _viewport.panStrip(
                      delta,
                      newestElapsed: newest,
                      oldestElapsed: 0,
                    );
                  }
                }
              },
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: _pane(theme, loaded, start, end),
              ),
            ),
          ),
          if (_graph == RecordingDashGraph.bands)
            Positioned(
              right: 8,
              top: TimeSeriesPanePainter.topGutter,
              child: BandToggles(
                selected: _visibleBands,
                onToggle: (i) {
                  setState(() {
                    _visibleBands = toggleVisibleBand(_visibleBands, i);
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _pane(
    ThemeData theme,
    _LoadedRecording loaded,
    double start,
    double end,
  ) {
    switch (_graph) {
      case RecordingDashGraph.rawEeg:
        return _rawEeg(theme, loaded, start);
      case RecordingDashGraph.bands:
        return TimeSeriesPane(
          series: bandSeriesFromRecords(
            bands: loaded.data.bands,
            electrodes: _selected,
            startElapsed: start,
            endElapsed: end,
            originMs: loaded.originMs,
          ),
          viewport: _viewport,
          newestElapsed: loaded.newestElapsed,
          connected: true,
          visibleBands: _visibleBands,
          drawLegend: false,
        );
      case RecordingDashGraph.histogram:
        final half = switch (_uv) {
          HistogramUvRange.uv50 => 50.0,
          HistogramUvRange.uv100 => 100.0,
          HistogramUvRange.uv200 => 200.0,
        };
        final samples = meanFromRecords(
          eeg: loaded.data.eeg,
          electrodes: _selected,
          startElapsed: start,
          endElapsed: end,
          originMs: loaded.originMs,
        );
        return Column(
          children: [
            Expanded(
              child: HistogramPane(
                counts: histogramCounts(samples, halfRange: half),
                halfRange: half,
                connected: true,
                hairlineUv: _hairlineUv,
                onTapUv: (uv) => setState(() => _hairlineUv = uv),
              ),
            ),
          ],
        );
      case RecordingDashGraph.psd:
        final samples = meanFromRecords(
          eeg: loaded.data.eeg,
          electrodes: _selected,
          startElapsed: start,
          endElapsed: end,
          originMs: loaded.originMs,
        );
        final spectrum = welch(samples);
        return Column(
          children: [
            Expanded(
              child: PsdPane(
                spectrum: spectrum,
                maxHz: _hz == PsdHzRange.hz100 ? 100 : 60,
                connected: true,
                peakHz: alphaPeakHz(spectrum),
                hairlineHz: _hairlineHz,
                onTapHz: (hz) => setState(() => _hairlineHz = hz),
              ),
            ),
          ],
        );
      case RecordingDashGraph.spectrogram:
        final pad = kDefaultFftN / SweepBuffer.sampleRate;
        final samples = meanFromRecords(
          eeg: loaded.data.eeg,
          electrodes: _selected,
          startElapsed: start - pad,
          endElapsed: end,
          originMs: loaded.originMs,
        );
        final columns = stftColumns(samples, startElapsed: start - pad);
        var magMin = _magMin;
        var magMax = _magMax;
        if (!_magLocked) {
          var lo = double.infinity;
          var hi = double.negativeInfinity;
          for (final c in columns) {
            for (final db in c.db) {
              if (!db.isFinite) continue;
              if (db < lo) lo = db;
              if (db > hi) hi = db;
            }
          }
          if (!lo.isInfinite) {
            if (hi - lo < 1) hi = lo + 1;
            magMin = lo;
            magMax = hi;
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
        return SpectrogramPane(
          columns: columns,
          viewport: _viewport,
          newestElapsed: loaded.newestElapsed,
          magMin: magMin,
          magMax: magMax,
          connected: true,
        );
    }
  }

  Widget _rawEeg(ThemeData theme, _LoadedRecording loaded, double start) {
    _syncAutoY(loaded, start);
    final n = loaded.labels.length;
    final trace = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final wipe = theme.colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        const minH = 160.0;
        Widget pane(int i) => SweepPane(
          electrode: i,
          label: loaded.labels[i],
          buffer: _buffer,
          viewport: _viewport,
          yScale: _yScale,
          showXAxis: i == n - 1,
          traceColor: trace,
          wipeColor: wipe,
          fileSamples: channelFromRecords(
            eeg: loaded.data.eeg,
            electrode: i,
            startElapsed: start,
            n: _viewport.windowSamples,
            originMs: loaded.originMs,
          ),
          newestElapsed: loaded.newestElapsed,
          captureStartedAtMs: loaded.originMs,
        );
        if (n * minH > constraints.maxHeight && constraints.maxHeight > 0) {
          return ListView.builder(
            itemCount: n,
            itemExtent: minH,
            itemBuilder: (context, i) => SizedBox(height: minH, child: pane(i)),
          );
        }
        return Column(
          children: [for (var i = 0; i < n; i++) Expanded(child: pane(i))],
        );
      },
    );
  }

  void _syncAutoY(_LoadedRecording loaded, double start) {
    if (_yScale.mode != YScaleMode.auto) return;
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    final n = _viewport.windowSamples;
    for (var ch = 0; ch < loaded.labels.length; ch++) {
      final samples = channelFromRecords(
        eeg: loaded.data.eeg,
        electrode: ch,
        startElapsed: start,
        n: n,
        originMs: loaded.originMs,
      );
      for (final s in samples) {
        if (!s.isFinite || s.abs() > 1e6) continue;
        if (s < lo) lo = s;
        if (s > hi) hi = s;
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
}

int _originMs(SessionData data, RecordingMetadata? meta) {
  if (data.eeg.isNotEmpty) {
    var minTs = data.eeg.first.timestamp;
    for (final rec in data.eeg) {
      if (rec.timestamp < minTs) minTs = rec.timestamp;
    }
    return minTs.round();
  }
  if (meta != null) return meta.startedAt.millisecondsSinceEpoch;
  return 0;
}

double _newestElapsed(SessionData data, int originMs, RecordingMetadata? meta) {
  var newest = 0.0;
  for (final rec in data.eeg) {
    final t0 = (rec.timestamp - originMs) / 1000.0;
    final span = rec.samples.isEmpty
        ? 0.0
        : (rec.samples.length - 1) / SweepBuffer.sampleRate;
    final t1 = t0 + span;
    if (t1 > newest) newest = t1;
  }
  if (newest <= 0 && meta != null) {
    newest = (meta.durationS != 0 ? meta.durationS : meta.elapsedSeconds)
        .toDouble();
  }
  return newest;
}

int _channelCount(SessionData data, RecordingMetadata? meta) {
  var maxCh = -1;
  for (final rec in data.eeg) {
    if (rec.electrode > maxCh) maxCh = rec.electrode;
  }
  final fromEeg = maxCh + 1;
  final fromMeta = meta?.device.channelCount ?? 0;
  return math.max(fromEeg, fromMeta > 0 ? fromMeta : 4);
}

List<String> _labelsFor(int n, RecordingMetadata? meta) {
  final known = meta?.device.channelLabels ?? const <String>[];
  if (known.length == n) return known;
  if (n <= 4) return kMuseElectrodeNames.take(n).toList();
  if (n == 8) return kCrownElectrodeNames;
  return [
    for (var i = 0; i < n; i++) i < known.length ? known[i] : 'CH${i + 1}',
  ];
}

Float64List channelFromRecords({
  required List<EegSampleRecord> eeg,
  required int electrode,
  required double startElapsed,
  required int n,
  required int originMs,
}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = double.nan;
  }
  for (final rec in eeg) {
    if (rec.electrode != electrode) continue;
    final t0 = (rec.timestamp - originMs) / 1000.0;
    for (var i = 0; i < rec.samples.length; i++) {
      final t = t0 + i / SweepBuffer.sampleRate;
      final idx = ((t - startElapsed) * SweepBuffer.sampleRate).round();
      if (idx >= 0 && idx < n) {
        out[idx] = rec.samples[i];
      }
    }
  }
  return out;
}

Float64List meanFromRecords({
  required List<EegSampleRecord> eeg,
  required Iterable<int> electrodes,
  required double startElapsed,
  required double endElapsed,
  required int originMs,
}) {
  final span = endElapsed - startElapsed;
  if (span <= 0) return Float64List(0);
  final n = (span * SweepBuffer.sampleRate).round();
  if (n <= 0) return Float64List(0);
  final selected = electrodes.toSet();
  if (selected.isEmpty) {
    return Float64List(n)..fillRange(0, n, double.nan);
  }
  final acc = Float64List(n);
  final counts = List<int>.filled(n, 0);
  for (final rec in eeg) {
    if (!selected.contains(rec.electrode)) continue;
    final t0 = (rec.timestamp - originMs) / 1000.0;
    for (var i = 0; i < rec.samples.length; i++) {
      final v = rec.samples[i];
      if (!v.isFinite) continue;
      final t = t0 + i / SweepBuffer.sampleRate;
      final idx = ((t - startElapsed) * SweepBuffer.sampleRate).round();
      if (idx >= 0 && idx < n) {
        acc[idx] += v;
        counts[idx]++;
      }
    }
  }
  for (var i = 0; i < n; i++) {
    acc[i] = counts[i] == 0 ? double.nan : acc[i] / counts[i];
  }
  return acc;
}

List<List<BandPoint>> bandSeriesFromRecords({
  required List<BandsRecord> bands,
  required Iterable<int> electrodes,
  required double startElapsed,
  required double endElapsed,
  required int originMs,
}) {
  final selected = electrodes.toSet();
  final byT = List.generate(bandNames.length, (_) => <int, List<double>>{});
  for (final b in bands) {
    if (!selected.contains(b.electrode)) continue;
    final elapsed = (b.timestamp - originMs) / 1000.0;
    if (elapsed < startElapsed - 1 || elapsed > endElapsed + 1) continue;
    final key = (elapsed * 1000).round();
    (byT[0][key] ??= []).add(linearToDb(b.delta));
    (byT[1][key] ??= []).add(linearToDb(b.theta));
    (byT[2][key] ??= []).add(linearToDb(b.alpha));
    (byT[3][key] ??= []).add(linearToDb(b.beta));
    (byT[4][key] ??= []).add(linearToDb(b.gamma));
  }
  return [
    for (final map in byT)
      [
        for (final k in (map.keys.toList()..sort()))
          BandPoint(
            k / 1000.0,
            map[k]!.reduce((a, b) => a + b) / map[k]!.length,
          ),
      ],
  ];
}
