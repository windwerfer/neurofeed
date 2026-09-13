import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

EegDto _eeg(int electrode, List<double> samples, {double ts = 0}) => EegDto(
  index: 0,
  electrode: electrode,
  timestamp: ts,
  samples: Float64List.fromList(samples),
);

BandsDto _bands(int electrode, {double timestamp = 1000}) => BandsDto(
  electrode: electrode,
  timestamp: timestamp,
  delta: 1,
  theta: 2,
  alpha: 3,
  beta: 4,
  gamma: 5,
  lineNoiseRatio: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('many SweepBuffer.append calls notify once after pump', (
    tester,
  ) async {
    final buf = SweepBuffer();
    var n = 0;
    buf.addListener(() => n++);
    for (var i = 0; i < 32; i++) {
      buf.append(_eeg(0, [i.toDouble()]));
    }
    expect(buf.sampleCount, 32);
    expect(n, 0);
    await tester.pump();
    expect(n, 1);
  });

  testWidgets('freeze notifies immediately without pumping', (tester) async {
    final buf = SweepBuffer();
    var n = 0;
    buf.addListener(() => n++);
    buf.append(_eeg(0, [1]));
    expect(n, 0);
    buf.freeze();
    expect(n, 1);
  });

  testWidgets('BandCache.appendBands burst notifies once after pump', (
    tester,
  ) async {
    final cache = BandCache();
    var n = 0;
    cache.addListener(() => n++);
    for (var e = 0; e < 4; e++) {
      cache.appendBands(_bands(e));
    }
    expect(cache.hasData, isTrue);
    expect(n, 0);
    await tester.pump();
    expect(n, 1);
  });
}
