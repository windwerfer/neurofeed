import 'package:neurofeed/src/feedback/import/computed_rebuild.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/edf_export.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

const _bandNames = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'];

/// Decode EDF/EDF+ bytes into an NFED6 recording [ImportResult].
///
/// Uses [fallbackSubject] when the patient code is `X` / missing. Does **not**
/// invent `feedback{}`. When band-named signals exist, fills computed 1 Hz.
ImportResult importEdfBytes({
  required List<int> bytes,
  required SubjectInfo fallbackSubject,
  String? recordingId,
  String? timeZone,
}) {
  final warnings = <ImportWarning>[];
  final decoded = decodeEdfImport(bytes: bytes);

  final eegLabels = <String>[];
  final samplesByElectrode = <int, List<double>>{};
  var rateHz = 256.0;

  // Optional band signals: label like `Alpha_TP9` or `Alpha TP9`.
  final bandByElectrode = <int, Map<String, List<double>>>{};
  final bandChannelOrder = <String>[];

  for (final sig in decoded.signals) {
    final label = sig.label.trim();
    if (label.isEmpty) continue;
    final lower = label.toLowerCase();
    if (lower.contains('annotation')) continue;

    final bandParsed = _parseBandLabel(label);
    if (bandParsed != null) {
      final ch = bandParsed.channel;
      if (!bandChannelOrder.contains(ch)) bandChannelOrder.add(ch);
      final ei = bandChannelOrder.indexOf(ch);
      bandByElectrode.putIfAbsent(ei, () => {})[bandParsed.band] =
          [for (final v in sig.data) v.toDouble()];
      continue;
    }

    final idx = eegLabels.length;
    eegLabels.add(label);
    samplesByElectrode[idx] = [for (final v in sig.data) v.toDouble()];
    if (sig.samplesPerRecord > 0) {
      rateHz = sig.samplesPerRecord.toDouble();
    }
  }

  if (eegLabels.isEmpty && bandChannelOrder.isEmpty) {
    throw StateError('EDF has no importable signal channels');
  }

  final events = <int>[];
  if (samplesByElectrode.isNotEmpty) {
    events.addAll(
      encodeEegPackets(
        samplesByElectrode: samplesByElectrode,
        sampleRateHz: rateHz,
      ),
    );
  }

  final bandRows = <BandInstant>[];
  if (bandByElectrode.isNotEmpty) {
    // Assume 1 sample/sec band signals (common for absolute bands).
    final n = bandByElectrode.values
        .expand((m) => m.values)
        .map((s) => s.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < n; i++) {
      final byEl = <int, BandValues>{};
      for (final e in bandByElectrode.keys) {
        final m = bandByElectrode[e]!;
        double? g(String b) {
          final col = m[b];
          if (col == null || i >= col.length) return null;
          return col[i];
        }
        final d = g('Delta');
        final th = g('Theta');
        final a = g('Alpha');
        final b = g('Beta');
        final ga = g('Gamma');
        if (d == null || th == null || a == null || b == null || ga == null) {
          continue;
        }
        byEl[e] = BandValues(
          delta: d,
          theta: th,
          alpha: a,
          beta: b,
          gamma: ga,
        );
      }
      if (byEl.isNotEmpty) {
        bandRows.add(BandInstant(timestampMs: i * 1000.0, byElectrode: byEl));
      }
    }
    events.addAll(encodeBandEvents(bandRows));
  }

  final rawBody = assembleRawBody(events);

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

  final channelLabels =
      eegLabels.isNotEmpty ? eegLabels : List<String>.from(bandChannelOrder);
  final maxSamples = samplesByElectrode.values
      .map((s) => s.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  var durationS = rateHz > 0 && maxSamples > 0
      ? (maxSamples / rateHz).ceil()
      : 0;
  if (durationS == 0 && bandRows.isNotEmpty) {
    durationS = bandRows.length;
  }
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
      const ImportWarning(
        'EDF patient code missing — using settings subject.id',
      ),
    );
  }

  final enabled = <RecordingStream>{
    if (samplesByElectrode.isNotEmpty) RecordingStream.eeg,
    if (bandRows.isNotEmpty) RecordingStream.bands,
  };
  final device = DeviceInfo(
    name: 'imported',
    id: '',
    firmware: '',
    model: 'imported',
    sensors: [
      if (enabled.contains(RecordingStream.eeg)) 'EEG',
    ],
    channelCount: channelLabels.length,
    channelLabels: channelLabels,
  );
  final streams = RecordingMetadata.streamsConfig(enabled);

  final computed = rebuildComputedFromBands(
    bandRows: bandRows,
    channelCount: channelLabels.isEmpty ? 1 : channelLabels.length,
  );
  final stats = assembleBaseStats(
    frames: computed,
    annotations: annotations,
    channelLabels: channelLabels,
  );

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
    stats: stats,
  );

  final container = assembleContainer(
    thumbnail: const [],
    metadataJson: metadataJson,
    computedFrames: computed,
    rawBody: rawBody,
  );

  if (events.isEmpty) {
    warnings.add(const ImportWarning('EDF contained no EEG/band samples'));
  }

  // EDF+D discontinuity → disconnect annotations: decode does not yet expose
  // per-record timekeeping jumps; see .ai/TODO/import-export.md.
  if (decoded.reserved.trim().toUpperCase().startsWith('EDF+D')) {
    warnings.add(
      const ImportWarning(
        'EDF+D discontinuous file — disconnect gaps not yet mapped',
      ),
    );
  }

  return ImportResult(
    id: id,
    containerBytes: container,
    metadataJson: metadataJson,
    warnings: warnings,
  );
}

({String band, String channel})? _parseBandLabel(String label) {
  final cleaned = label.trim().replaceAll(RegExp(r'\s+'), '_');
  for (final b in _bandNames) {
    final prefix = '${b}_';
    if (cleaned.startsWith(prefix) && cleaned.length > prefix.length) {
      return (band: b, channel: cleaned.substring(prefix.length));
    }
    if (cleaned.toLowerCase().startsWith('${b.toLowerCase()}_') &&
        cleaned.length > b.length + 1) {
      return (band: b, channel: cleaned.substring(b.length + 1));
    }
  }
  return null;
}
