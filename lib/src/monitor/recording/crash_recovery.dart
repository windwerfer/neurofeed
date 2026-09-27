import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/spine/capture_client.dart' as spine;
import 'package:neurofeed/src/session_format/models.dart';
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
  RecoverableRecording({required this.id, required this.scratch});

  final String id;
  final File scratch;
}

class _RecordingScratch {
  File? container;
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

/// Fallback metadata when the sidecar is missing or unreadable. The device
/// is unknown, so only a plain 4- or 5-channel frame is labelled as Muse;
/// any other width gets neutral `CH<n>` labels.
RecordingMetadata recoveredRecordingMetadata({
  required int elapsedSeconds,
  int channelCount = 4,
}) {
  final now = DateTime.now();
  final labels = channelCount == 4 || channelCount == 5
      ? electrodeNamesForKind(DeviceKind.muse, auxChannels: channelCount - 4)
      : [for (var i = 0; i < channelCount; i++) 'CH${i + 1}'];
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
    device: DeviceInfo(
      name: '',
      id: '',
      firmware: '',
      model: '',
      sensors: const ['EEG'],
      channelCount: labels.length,
      channelLabels: labels,
    ),
    streams: RecordingMetadata.streamsConfig(RecordingStream.values.toSet()),
  );
}

Map<dynamic, dynamic>? _lastComputedLine(Uint8List computed) {
  if (computed.isEmpty) return null;
  try {
    final lines = utf8.decode(computed, allowMalformed: true).split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].trim().isEmpty) continue;
      final decoded = jsonDecode(lines[i]);
      if (decoded is Map && decoded['t'] is num) return decoded;
    }
  } catch (_) {}
  return null;
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
  final last = _lastComputedLine(computed);
  final bands = last?['bands'];
  return recoveredRecordingMetadata(
    elapsedSeconds: last == null ? 0 : (last['t'] as num).round(),
    channelCount: bands is List && bands.isNotEmpty ? bands.length : 4,
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
    final file = await spine.assembleCaptureAt(
      dir: scratch,
      prefix: 'recording',
      id: id,
      metadataJson: metadataJson,
    );
    await _deleteTemps(files);
    debugPrint('[monitor-crash] assembled ${file.uri.pathSegments.last}');
    return RecoverableRecording(id: id, scratch: file);
  } catch (e, st) {
    debugPrint('[monitor-crash] assemble temps for $id failed: $e\n$st');
    return null;
  }
}

/// Scan [scratch] for leftover `recording_*` temps and assembled `.neurofeed`.
/// Assembled file is returned as-is (temps deleted). Temps only are assembled
/// with [spine.assembleCaptureAt] (`prefix: recording`, placeholder WebP).
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

    take(recordingIdFrom(name, '.neurofeed'), (f) => f.container = entity);
    take(recordingIdFrom(name, '.raw'), (f) => f.raw = entity);
    take(recordingIdFrom(name, '.computed'), (f) => f.computed = entity);
    take(recordingIdFrom(name, '.json'), (f) => f.json = entity);
    take(recordingIdFrom(name, '.json.tmp'), (f) => f.jsonTmp = entity);
  }

  final recovered = <RecoverableRecording>[];
  for (final entry in byId.entries) {
    final id = entry.key;
    final files = entry.value;
    if (files.container != null) {
      await _deleteTemps(files);
      recovered.add(RecoverableRecording(id: id, scratch: files.container!));
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
