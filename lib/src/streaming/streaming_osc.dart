import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// Encodes an OSC 1.0 message: address + type tag + 4-byte aligned args.
/// All arguments are float32 (our sample data is f32 on the wire).
Uint8List oscEncodeMessage(String address, List<double> args) {
  final buf = BytesBuilder(copy: false);
  _writeOscString(buf, address);
  _writeOscString(buf, ',${'f' * args.length}');
  final bytes = Float32List.fromList(args).buffer.asUint8List();
  buf.add(bytes);
  return buf.toBytes();
}

void _writeOscString(BytesBuilder buf, String value) {
  final codeUnits = value.codeUnits;
  buf.add(codeUnits);
  final padding = 4 - (codeUnits.length % 4);
  if (padding < 4) {
    buf.add(List.filled(padding, 0));
  }
}

/// Streams sensor groups as OSC messages over unicast UDP.
///
/// Each message carries one chunk of a single group: `[ts, v00..v0c-1,
/// v10..v1c-1, …]` where `ts` is the device timestamp (seconds) of the first
/// sample and `c` the group's channel count. EEG chunks are 12 samples
/// (one BLE packet), PPG 6, IMU 3, Bands 1 — matching the packet sizes the
/// events arrive in.
class OscStreamer implements StreamSender {
  OscStreamer(this.config);

  final StreamingConfig config;

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  final Map<String, List<double>> _pending = {};
  final Map<String, int> _chunkOf = {
    'eeg': 12,
    'ppg': 6,
    'imu': 3,
    'bands': 1,
  };
  double _chunkStartTs = 0;

  @override
  int packetsSent = 0;

  @override
  int bytesSent = 0;

  Future<void> start() async {
    final ip = config.oscIp;
    final port = config.oscPort;
    if (ip == null || port == null || port <= 0 || port > 65535) {
      throw ArgumentError('Invalid OSC destination $ip:$port');
    }
    _address = InternetAddress.tryParse(ip);
    if (_address == null) {
      throw ArgumentError('Invalid OSC destination IP: $ip');
    }
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  @override
  void push(GroupSample sample) {
    final socket = _socket;
    if (socket == null) return;
    final pending = _pending.putIfAbsent(sample.groupId, () => <double>[]);
    if (pending.isEmpty) {
      _chunkStartTs = sample.timestamp;
    }
    pending.addAll(sample.values);
    final chunk = _chunkOf[sample.groupId] ?? 1;
    if (pending.length < chunk * _groupChannelCount(sample.groupId)) return;
    final address = _messageAddress(sample.groupId);
    final args = [_chunkStartTs, ...pending];
    final bytes = oscEncodeMessage(address, args);
    socket.send(bytes, _address!, config.oscPort!);
    packetsSent++;
    bytesSent += bytes.length;
    pending.clear();
  }

  int _groupChannelCount(String groupId) =>
      StreamGroups.byId(groupId).channelCount;

  String _messageAddress(String groupId) {
    final prefix = config.prefix.endsWith('/')
        ? config.prefix.substring(0, config.prefix.length - 1)
        : config.prefix;
    return '$prefix/$groupId';
  }

  @override
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _address = null;
    _pending.clear();
  }
}