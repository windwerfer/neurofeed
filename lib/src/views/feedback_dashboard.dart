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
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/feedback/session_chart_data.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_summary.dart';
import 'package:muse_ml/src/reve/models.dart';
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
  SessionChartData? _prepared;
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
        final protocol = ProtocolInfo.forType(
          widget.metadata?.protocol ?? ProtocolType.drowsiness,
        );
        _prepared = prepareChartDataFromOverview(
          summary,
          metric: protocol.rewardMetric,
          conditions: protocol.conditions,
        );
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
    final copy = useProtocolCopy(ref, protocol);

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
        appBar: AppBar(title: Text('${copy.title} — Session')),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _dashboard(meta, fb, protocol, copy.title),
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
    String protocolTitle,
  ) {
    if (_prepared != null) {
      return _DashboardBody(
        protocol: protocol,
        protocolTitle: protocolTitle,
        durationMinutes: meta?.durationMinutes ?? fb.durationMinutes,
        elapsedSeconds: meta?.elapsedSeconds ?? fb.elapsedSeconds,
        soundName: meta?.sound ?? fb.soundName,
        feedbackSoundName: widget.readOnly
            ? (meta?.feedbackSound == null
                  ? null
                  : feedbackModeFromName(meta!.feedbackSound!).label)
            : fb.feedbackMode.label,
        prepared: _prepared!,
        drowsiness: widget.readOnly
            ? meta?.drowsiness
            : ref.read(feedbackStateProvider.notifier).sessionDrowsiness,
        music: widget.readOnly
            ? meta?.music
            : ref.read(feedbackStateProvider.notifier).sessionMusic,
        trainingStartOffsetSecs: _trainingStartOffset,
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
        _prepared ??= prepareChartData(
          data,
          trainingStartOffset: _trainingStartOffset,
          metric: protocol.rewardMetric,
          conditions: protocol.conditions,
        );
        _sessionData ??= data;
        // Legacy session without an embedded summary: fold the freshly
        // computed overview back into the metadata cache so the next open
        // fast-paths without re-parsing the .muse body.
        if (widget.readOnly &&
            widget.sessionId != null &&
            widget.metadata?.summary == null) {
          unawaited(() async {
            final store = await ref.read(sessionStoreProvider.future);
            await store.cacheOverview(
              widget.sessionId!,
              SessionOverview.fromData(
                data,
                trainingStartSecs: _trainingStartOffset,
              ),
            );
          }());
        }
        if (_thumbnail == null && !widget.readOnly) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
        }
        return _dashboard(meta, fb, protocol, protocolTitle);
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
        feedbackSound: fb.feedbackMode.name,
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
        drowsiness: notifier.sessionDrowsiness,
        music: notifier.sessionMusic,
        metadataDescription: ref
            .read(protocolCatalogProvider)
            .valueOrNull
            ?.forName(fb.protocol.name)
            ?.metadataDescription,
        sessionSettings: _captureSessionSettings(notifier, fb),
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

  /// Snapshots the session-affecting settings at save time so a saved file
  /// stays interpretable without the live prefs (recorded as
  /// [SessionMetadata.sessionSettings]).
  SessionSettings _captureSessionSettings(
    FeedbackStateNotifier notifier,
    FeedbackState fb,
  ) {
    final settings = ref.read(settingsProvider);
    final engine = guardrailEngineFromSettings(settings);
    return SessionSettings(
      dynamicAdapt: notifier.dynamicAdapt,
      responsiveness: notifier.responsiveness,
      baselinePercentile: fb.baselinePercentile,
      guardrailEnabled: notifier.guardrailEnabled,
      guardrailEngine: notifier.guardrailEnabled ? engine.name : 'none',
      warningThresholdPercentile: settings.warningThresholdPercentile,
      warningSound: settings.warningSoundName,
      musicFolder: settings.musicFolder,
      musicMinCutoffHz: settings.musicMinCutoffHz,
      musicMaxCutoffHz: settings.musicMaxCutoffHz,
      musicInvert: settings.musicInvertMapping,
      musicShuffle: settings.musicShuffle,
      binauralPresetId: settings.binauralPresetId,
      binauralCarrierHz: settings.binauralCarrierHz,
      binauralBeatHz: settings.binauralBeatHz,
      markersInFeedbackEnabled: settings.markersInFeedbackEnabled,
      eyeMarkersEnabled: settings.eyeMarkersEnabled,
    );
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
    required this.protocolTitle,
    required this.durationMinutes,
    required this.elapsedSeconds,
    required this.soundName,
    this.feedbackSoundName,
    required this.prepared,
    this.drowsiness,
    this.music,
    this.trainingStartOffsetSecs,
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
  final String protocolTitle;
  final int durationMinutes;
  final int elapsedSeconds;
  final String soundName;
  final String? feedbackSoundName;
  final SessionChartData prepared;

  /// Sleep-guardrail trace of this session (null when the guardrail did not
  /// run or recorded nothing).
  final SessionDrowsiness? drowsiness;

  /// Music-feedback record (track list + cutoff trace) of this session (null
  /// when music feedback did not run).
  final SessionMusic? music;

  /// Seconds from recording start to the training boundary; drowsiness
  /// offsets are wall-clock-relative to session start, so subtracting this
  /// aligns the trace with the training-window chart axis.
  final double? trainingStartOffsetSecs;

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
    final drowsy = widget.drowsiness;
    if (drowsy != null) {
      if (drowsy.buckets.isNotEmpty) {
        take([drowsy.buckets.last.offsetSecs + drowsy.bucketWidthSecs]);
      } else if (drowsy.series.isNotEmpty) {
        take([
          drowsy.series.last.offsetSecs - (widget.trainingStartOffsetSecs ?? 0),
        ]);
      }
    }
    final music = widget.music;
    if (music != null) {
      if (music.buckets.isNotEmpty) {
        take([music.buckets.last.offsetSecs + music.bucketWidthSecs]);
      } else if (music.series.isNotEmpty) {
        take([
          music.series.last.offsetSecs - (widget.trainingStartOffsetSecs ?? 0),
        ]);
      }
    }
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
      double? fixedYMinRight,
      double? fixedYMaxRight,
    }) {
      return _ZoomableChart(
        title: title,
        unit: unit,
        series: series,
        x: xs,
        viewport: vp,
        fixedYMin: fixedYMin,
        fixedYMax: fixedYMax,
        fixedYMinRight: fixedYMinRight,
        fixedYMaxRight: fixedYMaxRight,
      );
    }

    final notEnough = _notEnoughData;

    // Sleep-guardrail trace widgets for the current session: the model's
    // sleep-direction line vs the baseline warning threshold. Empty when the
    // guardrail produced no samples.
    List<Widget> drowsinessWidgets() {
      final drowsy = widget.drowsiness;
      if (drowsy == null || (drowsy.series.isEmpty && drowsy.buckets.isEmpty)) {
        return const [];
      }
      final offset = widget.trainingStartOffsetSecs ?? 0;
      final xs = drowsy.buckets.isNotEmpty
          ? [for (final b in drowsy.buckets) b.offsetSecs]
          : [
              for (final s in drowsy.series)
                (s.offsetSecs - offset).clamp(0.0, 1e9),
            ];
      final sleepDir = drowsy.buckets.isNotEmpty
          ? [for (final b in drowsy.buckets) b.sleepDir]
          : [for (final s in drowsy.series) s.sleepDir];
      final threshold = drowsy.threshold ?? double.nan;
      return [
        chart('Sleep guardrail (AI model)', 'sleep-dir score', [
          _Series(
            label: 'Sleep direction',
            color: const Color(0xFF1E88E5),
            values: sleepDir,
          ),
          if (threshold.isFinite)
            _Series(
              label: 'Warning threshold',
              color: const Color(0xFFFFA726),
              values: List.filled(xs.length, threshold),
            ),
        ], xs),
        const SizedBox(height: 16),
      ];
    }

    // Music-feedback widgets: the low-pass cutoff the reward drove (bounded by
    // the configured range) plus the track list with the offsets they started
    // at. Empty when music feedback produced no samples.
    String formatOffset(double secs) {
      if (secs.isNaN || secs < 0) {
        return '00:00';
      }
      final m = secs ~/ 60;
      final s = (secs % 60).toStringAsFixed(0).padLeft(2, '0');
      return '$m:$s';
    }

    List<Widget> musicWidgets() {
      final music = widget.music;
      if (music == null || (music.series.isEmpty && music.buckets.isEmpty)) {
        return const [];
      }
      final offset = widget.trainingStartOffsetSecs ?? 0;
      final xs = music.buckets.isNotEmpty
          ? [for (final b in music.buckets) b.offsetSecs]
          : [
              for (final s in music.series)
                (s.offsetSecs - offset).clamp(0.0, 1e9),
            ];
      final hz = music.buckets.isNotEmpty
          ? [for (final b in music.buckets) b.cutoffHz]
          : [for (final s in music.series) s.cutoffHz];
      return [
        Card(
          color: theme.colorScheme.surface,
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.music_note_outlined),
                    const SizedBox(width: 8),
                    Text('Music feedback', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    if (music.trackCount > 0)
                      Text(
                        '${music.trackCount} track(s)'
                        '${music.shuffle ? ' · shuffled' : ''}'
                        '${music.invert ? ' · inverted' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                chart('Low-pass cutoff', 'Hz', [
                  _Series(
                    label: 'Cutoff',
                    color: const Color(0xFF8E24AA),
                    values: hz,
                  ),
                  _Series(
                    label: 'Max',
                    color: const Color(0xFFBDBDBD),
                    values: List.filled(xs.length, music.maxCutoffHz),
                  ),
                  _Series(
                    label: 'Min',
                    color: const Color(0xFFBDBDBD),
                    values: List.filled(xs.length, music.minCutoffHz),
                  ),
                ], xs),
                if (music.tracks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Tracks', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final t in music.tracks)
                    if (t.name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.skip_next_outlined,
                              size: 16,
                              color: Color(0xFF8E24AA),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatOffset(t.offsetSecs - offset),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ];
    }

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
                _SummaryRow(label: 'Protocol', value: widget.protocolTitle),
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
                if (widget.feedbackSoundName != null)
                  _SummaryRow(
                    label: 'Feedback sound',
                    value: widget.feedbackSoundName!,
                  ),
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
                      if (widget.drowsiness != null) ...[
                        _StatChip(
                          label: 'Drift time',
                          value:
                              '${widget.drowsiness!.scoreTotalPct.toStringAsFixed(0)}%',
                          icon: Icons.nightlight_outlined,
                          color: const Color(0xFF1E88E5),
                        ),
                      ],
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
        if (prepared.bpm.isNotEmpty || prepared.spo2.isNotEmpty) ...[
          chart(
            'Heart rate / SpO₂',
            'bpm / %',
            [
              if (prepared.bpm.isNotEmpty)
                _Series(
                  label: 'Pulse (bpm)',
                  color: const Color(0xFFEC407A),
                  values: prepared.bpm,
                  axis: _AxisSide.left,
                  avgLineValue: stats.avgBpm,
                  avgLineStyle: const _AvgLineStyle(
                    dashPattern: [8, 4],
                    strokeWidth: 0.8,
                  ),
                ),
              if (prepared.spo2.isNotEmpty)
                _Series(
                  label: 'SpO₂ (%)',
                  color: const Color(0xFF26C6DA),
                  values: prepared.spo2,
                  axis: _AxisSide.right,
                  avgLineValue: stats.avgSpo2,
                  avgLineStyle: const _AvgLineStyle(
                    dashPattern: [3, 3],
                    strokeWidth: 0.8,
                  ),
                ),
            ],
            // Use bpmX for X-axis (both series share time base)
            prepared.bpm.isNotEmpty ? prepared.bpmX : prepared.spo2X,
            fixedYMin: 40,
            fixedYMax: 200,
            fixedYMinRight: 50,
            fixedYMaxRight: 100,
          ),
          const SizedBox(height: 16),
        ] else ...[
          notEnough(
            'Heart rate / SpO₂',
            'No reliable heart-rate or SpO₂ data was captured for this session.',
          ),
          const SizedBox(height: 16),
        ],
        ...drowsinessWidgets(),
        ...musicWidgets(),
      ],
    );
  }
}

_NotEnoughData _notEnoughData(String title, String detail) =>
    _NotEnoughData(title: title, detail: detail);

enum _AxisSide { left, right }

class _Series {
  const _Series({
    required this.label,
    required this.color,
    required this.values,
    this.axis = _AxisSide.left,
    this.avgLineValue,
    this.avgLineStyle,
  });

  final String label;
  final Color color;
  final List<double> values;
  final _AxisSide axis;

  /// Optional horizontal average line value
  final double? avgLineValue;
  /// Style for the average line (dashed/dotted, color defaults to series color)
  final _AvgLineStyle? avgLineStyle;
}

class _AvgLineStyle {
  const _AvgLineStyle({
    required this.dashPattern,
    this.strokeWidth = 0.8,
  });

  /// Dash pattern: [dash, gap] in pixels
  final List<double> dashPattern;
  final double strokeWidth;
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
    this.fixedYMinRight,
    this.fixedYMaxRight,
  });

  final String title;
  final String unit;
  final List<_Series> series;
  final List<double> x;
  final _ChartViewport viewport;

  /// Optional fixed y bounds for left axis (e.g. 0..1 relative power) so the scale
  /// matches across sessions.
  final double? fixedYMin;
  final double? fixedYMax;
  /// Optional fixed y bounds for right axis (e.g. SpO2 50..100).
  final double? fixedYMinRight;
  final double? fixedYMaxRight;

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
                                        yMinLeft: widget.fixedYMin,
                                        yMaxLeft: widget.fixedYMax,
                                        yMinRight: widget.fixedYMinRight,
                                        yMaxRight: widget.fixedYMaxRight,
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
    this.yMinLeft,
    this.yMaxLeft,
    this.yMinRight,
    this.yMaxRight,
  });

  final List<_Series> series;
  final List<double> x;
  final double viewStart;
  final double viewEnd;

  /// Left Y-axis fixed bounds (e.g. for HR: bpm). When null, auto-fit.
  final double? yMinLeft;
  final double? yMaxLeft;
  /// Right Y-axis fixed bounds (e.g. for SpO2: %). When null, auto-fit.
  final double? yMinRight;
  final double? yMaxRight;

  static const double _yGutter = 34;
  static const double _rightGutter = 34;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || x.isEmpty || viewEnd <= viewStart) {
      return;
    }

    // Separate series by axis side
    final leftSeries = series.where((s) => s.axis == _AxisSide.left).toList();
    final rightSeries = series.where((s) => s.axis == _AxisSide.right).toList();

    // Compute Y ranges for each axis
    final leftRange = _computeRange(leftSeries, yMinLeft, yMaxLeft);
    final rightRange = _computeRange(rightSeries, yMinRight, yMaxRight);

    if (leftRange == null && rightRange == null) return;

    const pad = 8.0;
    final w = size.width - _yGutter - _rightGutter - pad;
    final h = size.height - pad * 2;
    final x0 = pad + _yGutter;

    // X projection (shared)
    double px(double v) => x0 + (v - viewStart) / (viewEnd - viewStart) * w;
    // Left Y projection
    double pyLeft(double v) => leftRange != null
        ? pad + h - (v - leftRange.$1) / (leftRange.$2 - leftRange.$1) * h
        : size.height / 2;
    // Right Y projection
    double pyRight(double v) => rightRange != null
        ? pad + h - (v - rightRange.$1) / (rightRange.$2 - rightRange.$1) * h
        : size.height / 2;

    // Grid paint
    final grid = Paint()
      ..color = const Color(0x222A2D37)
      ..strokeWidth = 1;

    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final y = pad + h * i / ticks;
      canvas.drawLine(Offset(x0 - 4, y), Offset(x0, y), grid);
      canvas.drawLine(Offset(x0, y), Offset(x0 + w, y), grid);
    }

    // Left Y tick labels (fixed scale only)
    if (yMinLeft != null && yMaxLeft != null && leftRange != null) {
      final tp = TextPainter(
        text: const TextSpan(),
        textDirection: TextDirection.ltr,
      );
      for (var i = 0; i <= ticks; i++) {
        final t = leftRange.$2 - (leftRange.$2 - leftRange.$1) * i / ticks;
        tp.text = TextSpan(
          text: t.toStringAsFixed(0),
          style: const TextStyle(color: Color(0xFF9AA0AE), fontSize: 9),
        );
        tp.layout();
        final y = pad + h * i / ticks;
        tp.paint(canvas, Offset(x0 - 4 - tp.width, y - tp.height / 2));
      }
    }

    // Right Y tick labels (fixed scale only)
    if (yMinRight != null && yMaxRight != null && rightRange != null) {
      final tp = TextPainter(
        text: const TextSpan(),
        textDirection: TextDirection.ltr,
      );
      for (var i = 0; i <= ticks; i++) {
        final t = rightRange.$2 - (rightRange.$2 - rightRange.$1) * i / ticks;
        tp.text = TextSpan(
          text: t.toStringAsFixed(0),
          style: const TextStyle(color: Color(0xFF9AA0AE), fontSize: 9),
        );
        tp.layout();
        final y = pad + h * i / ticks;
        tp.paint(canvas, Offset(x0 + w + 4, y - tp.height / 2));
      }
    }

    // Draw average lines first (behind series)
    for (final s in series) {
      if (s.avgLineValue != null) {
        final isLeft = s.axis == _AxisSide.left;
        final range = isLeft ? leftRange : rightRange;
        if (range == null) continue;
        final py = isLeft ? pyLeft : pyRight;
        final lineY = py(s.avgLineValue!);
        if (lineY < pad || lineY > pad + h) continue;

        final style = s.avgLineStyle ?? _AvgLineStyle(dashPattern: [4, 4]);
        final paint = Paint()
          ..color = s.color.withValues(alpha: 0.6)
          ..strokeWidth = style.strokeWidth
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
        // Draw dashed/dotted line
        _drawDashedLine(canvas, paint, Offset(x0, lineY), Offset(x0 + w, lineY),
            style.dashPattern);
      }
    }

    // Draw series lines
    for (final s in series) {
      if (s.values.length != x.length) continue;
      final isLeft = s.axis == _AxisSide.left;
      final range = isLeft ? leftRange : rightRange;
      if (range == null) continue;
      final py = isLeft ? pyLeft : pyRight;

      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final path = Path();
      final pts = <Offset>[];
      for (var i = 0; i < s.values.length; i++) {
        if (x[i] < viewStart || x[i] > viewEnd) continue;
        pts.add(Offset(px(x[i]), py(s.values[i])));
      }
      if (pts.isNotEmpty && pts.length < 2) {
        canvas.drawCircle(pts.first, 1.6, paint);
        continue;
      }
      buildSmoothPath(path, pts);
      canvas.drawPath(path, paint);
    }
  }

  static (double, double)? _computeRange(
    List<_Series> series,
    double? fixedMin,
    double? fixedMax,
  ) {
    if (series.isEmpty) return null;
    if (fixedMin != null && fixedMax != null) return (fixedMin, fixedMax);

    final visibleValues = <double>[];
    for (final s in series) {
      for (final v in s.values) {
        visibleValues.add(v);
      }
    }

    if (visibleValues.isEmpty) return null;
    visibleValues.sort();
    final p5 = visibleValues[(visibleValues.length * 0.05).floor()];
    final p95 = visibleValues[(visibleValues.length * 0.95).floor()];
    final range = math.max(p95 - p5, 1e-6);

    final minY = fixedMin ?? p5 - range * 0.1;
    final maxY = fixedMax ?? p95 + range * 0.1;
    if (minY == maxY) return (minY - 1, maxY + 1);
    return (minY, maxY);
  }

  static void _drawDashedLine(
    Canvas canvas,
    Paint paint,
    Offset p1,
    Offset p2,
    List<double> dashPattern,
  ) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;

    var drawn = 0.0;
    var dashOn = true;
    var patternIndex = 0;
    var curX = p1.dx;
    var curY = p1.dy;
    final stepX = dx / dist;
    final stepY = dy / dist;

    while (drawn < dist) {
      final segment = dashPattern[patternIndex % dashPattern.length];
      patternIndex++;
      if (dashOn) {
        final endX = curX + stepX * segment;
        final endY = curY + stepY * segment;
        canvas.drawLine(Offset(curX, curY), Offset(endX, endY), paint);
        curX = endX;
        curY = endY;
      } else {
        curX += stepX * segment;
        curY += stepY * segment;
      }
      drawn += segment;
      dashOn = !dashOn;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.x != x ||
      oldDelegate.viewStart != viewStart ||
      oldDelegate.viewEnd != viewEnd ||
      oldDelegate.yMinLeft != yMinLeft ||
      oldDelegate.yMaxLeft != yMaxLeft ||
      oldDelegate.yMinRight != yMinRight ||
      oldDelegate.yMaxRight != yMaxRight;
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
