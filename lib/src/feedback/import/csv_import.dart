import 'dart:math' as math;

import 'package:neurofeed/src/feedback/import/computed_rebuild.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/session_format/stats_assemble.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

const _defaultChannels = ['TP9', 'AF7', 'AF8', 'TP10'];
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
  'Optics1': 0,
  'Optics2': 1,
  'Optics3': 2,
  'Optics4': 3,
};

enum CsvRecordingRate {
  /// ~1 row / second (Mind Monitor default / neurofeed CSV export).
  oneHz,

  /// Device-rate rows (RAW ~256 Hz); empty cells common.
  constant,
}

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

  final channelLabels = <String>[];
  for (final ch in _defaultChannels) {
    final hasRaw = col.containsKey('RAW_$ch');
    final hasBand = _bandNames.any((b) => col.containsKey('${b}_$ch'));
    if (hasRaw || hasBand) channelLabels.add(ch);
  }
  for (final h in headers) {
    if (h.startsWith('RAW_')) {
      final ch = h.substring(4);
      if (!channelLabels.contains(ch)) channelLabels.add(ch);
    }
  }
  if (channelLabels.isEmpty) {
    throw FormatException('CSV has no RAW_* or band columns');
  }

  final ppgCols = <String, int>{};
  for (final h in headers) {
    if (_ppgNameToChannel.containsKey(h) ||
        h.startsWith('PPG_') ||
        h.startsWith('Optics')) {
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
      rawByChannel[ch]!.add(_cellDouble(cells, col['RAW_$ch']));
      for (final b in _bandNames) {
        bandsByChannel[b]![ch]!.add(_cellDouble(cells, col['${b}_$ch']));
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
  final rate =
      medianDt >= 0.5 ? CsvRecordingRate.oneHz : CsvRecordingRate.constant;

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
ImportResult importCsvText({
  required String csvText,
  required SubjectInfo subject,
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
  if (!hasAnyBand) {
    warnings.add(const ImportWarning('no band columns — raw only'));
  }

  final bandRows = <BandInstant>[];
  final events = <int>[];
  if (parsed.rate == CsvRecordingRate.oneHz) {
    final packed = _encodeOneHz(parsed, bandRows);
    events.addAll(packed);
  } else {
    final packed = _encodeConstant(parsed, warnings, bandRows);
    events.addAll(packed);
  }

  // ACC / Gyro / PPG → raw streams.
  final accSamples = _collectImu(
    parsed.timestamps,
    parsed.accX,
    parsed.accY,
    parsed.accZ,
  );
  final gyroSamples = _collectImu(
    parsed.timestamps,
    parsed.gyroX,
    parsed.gyroY,
    parsed.gyroZ,
  );
  if (accSamples.isNotEmpty) {
    events.addAll(encodeAccelerometerEvents(accSamples));
    enabled.add(RecordingStream.imu);
  } else if (parsed.hasAcc) {
    warnings.add(
      const ImportWarning('Accelerometer columns present but all empty'),
    );
  }
  if (gyroSamples.isNotEmpty) {
    events.addAll(encodeGyroscopeEvents(gyroSamples));
    enabled.add(RecordingStream.imu);
  } else if (parsed.hasGyro) {
    warnings.add(const ImportWarning('Gyro columns present but all empty'));
  }

  final ppgPacked = _collectPpg(parsed);
  if (ppgPacked != null) {
    events.addAll(
      encodePpgPackets(
        samplesByChannel: ppgPacked.samples,
        timestampsMs: ppgPacked.timestampsMs,
      ),
    );
    enabled.add(RecordingStream.ppg);
  } else if (parsed.hasPpg) {
    warnings.add(const ImportWarning('PPG/Optics columns present but all empty'));
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
    channelCount: parsed.channelLabels.length,
  );
  final stats = assembleBaseStats(
    frames: computed,
    annotations: annotations,
    channelLabels: parsed.channelLabels,
  );

  final sensors = <String>[
    if (hasAnyRaw) 'EEG',
    if (enabled.contains(RecordingStream.ppg)) 'PPG',
    if (enabled.contains(RecordingStream.imu)) 'IMU',
  ];
  final device = DeviceInfo(
    name: 'imported',
    id: '',
    firmware: '',
    model: 'imported',
    sensors: sensors,
    channelCount: parsed.channelLabels.length,
    channelLabels: List<String>.from(parsed.channelLabels),
  );
  final streams = RecordingMetadata.streamsConfig(enabled);
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
    warnings: warnings,
  );
}

List<int> _encodeOneHz(
  ParsedMindMonitorCsv parsed,
  List<BandInstant> bandRowsOut,
) {
  final samplesByElectrode = <int, List<double>>{};
  for (var e = 0; e < parsed.channelLabels.length; e++) {
    samplesByElectrode[e] = [];
  }
  for (var i = 0; i < parsed.timestamps.length; i++) {
    final tMs = parsed.timestamps[i]
            .difference(parsed.timestamps.first)
            .inMicroseconds /
        1000.0;
    final byEl = <int, BandValues>{};
    for (var e = 0; e < parsed.channelLabels.length; e++) {
      final ch = parsed.channelLabels[e];
      final d = parsed.bandsByChannel['Delta']![ch]![i];
      final th = parsed.bandsByChannel['Theta']![ch]![i];
      final a = parsed.bandsByChannel['Alpha']![ch]![i];
      final b = parsed.bandsByChannel['Beta']![ch]![i];
      final g = parsed.bandsByChannel['Gamma']![ch]![i];
      if (d != null && th != null && a != null && b != null && g != null) {
        byEl[e] = BandValues(
          delta: d,
          theta: th,
          alpha: a,
          beta: b,
          gamma: g,
        );
      }
      final raw = parsed.rawByChannel[ch]![i];
      final prev = samplesByElectrode[e]!;
      if (raw != null) {
        prev.add(raw);
      } else if (prev.isNotEmpty) {
        prev.add(prev.last);
      } else {
        prev.add(0.0);
      }
    }
    if (byEl.isNotEmpty) {
      bandRowsOut.add(BandInstant(timestampMs: tMs, byElectrode: byEl));
    }
  }
  samplesByElectrode.removeWhere((e, samples) {
    final ch = parsed.channelLabels[e];
    return !parsed.rawByChannel[ch]!.any((v) => v != null);
  });
  return [
    ...encodeBandEvents(bandRowsOut),
    ...encodeEegPackets(
      samplesByElectrode: samplesByElectrode,
      sampleRateHz: 1.0,
      packetSamples: 1,
    ),
  ];
}

List<int> _encodeConstant(
  ParsedMindMonitorCsv parsed,
  List<ImportWarning> warnings,
  List<BandInstant> bandRowsOut,
) {
  final dt = parsed.medianDeltaSeconds;
  final rateHz = dt > 0 && dt < 0.05 ? (1.0 / dt) : 256.0;

  final samplesByElectrode = <int, List<double>>{};
  for (var e = 0; e < parsed.channelLabels.length; e++) {
    final ch = parsed.channelLabels[e];
    final col = parsed.rawByChannel[ch]!;
    final samples = <double>[];
    for (final v in col) {
      if (v != null) samples.add(v);
    }
    if (samples.isNotEmpty) {
      samplesByElectrode[e] = samples;
    }
  }

  final bandBySec = <int, Map<int, BandValues>>{};
  for (var i = 0; i < parsed.timestamps.length; i++) {
    final sec = parsed.timestamps[i]
            .difference(parsed.timestamps.first)
            .inMilliseconds ~/
        1000;
    for (var e = 0; e < parsed.channelLabels.length; e++) {
      final ch = parsed.channelLabels[e];
      final d = parsed.bandsByChannel['Delta']![ch]![i];
      final th = parsed.bandsByChannel['Theta']![ch]![i];
      final a = parsed.bandsByChannel['Alpha']![ch]![i];
      final b = parsed.bandsByChannel['Beta']![ch]![i];
      final g = parsed.bandsByChannel['Gamma']![ch]![i];
      if (d == null || th == null || a == null || b == null || g == null) {
        continue;
      }
      bandBySec.putIfAbsent(sec, () => {})[e] = BandValues(
        delta: d,
        theta: th,
        alpha: a,
        beta: b,
        gamma: g,
      );
    }
  }
  for (final sec in (bandBySec.keys.toList()..sort())) {
    bandRowsOut.add(
      BandInstant(
        timestampMs: sec * 1000.0,
        byElectrode: bandBySec[sec]!,
      ),
    );
  }

  if (samplesByElectrode.isEmpty) {
    warnings.add(
      const ImportWarning(
        'Constant-rate CSV had no RAW samples — bands only',
      ),
    );
  }

  return [
    ...encodeBandEvents(bandRowsOut),
    ...encodeEegPackets(
      samplesByElectrode: samplesByElectrode,
      sampleRateHz: rateHz,
    ),
  ];
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
