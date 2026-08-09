import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/charts/session_reader.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_summary.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/settings.dart';

class FeedbackDashboardView extends ConsumerStatefulWidget {
  const FeedbackDashboardView({
    super.key,
    this.sessionPath,
    this.sessionId,
    this.metadata,
    this.readOnly = false,
  });

  /// Scratch file to read for a live (unsaved) session.
  final String? sessionPath;

  /// History id to read from the session store (read-only history viewing).
  final String? sessionId;

  final SessionMetadata? metadata;
  final bool readOnly;

  @override
  ConsumerState<FeedbackDashboardView> createState() =>
      _FeedbackDashboardViewState();
}

class _FeedbackDashboardViewState extends ConsumerState<FeedbackDashboardView> {
  final TextEditingController _notes = TextEditingController();
  final GlobalKey _thumbKey = GlobalKey();
  Future<SessionData>? _dataFuture;
  _Prepared? _prepared;
  Uint8List? _thumbnail;
  SessionData? _sessionData;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final readOnly = widget.readOnly;
    if (readOnly && widget.sessionId != null) {
      final summary = widget.metadata?.summary;
      if (summary != null) {
        // Fast path: render the detail straight from the decimated overview in
        // the metadata head, without reading (or parsing) the .muse body.
        _prepared = _prepareOverview(summary);
      } else {
        // Legacy session without a summary: fall back to a full-body parse.
        final store = ref.read(sessionStoreProvider.future);
        _dataFuture = SessionReader.readBytes(
          store.then((s) => s.readMuse(widget.sessionId!)),
        );
      }
    } else {
      final path =
          widget.sessionPath ??
          ref.read(feedbackStateProvider.notifier).sessionFilePath;
      if (path != null) {
        _dataFuture = SessionReader.read(File(path));
      }
    }
    final notes = widget.metadata?.notes;
    if (notes != null && notes.isNotEmpty) {
      _notes.text = notes;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fb = ref.watch(feedbackStateProvider);
    final meta = widget.metadata;
    final protocol = ProtocolInfo.forType(meta?.protocol ?? fb.protocol);

    return Scaffold(
      appBar: AppBar(title: Text('${protocol.title} — Session')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _dashboard(meta, fb, protocol),
    );
  }

  Widget _dashboard(
    SessionMetadata? meta,
    FeedbackState fb,
    ProtocolInfo protocol,
  ) {
    if (_prepared != null) {
      return _DashboardBody(
        protocol: protocol,
        durationMinutes: meta?.durationMinutes ?? fb.durationMinutes,
        elapsedSeconds: meta?.elapsedSeconds ?? fb.elapsedSeconds,
        soundName: meta?.sound ?? fb.soundName,
        prepared: _prepared!,
        readOnly: widget.readOnly,
        thumbKey: _thumbKey,
        notesController: _notes,
        onSave: _save,
        onDiscard: _discard,
      );
    }
    final future = _dataFuture;
    if (future == null) {
      return _NoData(theme: Theme.of(context));
    }
    return FutureBuilder<SessionData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(
            theme: Theme.of(context),
            error: snapshot.error!,
            onDiscard: widget.readOnly ? null : _discard,
          );
        }
        final data = snapshot.data!;
        _prepared ??= _prepare(data);
        _sessionData ??= data;
        if (_thumbnail == null && !widget.readOnly) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
        }
        return _dashboard(meta, fb, protocol);
      },
    );
  }

  Future<void> _capture() async {
    final boundary =
        _thumbKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = byteData?.buffer.asUint8List();
    if (bytes != null && mounted) {
      setState(() => _thumbnail = bytes);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final notifier = ref.read(feedbackStateProvider.notifier);
    final fb = ref.read(feedbackStateProvider);
    debugPrint('[dashboard] save: sessionFilePath=${notifier.sessionFilePath}');
    final saved = await notifier.saveSession();
    if (saved != null) {
      debugPrint('[dashboard] save: finalized ${saved.path}');
      final stats = _prepared?.stats;
      final app = ref.read(appStateProvider);
      final channels = notifier.recordedChannels.map(channelName).toList()
        ..sort();
      final metadata = SessionMetadata(
        protocol: fb.protocol,
        durationMinutes: fb.durationMinutes,
        elapsedSeconds: fb.elapsedSeconds,
        sound: fb.soundName,
        savedAt: DateTime.now(),
        notes: _notes.text,
        stats: stats == null
            ? null
            : SessionStatsData(
                peakAlphaFreq: stats.peakAlphaFreq,
                peakAlphaPower: stats.peakAlphaPower,
                targetPct: stats.targetPct,
                stillnessPct: stats.stillnessPct,
                avgBpm: stats.avgBpm,
                avgAlphaRel: stats.avgAlphaRel,
              ),
        deviceName: app.status.connected ? app.status.name : null,
        deviceModel: app.status.connected ? app.status.firmware : null,
        deviceId: app.status.connected ? app.status.id : null,
        recordedChannels: channels,
        recordedData: notifier.recordStreams.map((s) => s.name).toList(),
        summary: _sessionData == null
            ? null
            : SessionOverview.fromData(_sessionData!),
        gestures: ref.read(settingsProvider).markersInFeedbackEnabled
            ? notifier.gestureMarkers
            : const [],
      );
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      try {
        debugPrint('[session] publish: reading bytes ${saved.path}');
        final museBytes = await saved.readAsBytes();
        final store = await ref.read(sessionStoreProvider.future);
        await store.publishSession(
          id,
          museBytes,
          metadata,
          pngBytes: _thumbnail,
        );
        debugPrint('[session] publish: complete ($id)');
      } catch (e) {
        debugPrint('[session] publish FAILED ($e)');
      }
    } else {
      debugPrint(
        '[dashboard] save: saveSession returned null (nothing to save)',
      );
    }
    if (mounted) {
      ref.invalidate(sessionListProvider);
      Navigator.of(context).pop();
    }
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    await ref.read(feedbackStateProvider.notifier).discardSession();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.protocol,
    required this.durationMinutes,
    required this.elapsedSeconds,
    required this.soundName,
    required this.prepared,
    required this.readOnly,
    required this.thumbKey,
    required this.notesController,
    required this.onSave,
    required this.onDiscard,
  });

  final ProtocolInfo protocol;
  final int durationMinutes;
  final int elapsedSeconds;
  final String soundName;
  final _Prepared prepared;
  final bool readOnly;
  final GlobalKey thumbKey;
  final TextEditingController notesController;
  final Future<void> Function() onSave;
  final Future<void> Function() onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = prepared.stats;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session summary', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _SummaryRow(label: 'Protocol', value: protocol.title),
                _SummaryRow(label: 'Duration', value: '$durationMinutes min'),
                _SummaryRow(
                  label: 'Elapsed',
                  value:
                      '${elapsedSeconds ~/ 60}:'
                      '${(elapsedSeconds % 60).toString().padLeft(2, '0')}',
                ),
                _SummaryRow(label: 'Background sound', value: soundName),
                if (prepared.x.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        label: 'Peak alpha',
                        value: stats.peakAlphaFreq == null
                            ? '—'
                            : '${stats.peakAlphaFreq!.toStringAsFixed(1)} Hz',
                        icon: Icons.auto_awesome,
                        color: const Color(0xFF66BB6A),
                      ),
                      _StatChip(
                        label: 'Target time',
                        value: '${stats.targetPct.toStringAsFixed(0)}%',
                        icon: Icons.track_changes,
                        color: const Color(0xFFAB47BC),
                      ),
                      _StatChip(
                        label: 'Stillness',
                        value: '${stats.stillnessPct.toStringAsFixed(0)}%',
                        icon: Icons.self_improvement,
                        color: const Color(0xFF4FC3F7),
                      ),
                      _StatChip(
                        label: 'Avg BPM',
                        value: stats.avgBpm == null
                            ? '—'
                            : stats.avgBpm!.toStringAsFixed(0),
                        icon: Icons.favorite,
                        color: const Color(0xFFEC407A),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (prepared.x.isNotEmpty) ...[
          RepaintBoundary(
            key: thumbKey,
            child: _SeriesChart(
              title: 'Alpha vs Theta (relative power, AF7/AF8 avg)',
              unit: 'rel. power',
              series: [
                _Series(
                  label: 'Alpha rel',
                  color: const Color(0xFF66BB6A),
                  values: prepared.alphaRel,
                ),
                _Series(
                  label: 'Theta rel',
                  color: const Color(0xFFAB47BC),
                  values: prepared.thetaRel,
                ),
              ],
              x: prepared.x,
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          const _NotEnoughData(
            title: 'Alpha vs Theta',
            detail:
                'Not enough signal data was recorded to build this graph. '
                'This usually means the headband was not in good contact or the '
                'connection dropped during the session. Check the electrodes and '
                'try again.',
          ),
          const SizedBox(height: 16),
        ],
        if (prepared.movement.isNotEmpty) ...[
          _SeriesChart(
            title: 'Movement score',
            unit: 'g stddev',
            series: [
              _Series(
                label: 'Movement',
                color: const Color(0xFFFFA726),
                values: prepared.movement,
              ),
            ],
            x: prepared.movementX,
          ),
          const SizedBox(height: 16),
        ] else ...[
          const _NotEnoughData(
            title: 'Movement score',
            detail: 'No movement data was recorded for this session.',
          ),
          const SizedBox(height: 16),
        ],
        if (prepared.bpm.isNotEmpty) ...[
          _SeriesChart(
            title: 'Heart rate',
            unit: 'bpm',
            series: [
              _Series(
                label: 'Pulse',
                color: const Color(0xFFEC407A),
                values: prepared.bpm,
              ),
            ],
            x: prepared.bpmX,
          ),
          const SizedBox(height: 16),
        ] else ...[
          const _NotEnoughData(
            title: 'Heart rate',
            detail:
                'No reliable heart-rate data was captured for this session.',
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: notesController,
          maxLines: 3,
          enabled: !readOnly,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
          ),
        ),
        if (!readOnly) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDiscard,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Prepared {
  final List<double> x;
  final List<double> alphaRel;
  final List<double> thetaRel;
  final List<double> movement;
  final List<double> movementX;
  final List<double> bpm;
  final List<double> bpmX;
  final _SessionStats stats;
  final int bandsCount;

  const _Prepared({
    required this.x,
    required this.alphaRel,
    required this.thetaRel,
    required this.movement,
    required this.movementX,
    required this.bpm,
    required this.bpmX,
    required this.stats,
    required this.bandsCount,
  });
}

class _SessionStats {
  final double? peakAlphaFreq;
  final double? peakAlphaPower;
  final double targetPct;
  final double stillnessPct;
  final double? avgBpm;
  final double avgAlphaRel;

  const _SessionStats({
    this.peakAlphaFreq,
    this.peakAlphaPower,
    required this.targetPct,
    required this.stillnessPct,
    this.avgBpm,
    required this.avgAlphaRel,
  });
}

_Prepared _prepare(SessionData data) {
  final bySecond = <int, Map<int, BandsRecord>>{};
  for (final b in data.bands) {
    bySecond.putIfAbsent(b.timestamp.floor(), () => {})[b.electrode] = b;
  }
  final seconds = bySecond.keys.toList()..sort();

  final x = <double>[];
  final alphaRel = <double>[];
  final thetaRel = <double>[];
  var targetSeconds = 0;
  var alphaRelSum = 0.0;
  final startTs = seconds.isEmpty ? 0.0 : seconds.first.toDouble();

  for (final s in seconds) {
    final ch = bySecond[s]!;
    final rel = _relativeAfRel(
      _afTuple(ch[electrodeAf7]),
      _afTuple(ch[electrodeAf8]),
    );
    if (rel == null) {
      continue;
    }
    final aRel = rel.$1;
    final tRel = rel.$2;
    x.add(s - startTs);
    alphaRel.add(aRel);
    thetaRel.add(tRel);
    alphaRelSum += aRel;
    if (aRel > tRel) {
      targetSeconds++;
    }
  }

  final movementX = <double>[];
  final movement = <double>[];
  var still = 0;
  for (final m in data.movements) {
    movementX.add(m.timestamp - startTs);
    movement.add(m.score);
    if (m.score <= movementGateThreshold) {
      still++;
    }
  }

  final bpmX = <double>[];
  final bpm = <double>[];
  var bpmSum = 0.0;
  for (final p in data.pulses) {
    if (p.confidence < 0.3) {
      continue;
    }
    bpmX.add(p.timestamp - startTs);
    bpm.add(p.bpm);
    bpmSum += p.bpm;
  }

  double? peakFreq;
  double? peakPower;
  for (final p in data.peakAlphas) {
    if (peakPower == null || p.power > peakPower) {
      peakPower = p.power;
      peakFreq = p.frequency;
    }
  }

  return _Prepared(
    x: x,
    alphaRel: alphaRel,
    thetaRel: thetaRel,
    movement: movement,
    movementX: movementX,
    bpm: bpm,
    bpmX: bpmX,
    bandsCount: data.bands.length,
    stats: _SessionStats(
      peakAlphaFreq: peakFreq,
      peakAlphaPower: peakPower,
      targetPct: x.isEmpty ? 0 : targetSeconds / x.length * 100,
      stillnessPct: data.movements.isEmpty
          ? 0
          : still / data.movements.length * 100,
      avgBpm: bpm.isEmpty ? null : bpmSum / bpm.length,
      avgAlphaRel: alphaRel.isEmpty ? 0 : alphaRelSum / alphaRel.length,
    ),
  );
}

/// Build a [_Prepared] from the decimated [SessionOverview] stored in the
/// metadata head, so the history detail renders without reading the `.muse`
/// body. Matches the full [SessionData] path bucket-for-bucket.
_Prepared _prepareOverview(SessionOverview overview) {
  final n = overview.bucketCount;
  final width = overview.bucketWidthSecs > 0 ? overview.bucketWidthSecs : 1.0;
  final af7 = overview.bands[electrodeAf7];
  final af8 = overview.bands[electrodeAf8];

  final x = <double>[];
  final alphaRel = <double>[];
  final thetaRel = <double>[];
  var targetSeconds = 0;
  var alphaRelSum = 0.0;

  for (var i = 0; i < n; i++) {
    final rel = _relativeAfRel(_bandAt(af7, i), _bandAt(af8, i));
    if (rel == null) {
      continue;
    }
    final aRel = rel.$1;
    final tRel = rel.$2;
    x.add(i * width);
    alphaRel.add(aRel);
    thetaRel.add(tRel);
    alphaRelSum += aRel;
    if (aRel > tRel) {
      targetSeconds++;
    }
  }

  final movementX = <double>[];
  final movement = <double>[];
  var still = 0;
  for (var i = 0; i < n; i++) {
    if (i >= overview.movement.length || overview.movement[i] == null) {
      continue;
    }
    final m = overview.movement[i]!;
    movementX.add(i * width);
    movement.add(m);
    if (m <= movementGateThreshold) {
      still++;
    }
  }

  final bpmX = <double>[];
  final bpm = <double>[];
  var bpmSum = 0.0;
  for (var i = 0; i < n; i++) {
    if (i >= overview.pulse.length || overview.pulse[i] == null) {
      continue;
    }
    final b = overview.pulse[i]!;
    bpmX.add(i * width);
    bpm.add(b);
    bpmSum += b;
  }

  double? peakFreq;
  double? peakPower;
  for (var i = 0; i < overview.peakAlphaPower.length; i++) {
    final p = overview.peakAlphaPower[i];
    if (p == null) {
      continue;
    }
    if (peakPower == null || p > peakPower) {
      peakPower = p;
      peakFreq = i < overview.peakAlphaFreq.length
          ? overview.peakAlphaFreq[i]
          : null;
    }
  }

  return _Prepared(
    x: x,
    alphaRel: alphaRel,
    thetaRel: thetaRel,
    movement: movement,
    movementX: movementX,
    bpm: bpm,
    bpmX: bpmX,
    bandsCount: overview.bands.length,
    stats: _SessionStats(
      peakAlphaFreq: peakFreq,
      peakAlphaPower: peakPower,
      targetPct: x.isEmpty ? 0 : targetSeconds / x.length * 100,
      stillnessPct: movement.isEmpty ? 0 : still / movement.length * 100,
      avgBpm: bpm.isEmpty ? null : bpmSum / bpm.length,
      avgAlphaRel: alphaRel.isEmpty ? 0 : alphaRelSum / alphaRel.length,
    ),
  );
}

/// Per-electrode band powers for bucket [i] from a summary series: `(delta,
/// theta, alpha, beta, gamma)` or null when that electrode/bucket has no data.
(double, double, double, double, double)? _bandAt(
  BandPowerSeries? series,
  int i,
) {
  if (series == null ||
      i >= series.delta.length ||
      series.delta[i] == null ||
      series.theta[i] == null ||
      series.alpha[i] == null ||
      series.beta[i] == null ||
      series.gamma[i] == null) {
    return null;
  }
  return (
    series.delta[i]!,
    series.theta[i]!,
    series.alpha[i]!,
    series.beta[i]!,
    series.gamma[i]!,
  );
}

/// Convert a parsed band record (or null) to the `(delta, theta, alpha, beta,
/// gamma)` tuple form used by [_relativeAfRel].
(double, double, double, double, double)? _afTuple(BandsRecord? band) {
  if (band == null) {
    return null;
  }
  return (band.delta, band.theta, band.alpha, band.beta, band.gamma);
}

/// Combined relative alpha/theta for one time point from the two frontal pads.
/// A pad with missing/zero total band power is dropped for that sample (matching
/// the ATR autodrop), so a session where only one AF pad was healthy still
/// builds the graph. Returns null only when neither pad is usable.
(double, double)? _relativeAfRel(
  (double, double, double, double, double)? af7,
  (double, double, double, double, double)? af8,
) {
  var aSum = 0.0;
  var tSum = 0.0;
  var count = 0;
  for (final band in [af7, af8]) {
    if (band == null) {
      continue;
    }
    final total = band.$1 + band.$2 + band.$3 + band.$4 + band.$5;
    if (total <= 0) {
      continue;
    }
    aSum += band.$3 / total;
    tSum += band.$2 / total;
    count++;
  }
  if (count == 0) {
    return null;
  }
  return (aSum / count, tSum / count);
}

class _Series {
  const _Series({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<double> values;
}

class _SeriesChart extends StatelessWidget {
  const _SeriesChart({
    required this.title,
    required this.unit,
    required this.series,
    required this.x,
  });

  final String title;
  final String unit;
  final List<_Series> series;
  final List<double> x;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                Text(unit, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(s.label, style: theme.textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (x.isEmpty || series.any((s) => s.values.length != x.length))
              SizedBox(
                height: 140,
                width: double.infinity,
                child: Center(
                  child: Text(
                    'No data',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 140,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ChartPainter(series: series, x: x),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmtTime(x.first), style: theme.textTheme.bodySmall),
                  Text(_fmtTime(x.last), style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _fmtTime(double seconds) {
  final s = seconds < 0 ? 0 : seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({required this.series, required this.x});

  final List<_Series> series;
  final List<double> x;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || x.isEmpty || x.last <= x.first) {
      return;
    }
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final s in series) {
      for (final v in s.values) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double px(double v) => pad + (v - x.first) / (x.last - x.first) * w;
    double py(double v) => pad + h - (v - minY) / (maxY - minY) * h;

    final grid = Paint()
      ..color = const Color(0x222A2D37)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = pad + h * i / 3;
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), grid);
    }

    for (final s in series) {
      if (s.values.length != x.length) {
        continue;
      }
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final path = Path();
      final pts = <Offset>[];
      for (var i = 0; i < s.values.length; i++) {
        pts.add(Offset(px(x[i]), py(s.values[i])));
      }
      _buildSmoothPath(path, pts);
      canvas.drawPath(path, paint);
    }
  }

  /// Catmull-Rom → cubic Bezier smoothing (same as the live bands graph), so
  /// the summary curves are rounded instead of spiky.
  void _buildSmoothPath(Path path, List<Offset> pts) {
    if (pts.isEmpty) return;
    path.moveTo(pts[0].dx, pts[0].dy);
    if (pts.length < 2) return;
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.x != x;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No session recording found.',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.theme,
    required this.error,
    required this.onDiscard,
  });

  final ThemeData theme;
  final Object error;
  final Future<void> Function()? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(
              'Could not load session: $error',
              style: theme.textTheme.bodySmall,
            ),
            if (onDiscard != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onDiscard,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Discard session'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
