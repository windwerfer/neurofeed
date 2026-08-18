import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

void main() {
  group('GroupMixer', () {
    test('emits a row only when every channel has a sample (EEG)', () {
      final mixer = GroupMixer(StreamGroups.eeg)..reset();
      // One electrode arrives: nothing drains.
      mixer.add(0, 100.0, [1, 2, 3, 4]);
      expect(mixer.drain(64), isEmpty);

      // All four electrodes arrive: rows drain in order.
      mixer.add(1, 100.0, [11, 12, 13, 14]);
      mixer.add(2, 100.0, [21, 22, 23, 24]);
      mixer.add(3, 100.0, [31, 32, 33, 34]);
      final rows = mixer.drain(64);
      expect(rows, hasLength(4));
      expect(rows[0].values, [1, 11, 21, 31]);
      expect(rows[3].values, [4, 14, 24, 34]);
      expect(rows[0].groupId, 'eeg');
    });

    test('timestamps step back by 1/rate within a packet', () {
      final mixer = GroupMixer(StreamGroups.eeg)..reset();
      for (var c = 0; c < 4; c++) {
        mixer.add(c, 100.0, [1, 2, 3]);
      }
      final rows = mixer.drain(64);
      expect(rows[0].timestamp, closeTo(100.0 - 2 / 256, 1e-9));
      expect(rows[1].timestamp, closeTo(100.0 - 1 / 256, 1e-9));
      expect(rows[2].timestamp, 100.0);
    });

    test('IMU: accel and gyro channels share one lockstep', () {
      final mixer = GroupMixer(StreamGroups.imu)..reset();
      for (var i = 0; i < 3; i++) {
        mixer.add(i, 200.0, [0.1, 0.2, 0.3]);
      }
      // Only accel half filled -> no row yet.
      expect(mixer.drain(64), isEmpty);
      for (var i = 3; i < 6; i++) {
        mixer.add(i, 200.0, [0.9, 0.8, 0.7]);
      }
      final rows = mixer.drain(64);
      expect(rows, hasLength(3));
      // Row 0 = first sample of every channel (each channel got [0.1,0.2,0.3]).
      expect(rows[0].values, [0.1, 0.1, 0.1, 0.9, 0.9, 0.9]);
      expect(rows[2].values, [0.3, 0.3, 0.3, 0.7, 0.7, 0.7]);
      expect(rows[0].values, hasLength(6));
    });

    test('bands: 20 channels across 4 electrode events', () {
      final mixer = GroupMixer(StreamGroups.bands)..reset();
      for (var e = 0; e < 4; e++) {
        mixer.add(e * 5, 300.0, [0.1 * e]);
        mixer.add(e * 5 + 1, 300.0, [0.2 * e]);
        mixer.add(e * 5 + 2, 300.0, [0.3 * e]);
        mixer.add(e * 5 + 3, 300.0, [0.4 * e]);
        mixer.add(e * 5 + 4, 300.0, [0.5 * e]);
      }
      final rows = mixer.drain(64);
      expect(rows, hasLength(1));
      expect(rows[0].values, hasLength(20));
      expect(rows[0].values[0], 0.0);
      expect(rows[0].values[5], 0.1);
      expect(rows[0].values[19], 1.5);
    });

    test('a lagging channel overflows instead of unbounded growth', () {
      final mixer = GroupMixer(StreamGroups.eeg)..reset();
      // Feed channels 1-3 for a long time, never channel 0.
      for (var i = 0; i < 300; i++) {
        for (var c = 1; c < 4; c++) {
          mixer.add(c, 100.0 + i, [i.toDouble()]);
        }
      }
      expect(mixer.droppedSamples, greaterThan(0));
      // Queues stay bounded.
      expect(mixer.drain(64), isEmpty); // channel 0 still empty
    });
  });
}