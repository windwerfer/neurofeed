import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/feedback/session_scalars.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/monitor/recording/crash_recovery.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/version.dart';

final recordingStoreProvider = FutureProvider<RecordingStore>((ref) async {
  final storage = await ref.watch(sessionStorageProvider.future);
  final cacheDir = await resolveSessionCacheDir(storage);
  final sqlite = await SessionSqlite.open(cacheDirectory: cacheDir);
  return RecordingStore(storage: storage, sqlite: sqlite);
});

/// Publish / discard assembled `recording_$ts.neurofeed` scratch files.
///
/// Upserts the same `session_metadata.db` as feedback (`kind = 'recording'`).
/// Does not import `session_store*.dart`.
class RecordingStore {
  RecordingStore({required SessionStorage storage, required SessionSqlite sqlite})
    : _storage = storage,
      _sqlite = sqlite;

  final SessionStorage _storage;
  final SessionSqlite _sqlite;

  /// Copy [scratch] into the history root and upsert sqlite `kind = recording`.
  /// Then delete the scratch `.neurofeed` and leftover temps. Protocol is empty.
  Future<void> publish(File scratch) async {
    final name = scratch.uri.pathSegments.last;
    final id = recordingIdFrom(name, '.neurofeed');
    if (id == null) {
      debugPrint('[monitor] publish: not a recording .neurofeed ($name)');
      return;
    }
    await _storage.ensureDir();
    await _storage.copyFromPath(name, scratch.path);

    RecordingMetadata meta;
    Uint8List thumb;
    SessionRowScalars rowScalars = const SessionRowScalars();
    ComputedScalars legacy = const ComputedScalars();
    try {
      final head = await ffi.parseHeadFromPath(path: scratch.path);
      thumb = head.thumbnail;
      final decoded = jsonDecode(utf8.decode(head.metadataJson));
      final decodedMap = decoded as Map<String, dynamic>;
      meta = RecordingMetadata.fromJson(decodedMap);
      rowScalars = SessionRowScalars.fromV6Metadata(
        <String, Object?>{for (final e in decodedMap.entries) e.key: e.value},
      );
      try {
        final frames = await ffi.extractComputedFromPath(path: scratch.path);
        legacy = extractComputedScalars(frames);
        if (rowScalars.avgHr == null &&
            rowScalars.peakAlphaHz == null &&
            rowScalars.signalQualityMean == null) {
          final assembled = assembleBaseStats(
            frames: frames,
            channelLabels: meta.device.channelLabels,
          );
          rowScalars = SessionRowScalars.fromStatsAndOutcome(stats: assembled);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[monitor] publish: parse failed: $e');
      meta = recoveredRecordingMetadata(elapsedSeconds: 0);
      thumb = Uint8List(0);
    }

    final now = DateTime.now();
    await _sqlite.upsertSession(
      SessionRow(
        id: id,
        path: name,
        formatVersion: meta.formatVersion,
        appVersion: meta.appVersion.isEmpty ? appVersion : meta.appVersion,
        savedAt: meta.savedAt,
        startedAt: meta.startedAt,
        durationS: meta.durationS != 0 ? meta.durationS : meta.elapsedSeconds,
        protocol: '',
        kind: 'recording',
        deviceName: meta.device.name,
        deviceModel: meta.device.model,
        deviceId: meta.device.id,
        recordedChannels: meta.device.channelLabels.join(','),
        recordedStreams: _enabledStreamsCsv(meta.streams),
        offMeta: 0,
        lenMeta: 0,
        offComputed: 0,
        lenComputed: 0,
        offRaw: 0,
        lenRaw: 0,
        avgHr: rowScalars.avgHr ?? legacy.avgHr,
        hrMin: rowScalars.hrMin,
        hrMax: rowScalars.hrMax,
        avgSpo2: rowScalars.avgSpo2 ?? legacy.avgSpo2,
        spo2Min: rowScalars.spo2Min,
        spo2Max: rowScalars.spo2Max,
        peakAlphaHz: rowScalars.peakAlphaHz ?? legacy.peakAlphaHz,
        peakAlphaPower: rowScalars.peakAlphaPower ?? legacy.peakAlphaPower,
        peakAlphaMeanHz: rowScalars.peakAlphaMeanHz,
        pctInTarget: rowScalars.pctInTarget ?? legacy.pctInTarget,
        avgMovement: rowScalars.avgMovement ?? legacy.avgMovement,
        stillnessPct: rowScalars.stillnessPct,
        guardrailWarnCount:
            rowScalars.guardrailWarnCount ?? legacy.guardrailWarnCount,
        avgSleepDir: rowScalars.avgSleepDir ?? legacy.avgSleepDir,
        avgAlphaRel: rowScalars.avgAlphaRel,
        guardWarnPct: rowScalars.guardWarnPct,
        guardThreshold: rowScalars.guardThreshold,
        signalQualityMean: rowScalars.signalQualityMean,
        pctQcOk: rowScalars.pctQcOk,
        qualityChannelUsable: rowScalars.qualityChannelUsable,
        annotationPauseS: rowScalars.annotationPauseS,
        annotationBadQualityS: rowScalars.annotationBadQualityS,
        annotationDisconnectS: rowScalars.annotationDisconnectS,
        batteryStartPct: rowScalars.batteryStartPct,
        batteryEndPct: rowScalars.batteryEndPct,
        experimentalScalars: rowScalars.experimentalScalars,
        markerCount: 0,
        userId: meta.subject?.id,
        timeZone: meta.timeZone,
        savedAtMs: meta.savedAt.toUtc().millisecondsSinceEpoch,
        sessionId: id,
        notesPreview: meta.notes.isEmpty
            ? null
            : (meta.notes.length > 50 ? meta.notes.substring(0, 50) : meta.notes),
        fileSize: await scratch.length(),
        mtime: now.millisecondsSinceEpoch,
        thumbnail: thumb.isNotEmpty ? thumb : null,
        createdAt: now,
        updatedAt: now,
      ),
    );
    debugPrint('[monitor] recording publish $name kind=recording');
    await discard(scratch);
  }

  /// Delete scratch `.neurofeed` and leftover `recording_$id` temps. Does not upsert.
  Future<void> discard(File scratch) async {
    final name = scratch.uri.pathSegments.last;
    final id = recordingIdFrom(name, '.neurofeed');
    if (id != null) {
      await deleteRecordingScratch(scratch.parent, id);
      return;
    }
    if (await scratch.exists()) {
      try {
        await scratch.delete();
      } catch (e) {
        debugPrint('[monitor] discard failed ${scratch.path}: $e');
      }
    }
  }
}

String _enabledStreamsCsv(StreamsConfig streams) {
  final names = <String>[];
  void add(String name, StreamInfo info) {
    if (info.enabled) names.add(name);
  }

  add('eeg', streams.eeg);
  add('bands', streams.bands);
  add('pulse', streams.pulse);
  add('spo2', streams.spo2);
  add('movement', streams.movement);
  add('peakAlpha', streams.peakAlpha);
  add('imu', streams.imu);
  add('ppg', streams.ppg);
  add('telemetry', streams.telemetry);
  add('gestures', streams.gestures);
  return names.join(',');
}
