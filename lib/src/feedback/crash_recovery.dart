import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/spine/capture_client.dart' as spine;
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/feedback/session_store.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/views/feedback_dashboard.dart';
import 'package:neurofeed/src/util/timezone.dart';

/// An assembled scratch `.neurofeed` left over from a crash or an interrupted save.
class RecoverableSession {
  RecoverableSession({
    required this.id,
    required this.scratch,
    required this.protocol,
    required this.elapsedSeconds,
    required this.calibrationKind,
    this.metadata,
  });

  final String id;
  final File scratch;
  final String protocol;
  final int elapsedSeconds;
  final String calibrationKind;
  final SessionMetadata? metadata;

  /// Publish the scratch `.neurofeed` into history, then delete it.
  Future<void> save(SessionStore store) async {
    final head = await ffi.parseHeadFromPath(path: scratch.path);
    final meta =
        SessionMetadata.fromJsonBytes(head.metadataJson) ??
        SessionMetadata(
          protocol: protocol,
          durationMinutes: elapsedSeconds <= 0
              ? 0
              : (elapsedSeconds / 60).ceil(),
          elapsedSeconds: elapsedSeconds,
          sound: '',
          savedAt: formatIso8601WithOffset(DateTime.now()),
          timeZone: captureIanaTimeZone(),
          sessionId: id,
        );
    await store.publishSession(id, meta, encodedPath: scratch.path);
    await discard();
  }

  /// Delete the scratch `.neurofeed`. Temps are already gone after assemble.
  Future<void> discard() async {
    if (await scratch.exists()) {
      await scratch.delete();
    }
  }
}

class _ScratchFiles {
  File? container;
  File? raw;
  File? computed;
  File? metadata;
}

String? _idFrom(String name, String suffix) {
  const prefix = 'session_';
  if (!name.startsWith(prefix) || !name.endsWith(suffix)) return null;
  final id = name.substring(prefix.length, name.length - suffix.length);
  return id.isEmpty ? null : id;
}

Future<void> _deleteTemps(_ScratchFiles files) async {
  for (final f in [files.raw, files.computed, files.metadata]) {
    if (f != null && await f.exists()) {
      try {
        await f.delete();
      } catch (e) {
        debugPrint('[crash] failed to delete ${f.path}: $e');
      }
    }
  }
}

double? _isoEpochSeconds(String? iso) {
  if (iso == null) return null;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return null;
  return parsed.millisecondsSinceEpoch / 1000.0;
}

Map<String, Object?>? _coerceJsonMap(Object? value) {
  final coerced = _coerceJsonValue(value);
  return coerced is Map<String, Object?> ? coerced : null;
}

Object? _coerceJsonValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries)
        e.key.toString(): _coerceJsonValue(e.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final v in value) _coerceJsonValue(v)];
  }
  return value;
}

List<double> _doubleList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final v in raw)
      if (v is num) v.toDouble(),
  ];
}

GestureType? _gestureTypeForAnnotation(String type) => switch (type) {
  'double_blink' => GestureType.doubleBlink,
  'double_jaw_clench' => GestureType.doubleClench,
  'eye_up' => GestureType.eyeUp,
  'eye_down' => GestureType.eyeDown,
  _ => null,
};

/// Rebuild [SessionCalibration] from the sidecar lines already on disk.
/// Clip phases keep their offsets from recording start. The session-start
/// epoch is `calibration_complete` time minus `elapsedSecs`, or a clip-end
/// timestamp minus that phase's `endSecs` when calibration never finished.
SessionCalibration? _recoveredCalibration({
  required bool sawCalibration,
  required String kind,
  required String? calibrationId,
  required List<SessionCalibrationPhase> phases,
  required List<SessionRecalibration> recalibrations,
  required double? elapsedSecs,
  required String? completeAt,
  required String? phaseAnchorAt,
  required double? phaseAnchorEnd,
  required double? baselinePercentile,
  required int? baselineCount,
  required double? baselineMean,
  required double? baselineStddev,
  Map<String, Object?>? calibrationJson,
  bool usedStartAnyway = false,
  bool skipped = false,
  String? skipSource,
  int? greenStableSeconds,
  int? faultyPadSeconds,
  int? baselineValidSeconds,
  int? baselineWallSeconds,
  List<double> baselineSamples = const [],
  int version = 2,
}) {
  if (!sawCalibration &&
      (calibrationId == null || calibrationId.isEmpty) &&
      kind.isEmpty) {
    return null;
  }
  final completeEpoch = _isoEpochSeconds(completeAt);
  double? sessionStart;
  if (completeEpoch != null && elapsedSecs != null) {
    sessionStart = completeEpoch - elapsedSecs;
  } else {
    final anchorEpoch = _isoEpochSeconds(phaseAnchorAt);
    if (anchorEpoch != null && phaseAnchorEnd != null) {
      sessionStart = anchorEpoch - phaseAnchorEnd;
    }
  }
  final end = sessionStart != null && elapsedSecs != null
      ? sessionStart + elapsedSecs
      : completeEpoch;
  return SessionCalibration(
    version: version,
    kind: kind.isEmpty ? 'single' : kind,
    calibrationId: calibrationId ?? '',
    calibrationJson: calibrationJson,
    calibrationStartSecs: sessionStart,
    calibrationEndSecs: end,
    trainingStartSecs: end,
    usedStartAnyway: usedStartAnyway,
    skipped: skipped,
    skipSource: skipSource,
    greenStableSeconds: greenStableSeconds,
    faultyPadSeconds: faultyPadSeconds,
    baselineValidSeconds: baselineValidSeconds,
    baselineWallSeconds: baselineWallSeconds,
    baseline: baselineCount == null
        ? null
        : SessionBaselineStats(
            percentile: baselinePercentile ?? 0,
            count: baselineCount,
            mean: baselineMean,
            stddev: baselineStddev,
          ),
    baselineSamples: baselineSamples,
    phases: phases,
    recalibrations: recalibrations,
  );
}

SessionMetadata _metadataFromTemps({
  required String id,
  required Uint8List jsonl,
  required List<ffi.ComputedFrame> frames,
}) {
  var protocol = '';
  int? plannedMinutes;
  String? sound;
  String? feedbackSound;
  String? startedAt;
  String? timeZone;
  String? protocolVersion;
  String? metadataDescription;
  Map<String, Object?>? protocolJson;
  var recordedData = const <String>[];
  String? userId;
  SessionSettings? sessionSettings;
  var calibrationKind = '';
  String? calibrationId;
  String? deviceName;
  String? deviceModel;
  String? deviceId;
  RawFiltering? rawFiltering;
  SignalConditioning? conditioning;
  var channelLabels = const <String>[];
  final phases = <SessionCalibrationPhase>[];
  final recalibrations = <SessionRecalibration>[];
  var sawCalibration = false;
  double? calibrationElapsed;
  String? calibrationCompleteAt;
  String? phaseAnchorAt;
  double? phaseAnchorEnd;
  double? baselinePercentile;
  int? baselineCount;
  double? baselineMean;
  double? baselineStddev;
  Map<String, Object?>? calibrationJson;
  var usedStartAnyway = false;
  var skipped = false;
  String? skipSource;
  int? greenStableSeconds;
  int? faultyPadSeconds;
  int? baselineValidSeconds;
  int? baselineWallSeconds;
  var baselineSamples = const <double>[];
  var calibrationVersion = 2;
  final intervals = <SessionAnnotation>[];
  final openPauseOnsets = <double>[];
  final gestureMarkers = <GestureMarker>[];
  final audioEvents = <Map<String, Object?>>[];
  final musicTracks = <MusicTrackMarker>[];
  final musicSeries = <MusicCutoffSample>[];
  var musicTrackCount = 0;
  var musicMin = 0.0;
  var musicMax = 0.0;
  var musicInvert = false;
  var musicShuffle = false;
  if (jsonl.isNotEmpty) {
    for (final line in utf8.decode(jsonl, allowMalformed: true).split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        final meta = _coerceJsonMap(decoded);
        if (meta == null) continue;
        final type = meta['type'];
        if (type == 'protocol') {
          protocol = meta['protocol'] as String? ?? protocol;
        } else if (type == 'session') {
          protocol = meta['protocol'] as String? ?? protocol;
          plannedMinutes =
              (meta['durationMinutes'] as num?)?.toInt() ?? plannedMinutes;
          sound = meta['sound'] as String? ?? sound;
          feedbackSound = meta['feedbackSound'] as String? ?? feedbackSound;
          startedAt = meta['startedAt'] as String? ?? startedAt;
          timeZone = meta['timeZone'] as String? ?? timeZone;
          protocolVersion =
              meta['protocolVersion'] as String? ?? protocolVersion;
          metadataDescription =
              meta['metadataDescription'] as String? ?? metadataDescription;
          protocolJson = _coerceJsonMap(meta['protocolJson']) ?? protocolJson;
          final streams = meta['recordedData'];
          if (streams is List) {
            recordedData = [
              for (final v in streams)
                if (v is String) v,
            ];
          }
          userId = meta['userId'] as String? ?? userId;
          final settings = SessionSettings.fromJson(
            _coerceJsonMap(meta['sessionSettings']),
          );
          if (settings != null) sessionSettings = settings;
        } else if (type == 'device') {
          deviceName = meta['name'] as String?;
          deviceModel = meta['firmware'] as String?;
          deviceId = meta['id'] as String?;
          rawFiltering = RawFiltering.fromJson(meta['rawFiltering']);
          conditioning = SignalConditioning.fromJson(meta['conditioning']);
          final labels = meta['channelLabels'];
          if (labels is List) {
            channelLabels = labels.whereType<String>().toList();
          }
        } else if (type == 'calibration_start') {
          sawCalibration = true;
          calibrationKind = meta['kind'] as String? ?? calibrationKind;
          calibrationId = meta['calibrationId'] as String? ?? calibrationId;
          calibrationJson =
              _coerceJsonMap(meta['calibrationJson']) ?? calibrationJson;
          if (meta['usedStartAnyway'] == true) usedStartAnyway = true;
        } else if (type == 'calibration_phase') {
          sawCalibration = true;
          final start = (meta['startSecs'] as num?)?.toDouble();
          final end = (meta['endSecs'] as num?)?.toDouble();
          final duration = start != null && end != null && end >= start
              ? end - start
              : 0.0;
          phases.add(
            SessionCalibrationPhase(
              name: meta['clipId'] as String? ?? '',
              durationSecs: duration,
              sampleCount: 0,
              clipFile: meta['clipFile'] as String?,
              spokenText: meta['spokenText'] as String?,
              eyes: meta['eyes'] as String?,
              challengeText: meta['challengeText'] as String?,
              startSecs: start,
              endSecs: end,
              kind: meta['kind'] as String?,
            ),
          );
          if (phaseAnchorAt == null &&
              meta['timestamp'] is String &&
              end != null) {
            phaseAnchorAt = meta['timestamp'] as String;
            phaseAnchorEnd = end;
          }
        } else if (type == 'calibration_complete') {
          sawCalibration = true;
          calibrationElapsed = (meta['elapsedSecs'] as num?)?.toDouble();
          calibrationCompleteAt = meta['timestamp'] as String?;
          baselinePercentile = (meta['baselinePercentile'] as num?)?.toDouble();
          baselineCount = (meta['baselineCount'] as num?)?.toInt();
          baselineMean = (meta['baselineMean'] as num?)?.toDouble();
          baselineStddev = (meta['baselineStddev'] as num?)?.toDouble();
          calibrationKind = meta['kind'] as String? ?? calibrationKind;
          calibrationId = meta['calibrationId'] as String? ?? calibrationId;
          calibrationVersion =
              (meta['version'] as num?)?.toInt() ?? calibrationVersion;
          calibrationJson =
              _coerceJsonMap(meta['calibrationJson']) ?? calibrationJson;
          if (meta.containsKey('baselineSamples')) {
            baselineSamples = _doubleList(meta['baselineSamples']);
          }
          if (meta['usedStartAnyway'] == true) usedStartAnyway = true;
          if (meta['skipped'] is bool) skipped = meta['skipped'] as bool;
          skipSource = meta['skipSource'] as String? ?? skipSource;
          greenStableSeconds =
              (meta['greenStableSeconds'] as num?)?.toInt() ??
              greenStableSeconds;
          faultyPadSeconds =
              (meta['faultyPadSeconds'] as num?)?.toInt() ?? faultyPadSeconds;
          baselineValidSeconds =
              (meta['baselineValidSeconds'] as num?)?.toInt() ??
              baselineValidSeconds;
          baselineWallSeconds =
              (meta['baselineWallSeconds'] as num?)?.toInt() ??
              baselineWallSeconds;
        } else if (type == 'recalibration') {
          sawCalibration = true;
          recalibrations.add(
            SessionRecalibration(
              atSecs: (meta['atSecs'] as num?)?.toDouble() ?? 0,
              baseline: SessionBaselineStats(
                percentile:
                    (meta['baselinePercentile'] as num?)?.toDouble() ?? 0,
                count: (meta['baselineCount'] as num?)?.toInt() ?? 0,
                mean: (meta['baselineMean'] as num?)?.toDouble(),
                stddev: (meta['baselineStddev'] as num?)?.toDouble(),
              ),
              baselineSamples: _doubleList(meta['baselineSamples']),
            ),
          );
        } else if (type == 'annotation') {
          final annType = meta['annotationType'] as String?;
          if (annType != null && annType.isNotEmpty) {
            final onset = (meta['onset'] as num?)?.toDouble() ?? 0;
            final durationValue = meta['duration'];
            if (annType == 'pause' && durationValue is! num) {
              openPauseOnsets.add(onset);
              continue;
            }
            final gesture = _gestureTypeForAnnotation(annType);
            if (gesture != null &&
                (durationValue == null || durationValue == 0)) {
              gestureMarkers.add(
                GestureMarker(type: gesture, offsetSeconds: onset.round()),
              );
            } else if (durationValue is num) {
              intervals.add(
                SessionAnnotation(
                  onset: onset,
                  duration: durationValue.toDouble(),
                  type: annType,
                ),
              );
            }
          }
        } else if (type == 'audio_event') {
          final audioType = meta['audioType'] as String?;
          if (audioType != null && audioType.isNotEmpty) {
            audioEvents.add({
              'onset': (meta['onset'] as num?)?.toDouble() ?? 0,
              'type': audioType,
            });
          }
        } else if (type == 'music') {
          musicTrackCount =
              (meta['trackCount'] as num?)?.toInt() ?? musicTrackCount;
          musicMin = (meta['minCutoffHz'] as num?)?.toDouble() ?? musicMin;
          musicMax = (meta['maxCutoffHz'] as num?)?.toDouble() ?? musicMax;
          musicInvert = meta['invert'] as bool? ?? musicInvert;
          musicShuffle = meta['shuffle'] as bool? ?? musicShuffle;
        } else if (type == 'music_track') {
          musicTracks.add(
            MusicTrackMarker(
              offsetSecs: (meta['at'] as num?)?.toDouble() ?? 0,
              name: meta['name'] as String? ?? '',
            ),
          );
          musicTrackCount =
              (meta['trackCount'] as num?)?.toInt() ?? musicTrackCount;
        } else if (type == 'music_sample') {
          musicSeries.add(
            MusicCutoffSample(
              offsetSecs: (meta['at'] as num?)?.toDouble() ?? 0,
              cutoffHz: (meta['hz'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      } catch (_) {}
    }
  }
  final contentEnd = frames.isEmpty ? null : frames.last.t;
  for (final onset in openPauseOnsets) {
    final already = intervals.any(
      (a) => a.type == 'pause' && (a.onset - onset).abs() < 1e-6,
    );
    if (already) continue;
    final end = contentEnd ?? onset;
    final duration = end - onset;
    intervals.add(
      SessionAnnotation(
        onset: onset,
        duration: duration < 0 ? 0 : duration,
        type: 'pause',
      ),
    );
  }
  final elapsed = frames.isEmpty ? 0 : frames.last.t.round();
  final scalars = extractComputedScalars(frames);
  final annotations = assembleAnnotations(
    intervals: intervals,
    gestures: gestureMarkers,
  );
  return SessionMetadata(
    protocol: protocol,
    durationMinutes:
        plannedMinutes ?? (elapsed <= 0 ? 0 : (elapsed / 60).ceil()),
    elapsedSeconds: elapsed,
    durationS: elapsed,
    sound: sound ?? '',
    feedbackSound: feedbackSound,
    savedAt: formatIso8601WithOffset(DateTime.now()),
    startedAt: startedAt,
    timeZone: timeZone ?? captureIanaTimeZone(),
    sessionId: id,
    protocolVersion: protocolVersion,
    metadataDescription: metadataDescription,
    protocolJson: protocolJson,
    recordedData: recordedData,
    userId: userId,
    sessionSettings: sessionSettings,
    annotations: annotations,
    gestures: gestureMarkers,
    audioEvents: audioEvents,
    music: musicSeries.isEmpty
        ? null
        : SessionMusic(
            trackCount: musicTrackCount,
            minCutoffHz: musicMin,
            maxCutoffHz: musicMax,
            invert: musicInvert,
            shuffle: musicShuffle,
            tracks: musicTracks,
            series: musicSeries,
          ),
    deviceName: deviceName,
    deviceModel: deviceModel,
    deviceId: deviceId,
    rawFiltering: rawFiltering,
    conditioning: conditioning,
    recordedChannels: channelLabels,
    calibration: _recoveredCalibration(
      sawCalibration: sawCalibration,
      kind: calibrationKind,
      calibrationId: calibrationId,
      phases: phases,
      recalibrations: recalibrations,
      elapsedSecs: calibrationElapsed,
      completeAt: calibrationCompleteAt,
      phaseAnchorAt: phaseAnchorAt,
      phaseAnchorEnd: phaseAnchorEnd,
      baselinePercentile: baselinePercentile,
      baselineCount: baselineCount,
      baselineMean: baselineMean,
      baselineStddev: baselineStddev,
      calibrationJson: calibrationJson,
      usedStartAnyway: usedStartAnyway,
      skipped: skipped,
      skipSource: skipped ? skipSource : null,
      greenStableSeconds: greenStableSeconds,
      faultyPadSeconds: faultyPadSeconds,
      baselineValidSeconds: baselineValidSeconds,
      baselineWallSeconds: baselineWallSeconds,
      baselineSamples: baselineSamples,
      version: calibrationVersion,
    ),
    drowsiness: frames.isEmpty
        ? null
        : SessionDrowsiness(
            scoreTotalPct:
                (scalars.guardrailWarnCount ?? 0) * 100 / frames.length,
            meanSleepDir: scalars.avgSleepDir ?? 0,
          ),
    avgSpo2: scalars.avgSpo2,
    peakAlphaHz: scalars.peakAlphaHz,
    peakAlphaPower: scalars.peakAlphaPower,
    pctInTarget: scalars.pctInTarget,
    avgMovement: scalars.avgMovement,
    guardrailWarnCount: scalars.guardrailWarnCount,
    avgSleepDir: scalars.avgSleepDir,
  );
}

Future<RecoverableSession?> _fromContainer(File file, String id) async {
  var protocol = '';
  var elapsed = 0;
  var calibrationKind = '';
  SessionMetadata? meta;
  try {
    final head = await ffi.parseHeadFromPath(path: file.path);
    meta = SessionMetadata.fromJsonBytes(head.metadataJson);
    if (meta != null) {
      protocol = meta.protocol;
      elapsed = meta.elapsedSeconds;
      calibrationKind = meta.calibration?.kind ?? '';
    }
  } catch (e) {
    debugPrint('[crash] failed to parse ${file.path}: $e');
  }
  return RecoverableSession(
    id: id,
    scratch: file,
    protocol: protocol,
    elapsedSeconds: elapsed,
    calibrationKind: calibrationKind,
    metadata: meta,
  );
}

Future<RecoverableSession?> _assembleTemps({
  required Directory scratch,
  required String id,
  required _ScratchFiles files,
}) async {
  try {
    final computed = files.computed != null && await files.computed!.exists()
        ? await files.computed!.readAsBytes()
        : Uint8List(0);
    final metadataBytes =
        files.metadata != null && await files.metadata!.exists()
        ? await files.metadata!.readAsBytes()
        : Uint8List(0);
    final frames = parseComputedJsonl(computed);
    final meta = _metadataFromTemps(
      id: id,
      jsonl: metadataBytes,
      frames: frames,
    );
    final metadataJson = meta.toJson();
    final stats = assembleBaseStats(
      frames: frames,
      annotations: meta.annotations,
      channelLabels: meta.recordedChannels.isEmpty
          ? const ['TP9', 'AF7', 'AF8', 'TP10']
          : meta.recordedChannels,
    );
    if (stats != null) metadataJson['stats'] = stats;
    final file = await spine.assembleCaptureAt(
      dir: scratch,
      prefix: 'session',
      id: id,
      metadataJson: metadataJson,
    );
    await _deleteTemps(files);
    return RecoverableSession(
      id: id,
      scratch: file,
      protocol: meta.protocol,
      elapsedSeconds: meta.elapsedSeconds,
      calibrationKind: meta.calibration?.kind ?? '',
      metadata: meta,
    );
  } catch (e, st) {
    debugPrint('[crash] assemble temps for $id failed: $e\n$st');
    return null;
  }
}

/// Scan [scratchDirectory] for leftover `session_*.neurofeed` and orphan
/// three-temps. Temps are assembled with [spine.assembleCaptureAt].
/// Does not scan `getTemporaryDirectory()/sessions`.
Future<List<RecoverableSession>> scanRecoverableSessions(
  SessionStorage storage,
) async {
  final scratch = await scratchDirectory(storage);
  if (!await scratch.exists()) return const [];

  final byId = <String, _ScratchFiles>{};
  await for (final entity in scratch.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    void take(String? id, void Function(_ScratchFiles f) set) {
      if (id == null) return;
      set(byId.putIfAbsent(id, _ScratchFiles.new));
    }

    take(_idFrom(name, '.neurofeed'), (f) => f.container = entity);
    take(_idFrom(name, '.raw'), (f) => f.raw = entity);
    take(_idFrom(name, '.computed'), (f) => f.computed = entity);
    take(_idFrom(name, '.metadata'), (f) => f.metadata = entity);
  }

  final recovered = <RecoverableSession>[];
  for (final entry in byId.entries) {
    final id = entry.key;
    final files = entry.value;
    if (files.container != null) {
      await _deleteTemps(files);
      final session = await _fromContainer(files.container!, id);
      if (session != null) recovered.add(session);
      continue;
    }
    if (files.raw == null && files.computed == null) {
      await _deleteTemps(files);
      continue;
    }
    final session = await _assembleTemps(
      scratch: scratch,
      id: id,
      files: files,
    );
    if (session != null) recovered.add(session);
  }
  return recovered;
}

/// Re-open the session summary for leftover scratch sessions at startup.
/// The summary cannot be dismissed except by Save or Discard.
Future<void> showCrashRecoveryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final storage = await ref.read(sessionStorageProvider.future);
  final sessions = await scanRecoverableSessions(storage);
  if (sessions.isEmpty) return;

  for (final session in sessions) {
    if (!context.mounted) return;
    ref
        .read(feedbackStateProvider.notifier)
        .restoreEndedSession(
          id: session.id,
          scratchPath: session.scratch.path,
          metadata: session.metadata,
        );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FeedbackDashboardView()),
    );
  }
}
