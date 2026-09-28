import 'dart:math' as math;

import 'package:neurofeed/src/feedback/import/computed_rebuild.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/montage_match.dart';
import 'package:neurofeed/src/feedback/import/native_eeg.dart';
import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/edf_export.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/session_format/eeg_conditioning_meta.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

const _bandNames = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'];

/// Decode EDF/EDF+ bytes into an NFED6 recording [ImportResult].
///
/// Keeps exactly one supported montage (Muse 4 ch + AUX, or Crown 8 ch);
/// other channels are dropped and non-256 Hz EEG is resampled (lossy).
/// Throws [ImportRefused] when no complete montage is present. Bands come
/// from our own FFT of the EEG. Uses [fallbackSubject] when the patient
/// code is `X` / missing. Does **not** invent `feedback{}`.
ImportResult importEdfBytes({
  required List<int> bytes,
  required SubjectInfo fallbackSubject,
  String sourceFileName = '',
  String? recordingId,
  String? timeZone,
}) {
  final warnings = <ImportWarning>[];
  final decoded = decodeEdfImport(bytes: bytes);
  final recordDuration = decoded.recordDurationSeconds > 0
      ? decoded.recordDurationSeconds
      : 1.0;

  final originalChannels = <String>[];
  final eegSignals = <EdfDecodedSignal>[];
  final bandSignals = <({String band, String channel, EdfDecodedSignal sig})>[];
  for (final sig in decoded.signals) {
    final label = sig.label.trim();
    if (label.isEmpty || label.toLowerCase().contains('annotation')) continue;
    originalChannels.add(label);
    final bandParsed = _parseBandLabel(label);
    if (bandParsed != null) {
      bandSignals.add((
        band: bandParsed.band,
        channel: bandParsed.channel,
        sig: sig,
      ));
    } else {
      eegSignals.add(sig);
    }
  }

  final bandChannels = <String>[];
  for (final b in bandSignals) {
    if (!bandChannels.contains(b.channel)) bandChannels.add(b.channel);
  }
  final sourceLabels = eegSignals.isNotEmpty
      ? [for (final s in eegSignals) s.label.trim()]
      : bandChannels;
  final match = matchSupportedMontage(sourceLabels);
  if (match == null) {
    throw ImportRefused(noSupportedMontageMessage(sourceLabels));
  }
  final channelLabels = match.labels;
  final dropped = [
    ...match.dropped,
    if (eegSignals.isNotEmpty) ...[for (final b in bandSignals) b.sig.label],
  ];

  final runs = _contiguousRuns(decoded.recordStartsSeconds, recordDuration);
  final events = <int>[];
  var bandRows = <BandInstant>[];
  SignalConditioning? conditioning;
  double? originalRateHz;
  var resampled = false;
  if (eegSignals.isNotEmpty) {
    final runsByElectrode = <int, List<EegRun>>{};
    for (var e = 0; e < channelLabels.length; e++) {
      final sig = eegSignals[match.sourceIndices[e]];
      final spr = sig.samplesPerRecord;
      final rate = spr / recordDuration;
      originalRateHz ??= rate;
      if (needsResample(rate)) resampled = true;
      final data = [for (final v in sig.data) v.toDouble()];
      runsByElectrode[e] = [
        for (final run in runs)
          if (run.firstRecord * spr < data.length)
            EegRun(
              run.startSeconds * 1000.0,
              resampleToNative(
                data.sublist(
                  run.firstRecord * spr,
                  math.min(run.endRecord * spr, data.length),
                ),
                rate,
              ),
            ),
      ];
    }
    events.addAll(encodeEegRuns(runsByElectrode));
    final fft = fftBandRows(runsByElectrode);
    bandRows = fft.rows;
    conditioning = signalConditioningFrom(fft.conditioning);
    events.addAll(encodeBandEvents(bandRows));
  } else {
    bandRows = _bandSignalRows(bandSignals, match);
    events.addAll(encodeBandEvents(bandRows));
  }
  if (dropped.isNotEmpty) {
    warnings.add(
      ImportWarning(
        'dropped ${dropped.length} channel(s) outside the '
        '${match.device == 'muse' ? 'Muse' : 'Crown'} montage: '
        '${dropped.join(', ')}',
      ),
    );
  }
  if (resampled) {
    warnings.add(
      ImportWarning(
        'EEG resampled from ${_hz(originalRateHz!)} Hz to $kNativeEegHz Hz',
      ),
    );
  }
  if (runs.length > 1) {
    warnings.add(
      ImportWarning(
        '${runs.length - 1} recording gap(s) (EDF+D) kept as disconnect',
      ),
    );
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
      SessionAnnotation(
        onset: a.onsetSeconds,
        duration: a.durationSeconds,
        type: type,
      ),
    );
  }

  final starts = decoded.recordStartsSeconds;
  var durationS = starts.isNotEmpty && eegSignals.isNotEmpty
      ? (starts.last + recordDuration).ceil()
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
  final id = recordingId ?? savedAt.toUtc().millisecondsSinceEpoch.toString();

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
    if (eegSignals.isNotEmpty) RecordingStream.eeg,
    if (bandRows.isNotEmpty) RecordingStream.bands,
  };
  final device = DeviceInfo(
    name: 'imported',
    id: '',
    firmware: '',
    model: 'imported',
    sensors: [if (enabled.contains(RecordingStream.eeg)) 'EEG'],
    channelCount: channelLabels.length,
    channelLabels: channelLabels,
    conditioning: conditioning,
  );
  final streams = RecordingMetadata.streamsConfig(enabled);

  final computed = rebuildComputedFromBands(
    bandRows: bandRows,
    channelCount: channelLabels.length,
    treatAsBels: eegSignals.isNotEmpty ? false : null,
  );
  final stats = assembleBaseStats(
    frames: computed,
    annotations: annotations,
    channelLabels: channelLabels,
  );

  if (events.isEmpty) {
    warnings.add(const ImportWarning('EDF contained no EEG/band samples'));
  }
  final isEdfD = decoded.reserved.trim().toUpperCase().startsWith('EDF+D');
  final hasDisconnect = annotations.any((a) => a.type == 'disconnect');
  if (isEdfD && !hasDisconnect) {
    warnings.add(
      const ImportWarning(
        'EDF+D file had no recoverable timekeeping gaps — no disconnect annotations',
      ),
    );
  }
  final refs = {
    for (final i in match.sourceIndices) referenceSuffix(sourceLabels[i]),
  };
  final provenance = ImportProvenance(
    sourceFormat: decoded.reserved.trim().toUpperCase().startsWith('EDF+')
        ? 'edf+'
        : 'edf',
    sourceFileName: sourceFileName,
    originalChannels: originalChannels,
    originalRateHz: originalRateHz,
    droppedChannels: dropped,
    resampled: resampled,
    rawPresent: eegSignals.isNotEmpty,
    reference: refs.length == 1 ? refs.single : null,
    prefiltering: {
      for (final s in decoded.signals)
        if (s.prefiltering.isNotEmpty) s.label.trim(): s.prefiltering,
    },
    lossy: dropped.isNotEmpty || resampled,
    warnings: [for (final w in warnings) w.message],
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
    provenance: provenance,
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

  return ImportResult(
    id: id,
    containerBytes: container,
    metadataJson: metadataJson,
    provenance: provenance,
    warnings: warnings,
  );
}

List<({double startSeconds, int firstRecord, int endRecord})> _contiguousRuns(
  List<double> starts,
  double recordDuration,
) {
  final runs = <({double startSeconds, int firstRecord, int endRecord})>[];
  if (starts.isEmpty) return runs;
  var first = 0;
  for (var i = 1; i <= starts.length; i++) {
    final split =
        i == starts.length ||
        starts[i] - (starts[i - 1] + recordDuration) > 0.05;
    if (split) {
      runs.add((startSeconds: starts[first], firstRecord: first, endRecord: i));
      first = i;
    }
  }
  return runs;
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

String _hz(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Band-named EDF signals (no EEG): one row per sample, 1 sample/second.
List<BandInstant> _bandSignalRows(
  List<({String band, String channel, EdfDecodedSignal sig})> signals,
  MontageMatch match,
) {
  final byElectrode = <int, Map<String, List<double>>>{};
  final channels = <String>[];
  for (final s in signals) {
    if (!channels.contains(s.channel)) channels.add(s.channel);
  }
  for (var e = 0; e < match.labels.length; e++) {
    final channel = channels[match.sourceIndices[e]];
    for (final s in signals) {
      if (s.channel != channel) continue;
      byElectrode.putIfAbsent(e, () => {})[s.band] = [
        for (final v in s.sig.data) v.toDouble(),
      ];
    }
  }
  final n = byElectrode.values
      .expand((m) => m.values)
      .fold<int>(0, (a, s) => math.max(a, s.length));
  final rows = <BandInstant>[];
  for (var i = 0; i < n; i++) {
    final byEl = <int, BandValues>{};
    for (final e in byElectrode.entries) {
      double? g(String b) {
        final col = e.value[b];
        return col == null || i >= col.length ? null : col[i];
      }

      final d = g('Delta'), th = g('Theta'), a = g('Alpha');
      final b = g('Beta'), ga = g('Gamma');
      if (d == null || th == null || a == null || b == null || ga == null) {
        continue;
      }
      byEl[e.key] = BandValues(delta: d, theta: th, alpha: a, beta: b, gamma: ga);
    }
    if (byEl.isNotEmpty) {
      rows.add(BandInstant(timestampMs: i * 1000.0, byElectrode: byEl));
    }
  }
  return rows;
}
