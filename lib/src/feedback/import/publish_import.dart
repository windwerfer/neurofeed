import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/feedback/import/csv_import.dart';
import 'package:neurofeed/src/feedback/import/edf_import.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/monitor/recording/recording_store.dart';
import 'package:neurofeed/src/settings.dart';

export 'package:neurofeed/src/feedback/import/csv_import.dart';
export 'package:neurofeed/src/feedback/import/edf_import.dart';
export 'package:neurofeed/src/feedback/import/import_types.dart';

/// Detect format from path / bytes and build an [ImportResult].
ImportResult importRecordingBytes({
  required List<int> bytes,
  required String fileName,
  required SubjectInfo subject,
  String? timeZone,
}) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.edf')) {
    return importEdfBytes(bytes: bytes, fallbackSubject: subject, timeZone: timeZone);
  }
  if (lower.endsWith('.csv')) {
    return importCsvText(
      csvText: utf8.decode(bytes),
      subject: subject,
      timeZone: timeZone,
    );
  }
  // Sniff: EDF version-0 header starts with "0       ".
  if (bytes.length >= 8 &&
      bytes[0] == 0x30 /* '0' */ &&
      bytes.sublist(1, 8).every((b) => b == 0x20)) {
    return importEdfBytes(bytes: bytes, fallbackSubject: subject, timeZone: timeZone);
  }
  // Fallback: try CSV text.
  final text = utf8.decode(bytes);
  if (text.startsWith('TimeStamp')) {
    return importCsvText(csvText: text, subject: subject, timeZone: timeZone);
  }
  throw FormatException('Unsupported import format: $fileName');
}

/// Write [result] as `recording_$id.neurofeed` into scratch, then
/// [RecordingStore.publish] so sqlite lists it.
Future<ImportResult> publishImportResult({
  required ImportResult result,
  required RecordingStore store,
  required SessionStorage storage,
}) async {
  final scratchDir = scratchDirectory(storage);
  if (!await scratchDir.exists()) {
    await scratchDir.create(recursive: true);
  }
  final scratch = File('${scratchDir.path}/recording_${result.id}.neurofeed');
  await scratch.writeAsBytes(result.containerBytes, flush: true);
  await store.publish(scratch);
  debugPrint(
    '[import] published recording_${result.id}.neurofeed '
    '(${result.containerBytes.length}B, ${result.warnings.length} warning(s))',
  );
  return result;
}

/// Read [path], convert, and publish into History.
Future<ImportResult> importAndPublishFile({
  required String path,
  required RecordingStore store,
  required SessionStorage storage,
  required SubjectInfo subject,
  String? timeZone,
}) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  final name = file.uri.pathSegments.isNotEmpty
      ? file.uri.pathSegments.last
      : path;
  final result = importRecordingBytes(
    bytes: bytes,
    fileName: name,
    subject: subject,
    timeZone: timeZone,
  );
  return publishImportResult(
    result: result,
    store: store,
    storage: storage,
  );
}
