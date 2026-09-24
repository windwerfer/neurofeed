import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:neurofeed/src/rust/api/capture.dart';
import 'package:neurofeed/src/settings.dart';

export 'package:neurofeed/src/rust/api/capture.dart';

List<String> recordingStreamNames(Set<RecordingStream> streams) =>
    streams.map((s) => s.name).toList();

Future<void> startCapture({
  required Directory dir,
  required String prefix,
  required String id,
  required Set<RecordingStream> streams,
  required int startedAtMs,
}) {
  return captureStart(
    dir: dir.path,
    prefix: prefix,
    id: id,
    recordStreams: recordingStreamNames(streams),
    startedAtMs: startedAtMs.toDouble(),
  );
}

void syncRecordingIndex({
  required void Function() clear,
  required void Function({required double elapsedT, required int fileLength})
  add,
}) {
  clear();
  for (final e in captureFlushIndex()) {
    add(elapsedT: e.elapsedS, fileLength: e.endOffset.toInt());
  }
}

Set<int> recordedChannelSet() => captureRecordedChannels().toSet();

Uint8List metadataJsonBytes(Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Future<File> assembleCapture({
  required Map<String, Object?> metadataJson,
  List<int> thumbnail = const [],
}) async {
  final path = await captureAssemble(
    metadataJson: metadataJsonBytes(metadataJson),
    thumbnail: thumbnail,
  );
  return File(path);
}

Future<File> assembleCaptureAt({
  required Directory dir,
  required String prefix,
  required String id,
  required Map<String, Object?> metadataJson,
  List<int> thumbnail = const [],
}) async {
  final path = await captureAssembleAt(
    dir: dir.path,
    prefix: prefix,
    id: id,
    metadataJson: metadataJsonBytes(metadataJson),
    thumbnail: thumbnail,
  );
  return File(path);
}
