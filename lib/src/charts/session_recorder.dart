import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class SessionRecorder {
  static const _magic = 0x4D55534542494E0A; // "MUSEBIN\n"
  static const _version = 3;
  static const _flushInterval = Duration(seconds: 30);
  static const _maxPendingBytes = 65536;

  File? _file;
  Timer? _flushTimer;
  final _pending = BytesBuilder();
  int _events = 0;

  bool get isRecording => _file != null;

  String? get currentFilePath => _file?.path;

  Future<void> start([Directory? dir]) async {
    if (_file != null) return;
    final d = dir ?? Directory.systemTemp;
    final sep = d.path.endsWith('/') ? '' : '/';
    final path = '${d.path}${sep}live_${DateTime.now().millisecondsSinceEpoch}.muse';
    _file = File(path);
    _events = 0;
    debugPrint('[session] recorder start: $path');

    final header = ByteData(12);
    header.setUint64(0, _magic, Endian.little);
    header.setUint32(8, _version, Endian.little);
    await _file!.writeAsBytes(header.buffer.asUint8List(),
        mode: FileMode.writeOnlyAppend);

    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  void writeEvent(MuseEventDto event) {
    _events++;
    Uint8List? encoded;
    switch (event) {
      case MuseEventDto_Eeg(:final field0):
        encoded = _encodeEeg(field0);
      case MuseEventDto_Telemetry(:final field0):
        encoded = _encodeTelemetry(field0);
      case MuseEventDto_Accelerometer(:final field0):
        encoded = _encodeImu(3, field0);
      case MuseEventDto_Gyroscope(:final field0):
        encoded = _encodeImu(4, field0);
      case MuseEventDto_Ppg(:final field0):
        encoded = _encodePpg(field0);
      case MuseEventDto_Bands(:final field0):
        encoded = _encodeBands(field0);
      case MuseEventDto_Pulse(:final field0):
        encoded = _encodePulse(field0);
      case MuseEventDto_Movement(:final field0):
        encoded = _encodeMovement(field0);
      case MuseEventDto_PeakAlpha(:final field0):
        encoded = _encodePeakAlpha(field0);
      default:
        return;
    }
    _pending.add(encoded);
    if (_pending.length > _maxPendingBytes) _flush();
  }

  Uint8List _encodeEeg(EegDto d) {
    final n = d.samples.length;
    final buf = ByteData(1 + 8 + 2 + 2 + n * 8);
    var off = 0;
    buf.setUint8(off, 1); off += 1;
    buf.setFloat64(off, d.timestamp, Endian.little); off += 8;
    buf.setInt16(off, d.electrode, Endian.little); off += 2;
    buf.setUint16(off, n, Endian.little); off += 2;
    for (final s in d.samples) {
      buf.setFloat64(off, s, Endian.little);
      off += 8;
    }
    return buf.buffer.asUint8List();
  }

  Uint8List _encodeTelemetry(TelemetrySnapshot t) {
    final buf = ByteData(1 + 8 + 4 + 4 + 2);
    var off = 0;
    buf.setUint8(off, 2); off += 1;
    final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;
    buf.setFloat64(off, ts, Endian.little); off += 8;
    buf.setFloat32(off, t.batteryLevel, Endian.little); off += 4;
    buf.setFloat32(off, t.fuelGaugeVoltage, Endian.little); off += 4;
    buf.setUint16(off, t.temperature, Endian.little);
    return buf.buffer.asUint8List();
  }

  Uint8List _encodeImu(int type, ImuDto imu) {
    final n = imu.samples.length;
    final buf = ByteData(1 + 8 + 2 + 2 + n * 24);
    var off = 0;
    buf.setUint8(off, type); off += 1;
    final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;
    buf.setFloat64(off, ts, Endian.little); off += 8;
    buf.setUint16(off, imu.sequenceId, Endian.little); off += 2;
    buf.setUint16(off, n, Endian.little); off += 2;
    for (final s in imu.samples) {
      buf.setFloat64(off, s.x, Endian.little); off += 8;
      buf.setFloat64(off, s.y, Endian.little); off += 8;
      buf.setFloat64(off, s.z, Endian.little); off += 8;
    }
    return buf.buffer.asUint8List();
  }

  Uint8List _encodePpg(PpgDto d) {
    final n = d.samples.length;
    final buf = ByteData(1 + 8 + 2 + 2 + n * 8);
    var off = 0;
    buf.setUint8(off, 5); off += 1;
    buf.setFloat64(off, d.timestamp, Endian.little); off += 8;
    buf.setInt16(off, d.channel, Endian.little); off += 2;
    buf.setUint16(off, n, Endian.little); off += 2;
    for (final s in d.samples) {
      buf.setFloat64(off, s, Endian.little);
      off += 8;
    }
    return buf.buffer.asUint8List();
  }

  Uint8List _encodeBands(BandsDto d) {
    // Type tag 6: timestamp(f64), electrode(i16), delta/theta/alpha/beta/gamma(f64×5)
    final buf = ByteData(1 + 8 + 2 + 5 * 8);
    var off = 0;
    buf.setUint8(off, 6); off += 1;
    buf.setFloat64(off, d.timestamp, Endian.little); off += 8;
    buf.setInt16(off, d.electrode, Endian.little); off += 2;
    buf.setFloat64(off, d.delta, Endian.little); off += 8;
    buf.setFloat64(off, d.theta, Endian.little); off += 8;
    buf.setFloat64(off, d.alpha, Endian.little); off += 8;
    buf.setFloat64(off, d.beta, Endian.little); off += 8;
    buf.setFloat64(off, d.gamma, Endian.little);
    return buf.buffer.asUint8List();
  }

  Uint8List _encodePulse(PulseDto d) {
    // Type tag 7: timestamp(f64), bpm(f32), confidence(f32)
    final buf = ByteData(1 + 8 + 4 + 4);
    var off = 0;
    buf.setUint8(off, 7); off += 1;
    buf.setFloat64(off, d.timestamp, Endian.little); off += 8;
    buf.setFloat32(off, d.bpm, Endian.little); off += 4;
    buf.setFloat32(off, d.confidence, Endian.little);
    return buf.buffer.asUint8List();
  }

  Uint8List _encodeMovement(MovementDto d) {
    // Type tag 8: timestamp(f64), score(f64)
    final buf = ByteData(1 + 8 + 8);
    var off = 0;
    buf.setUint8(off, 8); off += 1;
    buf.setFloat64(off, d.timestamp, Endian.little); off += 8;
    buf.setFloat64(off, d.score, Endian.little);
    return buf.buffer.asUint8List();
  }

  Uint8List _encodePeakAlpha(PeakAlphaDto d) {
    // Type tag 9: timestamp(f64), frequency(f64), power(f64)
    final buf = ByteData(1 + 8 + 8 + 8);
    var off = 0;
    buf.setUint8(off, 9); off += 1;
    buf.setFloat64(off, d.timestamp, Endian.little); off += 8;
    buf.setFloat64(off, d.frequency, Endian.little); off += 8;
    buf.setFloat64(off, d.power, Endian.little);
    return buf.buffer.asUint8List();
  }

  Future<File?> markSaved() async {
    await _flush();
    if (_file == null) {
      debugPrint('[session] markSaved: no active file, returning null');
      return null;
    }
    final dir = _file!.parent;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final newPath = '${dir.path}session_$ts.muse';
    debugPrint('[session] markSaved: renaming ${_file!.path} -> $newPath');
    try {
      final saved = await _file!.rename(newPath);
      _file = null;
      debugPrint('[session] markSaved: OK -> ${saved.path}');
      return saved;
    } catch (e) {
      debugPrint('[session] markSaved: rename FAILED ($e)');
      rethrow;
    }
  }

  Future<void> stop() async {
    debugPrint('[session] stop(): events=$_events');
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
    if (_file != null) {
      try {
        await _file!.delete();
        debugPrint('[session] stop(): deleted temp file');
      } catch (e) {
        debugPrint('[session] stop(): delete failed ($e)');
      }
      _file = null;
    }
  }

  Future<void> flush() => _flush();

  Future<void> _flush() async {
    if (_pending.isEmpty || _file == null) return;
    final raw = _pending.toBytes();
    _pending.clear();
    try {
      final compressed = await compressBlock(data: raw);
      final size = compressed.length;
      final frame = Uint8List(4 + size);
      frame.buffer.asByteData().setUint32(0, size, Endian.little);
      frame.setRange(4, 4 + size, compressed);
      await _file!.writeAsBytes(frame, mode: FileMode.writeOnlyAppend);
    } catch (e) {
      debugPrint('[session] flush FAILED, re-queueing ($e)');
      _pending.add(raw);
    }
  }
}
