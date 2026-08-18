import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/streaming/streaming_brainflow.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

StreamingConfig _config(int port, {bool separateGroups = false}) =>
    StreamingConfig(
      protocol: StreamProtocol.brainflow,
      enabled: true,
      oscIp: null,
      oscPort: null,
      prefix: '',
      separateGroups: separateGroups,
      brainflowIp: '127.0.0.1',
      brainflowPort: port,
    );

/// Mirrors the PC-side STREAMING_BOARD receiver on a fixed port: collects
/// datagrams until the completer completes (keeps listening past that).
Future<Completer<List<Uint8List>>> _receiverOn(int port) async {
  final socket = await RawDatagramSocket.bind(
    InternetAddress.loopbackIPv4,
    port,
  );
  final received = Completer<List<Uint8List>>();
  final all = <Uint8List>[];
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    while (true) {
      final dg = socket.receive();
      if (dg == null) break;
      all.add(dg.data);
    }
    if (!received.isCompleted && all.isNotEmpty) {
      received.complete(List.of(all));
    }
  });
  return received;
}

List<double> _doubles(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < bytes.length; i += 8)
      bd.getFloat64(i, Endian.little),
  ];
}

void main() {
  test('BrainFlow streamer batches 3 EEG samples into 8-row datagrams', () async {
    final receiver = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(receiver.close);
    final received = Completer<Uint8List>();
    receiver.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = receiver.receive();
        if (dg != null && !received.isCompleted) received.complete(dg.data);
      }
    });

    final streamer = BrainflowStreamer(_config(receiver.port));
    await streamer.start();
    addTearDown(streamer.stop);

    // Two rows: not yet a complete batch of 3 — nothing may be sent.
    for (var i = 0; i < 2; i++) {
      streamer.push(GroupSample('eeg', 1_700_000_000_000.0 + i, [1, 2, 3, 4]));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(streamer.packetsSent, 0);

    // Third row completes one datagram.
    streamer.push(GroupSample('eeg', 1_700_000_000_002.0, [5, 6, 7, 8]));
    expect(streamer.packetsSent, 1);
    final data = await received.future.timeout(const Duration(seconds: 2));

    // batch(3) * numRows(8) little-endian doubles, no header.
    expect(data.length, BrainflowStreamer.batchSize * 8 * 8);
    final pkg0 = _doubles(data).sublist(0, 8);
    final pkg1 = _doubles(data).sublist(8, 16);
    final pkg2 = _doubles(data).sublist(16, 24);

    expect(pkg0[0], 0); // package_num
    expect(pkg0.sublist(1, 5), [1, 2, 3, 4]); // TP9 AF7 AF8 TP10
    expect(pkg0[5], 0); // other row
    expect(pkg0[6], 1_700_000_000.0); // UNIX seconds (ms epoch / 1000)
    expect(pkg0[7], 0); // marker

    expect(pkg1[0], 1);
    expect(pkg1[6], 1_700_000_000.001);
    expect(pkg2[0], 2);
    expect(pkg2.sublist(1, 5), [5, 6, 7, 8]);
    expect(pkg2[6], 1_700_000_000.002);
  });

  test('BrainFlow eeg-only mode ignores imu/ppg and keeps numbering', () async {
    final receiver = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(receiver.close);
    final received = Completer<List<Uint8List>>();
    final all = <Uint8List>[];
    receiver.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = receiver.receive();
        if (dg == null) return;
        all.add(dg.data);
        if (!received.isCompleted && all.length >= 2) {
          received.complete(List.of(all));
        }
      }
    });

    final streamer = BrainflowStreamer(_config(receiver.port));
    await streamer.start();
    addTearDown(streamer.stop);

    // IMU/PPG pushes are ignored when separateGroups is off.
    streamer.push(GroupSample('imu', 1_700_000_000_000.0, [1, 2, 3, 4, 5, 6]));
    streamer.push(GroupSample('ppg', 1_700_000_000_000.0, [1, 2, 3]));
    streamer.push(GroupSample('bands', 1_700_000_000_000.0, [0.1, 0.2]));
    expect(streamer.packetsSent, 0);

    for (var i = 0; i < 6; i++) {
      streamer.push(GroupSample('eeg', 1_700_000_000_000.0 + i, [
        i + 1,
        i + 2,
        i + 3,
        i + 4,
      ]));
    }
    expect(streamer.packetsSent, 2);

    final dgs = await received.future.timeout(const Duration(seconds: 2));
    expect(dgs.length, 2);
    final first = _doubles(dgs[0]);
    final second = _doubles(dgs[1]);
    expect(first[0], 0);
    expect(first[8], 1);
    expect(first[16], 2);
    expect(second[0], 3);
    expect(second[8], 4);
    expect(second[16], 5);
  });

  test('BrainFlow separate-groups mode streams EEG, IMU and PPG presets', () async {
    // Find three consecutive free ports, then bind the receivers on them.
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final base = probe.port;
    probe.close();
    final rEeg = await _receiverOn(base);
    final rImu = await _receiverOn(base + 1);
    final rPpg = await _receiverOn(base + 2);

    final streamer = BrainflowStreamer(_config(base, separateGroups: true));
    await streamer.start();
    addTearDown(streamer.stop);

    for (var i = 0; i < 3; i++) {
      streamer.push(GroupSample('eeg', 1_700_000_000_000.0 + i, [
        i + 1,
        i + 2,
        i + 3,
        i + 4,
      ]));
      streamer.push(GroupSample('imu', 1_700_000_000_000.0 + i, [
        10.0 + i,
        20.0 + i,
        30.0 + i,
        40.0 + i,
        50.0 + i,
        60.0 + i,
      ]));
      streamer.push(GroupSample('ppg', 1_700_000_000_000.0 + i, [
        100.0 + i,
        200.0 + i,
        300.0 + i,
      ]));
    }
    expect(streamer.packetsSent, 3);

    final dgEeg = (await rEeg.future.timeout(const Duration(seconds: 2))).single;
    final dgImu = (await rImu.future.timeout(const Duration(seconds: 2))).single;
    final dgPpg = (await rPpg.future.timeout(const Duration(seconds: 2))).single;

    // EEG: default preset, 3 x 8 rows.
    expect(dgEeg.length, BrainflowStreamer.batchSize * 8 * 8);
    final eeg = _doubles(dgEeg);
    expect(eeg[0], 0);
    expect(eeg.sublist(1, 5), [1, 2, 3, 4]);
    expect(eeg[6], 1_700_000_000.0);
    expect(eeg[7], 0);

    // IMU: auxiliary preset, 3 x 9 rows: accel then gyro, ts in row 7.
    expect(dgImu.length, BrainflowStreamer.batchSize * 9 * 8);
    final imu = _doubles(dgImu);
    expect(imu[0], 0);
    expect(imu.sublist(1, 7), [10, 20, 30, 40, 50, 60]);
    expect(imu[7], 1_700_000_000.0);
    expect(imu[8], 0); // marker
    expect(imu[9], 1); // package 1
    expect(imu.sublist(10, 16), [11, 21, 31, 41, 51, 61]);
    expect(imu[16], 1_700_000_000.001);
    expect(imu[18], 2); // package 2
    expect(imu.sublist(19, 25), [12, 22, 32, 42, 52, 62]);
    expect(imu[25], 1_700_000_000.002);

    // PPG: ancillary preset, 3 x 6 rows: ambient/ir/red, ts in row 4.
    expect(dgPpg.length, BrainflowStreamer.batchSize * 6 * 8);
    final ppg = _doubles(dgPpg);
    expect(ppg[0], 0);
    expect(ppg.sublist(1, 4), [100, 200, 300]);
    expect(ppg[4], 1_700_000_000.0);
    expect(ppg[5], 0); // marker
    expect(ppg[6], 1); // package 1
    expect(ppg.sublist(7, 10), [101, 201, 301]);
    expect(ppg[10], 1_700_000_000.001);
    expect(ppg[12], 2); // package 2
    expect(ppg.sublist(13, 16), [102, 202, 302]);
    expect(ppg[16], 1_700_000_000.002);
  });
}