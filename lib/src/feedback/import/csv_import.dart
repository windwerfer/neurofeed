import 'dart:math' as math;

import 'package:neurofeed/src/feedback/import/computed_rebuild.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/montage_match.dart';
import 'package:neurofeed/src/feedback/import/native_eeg.dart';
import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/session_format/eeg_conditioning_meta.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

const _bandNames = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'];

/// Preferred PPG channel name → Muse channel index.
const _ppgNameToChannel = {
  'PPG_Ambient': 0,
  'PPG_Green': 0,
  'PPG_IR': 1,
  'PPG_IR-H16': 1,
  'PPG_Red': 2,
  'PPG_1': 0,
  'PPG_2': 1,
  'PPG_3': 2,
};

enum CsvRecordingRate {
  /// Recording Interval 0.5 s … 60 s (default 1 s; neurofeed CSV export):
  /// each row is a snapshot, so only bands are imported.
  interval,

  /// Constant: every sample (RAW 256 Hz, 220 Hz on MU-01; bands ~10 Hz).
  constant,
}

/// Median row spacing below this is Constant; at or above it, Interval.
const double kCsvConstantMaxRowSeconds = 0.25;

/// EEG span behind one Mind Monitor band row (~1 s window).
const double kCsvBandWindowSeconds = 1.0;

/// Interval rows at or above this (2 s with jitter) cover too little of the
/// session; the import dialog warns.
const double kCsvCoverageWarnSeconds = 1.9;

/// Share of the session covered by band rows every [intervalSeconds].
double csvIntervalCoverage(double intervalSeconds) =>
    math.min(1.0, kCsvBandWindowSeconds / intervalSeconds);

/// Parsed Mind Monitor / neurofeed CSV ready to assemble.
class ParsedMindMonitorCsv {
  ParsedMindMonitorCsv({
    required this.headers,
    required this.timestamps,
    required this.rate,
    required this.medianDeltaSeconds,
    required this.rawByChannel,
    required this.bandsByChannel,
    required this.channelLabels,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.ppgByChannel,
    required this.ppgChannelLabels,
    required this.sourceChannels,
    required this.opticsColumns,
    required this.elements,
    required this.hasAcc,
    required this.hasGyro,
    required this.hasPpg,
    required this.hasHsi,
    required this.hasBattery,
    required this.hasElements,
  });

  final List<String> headers;
  final List<DateTime> timestamps;
  final CsvRecordingRate rate;
  final double medianDeltaSeconds;

  /// Channel label → list aligned with [timestamps] (null = empty cell).
  final Map<String, List<double?>> rawByChannel;

  /// Band name (`Delta`…) → channel → values aligned with rows.
  final Map<String, Map<String, List<double?>>> bandsByChannel;

  final List<String> channelLabels;

  /// Aligned with rows; null = empty.
  final List<double?> accX;
  final List<double?> accY;
  final List<double?> accZ;
  final List<double?> gyroX;
  final List<double?> gyroY;
  final List<double?> gyroZ;

  /// Muse PPG channel index → row-aligned values.
  final Map<int, List<double?>> ppgByChannel;
  final List<String> ppgChannelLabels;

  /// EEG channel names as found in the file (RAW_/band names, AUX columns).
  final List<String> sourceChannels;

  /// Optics (Athena fNIRS) columns — never imported.
  final List<String> opticsColumns;

  /// Row-aligned Elements cell (empty string when absent).
  final List<String> elements;

  final bool hasAcc;
  final bool hasGyro;
  final bool hasPpg;
  final bool hasHsi;
  final bool hasBattery;
  final bool hasElements;
}

/// Parse a Mind Monitor / neurofeed CSV string.
///
/// Accepts the neurofeed export subset (TimeStamp + bands + RAW) and fuller
/// headers with optional ACC/Gyro/PPG/HSI/Battery/Elements columns.
ParsedMindMonitorCsv parseMindMonitorCsv(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    throw FormatException('CSV is empty');
  }
  final headers = _splitCsvLine(lines.first);
  if (headers.isEmpty || headers.first != 'TimeStamp') {
    throw FormatException('CSV must start with TimeStamp column');
  }

  final col = {for (var i = 0; i < headers.length; i++) headers[i]: i};

  final eegNames = <String>[];
  for (final h in headers) {
    String? ch;
    if (h.startsWith('RAW_')) ch = h.substring(4);
    for (final band in _bandNames) {
      if (h.startsWith('${band}_')) ch = h.substring(band.length + 1);
    }
    if (ch != null && !eegNames.contains(ch)) eegNames.add(ch);
  }
  final auxColumns = [
    for (final h in headers)
      if (h.toUpperCase().startsWith('AUX')) h,
  ].take(kMuseAuxElectrodeNames.length).toList();
  final match = matchSupportedMontage([
    ...eegNames,
    for (var i = 0; i < auxColumns.length; i++) kMuseAuxElectrodeNames[i],
  ]);
  if (match == null) {
    throw ImportRefused(noSupportedMontageMessage([...eegNames, ...auxColumns]));
  }
  final channelLabels = match.labels;
  // Our label → CSV column suffix (`RAW_<suffix>`, `Alpha_<suffix>`), or the
  // full AUX column name.
  final columnFor = <String, String>{
    for (var e = 0; e < channelLabels.length; e++)
      channelLabels[e]: match.sourceIndices[e] < eegNames.length
          ? eegNames[match.sourceIndices[e]]
          : auxColumns[match.sourceIndices[e] - eegNames.length],
  };
  final opticsColumns = [
    for (final h in headers)
      if (h.startsWith('Optics')) h,
  ];

  final ppgCols = <String, int>{};
  for (final h in headers) {
    if (_ppgNameToChannel.containsKey(h) || h.startsWith('PPG_')) {
      ppgCols[h] = col[h]!;
    }
  }
  // Assign unknown PPG_/Optics* names by sorted order after known ones.
  final ppgChannelLabels = ppgCols.keys.toList()
    ..sort((a, b) {
      final ia = _ppgNameToChannel[a] ?? 100;
      final ib = _ppgNameToChannel[b] ?? 100;
      if (ia != ib) return ia.compareTo(ib);
      return a.compareTo(b);
    });
  final ppgIndexByName = <String, int>{};
  var nextUnknown = 0;
  for (final name in ppgChannelLabels) {
    ppgIndexByName[name] =
        _ppgNameToChannel[name] ?? (10 + nextUnknown++);
  }

  final timestamps = <DateTime>[];
  final rawByChannel = {
    for (final ch in channelLabels) ch: <double?>[],
  };
  final bandsByChannel = {
    for (final b in _bandNames)
      b: {for (final ch in channelLabels) ch: <double?>[]},
  };
  final accX = <double?>[];
  final accY = <double?>[];
  final accZ = <double?>[];
  final gyroX = <double?>[];
  final gyroY = <double?>[];
  final gyroZ = <double?>[];
  final ppgByChannel = {
    for (final name in ppgChannelLabels) ppgIndexByName[name]!: <double?>[],
  };
  final elements = <String>[];

  for (var li = 1; li < lines.length; li++) {
    final cells = _splitCsvLine(lines[li]);
    if (cells.isEmpty) continue;
    final ts = _parseTimeStamp(cells[0]);
    if (ts == null) {
      throw FormatException('bad TimeStamp on line ${li + 1}: ${cells[0]}');
    }
    timestamps.add(ts);
    for (final ch in channelLabels) {
      final src = columnFor[ch]!;
      final isAux = isAuxChannelLabel(ch);
      rawByChannel[ch]!.add(
        _cellDouble(cells, isAux ? col[src] : col['RAW_$src']),
      );
      for (final b in _bandNames) {
        bandsByChannel[b]![ch]!.add(
          isAux ? null : _cellDouble(cells, col['${b}_$src']),
        );
      }
    }
    accX.add(_cellDouble(cells, col['Accelerometer_X']));
    accY.add(_cellDouble(cells, col['Accelerometer_Y']));
    accZ.add(_cellDouble(cells, col['Accelerometer_Z']));
    gyroX.add(_cellDouble(cells, col['Gyro_X']));
    gyroY.add(_cellDouble(cells, col['Gyro_Y']));
    gyroZ.add(_cellDouble(cells, col['Gyro_Z']));
    for (final name in ppgChannelLabels) {
      final idx = ppgIndexByName[name]!;
      ppgByChannel[idx]!.add(_cellDouble(cells, ppgCols[name]));
    }
    final elIdx = col['Elements'];
    if (elIdx != null && elIdx < cells.length) {
      elements.add(cells[elIdx].trim());
    } else {
      elements.add('');
    }
  }
  if (timestamps.length < 2) {
    throw FormatException('CSV needs at least two data rows');
  }

  final deltas = <double>[];
  for (var i = 1; i < timestamps.length; i++) {
    deltas.add(
      timestamps[i].difference(timestamps[i - 1]).inMicroseconds / 1e6,
    );
  }
  deltas.sort();
  final medianDt = deltas[deltas.length ~/ 2];
  final rate = medianDt < kCsvConstantMaxRowSeconds
      ? CsvRecordingRate.constant
      : CsvRecordingRate.interval;

  bool hasPrefix(String p) => headers.any((h) => h.startsWith(p));
  final hasAcc = hasPrefix('Accelerometer_');
  final hasGyro = hasPrefix('Gyro_');
  final hasPpg = ppgChannelLabels.isNotEmpty;

  return ParsedMindMonitorCsv(
    headers: headers,
    timestamps: timestamps,
    rate: rate,
    medianDeltaSeconds: medianDt,
    rawByChannel: rawByChannel,
    bandsByChannel: bandsByChannel,
    channelLabels: channelLabels,
    accX: accX,
    accY: accY,
    accZ: accZ,
    gyroX: gyroX,
    gyroY: gyroY,
    gyroZ: gyroZ,
    ppgByChannel: ppgByChannel,
    ppgChannelLabels: ppgChannelLabels,
    sourceChannels: [...eegNames, ...auxColumns],
    opticsColumns: opticsColumns,
    elements: elements,
    hasAcc: hasAcc,
    hasGyro: hasGyro,
    hasPpg: hasPpg,
    hasHsi: headers.any((h) => h.startsWith('HSI_') || h == 'HeadBandOn'),
    hasBattery: headers.contains('Battery'),
    hasElements: headers.contains('Elements'),
  );
}

/// Build an NFED6 recording from Mind Monitor / neurofeed CSV text.
///
/// Interval files import bands only (a RAW snapshot per interval is not
/// EEG); Constant files keep RAW (220 Hz resampled to 256 Hz), AUX and every
/// band value. Optics columns are dropped.
ImportResult importCsvText({
  required String csvText,
  required SubjectInfo subject,
  String sourceFileName = '',
  String? recordingId,
  String? timeZone,
}) {
  final warnings = <ImportWarning>[];
  final parsed = parseMindMonitorCsv(csvText);

  final startedAt = parsed.timestamps.first;
  final endedAt = parsed.timestamps.last;
  final durationS = math
      .max(
        1,
        endedAt.difference(startedAt).inMilliseconds / 1000.0,
      )
      .ceil();
  final savedAt = DateTime.now();
  final tz = timeZone ?? captureIanaTimeZone();
  final id = recordingId ??
      savedAt.toUtc().millisecondsSinceEpoch.toString();

  final enabled = <RecordingStream>{};
  final hasAnyRaw = parsed.rawByChannel.values.any(
    (col) => col.any((v) => v != null),
  );
  final hasAnyBand = parsed.bandsByChannel.values.any(
    (m) => m.values.any((col) => col.any((v) => v != null)),
  );
  if (hasAnyRaw) enabled.add(RecordingStream.eeg);
  if (hasAnyBand) enabled.add(RecordingStream.bands);
  if (enabled.isEmpty) {
    throw StateError('CSV has no RAW or band values');
  }
  if (!hasAnyRaw) {
    warnings.add(const ImportWarning('no RAW columns — bands only'));
  }
  if (!hasAnyBand && parsed.rate == CsvRecordingRate.interval) {
    throw const ImportRefused(
      'This Mind Monitor CSV uses a recording interval and has no band '
      'columns — one RAW snapshot per interval is not importable EEG.',
    );
  }

  final interval = parsed.rate == CsvRecordingRate.interval;
  final channelLabels = parsed.channelLabels;
  final events = <int>[];
  var bandRows = <BandInstant>[];
  SignalConditioning? conditioning;
  double? recordingInterval;
  var bandsFromFft = false;
  double? rawRateHz;
  var resampled = false;
  final dropped = <String>[...parsed.opticsColumns];
  if (parsed.opticsColumns.isNotEmpty) {
    warnings.add(
      ImportWarning(
        'dropped ${parsed.opticsColumns.length} Optics (fNIRS) column(s)',
      ),
    );
  }

  if (interval) {
    enabled.remove(RecordingStream.eeg);
    bandRows = _bandRowsAt(parsed, dedupe: false);
    recordingInterval =
        ((_medianGapSeconds(bandRows) ?? parsed.medianDeltaSeconds) * 10)
            .round() /
        10;
    events.addAll(encodeBandEvents(bandRows));
    final auxColumns = parsed.sourceChannels
        .where((c) => c.toUpperCase().startsWith('AUX'))
        .toList();
    dropped.addAll(auxColumns);
    final skipped = [
      if (hasAnyRaw) 'RAW',
      if (auxColumns.isNotEmpty) 'AUX',
      if (parsed.hasAcc || parsed.hasGyro) 'IMU',
      if (parsed.hasPpg) 'PPG',
    ];
    if (skipped.isNotEmpty) {
      warnings.add(
        ImportWarning(
          'Recording interval ${_seconds(recordingInterval)} s: '
          '${skipped.join('/')} are one snapshot per interval — not imported '
          '(bands only)',
        ),
      );
    }
  } else {
    final raw = _constantRaw(parsed);
    rawRateHz = raw.runs.isEmpty ? null : raw.rateHz;
    resampled = raw.runs.isNotEmpty && needsResample(raw.rateHz);
    events.addAll(encodeEegRuns(raw.runs));
    if (resampled) {
      warnings.add(
        ImportWarning(
          'RAW resampled from ${raw.rateHz.round()} Hz to $kNativeEegHz Hz',
        ),
      );
    }
    if (raw.runs.isEmpty) enabled.remove(RecordingStream.eeg);
    bandRows = _bandRowsAt(parsed, dedupe: true);
    if (bandRows.isEmpty && raw.runs.isNotEmpty) {
      final fft = fftBandRows(raw.runs);
      bandRows = fft.rows;
      conditioning = signalConditioningFrom(fft.conditioning, startMs: 0);
      bandsFromFft = true;
      enabled.add(RecordingStream.bands);
      warnings.add(
        const ImportWarning('no band columns — bands computed from RAW'),
      );
    } else if (raw.runs.isNotEmpty) {
      // Charts show the conditioned RAW; record what that conditioning is.
      conditioning = signalConditioningFrom(
        conditionRuns(raw.runs).conditioning,
        startMs: 0,
      );
    }
    events.addAll(encodeBandEvents(bandRows));
  }
  final rawPresent = enabled.contains(RecordingStream.eeg);

  // ACC / Gyro / PPG → raw streams (Constant only).
  final accSamples = interval
      ? const <ImuSample>[]
      : _collectImu(parsed.timestamps, parsed.accX, parsed.accY, parsed.accZ);
  final gyroSamples = interval
      ? const <ImuSample>[]
      : _collectImu(
          parsed.timestamps,
          parsed.gyroX,
          parsed.gyroY,
          parsed.gyroZ,
        );
  if (accSamples.isNotEmpty) {
    events.addAll(encodeAccelerometerEvents(accSamples));
    enabled.add(RecordingStream.imu);
  } else if (parsed.hasAcc && !interval) {
    warnings.add(
      const ImportWarning('Accelerometer columns present but all empty'),
    );
  }
  if (gyroSamples.isNotEmpty) {
    events.addAll(encodeGyroscopeEvents(gyroSamples));
    enabled.add(RecordingStream.imu);
  } else if (parsed.hasGyro && !interval) {
    warnings.add(const ImportWarning('Gyro columns present but all empty'));
  }

  final ppgPacked = interval ? null : _collectPpg(parsed);
  if (ppgPacked != null) {
    events.addAll(
      encodePpgPackets(
        samplesByChannel: ppgPacked.samples,
        timestampsMs: ppgPacked.timestampsMs,
      ),
    );
    enabled.add(RecordingStream.ppg);
  } else if (parsed.hasPpg && !interval) {
    warnings.add(const ImportWarning('PPG columns present but all empty'));
  }

  final rawBody = assembleRawBody(events);

  // Elements → locked annotations (doubles only).
  final annotations = <SessionAnnotation>[];
  if (parsed.hasElements) {
    final marks = <ElementMark>[];
    for (var i = 0; i < parsed.elements.length; i++) {
      final raw = parsed.elements[i];
      if (raw.isEmpty) continue;
      final onset = parsed.timestamps[i]
              .difference(parsed.timestamps.first)
              .inMicroseconds /
          1e6;
      marks.add(ElementMark(onsetSeconds: onset, raw: raw));
    }
    final mapped = mapElementsToAnnotations(marks);
    annotations.addAll(mapped.annotations);
    warnings.addAll(mapped.warnings);
  }

  // Computed 1 Hz from bands (linear power for charts).
  final computed = rebuildComputedFromBands(
    bandRows: bandRows,
    channelCount: channelLabels.length,
    treatAsBels: bandsFromFft ? false : null,
  );
  final stats = assembleBaseStats(
    frames: computed,
    annotations: annotations,
    channelLabels: channelLabels,
  );

  final sensors = <String>[
    if (rawPresent) 'EEG',
    if (enabled.contains(RecordingStream.ppg)) 'PPG',
    if (enabled.contains(RecordingStream.imu)) 'IMU',
  ];
  final device = DeviceInfo(
    name: 'imported',
    id: '',
    firmware: '',
    model: 'imported',
    sensors: sensors,
    channelCount: channelLabels.length,
    channelLabels: List<String>.from(channelLabels),
    conditioning: conditioning,
  );
  final streams = RecordingMetadata.streamsConfig(enabled);
  final provenance = ImportProvenance(
    sourceFormat: 'mind_monitor_csv',
    sourceFileName: sourceFileName,
    originalChannels: parsed.sourceChannels,
    originalRateHz: rawRateHz,
    droppedChannels: dropped,
    resampled: resampled,
    rawPresent: rawPresent,
    recordingInterval: recordingInterval,
    intervalCoverage: recordingInterval == null
        ? null
        : (csvIntervalCoverage(recordingInterval) * 1000).round() / 1000,
    reference: kMuseElectrodeNames.contains(channelLabels.first) ? 'FPz' : null,
    lossy: (interval && hasAnyRaw) || resampled || dropped.isNotEmpty,
    warnings: [for (final w in warnings) w.message],
  );
  final meta = RecordingMetadata(
    formatVersion: kFormatVersionV6,
    appVersion: appVersion,
    kind: 'recording',
    savedAt: savedAt,
    startedAt: startedAt,
    elapsedSeconds: durationS,
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

/// Median gap between consecutive band rows; null with fewer than two rows.
double? _medianGapSeconds(List<BandInstant> rows) {
  if (rows.length < 2) return null;
  final gaps = [
    for (var i = 1; i < rows.length; i++)
      (rows[i].timestampMs - rows[i - 1].timestampMs) / 1000.0,
  ]..sort();
  return gaps[gaps.length ~/ 2];
}

String _seconds(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}

/// One band row per CSV row that has all five bands for a head channel.
/// [dedupe] skips values repeated from the previous row (Constant files
/// may repeat the latest ~10 Hz band value on sample rows).
List<BandInstant> _bandRowsAt(
  ParsedMindMonitorCsv parsed, {
  required bool dedupe,
}) {
  final rows = <BandInstant>[];
  final last = <int, List<double>>{};
  final t0 = parsed.timestamps.first;
  for (var i = 0; i < parsed.timestamps.length; i++) {
    final byEl = <int, BandValues>{};
    for (var e = 0; e < parsed.channelLabels.length; e++) {
      final ch = parsed.channelLabels[e];
      final v = [
        for (final b in _bandNames) parsed.bandsByChannel[b]![ch]![i],
      ];
      if (v.any((x) => x == null)) continue;
      final values = v.cast<double>();
      final prev = last[e];
      if (dedupe && prev != null && _sameValues(prev, values)) continue;
      last[e] = values;
      byEl[e] = BandValues(
        delta: values[0],
        theta: values[1],
        alpha: values[2],
        beta: values[3],
        gamma: values[4],
      );
    }
    if (byEl.isNotEmpty) {
      rows.add(
        BandInstant(
          timestampMs:
              parsed.timestamps[i].difference(t0).inMicroseconds / 1000.0,
          byElectrode: byEl,
        ),
      );
    }
  }
  return rows;
}

bool _sameValues(List<double> a, List<double> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Constant-mode RAW/AUX per electrode as one 256 Hz run. The source rate is
/// 220 Hz (MU-01) or 256 Hz, whichever the sample spacing is closer to.
({Map<int, List<EegRun>> runs, double rateHz}) _constantRaw(
  ParsedMindMonitorCsv parsed,
) {
  final t0 = parsed.timestamps.first;
  final runs = <int, List<EegRun>>{};
  double? rateHz;
  for (var e = 0; e < parsed.channelLabels.length; e++) {
    final col = parsed.rawByChannel[parsed.channelLabels[e]]!;
    final samples = <double>[];
    int? first;
    var lastIdx = 0;
    for (var i = 0; i < col.length; i++) {
      final v = col[i];
      if (v == null) continue;
      first ??= i;
      lastIdx = i;
      samples.add(v);
    }
    if (first == null || samples.length < 2) continue;
    final span =
        parsed.timestamps[lastIdx].difference(parsed.timestamps[first])
            .inMicroseconds /
        1e6;
    if (rateHz == null && span > 0) {
      final est = (samples.length - 1) / span;
      rateHz = (est - 220).abs() < (est - kNativeEegHz).abs()
          ? 220.0
          : kNativeEegHz.toDouble();
    }
    runs[e] = [
      EegRun(
        parsed.timestamps[first].difference(t0).inMicroseconds / 1000.0,
        resampleToNative(samples, rateHz ?? kNativeEegHz.toDouble()),
      ),
    ];
  }
  return (runs: runs, rateHz: rateHz ?? kNativeEegHz.toDouble());
}

List<ImuSample> _collectImu(
  List<DateTime> timestamps,
  List<double?> x,
  List<double?> y,
  List<double?> z,
) {
  final out = <ImuSample>[];
  final t0 = timestamps.first;
  for (var i = 0; i < timestamps.length; i++) {
    final xv = x[i];
    final yv = y[i];
    final zv = z[i];
    if (xv == null && yv == null && zv == null) continue;
    out.add(
      ImuSample(
        timestampMs:
            timestamps[i].difference(t0).inMicroseconds / 1000.0,
        x: xv ?? 0,
        y: yv ?? 0,
        z: zv ?? 0,
      ),
    );
  }
  return out;
}

({Map<int, List<double>> samples, List<double> timestampsMs})? _collectPpg(
  ParsedMindMonitorCsv parsed,
) {
  if (parsed.ppgByChannel.isEmpty) return null;
  final t0 = parsed.timestamps.first;
  final aligned = <int, List<double>>{};
  final alignedTs = <double>[];
  for (var i = 0; i < parsed.timestamps.length; i++) {
    final present = <MapEntry<int, double>>[];
    for (final e in parsed.ppgByChannel.entries) {
      final v = e.value[i];
      if (v != null) present.add(MapEntry(e.key, v));
    }
    if (present.isEmpty) continue;
    alignedTs.add(
      parsed.timestamps[i].difference(t0).inMicroseconds / 1000.0,
    );
    for (final e in present) {
      aligned.putIfAbsent(e.key, () => []).add(e.value);
    }
  }
  if (aligned.isEmpty) return null;
  return (samples: aligned, timestampsMs: alignedTs);
}

List<String> _splitCsvLine(String line) {
  return line.split(',');
}

DateTime? _parseTimeStamp(String raw) {
  final s = raw.trim();
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
  ).firstMatch(s);
  if (m == null) return DateTime.tryParse(s);
  final ms = int.tryParse((m[7] ?? '0').padRight(3, '0')) ?? 0;
  return DateTime(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
    ms,
  );
}

double? _cellDouble(List<String> cells, int? index) {
  if (index == null || index >= cells.length) return null;
  final s = cells[index].trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}
