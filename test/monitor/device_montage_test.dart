import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';

void main() {
  group('recordedChannelLabels', () {
    test('Muse labels follow electrode index, not alphabetical order', () {
      final labels = recordedChannelLabels(
        kind: DeviceKind.muse,
        electrodes: {3, 1, 0, 2},
      );
      expect(labels, ['TP9', 'AF7', 'AF8', 'TP10']);
      expect(labels[0], 'TP9');
    });

    test('Crown gets Crown labels in electrode order', () {
      final labels = recordedChannelLabels(
        kind: DeviceKind.neurosity,
        electrodes: {0, 1, 2, 3, 4, 5, 6, 7},
      );
      expect(labels, kCrownElectrodeNames);
    });

    test('empty recording still maps the device montage', () {
      expect(
        recordedChannelLabels(kind: DeviceKind.muse, electrodes: const {}),
        kMuseElectrodeNames,
      );
    });
  });
}
