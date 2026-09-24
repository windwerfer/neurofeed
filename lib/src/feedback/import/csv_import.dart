import 'dart:math' as math;
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

const _defaultChannels = ['TP9', 'AF7', 'AF8', 'TP10'];
const _bandNames = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'];

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
  // Also pick up any RAW_* not in the default Muse set.
  for (final h in headers) {
    if (h.startsWith('RAW_')) {
      final ch = h.substring(4);
      if (!channelLabels.contains(ch)) channelLabels.add(ch);
    }
  }
  if (channelLabels.isEmpty) {
    throw FormatException('CSV has no RAW_* or band columns');
  }

  final timestamps = <DateTime>[];
  final rawByChannel = {
    for (final ch in channelLabels) ch: <double?>[],
  };
  final bandsByChannel = {
    for (final b in _bandNames)
      b: {for (final ch in channelLabels) ch: <double?>[]},
  };

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
  // ~1 s → oneHz; much faster → Constant. Mid-range (~0.1 s bands-only) also
  // treated as Constant so RAW packing still works when present.
  final rate = medianDt >= 0.5 ? CsvRecordingRate.oneHz : CsvRecordingRate.constant;

  bool hasPrefix(String p) => headers.any((h) => h.startsWith(p));

  return ParsedMindMonitorCsv(
    headers: headers,
    timestamps: timestamps,
    rate: rate,
    medianDeltaSeconds: medianDt,
    rawByChannel: rawByChannel,
    bandsByChannel: bandsByChannel,
    channelLabels: channelLabels,
    hasAcc: hasPrefix('Accelerometer_'),
    hasGyro: hasPrefix('Gyro_'),
    hasPpg: hasPrefix('PPG_') || hasPrefix('Optics'),
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

  if (parsed.hasAcc || parsed.hasGyro || parsed.hasPpg) {
    warnings.add(
      const ImportWarning(
        'ACC/Gyro/PPG columns present but not yet imported into raw streams',
      ),
    );
  }
  if (parsed.hasElements) {
    warnings.add(
      const ImportWarning(
        'Elements column present — single blink/jaw not mapped (locked types are doubles only)',
      ),
    );
  }

  final startedAt = parsed.timestamps.first;
  final endedAt = parsed.timestamps.last;
  final durationS = math.max(
    1,
    endedAt.difference(startedAt).inMilliseconds / 1000.0,
  ).ceil();
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

  final events = <int>[];
  if (parsed.rate == CsvRecordingRate.oneHz) {
    events.addAll(_encodeOneHz(parsed));
  } else {
    events.addAll(_encodeConstant(parsed, warnings));
  }
  final rawBody = assembleRawBody(events);

  final device = DeviceInfo(
    name: 'imported',
    id: '',
    firmware: '',
    model: 'imported',
    sensors: [
      if (hasAnyRaw) 'EEG',
    ],
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
  );

  final container = assembleContainer(
    thumbnail: const [],
    metadataJson: metadataJson,
    computedFrames: const [],
    rawBody: rawBody,
  );

  return ImportResult(
    id: id,
    containerBytes: container,
    metadataJson: metadataJson,
    warnings: warnings,
  );
}

List<int> _encodeOneHz(ParsedMindMonitorCsv parsed) {
  final bandRows = <BandInstant>[];
  final samplesByElectrode = <int, List<double>>{};
  // Keep row-aligned RAW so encodeEegPackets @ 1 Hz matches wall seconds
  // even when a cell is empty (empty → NaN placeholder, filtered below).
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
      // Hold last sample across empty 1 Hz cells so packet index == second.
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
      bandRows.add(BandInstant(timestampMs: tMs, byElectrode: byEl));
    }
  }
  // Drop electrodes that never had a real RAW value.
  samplesByElectrode.removeWhere((e, samples) {
    final ch = parsed.channelLabels[e];
    return !parsed.rawByChannel[ch]!.any((v) => v != null);
  });
  return [
    ...encodeBandEvents(bandRows),
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
) {
  // Infer EEG rate from median Δt when RAW present; else nominal 256.
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

  // Bands at Constant are sparse (~10 Hz); keep last-of-second as 1 Hz tags.
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
  final bandRows = [
    for (final sec in (bandBySec.keys.toList()..sort()))
      BandInstant(
        timestampMs: sec * 1000.0,
        byElectrode: bandBySec[sec]!,
      ),
  ];

  if (samplesByElectrode.isEmpty) {
    warnings.add(
      const ImportWarning(
        'Constant-rate CSV had no RAW samples — bands only',
      ),
    );
  }

  return [
    ...encodeBandEvents(bandRows),
    ...encodeEegPackets(
      samplesByElectrode: samplesByElectrode,
      sampleRateHz: rateHz,
    ),
  ];
}

List<String> _splitCsvLine(String line) {
  // Mind Monitor / Excel CSV: plain commas, no quoted commas in our dialect.
  return line.split(',');
}

DateTime? _parseTimeStamp(String raw) {
  final s = raw.trim();
  // YYYY-MM-DD HH:MM:SS.mmm (Mind Monitor local wall).
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
