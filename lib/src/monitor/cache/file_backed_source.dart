import 'dart:io';
import 'dart:typed_data';

import 'package:muse_ml/src/monitor/cache/recording_index.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';

const double _eegRateHz = 256.0;

SessionData _emptySessionData() => SessionData(
  bands: const [],
  pulses: const [],
  spo2S: const [],
  movements: const [],
  peakAlphas: const [],
  eegSamples: BigInt.zero,
  eeg: const [],
);

/// File-backed Inspect of an in-progress `tmp_` / `recording_` `.raw`.
///
/// Reads complete flush frames, prepends [sessionHeaderBytes], then
/// [sessionParseBody]. Record timestamps are converted to elapsed seconds
/// from [captureStartedAtMs].
class FileBackedSource {
  FileBackedSource({
    required this.file,
    required this.index,
    required this.captureStartedAtMs,
  });

  final File file;
  final RecordingIndex index;
  final int? captureStartedAtMs;

  /// Records whose elapsed `t` overlaps `[startElapsed, endElapsed]`.
  ///
  /// Returns empty data when [captureStartedAtMs] is null — never treats
  /// that as unix epoch.
  SessionData getRange(double startElapsed, double endElapsed) {
    final started = captureStartedAtMs;
    if (started == null) return _emptySessionData();

    final span = index.covering(startElapsed, endElapsed);
    if (span == null) return _emptySessionData();
    if (!file.existsSync()) return _emptySessionData();

    final raf = file.openSync();
    try {
      final fileLen = raf.lengthSync();
      final end = span.endOffset < fileLen ? span.endOffset : fileLen;
      if (span.startOffset >= end) return _emptySessionData();
      raf.setPositionSync(span.startOffset);
      final frames = raf.readSync(end - span.startOffset);
      final complete = completeFrames(frames);
      if (complete.isEmpty) return _emptySessionData();

      final header = sessionHeaderBytes();
      final body = Uint8List(header.length + complete.length);
      body.setAll(0, header);
      body.setAll(header.length, complete);
      final parsed = sessionParseBody(bytes: body);
      return _toElapsed(parsed, started, startElapsed, endElapsed);
    } finally {
      raf.closeSync();
    }
  }
}

/// Keep only complete `[u32 LE length][payload]` frames; drop a truncated tail.
Uint8List completeFrames(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (data.length < 4) return Uint8List(0);
  final view = ByteData.sublistView(data);
  var offset = 0;
  var lastComplete = 0;
  while (offset + 4 <= data.length) {
    final frameLen = view.getUint32(offset, Endian.little);
    final frameEnd = offset + 4 + frameLen;
    if (frameEnd > data.length) break;
    lastComplete = frameEnd;
    offset = frameEnd;
  }
  if (lastComplete == 0) return Uint8List(0);
  if (lastComplete == data.length) return data;
  return Uint8List.sublistView(data, 0, lastComplete);
}

SessionData _toElapsed(
  SessionData data,
  int captureStartedAtMs,
  double startElapsed,
  double endElapsed,
) {
  double conv(double tsMs) => (tsMs - captureStartedAtMs) / 1000.0;
  bool inWindow(double t) => t >= startElapsed && t <= endElapsed;

  final eeg = <EegSampleRecord>[];
  var sampleCount = 0;
  for (final rec in data.eeg) {
    final t0 = conv(rec.timestamp);
    final span = rec.samples.isEmpty
        ? 0.0
        : (rec.samples.length - 1) / _eegRateHz;
    final t1 = t0 + span;
    if (t0 <= endElapsed && t1 >= startElapsed) {
      eeg.add(rec.copyWith(timestamp: t0));
      sampleCount += rec.samples.length;
    }
  }

  return SessionData(
    bands: [
      for (final b in data.bands)
        if (inWindow(conv(b.timestamp)))
          b.copyWith(timestamp: conv(b.timestamp)),
    ],
    pulses: [
      for (final p in data.pulses)
        if (inWindow(conv(p.timestamp)))
          p.copyWith(timestamp: conv(p.timestamp)),
    ],
    spo2S: [
      for (final s in data.spo2S)
        if (inWindow(conv(s.timestamp)))
          s.copyWith(timestamp: conv(s.timestamp)),
    ],
    movements: [
      for (final m in data.movements)
        if (inWindow(conv(m.timestamp)))
          m.copyWith(timestamp: conv(m.timestamp)),
    ],
    peakAlphas: [
      for (final p in data.peakAlphas)
        if (inWindow(conv(p.timestamp)))
          p.copyWith(timestamp: conv(p.timestamp)),
    ],
    eegSamples: BigInt.from(sampleCount),
    eeg: eeg,
  );
}
