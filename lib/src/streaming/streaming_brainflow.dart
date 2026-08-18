import 'dart:io';
import 'dart:typed_data';

import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// Streams the EEG group in BrainFlow's "streaming_board" wire format
/// (see `multicast_streamer.cpp` / `streaming_board.cpp` upstream): raw
/// little-endian IEEE-754 doubles, no header, one datagram per batch.
///
/// Row layout is the Muse 2 / Muse S **default preset**
/// (`brainflow_boards.cpp` board 38/39): `num_rows = 8` →
/// `[package_num, TP9, AF7, AF8, TP10, other, timestamp(UNIX seconds),
/// marker]`. A PC receives it with `BoardShim(STREAMING_BOARD)` and
/// `master_board = MUSE_2_BOARD` (or `MUSE_S_BOARD`); the receiver drops
/// datagrams that are not exactly `batch_size * num_rows` doubles, so the
/// batch must match BrainFlow's default (`BRAINFLOW_BATCH_SIZE` = 3).
class BrainflowStreamer implements StreamSender {
  BrainflowStreamer(this.config);

  final StreamingConfig config;

  static const int numRows = 8;
  static const int batchSize = 3;

  /// EEG channels land in rows 1..4 (TP9, AF7, AF8, TP10).
  static const int _eegRow0 = 1;

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  final List<List<double>> _pending = [];
  int _packageNum = 0;

  @override
  int packetsSent = 0;

  @override
  int bytesSent = 0;

  Future<void> start() async {
    final ip = config.brainflowIp;
    final port = config.brainflowPort;
    if (ip == null || port == null) {
      throw StateError('brainflow ip/port not configured');
    }
    final address = InternetAddress.tryParse(ip);
    if (address == null) {
      throw ArgumentError('invalid BrainFlow multicast address: $ip');
    }
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _address = address;
  }

  @override
  void push(GroupSample sample) {
    final socket = _socket;
    final address = _address;
    final port = config.brainflowPort;
    if (socket == null || address == null || port == null) return;
    if (sample.groupId != 'eeg') return;

    final eeg = <double>[0, 0, 0, 0];
    for (var i = 0; i < 4 && i < sample.values.length; i++) {
      eeg[i] = sample.values[i];
    }
    final row = List<double>.filled(numRows, 0.0);
    row[0] = _packageNum.toDouble();
    for (var i = 0; i < 4; i++) {
      row[_eegRow0 + i] = eeg[i];
    }
    row[6] = sample.timestamp / 1000.0; // ms epoch → UNIX seconds
    _packageNum++;
    _pending.add(row);

    if (_pending.length < batchSize) return;

    final bytes = ByteData(batchSize * numRows * 8);
    var offset = 0;
    for (final r in _pending) {
      for (final v in r) {
        bytes.setFloat64(offset, v, Endian.little);
        offset += 8;
      }
    }
    _pending.clear();
    socket.send(bytes.buffer.asUint8List(), address, port);
    packetsSent++;
    bytesSent += bytes.lengthInBytes;
  }

  @override
  Future<void> stop() async {
    _pending.clear();
    _socket?.close();
    _socket = null;
    _address = null;
  }
}