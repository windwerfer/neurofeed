import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class BandsRecord {
  const BandsRecord({
    required this.timestamp,
    required this.electrode,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
  });

  final double timestamp;
  final int electrode;
  final double delta;
  final double theta;
  final double alpha;
  final double beta;
  final double gamma;
}

class PulseRecord {
  const PulseRecord({
    required this.timestamp,
    required this.bpm,
    required this.confidence,
  });

  final double timestamp;
  final double bpm;
  final double confidence;
}

class MovementRecord {
  const MovementRecord({required this.timestamp, required this.score});

  final double timestamp;
  final double score;
}

class PeakAlphaRecord {
  const PeakAlphaRecord({
    required this.timestamp,
    required this.frequency,
    required this.power,
  });

  final double timestamp;
  final double frequency;
  final double power;
}

class SessionData {
  final List<BandsRecord> bands = [];
  final List<PulseRecord> pulses = [];
  final List<MovementRecord> movements = [];
  final List<PeakAlphaRecord> peakAlphas = [];
  int eegSamples = 0;
}

class SessionReader {
  static const _magic = 0x4D55534542494E0A; // "MUSEBIN\n"

  static Future<SessionData> read(File file) =>
      readBytes(file.readAsBytes(), label: file.path);

  static Future<SessionData> readBytes(
    Future<List<int>?> future, {
    String label = '<memory>',
  }) async {
    final bytes = await future;
    if (bytes == null) {
      throw const FormatException('No session bytes available');
    }
    return readRaw(bytes, label: label);
  }

  static Future<SessionData> readRaw(
    List<int> raw, {
    String label = '<memory>',
  }) async {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final data = ByteData.sublistView(bytes);
    var off = 0;

    if (bytes.length < 12) {
      throw const FormatException('Truncated .muse header');
    }
    final magic = data.getUint64(off, Endian.little);
    off += 8;
    if (magic != _magic) {
      throw const FormatException('Not a .muse file');
    }
    final version = data.getUint32(off, Endian.little);
    off += 4;
    if (version < 2 || version > 3) {
      throw FormatException('Unsupported format version $version');
    }

    final session = SessionData();
    while (off + 4 <= bytes.length) {
      final frameSize = data.getUint32(off, Endian.little);
      off += 4;
      if (off + frameSize > bytes.length) {
        break;
      }
      final frame = bytes.sublist(off, off + frameSize);
      off += frameSize;
      final decoded = await decompressBlock(data: frame);
      if (decoded.isEmpty) {
        continue;
      }
      _parseRecords(ByteData.sublistView(decoded), session);
    }
    debugPrint(
        '[reader] $label: ${bytes.length}B bands=${session.bands.length} '
        'pulses=${session.pulses.length} mov=${session.movements.length} '
        'peak=${session.peakAlphas.length}');
    return session;
  }

  static void _parseRecords(ByteData d, SessionData session) {
    var off = 0;
    while (off < d.lengthInBytes) {
      final tag = d.getUint8(off);
      off += 1;
      switch (tag) {
        case 1:
          off = _skipEeg(d, off, session);
        case 2:
          off += 8 + 4 + 4 + 2;
        case 3 || 4:
          off = _skipImu(d, off);
        case 5:
          off = _skipPpg(d, off);
        case 6:
          off = _parseBands(d, off, session);
        case 7:
          final ts = d.getFloat64(off, Endian.little);
          off += 8;
          final bpm = d.getFloat32(off, Endian.little);
          off += 4;
          final confidence = d.getFloat32(off, Endian.little);
          off += 4;
          session.pulses.add(
            PulseRecord(timestamp: ts, bpm: bpm, confidence: confidence),
          );
        case 8:
          final ts = d.getFloat64(off, Endian.little);
          off += 8;
          final score = d.getFloat64(off, Endian.little);
          off += 8;
          session.movements.add(MovementRecord(timestamp: ts, score: score));
        case 9:
          final ts = d.getFloat64(off, Endian.little);
          off += 8;
          final frequency = d.getFloat64(off, Endian.little);
          off += 8;
          final power = d.getFloat64(off, Endian.little);
          off += 8;
          session.peakAlphas.add(
            PeakAlphaRecord(timestamp: ts, frequency: frequency, power: power),
          );
        default:
          return;
      }
    }
  }

  static int _skipEeg(ByteData d, int off, SessionData session) {
    off += 8 + 2;
    final count = d.getUint16(off, Endian.little);
    off += 2;
    session.eegSamples += count;
    return off + count * 8;
  }

  static int _skipImu(ByteData d, int off) {
    off += 8 + 2;
    final count = d.getUint16(off, Endian.little);
    off += 2;
    return off + count * 24;
  }

  static int _skipPpg(ByteData d, int off) {
    off += 8 + 2;
    final count = d.getUint16(off, Endian.little);
    off += 2;
    return off + count * 8;
  }

  static int _parseBands(ByteData d, int off, SessionData session) {
    final ts = d.getFloat64(off, Endian.little);
    off += 8;
    final electrode = d.getInt16(off, Endian.little);
    off += 2;
    final delta = d.getFloat64(off, Endian.little);
    off += 8;
    final theta = d.getFloat64(off, Endian.little);
    off += 8;
    final alpha = d.getFloat64(off, Endian.little);
    off += 8;
    final beta = d.getFloat64(off, Endian.little);
    off += 8;
    final gamma = d.getFloat64(off, Endian.little);
    off += 8;
    session.bands.add(
      BandsRecord(
        timestamp: ts,
        electrode: electrode,
        delta: delta,
        theta: theta,
        alpha: alpha,
        beta: beta,
        gamma: gamma,
      ),
    );
    return off;
  }
}
