import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/charts/band_style.dart' show bandColors;
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';
import 'package:neurofeed/src/feedback/trust/trust_guard.dart';
import 'package:neurofeed/src/feedback/trust/trust_inhibit.dart';
import 'package:neurofeed/src/history/history_dashboard_summary.dart';
import 'package:neurofeed/src/history/history_trust_viewport.dart';
import 'package:neurofeed/src/history/session_trust.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/feedback/session_chart_data.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/monitor/views/recording_dashboard.dart';
import 'package:neurofeed/src/feedback/session_store.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';

enum _SessionSummaryChip {
  dashboard,
  feedback,
  bands,
  rawEeg,
  histogram,
  psd,
  spectrogram,
  hrSpo2,
  movement,
}

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

class _DashboardLoad {
  const _DashboardLoad({
    required this.prepared,
    required this.metadata,
    required this.stats,
    this.durationS,
    this.elapsedSeconds,
    this.feedback,
    this.trust,
    this.protocolDoc,
    this.guardFeature = guardFeatureNone,
    this.rewardLabel = '',
    this.guardLabel = '',
    required this.containerPath,
  });

  final String containerPath;
  final SessionChartData prepared;
  final SessionMetadata metadata;

  /// Nested metadata `stats`, copied before [SessionMetadata] flattens it.
  final Map<String, Object?> stats;
  final num? durationS;
  final num? elapsedSeconds;
  final HistoryDashboardTotals? feedback;
  final SessionTrust? trust;
  final ProtocolDocument? protocolDoc;
  final String guardFeature;
  final String rewardLabel;
  final String guardLabel;
}

class _FeedbackDashboardViewState extends ConsumerState<FeedbackDashboardView> {
  final TextEditingController _notes = TextEditingController();
  final GlobalKey _thumbKey = GlobalKey();
  Future<_DashboardLoad>? _loadFuture;
  SessionChartData? _prepared;
  SessionMetadata? _fileMeta;
  Map<String, Object?> _summaryStats = const {};
  num? _durationS;
  num? _summaryElapsed;
  HistoryDashboardTotals? _feedbackTotals;
  SessionTrust? _sessionTrust;
  ProtocolDocument? _savedProtocol;
  String _guardFeature = guardFeatureNone;
  String _rewardLabel = '';
  String _guardLabel = '';
  String? _containerPath;
  bool _rewardOn = true;
  bool _guardOn = false;
  final HistoryTrustViewport _historyViewport = HistoryTrustViewport();
  Object? _loadError;
  Uint8List? _thumbnail;
  bool _busy = false;
  _SessionSummaryChip _chip = _SessionSummaryChip.dashboard;

  /// Notes value that is persisted on disk (used to detect unsaved edits).
  String _savedNotes = '';
  bool _notesSaving = false;
  bool _notesSavedFlash = false;
  Timer? _notesFlashTimer;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadSession();
    _loadFuture!
        .then((loaded) {
          if (!mounted) return;
          setState(() {
            _prepared = loaded.prepared;
            _fileMeta = loaded.metadata;
            _summaryStats = loaded.stats;
            _durationS = loaded.durationS;
            _summaryElapsed = loaded.elapsedSeconds;
            _feedbackTotals = loaded.feedback;
            _sessionTrust = loaded.trust;
            _savedProtocol = loaded.protocolDoc;
            _guardFeature = loaded.guardFeature;
            _rewardLabel = loaded.rewardLabel;
            _guardLabel = loaded.guardLabel;
            _containerPath = loaded.containerPath;
            _applyHistoryTrustDefaults(loaded);
            _loadError = null;
            if (loaded.metadata.notes.isNotEmpty && _notes.text.isEmpty) {
              _notes.text = loaded.metadata.notes;
              _savedNotes = _notes.text;
            }
          });
          if (!widget.readOnly) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
          }
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => _loadError = e);
        });
    final notes = widget.metadata?.notes;
    if (notes != null && notes.isNotEmpty) {
      _notes.text = notes;
    }
    _savedNotes = _notes.text;
    _notes.addListener(_onNotesChanged);
  }

  Future<_DashboardLoad> _loadSession() async {
    late final String path;
    if (widget.readOnly && widget.sessionId != null) {
      final store = await ref.read(sessionStoreProvider.future);
      final resolved = await store.resolveContainerPath(widget.sessionId!);
      if (resolved == null) {
        throw StateError('session file missing');
      }
      path = resolved;
    } else {
      final scratch =
          widget.sessionPath ??
          ref.read(feedbackStateProvider.notifier).scratchPath;
      if (scratch == null) {
        throw StateError('scratch .neurofeed not assembled');
      }
      if (!await File(scratch).exists()) {
        throw StateError('scratch .neurofeed missing');
      }
      path = scratch;
    }
    final frames = await extractComputedFromPath(path: path);
    final head = await parseHeadFromPath(path: path);
    final root = _metadataMap(head.metadataJson);
    final meta =
        SessionMetadata.fromJsonBytes(head.metadataJson) ??
        widget.metadata ??
        SessionMetadata(
          protocol: '',
          durationMinutes: 0,
          elapsedSeconds: 0,
          sound: '',
          savedAt: DateTime.now().toIso8601String(),
        );
    final catalog = await ProtocolCatalog.load();
    final protocol = catalog.forName(meta.protocol);
    final prepared = prepareChartDataFromComputed(
      frames,
      trainingStartOffset: meta.calibration?.trainingStartOffsetSecs,
      metric: protocol?.reward?.feature ?? 'band.atr',
      conditions: protocol?.conditions ?? const [],
      recordingStartMs: recordingStartMsFromIso(meta.startedAt),
      channelLabels: meta.recordedChannels.isEmpty
          ? kMuseElectrodeNames
          : meta.recordedChannels,
    );
    final training =
        meta.calibration?.trainingStartOffsetSecs ??
        widget.metadata?.calibration?.trainingStartOffsetSecs ??
        (widget.readOnly || !mounted
            ? null
            : ref.read(feedbackStateProvider.notifier).trainingStartOffsetSecs);
    final savedProtocol = _savedProtocolDoc(meta, catalog);
    final guardFeature = _savedGuardFeature(meta, savedProtocol);
    final trust = _sessionTrustFor(
      frames: frames,
      trainingStartOffsetSecs: training,
      meta: meta,
    );
    return _DashboardLoad(
      prepared: prepared,
      metadata: meta,
      stats: _nestedStats(root),
      durationS: _finiteNum(root?['durationS']),
      elapsedSeconds: _finiteNum(root?['elapsedSeconds']),
      feedback: trust == null
          ? null
          : HistoryDashboardTotals.fromSessionTrust(trust),
      trust: trust,
      protocolDoc: savedProtocol,
      guardFeature: guardFeature,
      rewardLabel: _featureShortLabel(catalog, savedProtocol?.reward?.feature),
      guardLabel: _featureShortLabel(catalog, guardFeature),
      containerPath: path,
    );
  }

  void _applyHistoryTrustDefaults(_DashboardLoad loaded) {
    final trust = loaded.trust;
    if (trust == null) return;
    final rewardLane =
        trust.reward.isNotEmpty && (loaded.protocolDoc?.hasReward ?? false);
    final guardLane =
        trust.guard.isNotEmpty &&
        trustGuardPaneSpecs(loaded.guardFeature).isNotEmpty;
    _rewardOn = rewardLane;
    _guardOn = !rewardLane && guardLane;
    final end = historyTrustLastT(trust);
    if (end != null) _historyViewport.anchorTo(end);
  }

  bool get _notesDirty => _notes.text != _savedNotes;

  /// Offset (seconds from recording start) where training began, for trimming
  /// the displayed window/metrics to the training portion. Live sessions read
  /// it from the notifier; history sessions from the stored calibration record
  /// (null on old files → full-window rendering, as before).
  double? get _trainingStartOffset {
    return _fileMeta?.calibration?.trainingStartOffsetSecs ??
        widget.metadata?.calibration?.trainingStartOffsetSecs ??
        (widget.readOnly
            ? null
            : ref.read(feedbackStateProvider.notifier).trainingStartOffsetSecs);
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
    _historyViewport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fb = ref.watch(feedbackStateProvider);
    final meta = _fileMeta ?? widget.metadata;
    final catalog = ref.watch(protocolCatalogProvider).valueOrNull;
    final protocol = protocolOrPlaceholder(
      catalog,
      meta?.protocol ?? fb.protocol,
    );
    final copy = useProtocolCopy(ref, protocol);

    return PopScope(
      // Live summary must Save or Discard — Back must not drop the scratch.
      // History detail still warns when notes are dirty.
      canPop: widget.readOnly && !_notesDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (widget.readOnly) {
          _confirmUnsavedNotes();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${copy.title} — Session'),
          automaticallyImplyLeading: widget.readOnly,
          actions: widget.readOnly
              ? null
              : [
                  TextButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Save'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _discard,
                    child: const Text('Discard'),
                  ),
                ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _chipBar(),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _dashboard(meta, fb),
            ),
          ],
        ),
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

  bool get _showFeedbackChip =>
      _feedbackLane(_sessionTrust, _savedProtocol, _guardFeature);

  _SessionSummaryChip get _visibleChip =>
      _chip == _SessionSummaryChip.feedback && !_showFeedbackChip
      ? _SessionSummaryChip.dashboard
      : _chip;

  Widget _chipBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SegmentedButton<_SessionSummaryChip>(
        segments: [
          const ButtonSegment(
            value: _SessionSummaryChip.dashboard,
            label: Text('Dashboard'),
          ),
          if (_showFeedbackChip)
            const ButtonSegment(
              value: _SessionSummaryChip.feedback,
              label: Text('Feedback'),
            ),
          const ButtonSegment(
            value: _SessionSummaryChip.bands,
            label: Text('Bands'),
          ),
          const ButtonSegment(
            value: _SessionSummaryChip.rawEeg,
            label: Text('Raw EEG'),
          ),
          const ButtonSegment(
            value: _SessionSummaryChip.histogram,
            label: Text('Histogram'),
          ),
          const ButtonSegment(
            value: _SessionSummaryChip.psd,
            label: Text('PSD'),
          ),
          const ButtonSegment(
            value: _SessionSummaryChip.spectrogram,
            label: Text('Spectrogram'),
          ),
          const ButtonSegment(
            value: _SessionSummaryChip.hrSpo2,
            label: Text('HR+SpO2'),
          ),
          const ButtonSegment(
            value: _SessionSummaryChip.movement,
            label: Text('Movement'),
          ),
        ],
        selected: {_visibleChip},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelectionChanged: (next) {
          if (next.isEmpty) return;
          setState(() => _chip = next.first);
        },
      ),
    );
  }

  RecordingDashGraph? _signalFor(_SessionSummaryChip chip) => switch (chip) {
    _SessionSummaryChip.dashboard || _SessionSummaryChip.feedback => null,
    _SessionSummaryChip.bands => RecordingDashGraph.bands,
    _SessionSummaryChip.rawEeg => RecordingDashGraph.rawEeg,
    _SessionSummaryChip.histogram => RecordingDashGraph.histogram,
    _SessionSummaryChip.psd => RecordingDashGraph.psd,
    _SessionSummaryChip.spectrogram => RecordingDashGraph.spectrogram,
    _SessionSummaryChip.hrSpo2 => RecordingDashGraph.hrSpo2,
    _SessionSummaryChip.movement => RecordingDashGraph.movement,
  };

  Widget _dashboard(SessionMetadata? meta, FeedbackState fb) {
    if (_prepared != null) {
      final signal = _signalFor(_visibleChip);
      final path = _containerPath;
      if (signal != null && path != null) {
        return HistorySignalGraphs(
          key: ValueKey('session-graphs-$path'),
          absolutePath: path,
          graph: signal,
        );
      }
      return switch (_visibleChip) {
        _SessionSummaryChip.dashboard => _DashboardBody(
          summaryStats: _summaryStats,
          durationS: _durationS,
          summaryElapsed: _summaryElapsed,
          feedback: _feedbackTotals,
          music: meta?.music,
          gestures:
              meta?.gestures ??
              (widget.readOnly
                  ? null
                  : ref.read(feedbackStateProvider.notifier).gestureMarkers),
          trainingStartOffsetSecs: _trainingStartOffset,
          thumbKey: _thumbKey,
          notesController: _notes,
          onSaveNotes: widget.readOnly ? _saveNotes : null,
          notesDirty: _notesDirty,
          notesSaving: _notesSaving,
          notesSavedFlash: _notesSavedFlash,
        ),
        _SessionSummaryChip.feedback => _feedbackBody(),
        _ => const SizedBox.shrink(),
      };
    }
    if (_loadError != null) {
      return _LoadError(
        theme: Theme.of(context),
        error: _loadError!,
        onDiscard: widget.readOnly ? null : _discard,
      );
    }
    if (_loadFuture != null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _NoData(theme: Theme.of(context));
  }

  Widget _feedbackBody() {
    final trust = _sessionTrust;
    final protocol = _savedProtocol;
    if (trust == null || protocol == null) return const SizedBox.shrink();
    final overrides =
        _fileMeta?.sessionSettings?.inhibitCeilingOverrides ?? const {};
    return HistoryTrustReplay(
      trust: trust,
      viewport: _historyViewport,
      showReward: _rewardOn,
      showGuard: _guardOn,
      onReward: (on) => setState(() => _rewardOn = on),
      onGuard: (on) => setState(() => _guardOn = on),
      inhibit: trustInhibitSpecs(
        overlayInhibitCeilings(protocol.conditions, overrides),
      ),
      guardPanes: trustGuardPaneSpecs(_guardFeature),
      rewardLabel: _rewardLabel,
      guardLabel: _guardLabel,
      rewardColor: protocol.color,
      guardColor: bandColors[0],
    );
  }

  int _captureAttempts = 0;

  Future<void> _capture() async {
    final boundary =
        _thumbKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) return;
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes != null && mounted) {
        setState(() => _thumbnail = bytes);
      }
    } catch (_) {
      // The summary boundary can still be dirty on the frame that mounts it.
      if (_captureAttempts++ > 4 || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_capture());
      });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final notifier = ref.read(feedbackStateProvider.notifier);
    try {
      final path = notifier.scratchPath;
      final id = notifier.sessionId;
      debugPrint('[dashboard] save: scratchPath=$path id=$id');
      if (path == null || id == null) {
        debugPrint('[dashboard] save: no scratch .neurofeed to publish');
        return;
      }
      final thumb = encodeThumbnailWebP(_thumbnail ?? Uint8List(0));
      final stats = _prepared?.stats;
      final metadata =
          _fileMeta?.withSaveFields(
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
            avgSpo2: stats?.avgSpo2,
          ) ??
          notifier.buildSessionMetadata(notes: _notes.text, stats: stats);
      final frames = await extractComputedFromPath(path: path);
      final baseStats = assembleBaseStats(
        frames: frames,
        annotations: metadata.annotations,
        channelLabels: metadata.recordedChannels.isEmpty
            ? kMuseElectrodeNames
            : metadata.recordedChannels,
      );
      final patched = '${Directory.systemTemp.path}/nf_save_$id.neurofeed';
      await rewriteHeadToPath(
        srcPath: path,
        destPath: patched,
        metadataJson: utf8.encode(
          jsonEncode(
            buildFeedbackMetadata(
              meta: metadata,
              subject: ref.read(settingsProvider).subjectInfo,
              stats: baseStats,
            ),
          ),
        ),
        thumbnail: thumb,
      );
      final store = await ref.read(sessionStoreProvider.future);
      await store.publishSession(
        id,
        metadata,
        encodedPath: patched,
        subject: ref.read(settingsProvider).subjectInfo,
      );
      try {
        await File(patched).delete();
      } catch (_) {}
      await notifier.deleteScratch();
      notifier.reset();
      debugPrint('[dashboard] save: published session_$id.neurofeed');
      if (mounted) {
        ref.invalidate(sessionListProvider);
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      debugPrint('[dashboard] save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Could not save session: $e'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    try {
      final notifier = ref.read(feedbackStateProvider.notifier);
      await notifier.discardSession();
      notifier.reset();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
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
    required this.summaryStats,
    this.durationS,
    this.summaryElapsed,
    this.feedback,
    this.music,
    this.gestures,
    this.trainingStartOffsetSecs,
    required this.thumbKey,
    required this.notesController,
    this.onSaveNotes,
    this.notesDirty = false,
    this.notesSaving = false,
    this.notesSavedFlash = false,
  });

  final Map<String, Object?> summaryStats;
  final num? durationS;
  final num? summaryElapsed;
  final HistoryDashboardTotals? feedback;

  /// Music-feedback record (track list) of this session (null
  /// when music feedback did not run).
  final SessionMusic? music;

  /// Gesture markers recorded during the session.
  final List<GestureMarker>? gestures;

  /// Seconds from recording start to the training boundary. Music and
  /// gesture offsets are relative to session start.
  final double? trainingStartOffsetSecs;

  final GlobalKey thumbKey;
  final TextEditingController notesController;
  final Future<void> Function()? onSaveNotes;
  final bool notesDirty;
  final bool notesSaving;
  final bool notesSavedFlash;

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Music-feedback track list. Empty when music feedback produced no samples.
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
      if (music == null || music.series.isEmpty) {
        return const [];
      }
      final offset = widget.trainingStartOffsetSecs ?? 0;
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

    // Gesture marker widgets: shows markers for double-blink, double-clench,
    // and eye up/down transitions recorded during the session.
    List<Widget> gestureWidgets() {
      final gestures = widget.gestures;
      if (gestures == null || gestures.isEmpty) {
        return const [];
      }
      final offset = widget.trainingStartOffsetSecs ?? 0;
      final theme = Theme.of(context);

      // Group by type for summary counts
      final counts = <GestureType, int>{};
      for (final g in gestures) {
        counts[g.type] = (counts[g.type] ?? 0) + 1;
      }

      String formatOffset(double secs) {
        if (secs.isNaN || secs < 0) return '00:00';
        final m = secs ~/ 60;
        final s = (secs % 60).toStringAsFixed(0).padLeft(2, '0');
        return '$m:$s';
      }

      IconData iconForType(GestureType t) => switch (t) {
        GestureType.doubleBlink => Icons.remove_red_eye_outlined,
        GestureType.doubleClench => Icons.pan_tool_outlined,
        GestureType.eyeUp => Icons.keyboard_arrow_up,
        GestureType.eyeDown => Icons.keyboard_arrow_down,
      };

      Color colorForType(GestureType t) => switch (t) {
        GestureType.doubleBlink => const Color(0xFF1E88E5),
        GestureType.doubleClench => const Color(0xFFFFA726),
        GestureType.eyeUp => const Color(0xFF66BB6A),
        GestureType.eyeDown => const Color(0xFFAB47BC),
      };

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
                    const Icon(Icons.gesture_outlined),
                    const SizedBox(width: 8),
                    Text('Gesture markers', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      '${gestures.length} marker(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final entry in counts.entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            iconForType(entry.key),
                            size: 16,
                            color: colorForType(entry.key),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${entry.key.name}: ${entry.value}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Timeline', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final g in gestures)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          iconForType(g.type),
                          size: 16,
                          color: colorForType(g.type),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            g.type.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatOffset(g.offsetSeconds - offset),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
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
        RepaintBoundary(
          key: widget.thumbKey,
          child: HistoryDashboardSummary(
            stats: widget.summaryStats,
            durationS: widget.durationS,
            elapsedSeconds: widget.summaryElapsed,
            feedback: widget.feedback,
          ),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        ...musicWidgets(),
        ...gestureWidgets(),
      ],
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

/// Nested `stats` from metadata JSON. [SessionMetadata] keeps only the old
/// flat card, so this copy is what the Dashboard summary reads.
Map<String, Object?> _nestedStats(Map<String, Object?>? root) {
  final raw = root?['stats'];
  if (raw is! Map) return const {};
  return Map<String, Object?>.from(
    raw.map((key, value) => MapEntry('$key', value)),
  );
}

num? _finiteNum(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value;
}

Map<String, Object?>? _metadataMap(List<int> bytes) {
  if (bytes.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;
    return Map<String, Object?>.from(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  } catch (_) {
    return null;
  }
}

/// Null when the trust reader throws, so feedback cells stay out.
SessionTrust? _sessionTrustFor({
  required List<ComputedFrame> frames,
  required double? trainingStartOffsetSecs,
  required SessionMetadata meta,
}) {
  try {
    return readSessionTrust(
      frames: frames,
      trainingStartOffsetSecs: trainingStartOffsetSecs,
      annotations: meta.annotations,
      audioEvents: meta.audioEvents,
    );
  } catch (_) {
    return null;
  }
}

ProtocolDocument? _savedProtocolDoc(
  SessionMetadata meta,
  ProtocolCatalog catalog,
) {
  final raw = meta.protocolJson;
  if (raw != null) {
    try {
      final id = meta.protocol.isNotEmpty
          ? meta.protocol
          : raw['id'] as String? ?? '';
      return ProtocolDocument.fromJson(raw, id: id, features: catalog.features);
    } catch (_) {}
  }
  return catalog.forName(meta.protocol);
}

String _savedGuardFeature(SessionMetadata meta, ProtocolDocument? protocol) {
  final saved = meta.sessionSettings?.guardFeature;
  if (saved != null && saved.isNotEmpty) return saved;
  final feature = protocol?.guard?.feature;
  if (feature == null || feature.isEmpty) return guardFeatureNone;
  return feature;
}

String _featureShortLabel(ProtocolCatalog catalog, String? id) {
  if (id == null || id.isEmpty || id == guardFeatureNone) return '';
  return catalog.features[id]?.shortLabel ?? id;
}

bool _feedbackLane(
  SessionTrust? trust,
  ProtocolDocument? protocol,
  String guardFeature,
) {
  if (trust == null) return false;
  final reward = trust.reward.isNotEmpty && (protocol?.hasReward ?? false);
  final guard =
      trust.guard.isNotEmpty && trustGuardPaneSpecs(guardFeature).isNotEmpty;
  return reward || guard;
}
