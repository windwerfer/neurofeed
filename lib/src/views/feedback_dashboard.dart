import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/session_reader.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/target_state.dart';

class FeedbackDashboardView extends ConsumerStatefulWidget {
  const FeedbackDashboardView({
    super.key,
    this.sessionPath,
    this.metadata,
    this.readOnly = false,
  });

  final String? sessionPath;
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final path =
        widget.sessionPath ??
        ref.read(feedbackStateProvider.notifier).sessionFilePath;
    if (path != null) {
      _dataFuture = SessionReader.read(File(path));
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('${protocol.title} — Session')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _dataFuture == null
              ? _NoData(theme: theme)
              : FutureBuilder<SessionData>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _LoadError(
                        theme: theme,
                        error: snapshot.error!,
                        onDiscard: widget.readOnly ? null : _discard,
                      );
                    }
                    final data = snapshot.data!;
                    _prepared ??= _prepare(data);
                    if (_thumbnail == null && !widget.readOnly) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
                    }
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
                  },
                ),
    );
  }

  Future<void> _capture() async {
    final boundary = _thumbKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
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
    final saved = await notifier.saveSession();
    if (saved != null) {
      final stats = _prepared?.stats;
      await ref.read(sessionStoreProvider).writeMetadata(
        saved,
        SessionMetadata(
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
        ),
      );
      if (_thumbnail != null) {
        final pngPath = saved.path.replaceFirst(RegExp(r'\.muse$'), '.png');
        try {
          await File(pngPath).writeAsBytes(_thumbnail!);
        } catch (e) {
          debugPrint('[dashboard] thumbnail save failed: $e');
        }
      }
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
                _SummaryRow(
                  label: 'Duration',
                  value: '$durationMinutes min',
                ),
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
            detail: 'Not enough signal data was recorded to build this graph. '
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
            detail: 'No reliable heart-rate data was captured for this session.',
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
    final af7 = ch[electrodeAf7];
    final af8 = ch[electrodeAf8];
    if (af7 == null || af8 == null) {
      continue;
    }
    final total7 = af7.delta + af7.theta + af7.alpha + af7.beta + af7.gamma;
    final total8 = af8.delta + af8.theta + af8.alpha + af8.beta + af8.gamma;
    if (total7 <= 0 || total8 <= 0) {
      continue;
    }
    final aRel = (af7.alpha / total7 + af8.alpha / total8) / 2;
    final tRel = (af7.theta / total7 + af8.theta / total8) / 2;
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
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
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
      for (var i = 0; i < s.values.length; i++) {
        final pt = Offset(px(x[i]), py(s.values[i]));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, paint);
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
            Text('Could not load session: $error',
                style: theme.textTheme.bodySmall),
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
