import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';
import 'package:muse_ml/src/streaming/streaming_osc.dart';

void main() {
  group('oscEncodeMessage', () {
    test('pads address and type tag to 4-byte boundaries', () {
      final bytes = oscEncodeMessage('/muse/eeg', []);
      // address: 9 chars + NUL -> padded to 12
      // tag: "," -> padded to 4
      expect(bytes.length, 16);
      expect(String.fromCharCodes(bytes.sublist(0, 9)), '/muse/eeg');
      expect(bytes.sublist(9, 12), [0, 0, 0]);
      expect(bytes.sublist(12, 14), [0x2C, 0x00]); // ","
    });

    test('encodes floats big-endian as float32', () {
      final bytes = oscEncodeMessage('/muse/ppg', [1.0, 2.5]);
      // 12 addr + 4 tag + 8 data
      expect(bytes.length, 24);
      final data = bytes.sublist(16);
      expect(Float32List.sublistView(Uint8List.fromList(data)), [1.0, 2.5]);
    });

    test('long address over one padding block is still aligned', () {
      final bytes = oscEncodeMessage('/muse/long/grouptype_name', [0.0]);
      // payload starts at a 4-byte boundary
      expect(bytes.length % 4, 0);
    });
  });

  group('OscStreamer (UDP)', () {
    test('batches a 12-sample EEG chunk into one datagram', () async {
      final receiver = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(receiver.close);
      final streamer = OscStreamer(
        StreamingConfig(
          protocol: StreamProtocol.osc,
          enabled: true,
          oscIp: '127.0.0.1',
          oscPort: receiver.port,
          prefix: '/muse',
          separateGroups: true,
        ),
      );
      await streamer.start();
      addTearDown(streamer.stop);

      final received = Completer<Datagram>();
      receiver.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final dg = receiver.receive();
            if (dg == null) break;
            if (!received.isCompleted) received.complete(dg);
          }
        }
      });

      // 12 rows x 4 channels: ts + 48 floats -> single message.
      for (var i = 0; i < 12; i++) {
        streamer.push(GroupSample('eeg', 100.0 + i / 256, [1, 2, 3, 4]));
      }
      expect(streamer.packetsSent, 1);

      final datagram = await received.future.timeout(
        const Duration(seconds: 2),
      );
      expect(datagram.address, InternetAddress.loopbackIPv4);
      expect(datagram.data.length % 4, 0);
      // address /muse/eeg + tag ,f…49 + 49 floats
      final data = datagram.data;
      expect(String.fromCharCodes(data.sublist(0, 9)), '/muse/eeg');
      expect(data[9], 0); // NUL padding
      expect(data[12], 0x2C); // ',' type tag
      expect(data[13], 0x66); // 'f'
      // offset: 12 (address) + 52 (tag ",f…" x50 chars padded)
      final floats = Float32List.sublistView(Uint8List.fromList(data), 64);
      expect(floats.length, 1 + 48);
      expect(floats[0], closeTo(100.0, 1e-3));
      expect(floats[1], 1.0);
      expect(floats[4], 4.0);
    });
  });
}