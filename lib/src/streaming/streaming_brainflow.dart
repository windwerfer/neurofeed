import 'dart:io';
import 'dart:typed_data';

import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// Streams sensor groups in BrainFlow's "streaming_board" wire format
/// (see `multicast_streamer.cpp` / `streaming_board.cpp` upstream): raw
/// little-endian IEEE-754 doubles, no header, one datagram per batch.
///
/// Each BrainFlow preset is its own multicast stream on its own port:
/// * `eeg` → **default preset** (Muse 2/S `brainflow_boards.cpp` board
///   38/39, `num_rows = 8`): `[package_num, TP9, AF7, AF8, TP10, other,
///   timestamp(UNIX seconds), marker]` on the configured port;
/// * `imu` → **auxiliary preset** (`num_rows = 9`, 52 Hz): `[package_num,
///   accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z, timestamp, marker]`
///   on port+1 — enabled by `separateGroups`;
/// * `ppg` → **ancillary preset** (`num_rows = 6`, 64 Hz): `[package_num,
///   ambient, infrared, red, timestamp, marker]` on port+2.
///
/// A PC receives all three with `BoardShim(STREAMING_BOARD)` and
/// `master_board = MUSE_2_BOARD` (or `MUSE_S_BOARD`), setting
/// `ip_address/ip_port` (+ `ip_address_aux`/`ip_port_aux`,
/// `ip_address_anc`/`ip_port_anc`). The receiver drops datagrams that are
/// not exactly `batch_size * num_rows` doubles, so the batch must match
/// BrainFlow's default (`BRAINFLOW_BATCH_SIZE` = 3).
class BrainflowStreamer implements StreamSender {
  BrainflowStreamer(this.config);

  final StreamingConfig config;

  static const int batchSize = 3;

  static const int _eegRows = 8;
  static const int _auxRows = 9;
  static const int _ancRows = 6;

  RawDatagramSocket? _socket;
  final Map<String, InternetAddress> _addresses = {};
  final Map<String, int> _ports = {};
  final Map<String, int> _rowCounts = {};
  final Map<String, List<List<double>>> _pending = {};
  final Map<String, int> _packageNums = {};

  @override
  int packetsSent = 0;

  @override
  int bytesSent = 0;

  Future<void> start() async {
    final ip = config.brainflowIp;
    final basePort = config.brainflowPort;
    if (ip == null || basePort == null) {
      throw StateError('brainflow ip/port not configured');
    }
    final address = InternetAddress.tryParse(ip);
    if (address == null) {
      throw ArgumentError('invalid BrainFlow multicast address: $ip');
    }

    _addresses['eeg'] = address;
    _ports['eeg'] = basePort;
    _rowCounts['eeg'] = _eegRows;
    if (config.separateGroups) {
      _addresses['imu'] = address;
      _ports['imu'] = basePort + 1;
      _rowCounts['imu'] = _auxRows;
      _addresses['ppg'] = address;
      _ports['ppg'] = basePort + 2;
      _rowCounts['ppg'] = _ancRows;
    }
    for (final id in _rowCounts.keys) {
      _pending[id] = [];
      _packageNums[id] = 0;
    }
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  @override
  void push(GroupSample sample) {
    final socket = _socket;
    if (socket == null) return;
    final address = _addresses[sample.groupId];
    final port = _ports[sample.groupId];
    if (address == null || port == null) return;

    final rows = _rowCounts[sample.groupId]!;
    final pending = _pending[sample.groupId]!;
    pending.add(_buildRow(sample, rows));
    if (pending.length < batchSize) return;

    final bytes = ByteData(batchSize * rows * 8);
    var offset = 0;
    for (final r in pending) {
      for (final v in r) {
        bytes.setFloat64(offset, v, Endian.little);
        offset += 8;
      }
    }
    pending.clear();
    socket.send(bytes.buffer.asUint8List(), address, port);
    packetsSent++;
    bytesSent += bytes.lengthInBytes;
  }

  List<double> _buildRow(GroupSample sample, int rows) {
    final row = List<double>.filled(rows, 0.0);
    final packageNum = _packageNums[sample.groupId]!;
    row[0] = packageNum.toDouble();
    _packageNums[sample.groupId] = packageNum + 1;
    final values = sample.values;
    switch (sample.groupId) {
      case 'eeg':
        for (var i = 0; i < 4 && i < values.length; i++) {
          row[1 + i] = values[i];
        }
        row[6] = sample.timestamp / 1000.0;
      case 'imu':
        for (var i = 0; i < 6 && i < values.length; i++) {
          row[1 + i] = values[i];
        }
        row[7] = sample.timestamp / 1000.0;
      case 'ppg':
        for (var i = 0; i < 3 && i < values.length; i++) {
          row[1 + i] = values[i];
        }
        row[4] = sample.timestamp / 1000.0;
      default:
        break;
    }
    return row;
  }

  @override
  Future<void> stop() async {
    _pending.clear();
    _addresses.clear();
    _ports.clear();
    _rowCounts.clear();
    _packageNums.clear();
    _socket?.close();
    _socket = null;
  }
}