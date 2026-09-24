import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/spine/capture_client.dart' as spine;
import 'package:neurofeed/src/session_v5/models.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/version.dart';
import 'package:neurofeed/src/util/timezone.dart';

const _recordingPrefix = 'recording_';

bool isTmpScratchName(String name) {
  if (!name.startsWith('tmp_')) return false;
  return name.endsWith('.raw') ||
      name.endsWith('.computed') ||
      name.endsWith('.json') ||
      name.endsWith('.json.tmp');
}

/// Id from a `recording_$id` scratch name, or null if the prefix/suffix
/// does not match. Does not accept `tmp_` or `session_`.
String? recordingIdFrom(String name, String suffix) {
  if (!name.startsWith(_recordingPrefix) || !name.endsWith(suffix)) {
    return null;
  }
  final id = name.substring(
    _recordingPrefix.length,
    name.length - suffix.length,
  );
  return id.isEmpty ? null : id;
}

/// Glob-delete leftover `tmp_*` scratch files. Does not touch `session_*` or
/// `recording_*` (those scanners stay prefix-strict).
Future<int> deleteLeftoverTmpCaptures(Directory scratch) async {
  if (!await scratch.exists()) return 0;
  var n = 0;
  await for (final entity in scratch.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!isTmpScratchName(name)) continue;
    try {
      await entity.delete();
      n++;
      debugPrint('[monitor-crash] deleted leftover $name');
    } catch (e) {
      debugPrint('[monitor-crash] failed to delete $name: $e');
    }
  }
  return n;
}

class RecoverableRecording {
  RecoverableRecording({required this.id, required this.scratchV5});

  final String id;
  final File scratchV5;
}

class _RecordingScratch {
  File? v5;
  File? raw;
  File? computed;
  File? json;
  File? jsonTmp;
}

/// Delete `recording_$id` scratch `.neurofeed` and leftover temps (not history-root files).
Future<void> deleteRecordingScratch(Directory dir, String id) async {
  for (final suffix in const [
    '.neurofeed',
    '.raw',
    '.computed',
    '.json',
    '.json.tmp',
  ]) {
    final f = File('${dir.path}/$_recordingPrefix$id$suffix');
    if (!await f.exists()) continue;
    try {
      await f.delete();
      debugPrint('[monitor-crash] deleted ${f.uri.pathSegments.last}');
    } catch (e) {
      debugPrint('[monitor-crash] failed to delete ${f.path}: $e');
    }
  }
}

RecordingMetadata recoveredRecordingMetadata({required int elapsedSeconds}) {
  final now = DateTime.now();
  return RecordingMetadata(
    formatVersion: 6,
    appVersion: appVersion,
    kind: 'recording',
    savedAt: now,
    startedAt: now.subtract(Duration(seconds: elapsedSeconds)),
    timeZone: captureIanaTimeZone(),
    sessionId: const Uuid().v4(),
    elapsedSeconds: elapsedSeconds,
    durationS: elapsedSeconds,
    device: const DeviceInfoV5(
      name: '',
      id: '',
      firmware: '',
      model: '',
      sensors: ['EEG'],
      channelCount: 4,
      channelLabels: ['TP9', 'AF7', 'AF8', 'TP10'],
    ),
    streams: RecordingMetadata.streamsConfig(RecordingStream.values.toSet()),
  );
}

int _elapsedFromComputed(Uint8List computed) {
  if (computed.isEmpty) return 0;
  try {
    final lines = utf8.decode(computed, allowMalformed: true).split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].trim().isEmpty) continue;
      final decoded = jsonDecode(lines[i]);
      if (decoded is Map && decoded['t'] is num) {
        return (decoded['t'] as num).round();
      }
    }
  } catch (_) {}
  return 0;
}

Map<String, Object?> _metadataJsonFromSidecar(
  File? jsonFile,
  Uint8List computed,
) {
  if (jsonFile != null && jsonFile.existsSync()) {
    try {
      final decoded = jsonDecode(jsonFile.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return RecordingMetadata.fromJson(decoded).toJson();
      }
    } catch (e) {
      debugPrint('[monitor-crash] sidecar parse failed: $e');
    }
  }
  return recoveredRecordingMetadata(
    elapsedSeconds: _elapsedFromComputed(computed),
  ).toJson();
}

Future<void> _deleteTemps(_RecordingScratch files) async {
  for (final f in [files.raw, files.computed, files.json, files.jsonTmp]) {
    if (f == null || !await f.exists()) continue;
    try {
      await f.delete();
    } catch (e) {
      debugPrint('[monitor-crash] failed to delete ${f.path}: $e');
    }
  }
}

Future<RecoverableRecording?> _assembleTemps({
  required Directory scratch,
  required String id,
  required _RecordingScratch files,
}) async {
  try {
    final computed = files.computed != null && await files.computed!.exists()
        ? await files.computed!.readAsBytes()
        : Uint8List(0);
    final metadataJson = _metadataJsonFromSidecar(files.json, computed);
    final file = await spine.assembleCaptureV5At(
      dir: scratch,
      prefix: 'recording',
      id: id,
      metadataJson: metadataJson,
    );
    await _deleteTemps(files);
    debugPrint('[monitor-crash] assembled ${file.uri.pathSegments.last}');
    return RecoverableRecording(id: id, scratchV5: file);
  } catch (e, st) {
    debugPrint('[monitor-crash] assemble temps for $id failed: $e\n$st');
    return null;
  }
}

/// Scan [scratch] for leftover `recording_*` temps and assembled `.neurofeed`.
/// Assembled file is returned as-is (temps deleted). Temps only are assembled
/// with [spine.assembleCaptureV5At] (FFI name kept; `prefix: recording`, placeholder WebP).
/// Does not touch `tmp_*` or `session_*`.
Future<List<RecoverableRecording>> scanRecoverableRecordings(
  Directory scratch,
) async {
  if (!await scratch.exists()) return const [];

  final byId = <String, _RecordingScratch>{};
  await for (final entity in scratch.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    void take(String? id, void Function(_RecordingScratch f) set) {
      if (id == null) return;
      set(byId.putIfAbsent(id, _RecordingScratch.new));
    }

    take(recordingIdFrom(name, '.neurofeed'), (f) => f.v5 = entity);
    take(recordingIdFrom(name, '.raw'), (f) => f.raw = entity);
    take(recordingIdFrom(name, '.computed'), (f) => f.computed = entity);
    take(recordingIdFrom(name, '.json'), (f) => f.json = entity);
    take(recordingIdFrom(name, '.json.tmp'), (f) => f.jsonTmp = entity);
  }

  final recovered = <RecoverableRecording>[];
  for (final entry in byId.entries) {
    final id = entry.key;
    final files = entry.value;
    if (files.v5 != null) {
      await _deleteTemps(files);
      recovered.add(RecoverableRecording(id: id, scratchV5: files.v5!));
      continue;
    }
    if (files.raw == null && files.computed == null) {
      await _deleteTemps(files);
      continue;
    }
    final rec = await _assembleTemps(scratch: scratch, id: id, files: files);
    if (rec != null) recovered.add(rec);
  }
  return recovered;
}
