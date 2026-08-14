import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/band_cache.dart' show bandColors, bandNames;
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/charts/session_reader.dart';
import 'package:muse_ml/src/charts/smooth_path.dart';
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

  /// Notes value that is persisted on disk (used to detect unsaved edits).
  String _savedNotes = '';
  bool _notesSaving = false;
  bool _notesSavedFlash = false;
  Timer? _notesFlashTimer;

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
    _savedNotes = _notes.text;
    _notes.addListener(_onNotesChanged);
  }

  bool get _notesDirty => _notes.text != _savedNotes;

  /// Offset (seconds from recording start) where training began, for trimming
  /// the displayed window/metrics to the training portion. Live sessions read
  /// it from the notifier; history sessions from the stored calibration record
  /// (null on old files → full-window rendering, as before).
  double? get _trainingStartOffset {
    if (widget.readOnly) {
      return widget.metadata?.calibration?.trainingStartOffsetSecs;
    }
    return ref.read(feedbackStateProvider.notifier).trainingStartOffsetSecs;
  }

  void _onNotesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _notes.removeListener(_onNotesChanged);
    _notesFlashTimer?.cancel();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fb = ref.watch(feedbackStateProvider);
    final meta = widget.metadata;
    final protocol = ProtocolInfo.forType(meta?.protocol ?? fb.protocol);

    return PopScope(
      // Warn before leaving a history session with unsaved notes edits. The
      // live session view has its own explicit Save/Discard path, so it is
      // not guarded here.
      canPop: !widget.readOnly || !_notesDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _confirmUnsavedNotes();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${protocol.title} — Session')),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _dashboard(meta, fb, protocol),
      ),
    );
  }

  /// Back-navigation guard for the read-only history detail with unsaved notes.
  /// Offers to save before leaving.
  Future<void> _confirmUnsavedNotes() async {
    final theme = Theme.of(context);
    final action = await showDialog<_UnsavedNotesChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved notes'),
        content: const Text(
          'You edited the notes for this session. Save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnsavedNotesChoice.leave),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnsavedNotesChoice.cancel),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
            ),
            onPressed: () =>
                Navigator.of(context).pop(_UnsavedNotesChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case _UnsavedNotesChoice.save:
        await _saveNotes();
        if (mounted && !_notesDirty) {
          Navigator.of(context).pop();
        }
        break;
      case _UnsavedNotesChoice.leave:
        Navigator.of(context).pop();
        break;
      case _UnsavedNotesChoice.cancel:
      case null:
        break;
    }
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
        onSaveNotes: widget.readOnly ? _saveNotes : null,
        notesDirty: _notesDirty,
        notesSaving: _notesSaving,
        notesSavedFlash: _notesSavedFlash,
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
        _prepared ??= _prepare(data, trainingStartOffset: _trainingStartOffset);
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
            : SessionOverview.fromData(
                _sessionData!,
                trainingStartSecs: notifier.trainingStartOffsetSecs,
              ),
        gestures: ref.read(settingsProvider).markersInFeedbackEnabled
            ? notifier.gestureMarkers
            : const [],
        calibration: notifier.calibration,
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

  /// Persist edited notes back into a saved (history) session file. Only wired
  /// for the read-only detail view, where there is no live session to save.
  Future<void> _saveNotes() async {
    final id = widget.sessionId;
    if (id == null) {
      return;
    }
    setState(() => _notesSaving = true);
    final store = await ref.read(sessionStoreProvider.future);
    final ok = await store.updateNotes(id, _notes.text);
    ref.invalidate(sessionListProvider);
    if (!mounted) {
      return;
    }
    setState(() {
      _notesSaving = false;
      if (ok) {
        _savedNotes = _notes.text;
        _notesSavedFlash = true;
      }
    });
    _notesFlashTimer?.cancel();
    _notesFlashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _notesSavedFlash = false);
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not save notes'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
  }
}

class _DashboardBody extends StatefulWidget {
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
    this.onSaveNotes,
    this.notesDirty = false,
    this.notesSaving = false,
    this.notesSavedFlash = false,
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
  final Future<void> Function()? onSaveNotes;
  final bool notesDirty;
  final bool notesSaving;
  final bool notesSavedFlash;

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  late final _ChartViewport _viewport;

  @override
  void initState() {
    super.initState();
    final p = widget.prepared;
    var end = widget.elapsedSeconds.toDouble();
    void take(List<double> xs) {
      if (xs.isNotEmpty && xs.last > end) end = xs.last;
    }

    take(p.x);
    take(p.movementX);
    take(p.bpmX);
    _viewport = _ChartViewport(0, math.max(end, 1.0));
  }

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = widget.prepared.stats;
    final prepared = widget.prepared;
    final vp = _viewport;

    Widget chart(
      String title,
      String unit,
      List<_Series> series,
      List<double> xs, {
      double? fixedYMin,
      double? fixedYMax,
    }) {
      return _ZoomableChart(
        title: title,
        unit: unit,
        series: series,
        x: xs,
        viewport: vp,
        fixedYMin: fixedYMin,
        fixedYMax: fixedYMax,
      );
    }

    final notEnough = _notEnoughData;

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
                _SummaryRow(label: 'Protocol', value: widget.protocol.title),
                _SummaryRow(
                  label: 'Duration',
                  value: '${widget.durationMinutes} min',
                ),
                _SummaryRow(
                  label: 'Elapsed',
                  value:
                      '${widget.elapsedSeconds ~/ 60}:'
                      '${(widget.elapsedSeconds % 60).toString().padLeft(2, '0')}',
                ),
                _SummaryRow(label: 'Background sound', value: widget.soundName),
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
            key: widget.thumbKey,
            child: chart(
              'Alpha vs Theta (relative power, AF7/AF8 avg)',
              'rel. power',
              [
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
              prepared.x,
              fixedYMin: 0,
              fixedYMax: 1,
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          notEnough(
            'Alpha vs Theta',
            'Not enough signal data was recorded to build this graph. '
                'This usually means the headband was not in good contact or the '
                'connection dropped during the session. Check the electrodes and '
                'try again.',
          ),
          const SizedBox(height: 16),
        ],
        Stack(
          children: [
            TextField(
              controller: widget.notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.onSaveNotes != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: _NotesStatusIcon(
                  dirty: widget.notesDirty,
                  saving: widget.notesSaving,
                  savedFlash: widget.notesSavedFlash,
                  onSave: widget.onSaveNotes,
                ),
              ),
          ],
        ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onSave,
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
                  onPressed: widget.onDiscard,
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
        const SizedBox(height: 16),
        if (prepared.x.isNotEmpty) ...[
          chart(
            'Bands (relative power, AF7/AF8 avg)',
            'rel. power',
            [
              _Series(
                label: bandNames[0],
                color: bandColors[0],
                values: prepared.deltaRel,
              ),
              _Series(
                label: bandNames[1],
                color: bandColors[1],
                values: prepared.thetaRel,
              ),
              _Series(
                label: bandNames[2],
                color: bandColors[2],
                values: prepared.alphaRel,
              ),
              _Series(
                label: bandNames[3],
                color: bandColors[3],
                values: prepared.betaRel,
              ),
              _Series(
                label: bandNames[4],
                color: bandColors[4],
                values: prepared.gammaRel,
              ),
            ],
            prepared.x,
            fixedYMin: 0,
            fixedYMax: 1,
          ),
          const SizedBox(height: 16),
        ] else ...[
          notEnough(
            'Bands',
            'Not enough signal data was recorded to build this graph.',
          ),
          const SizedBox(height: 16),
        ],
        if (prepared.movement.isNotEmpty) ...[
          chart('Movement score', 'g stddev', [
            _Series(
              label: 'Movement',
              color: const Color(0xFFFFA726),
              values: prepared.movement,
            ),
          ], prepared.movementX),
          const SizedBox(height: 16),
        ] else ...[
          notEnough(
            'Movement score',
            'No movement data was recorded for this session.',
          ),
          const SizedBox(height: 16),
        ],
        if (prepared.bpm.isNotEmpty) ...[
          chart('Heart rate', 'bpm', [
            _Series(
              label: 'Pulse',
              color: const Color(0xFFEC407A),
              values: prepared.bpm,
            ),
          ], prepared.bpmX),
          const SizedBox(height: 16),
        ] else ...[
          notEnough(
            'Heart rate',
            'No reliable heart-rate data was captured for this session.',
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _Prepared {
  final List<double> x;
  final List<double> alphaRel;
  final List<double> thetaRel;
  final List<double> deltaRel;
  final List<double> betaRel;
  final List<double> gammaRel;
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
    required this.deltaRel,
    required this.betaRel,
    required this.gammaRel,
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

_Prepared _prepare(SessionData data, {double? trainingStartOffset}) {
  // When the session includes calibration, the displayed window and metrics
  // cover the training portion only. The boundary is an offset from the first
  // recorded event, so it works regardless of device-clock drift.
  double? cut;
  if (trainingStartOffset != null && trainingStartOffset > 0) {
    var allMin = double.infinity;
    for (final b in data.bands) {
      if (b.timestamp < allMin) allMin = b.timestamp;
    }
    for (final p in data.pulses) {
      if (p.timestamp < allMin) allMin = p.timestamp;
    }
    for (final m in data.movements) {
      if (m.timestamp < allMin) allMin = m.timestamp;
    }
    if (allMin.isFinite) {
      cut = allMin + trainingStartOffset;
    }
  }

  final bySecond = <int, Map<int, BandsRecord>>{};
  for (final b in data.bands) {
    bySecond.putIfAbsent(b.timestamp.floor(), () => {})[b.electrode] = b;
  }
  final seconds = bySecond.keys.toList()..sort();

  final x = <double>[];
  final alphaRel = <double>[];
  final thetaRel = <double>[];
  final deltaRel = <double>[];
  final betaRel = <double>[];
  final gammaRel = <double>[];
  var targetSeconds = 0;
  var alphaRelSum = 0.0;
  var startTs = seconds.isEmpty ? 0.0 : seconds.first.toDouble();
  if (cut != null && cut > startTs) {
    startTs = cut;
  }

  for (final s in seconds) {
    if (cut != null && s < cut) {
      continue;
    }
    final ch = bySecond[s]!;
    final all = _relativeAll(
      _afTuple(ch[electrodeAf7]),
      _afTuple(ch[electrodeAf8]),
    );
    if (all == null) {
      continue;
    }
    final aRel = all.$3;
    final tRel = all.$2;
    final dRel = all.$1;
    final bRel = all.$4;
    final gRel = all.$5;
    x.add(s - startTs);
    alphaRel.add(aRel);
    thetaRel.add(tRel);
    deltaRel.add(dRel);
    betaRel.add(bRel);
    gammaRel.add(gRel);
    alphaRelSum += aRel;
    if (aRel > tRel) {
      targetSeconds++;
    }
  }

  final movementX = <double>[];
  final movement = <double>[];
  var still = 0;
  for (final m in data.movements) {
    if (cut != null && m.timestamp < cut) {
      continue;
    }
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
    if (cut != null && p.timestamp < cut) {
      continue;
    }
    bpmX.add(p.timestamp - startTs);
    bpm.add(p.bpm);
    bpmSum += p.bpm;
  }

  double? peakFreq;
  double? peakPower;
  for (final p in data.peakAlphas) {
    if (cut != null && p.timestamp < cut) {
      continue;
    }
    if (peakPower == null || p.power > peakPower) {
      peakPower = p.power;
      peakFreq = p.frequency;
    }
  }

  return _Prepared(
    x: x,
    alphaRel: alphaRel,
    thetaRel: thetaRel,
    deltaRel: deltaRel,
    betaRel: betaRel,
    gammaRel: gammaRel,
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
  final deltaRel = <double>[];
  final betaRel = <double>[];
  final gammaRel = <double>[];
  var targetSeconds = 0;
  var alphaRelSum = 0.0;

  for (var i = 0; i < n; i++) {
    final all = _relativeAll(_bandAt(af7, i), _bandAt(af8, i));
    if (all == null) {
      continue;
    }
    final aRel = all.$3;
    final tRel = all.$2;
    final dRel = all.$1;
    final bRel = all.$4;
    final gRel = all.$5;
    x.add(i * width);
    alphaRel.add(aRel);
    thetaRel.add(tRel);
    deltaRel.add(dRel);
    betaRel.add(bRel);
    gammaRel.add(gRel);
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
    deltaRel: deltaRel,
    betaRel: betaRel,
    gammaRel: gammaRel,
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

/// Combined relative band powers for one time point from the two frontal pads.
/// A pad with missing/zero total band power is dropped for that sample (matching
/// the ATR autodrop), so a session where only one AF pad was healthy still
/// builds the graph. Returns null only when neither pad is usable.
/// Tuple is (delta, theta, alpha, beta, gamma) fractions of total power.
(double, double, double, double, double)? _relativeAll(
  (double, double, double, double, double)? af7,
  (double, double, double, double, double)? af8,
) {
  final sums = List<double>.filled(5, 0);
  var count = 0;
  for (final band in [af7, af8]) {
    if (band == null) {
      continue;
    }
    final total = band.$1 + band.$2 + band.$3 + band.$4 + band.$5;
    if (total <= 0) {
      continue;
    }
    sums[0] += band.$1 / total;
    sums[1] += band.$2 / total;
    sums[2] += band.$3 / total;
    sums[3] += band.$4 / total;
    sums[4] += band.$5 / total;
    count++;
  }
  if (count == 0) {
    return null;
  }
  return (
    sums[0] / count,
    sums[1] / count,
    sums[2] / count,
    sums[3] / count,
    sums[4] / count,
  );
}

_NotEnoughData _notEnoughData(String title, String detail) =>
    _NotEnoughData(title: title, detail: detail);

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

/// Shared time-window state for all summary graphs. Every chart renders the
/// exact same slice of the session, so zooming/panning one graph moves them all.
class _ChartViewport extends ChangeNotifier {
  _ChartViewport(this.fullStart, this.fullEnd)
    : _viewStart = fullStart,
      _viewEnd = fullEnd;

  final double fullStart;
  final double fullEnd;
  double _viewStart;
  double _viewEnd;

  double get viewStart => _viewStart;
  double get viewEnd => _viewEnd;
  double get span => _viewEnd - _viewStart;
  double get fullSpan => fullEnd - fullStart;
  bool get isZoomed => span < fullSpan - 1e-6;

  double get minSpan => math.max(1.0, fullSpan / 500);

  void setView(double start, double end) {
    var span = (end - start).clamp(minSpan, fullSpan);
    var s = start;
    if (s < fullStart) s = fullStart;
    if (s + span > fullEnd) s = fullEnd - span;
    _viewStart = s;
    _viewEnd = s + span;
    notifyListeners();
  }

  /// Keep the time under [frac] (0..1 of chart width) fixed while scaling the
  /// visible window by [factor] (>1 zooms in to a smaller slice).
  void zoomAtFrac({required double frac, required double factor}) {
    final newSpan = (span * factor).clamp(minSpan, fullSpan);
    final anchorT = _viewStart + frac * span;
    var s = anchorT - frac * newSpan;
    if (s > fullEnd - newSpan) s = fullEnd - newSpan;
    if (s < fullStart) s = fullStart;
    setView(s, s + newSpan);
  }

  /// Shift the window horizontally. Only meaningful while zoomed in; a fully
  /// zoomed-out view is already showing everything so nothing moves.
  void panByDx({required double dx, required double width}) {
    if (width <= 0 || !isZoomed) return;
    final dt = dx / width * span;
    var s = _viewStart - dt;
    if (s + span > fullEnd) s = fullEnd - span;
    if (s < fullStart) s = fullStart;
    setView(s, s + span);
  }

  void reset() => setView(fullStart, fullEnd);
}

class _ZoomableChart extends StatefulWidget {
  const _ZoomableChart({
    required this.title,
    required this.unit,
    required this.series,
    required this.x,
    required this.viewport,
    this.fixedYMin,
    this.fixedYMax,
  });

  final String title;
  final String unit;
  final List<_Series> series;
  final List<double> x;
  final _ChartViewport viewport;

  /// Optional fixed y bounds (e.g. 0..1 relative power) so the scale matches
  /// across sessions.
  final double? fixedYMin;
  final double? fixedYMax;

  @override
  State<_ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<_ZoomableChart> {
  double _gestureStartSpan = 0;
  double _gestureStartT = 0;
  double _gestureStartFrac = 0;
  double _chartWidth = 0;
  final Set<String> _hidden = {};

  void _toggleSeries(String label) {
    setState(() {
      if (!_hidden.add(label)) {
        _hidden.remove(label);
      }
    });
  }

  List<_Series> get _visibleSeries =>
      widget.series.where((s) => !_hidden.contains(s.label)).toList();

  void _onScaleStart(ScaleStartDetails d) {
    if (_chartWidth <= 0) return;
    _gestureStartSpan = widget.viewport.span;
    _gestureStartFrac = (d.localFocalPoint.dx / _chartWidth).clamp(0.0, 1.0);
    _gestureStartT =
        widget.viewport.viewStart + _gestureStartFrac * _gestureStartSpan;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_chartWidth <= 0) return;
    final newSpan = (_gestureStartSpan / d.scale).clamp(
      widget.viewport.minSpan,
      widget.viewport.fullSpan,
    );
    final curFrac = (d.localFocalPoint.dx / _chartWidth).clamp(0.0, 1.0);
    final start = _gestureStartT - curFrac * newSpan;
    widget.viewport.setView(start, start + newSpan);
  }

  void _onSignal(PointerSignalEvent e) {
    if (_chartWidth <= 0) return;
    // Desktop zoom deliberately requires the modifier so a plain wheel or
    // trackpad scroll still scrolls the page normally.
    final kb = HardwareKeyboard.instance;
    if (e is PointerScrollEvent) {
      if (!kb.isControlPressed && !kb.isMetaPressed) {
        return;
      }
      GestureBinding.instance.pointerSignalResolver.register(
        e,
        (_) => widget.viewport.zoomAtFrac(
          frac: (e.localPosition.dx / _chartWidth).clamp(0.0, 1.0),
          factor: math.exp(e.scrollDelta.dy * 0.002),
        ),
      );
    } else if (e is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(
        e,
        (_) => widget.viewport.zoomAtFrac(
          frac: (e.localPosition.dx / _chartWidth).clamp(0.0, 1.0),
          factor: e.scale,
        ),
      );
    }
  }

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
                  child: Text(widget.title, style: theme.textTheme.titleSmall),
                ),
                Text(widget.unit, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final s in widget.series)
                  GestureDetector(
                    onTap: () => _toggleSeries(s.label),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: _hidden.contains(s.label)
                                  ? Colors.transparent
                                  : theme.colorScheme.onSurfaceVariant
                                        .withAlpha(80),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          s.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _hidden.contains(s.label)
                                ? theme.colorScheme.onSurfaceVariant.withAlpha(
                                    140,
                                  )
                                : null,
                            decoration: _hidden.contains(s.label)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          _hidden.contains(s.label)
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.x.isEmpty ||
                widget.series.any((s) => s.values.length != widget.x.length))
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
            else
              ListenableBuilder(
                listenable: widget.viewport,
                builder: (context, _) {
                  final vp = widget.viewport;
                  final visible = _visibleSeries;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 140,
                        width: double.infinity,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _chartWidth = constraints.maxWidth;
                            return Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerSignal: _onSignal,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: _onScaleStart,
                                onScaleUpdate: _onScaleUpdate,
                                onDoubleTap: vp.reset,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(
                                      painter: _ChartPainter(
                                        series: visible,
                                        x: widget.x,
                                        viewStart: vp.viewStart,
                                        viewEnd: vp.viewEnd,
                                        yMin: widget.fixedYMin,
                                        yMax: widget.fixedYMax,
                                      ),
                                    ),
                                    if (visible.isEmpty)
                                      Center(
                                        child: Text(
                                          'All lines hidden — tap a label to show it',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmtTime(vp.viewStart),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (vp.isZoomed)
                            InkWell(
                              onTap: vp.reset,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fullscreen_exit,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Reset zoom',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              'pinch / ctrl+scroll to zoom, drag to pan',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Text(
                            _fmtTime(vp.viewEnd),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
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
  const _ChartPainter({
    required this.series,
    required this.x,
    required this.viewStart,
    required this.viewEnd,
    this.yMin,
    this.yMax,
  });

  final List<_Series> series;
  final List<double> x;
  final double viewStart;
  final double viewEnd;

  /// Optional fixed y bounds. When null the y-range is auto-fit to the visible
  /// data; when set (e.g. 0..1 relative power) the scale stays constant across
  /// sessions for direct comparison.
  final double? yMin;
  final double? yMax;

  static const double _yGutter = 34;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || x.isEmpty || viewEnd <= viewStart) {
      return;
    }

    var minY = yMin ?? double.infinity;
    var maxY = yMax ?? double.negativeInfinity;
    if (yMin == null || yMax == null) {
      for (final s in series) {
        if (s.values.length != x.length) {
          continue;
        }
        for (var i = 0; i < s.values.length; i++) {
          if (x[i] < viewStart || x[i] > viewEnd) {
            continue;
          }
          final v = s.values[i];
          if (v < minY) minY = v;
          if (v > maxY) maxY = v;
        }
      }
    }
    if (minY == double.infinity) {
      return;
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    const pad = 8.0;
    final w = size.width - _yGutter - pad;
    final h = size.height - pad * 2;
    final x0 = pad + _yGutter;
    double px(double v) => x0 + (v - viewStart) / (viewEnd - viewStart) * w;
    double py(double v) => pad + h - (v - minY) / (maxY - minY) * h;

    final grid = Paint()
      ..color = const Color(0x222A2D37)
      ..strokeWidth = 1;
    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final y = pad + h * i / ticks;
      canvas.drawLine(Offset(x0 - 4, y), Offset(x0, y), grid);
      canvas.drawLine(Offset(x0, y), Offset(x0 + w, y), grid);
    }

    // Y tick labels (only drawn for a fixed scale, where comparing matters).
    if (yMin != null && yMax != null) {
      final tp = TextPainter(
        text: const TextSpan(),
        textDirection: TextDirection.ltr,
      );
      for (var i = 0; i <= ticks; i++) {
        final t = maxY - (maxY - minY) * i / ticks;
        tp.text = TextSpan(
          text: t.toStringAsFixed(2),
          style: const TextStyle(color: Color(0xFF9AA0AE), fontSize: 9),
        );
        tp.layout();
        final y = pad + h * i / ticks;
        tp.paint(canvas, Offset(x0 - 4 - tp.width, y - tp.height / 2));
      }
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
        if (x[i] < viewStart || x[i] > viewEnd) {
          continue;
        }
        pts.add(Offset(px(x[i]), py(s.values[i])));
      }
      if (pts.isNotEmpty && pts.length < 2) {
        // A single visible sample shouldn't collapse to a dot.
        canvas.drawCircle(pts.first, 1.6, paint);
        continue;
      }
      buildSmoothPath(path, pts);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.x != x ||
      oldDelegate.viewStart != viewStart ||
      oldDelegate.viewEnd != viewEnd;
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

/// Outcome chosen from the unsaved-notes confirmation dialog.
enum _UnsavedNotesChoice { save, leave, cancel }

/// Discrete corner control for the notes field in the history detail view.
///
/// * dirty & idle → a small save chevron that persists the edit;
/// * saving → a compact spinner;
/// * just saved → a subtle check, fading out after a moment.
class _NotesStatusIcon extends StatelessWidget {
  const _NotesStatusIcon({
    required this.dirty,
    required this.saving,
    required this.savedFlash,
    this.onSave,
  });

  final bool dirty;
  final bool saving;
  final bool savedFlash;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (saving) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (savedFlash) {
      return Icon(Icons.check_circle_outline, size: 16, color: muted);
    }
    if (!dirty) {
      // Nothing to save — stay invisible so the field reads as a plain box.
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'Save notes',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onSave,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: Icon(Icons.check, size: 14),
            ),
          ),
        ),
      ),
    );
  }
}
