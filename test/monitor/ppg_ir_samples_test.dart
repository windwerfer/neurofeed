import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/cache/optical_cache.dart';
import 'package:neurofeed/src/monitor/views/recording_dashboard.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';

void main() {
  test('ppgIrChartSamples spaces infrared from the packet end', () {
    final rate = OpticalCache.ppgSampleRate;
    final samples = ppgIrChartSamples(
      packets: [
        PpgSampleRecord(
          timestamp: 1000,
          channel: kPpgInfraredChannel,
          samples: Float32List.fromList([1, double.nan, 3]),
        ),
        PpgSampleRecord(
          timestamp: 1000,
          channel: 2,
          samples: Float32List.fromList([9]),
        ),
      ],
      originMs: 0,
      startElapsed: 0,
      endElapsed: 2,
    );
    expect(samples.map((s) => s.v), [1, 3]);
    expect(samples.last.t, 1.0);
    expect(samples.first.t, closeTo(1.0 - 2 / rate, 1e-9));
  });

  test('ppgIrChartSamples drops packets outside the window', () {
    final samples = ppgIrChartSamples(
      packets: [
        PpgSampleRecord(
          timestamp: 5000,
          channel: kPpgInfraredChannel,
          samples: Float32List.fromList([1, 2]),
        ),
      ],
      originMs: 0,
      startElapsed: 0,
      endElapsed: 1,
    );
    expect(samples, isEmpty);
  });
}
