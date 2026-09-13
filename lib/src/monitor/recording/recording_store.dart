import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/session_sqlite.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/recording/crash_recovery.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/rust/api/session_format.dart' as ffi;
import 'package:muse_ml/src/session_v5/assemble.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/version.dart';

final recordingStoreProvider = FutureProvider<RecordingStore>((ref) async {
  final storage = await ref.watch(sessionStorageProvider.future);
  final cacheDir = await resolveSessionCacheDir(storage);
  final sqlite = await SessionSqlite.open(cacheDirectory: cacheDir);
  return RecordingStore(storage: storage, sqlite: sqlite);
});

/// Publish / discard assembled `recording_$ts.muse.feedback` scratch files.
///
/// Upserts the same `session_metadata.db` as feedback (`kind = 'recording'`).
/// Does not import `session_store*.dart`.
class RecordingStore {
  RecordingStore({required SessionStorage storage, required SessionSqlite sqlite})
    : _storage = storage,
      _sqlite = sqlite;

  final SessionStorage _storage;
  final SessionSqlite _sqlite;

  /// Copy [scratchV5] into the history root and upsert sqlite `kind = recording`.
  /// Then delete the scratch v5 and leftover temps. Protocol is empty.
  Future<void> publish(File scratchV5) async {
    final name = scratchV5.uri.pathSegments.last;
    final id = recordingIdFrom(name, '.muse.feedback');
    if (id == null) {
      debugPrint('[monitor] publish: not a recording v5 ($name)');
      return;
    }
    final bytes = Uint8List.fromList(await scratchV5.readAsBytes());
    await _storage.ensureDir();
    await _storage.writeFileAtomic(name, bytes);

    RecordingMetadata meta;
    Uint8List thumb;
    ComputedScalars scalars = const ComputedScalars();
    try {
      final head = ffi.v5ParseHead(bytes: bytes);
      thumb = head.thumbnail;
      final decoded = jsonDecode(utf8.decode(head.metadataJson));
      meta = RecordingMetadata.fromJson(decoded as Map<String, dynamic>);
      try {
        scalars = extractComputedScalars(ffi.v5ExtractComputed(bytes: bytes));
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
        avgHr: scalars.avgHr,
        avgSpo2: scalars.avgSpo2,
        peakAlphaHz: scalars.peakAlphaHz,
        peakAlphaPower: scalars.peakAlphaPower,
        pctInTarget: scalars.pctInTarget,
        avgMovement: scalars.avgMovement,
        guardrailWarnCount: scalars.guardrailWarnCount,
        avgSleepDir: scalars.avgSleepDir,
        markerCount: 0,
        sessionId: id,
        notesPreview: meta.notes.isEmpty
            ? null
            : (meta.notes.length > 50 ? meta.notes.substring(0, 50) : meta.notes),
        fileSize: bytes.length,
        mtime: now.millisecondsSinceEpoch,
        thumbnail: thumb.isNotEmpty ? thumb : null,
        createdAt: now,
        updatedAt: now,
      ),
    );
    debugPrint('[monitor] recording publish $name kind=recording');
    await discard(scratchV5);
  }

  /// Delete scratch v5 and leftover `recording_$id` temps. Does not upsert.
  Future<void> discard(File scratchV5) async {
    final name = scratchV5.uri.pathSegments.last;
    final id = recordingIdFrom(name, '.muse.feedback');
    if (id != null) {
      await deleteRecordingScratch(scratchV5.parent, id);
      return;
    }
    if (await scratchV5.exists()) {
      try {
        await scratchV5.delete();
      } catch (e) {
        debugPrint('[monitor] discard failed ${scratchV5.path}: $e');
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
