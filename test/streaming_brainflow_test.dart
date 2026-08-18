import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/streaming/streaming_brainflow.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// Mirrors the BrainFlow STREAMING_BOARD receiver
/// (`streaming_board.cpp` `read_thread`): read exactly
/// `batch * num_rows` doubles per datagram, then split into packages.
List<Uint8List> _readExact(RawDatagramSocket socket, int bytes) {
  final out = <Uint8List>[];
  while (true) {
    final dg = socket.receive();
    if (dg == null) break;
    out.add(dg.data);
  }
  return out;
}

StreamingConfig _config(int port) => StreamingConfig(
      protocol: StreamProtocol.brainflow,
      enabled: true,
      oscIp: null,
      oscPort: null,
      prefix: '',
      separateGroups: false,
      brainflowIp: '127.0.0.1',
      brainflowPort: port,
    );

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
        final dgs = _readExact(receiver, BrainflowStreamer.numRows * 8);
        for (final dg in dgs) {
          if (!received.isCompleted) received.complete(dg);
        }
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
    expect(data.length, BrainflowStreamer.batchSize * BrainflowStreamer.numRows * 8);
    final rows = _doubles(data);
    final pkg0 = rows.sublist(0, 8);
    final pkg1 = rows.sublist(8, 16);
    final pkg2 = rows.sublist(16, 24);

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

  test('BrainFlow streamer continues package numbering across batches', () async {
    final receiver = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(receiver.close);
    final received = Completer<List<Uint8List>>();
    final all = <Uint8List>[];
    receiver.listen((event) {
      if (event == RawSocketEvent.read) {
        final dgs = _readExact(receiver, -1);
        all.addAll(dgs);
        if (all.length >= 2 && !received.isCompleted) {
          received.complete(List.of(all));
        }
      }
    });

    final streamer = BrainflowStreamer(_config(receiver.port));
    await streamer.start();
    addTearDown(streamer.stop);

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
}