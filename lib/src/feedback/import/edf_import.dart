import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/edf_export.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

/// Decode EDF/EDF+ bytes into an NFED6 recording [ImportResult].
///
/// Uses [fallbackSubject] when the patient code is `X` / missing. Does **not**
/// invent `feedback{}`. Computed section is empty (recompute later).
ImportResult importEdfBytes({
  required List<int> bytes,
  required SubjectInfo fallbackSubject,
  String? recordingId,
  String? timeZone,
}) {
  final warnings = <ImportWarning>[];
  final decoded = decodeEdfImport(bytes: bytes);

  final labels = <String>[];
  final samplesByElectrode = <int, List<double>>{};
  var rateHz = 256.0;
  for (final sig in decoded.signals) {
    final label = sig.label.trim();
    if (label.isEmpty) continue;
    // Skip non-EEG-looking signals for the raw EEG body (band/aux later).
    final lower = label.toLowerCase();
    if (lower.contains('annotation')) continue;
    final idx = labels.length;
    labels.add(label);
    samplesByElectrode[idx] = [for (final v in sig.data) v.toDouble()];
    if (sig.samplesPerRecord > 0) {
      rateHz = sig.samplesPerRecord.toDouble();
    }
  }
  if (labels.isEmpty) {
    throw StateError('EDF has no importable signal channels');
  }

  final eegEvents = encodeEegPackets(
    samplesByElectrode: samplesByElectrode,
    sampleRateHz: rateHz,
  );
  final rawBody = assembleRawBody(eegEvents);

  final annotations = <SessionAnnotation>[];
  for (final a in decoded.annotations) {
    final type = mapImportAnnotationType(a.text);
    if (type == null) {
      if (a.text.trim().isNotEmpty) {
        warnings.add(ImportWarning('skipped EDF annotation "${a.text}"'));
      }
      continue;
    }
    annotations.add(
      SessionAnnotation(onset: a.onsetSeconds, duration: 0, type: type),
    );
  }

  final maxSamples = samplesByElectrode.values
      .map((s) => s.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final durationS = rateHz > 0 ? (maxSamples / rateHz).ceil() : 0;
  final elapsed = durationS;

  final startedAt = DateTime(
    decoded.year,
    decoded.month,
    decoded.day,
    decoded.hour,
    decoded.minute,
    decoded.second,
  );
  final savedAt = DateTime.now();
  final tz = timeZone ?? captureIanaTimeZone();
  final id = recordingId ??
      savedAt.toUtc().millisecondsSinceEpoch.toString();

  final code = edfPatientCode(decoded.patientId);
  final subject = (code != null && code.isNotEmpty)
      ? SubjectInfo(id: code, nickname: fallbackSubject.nickname)
      : fallbackSubject;
  if (code == null) {
    warnings.add(
      const ImportWarning('EDF patient code missing — using settings subject.id'),
    );
  }

  final device = DeviceInfo(
    name: 'imported',
    id: '',
    firmware: '',
    model: 'imported',
    sensors: const ['EEG'],
    channelCount: labels.length,
    channelLabels: labels,
  );
  final streams = RecordingMetadata.streamsConfig({RecordingStream.eeg});
  final meta = RecordingMetadata(
    formatVersion: kFormatVersionV6,
    appVersion: appVersion,
    kind: 'recording',
    savedAt: savedAt,
    startedAt: startedAt,
    elapsedSeconds: elapsed,
    durationS: durationS,
    notes: '',
    device: device,
    streams: streams,
    timeZone: tz,
    sessionId: id,
    subject: subject,
  );
  final metadataJson = buildRecordingMetadata(
    meta: meta,
    subject: subject,
    sessionId: id,
    annotations: annotations,
  );

  final container = assembleContainer(
    thumbnail: const [],
    metadataJson: metadataJson,
    computedFrames: const [],
    rawBody: rawBody,
  );

  if (eegEvents.isEmpty) {
    warnings.add(const ImportWarning('EDF contained no EEG samples'));
  }

  return ImportResult(
    id: id,
    containerBytes: container,
    metadataJson: metadataJson,
    warnings: warnings,
  );
}
