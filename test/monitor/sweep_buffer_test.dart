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

  test('append with display window 0 is RAM-only', () {
    final buf = SweepBuffer();
    expect(buf.displayWindow, 0);
    buf.append(_eeg(0, [1, 2, 3]));
    expect(buf.sampleCount, 3);
    expect(buf.cursor, 0);
    expect(buf.displaySample(0, 0), isNaN);
  });

  test('setDisplayWindow(0) then append does not grow display or cursor', () {
    final buf = SweepBuffer();
    buf.setDisplayWindow(10);
    buf.append(_eeg(0, List<double>.filled(15, 1)));
    expect(buf.cursor, 15);
    expect(buf.displayWindow, 10);
    expect(buf.displaySample(0, 0), 1);

    buf.setDisplayWindow(0);
    expect(buf.displayWindow, 0);
    expect(buf.cursor, 0);
    final ram = buf.sampleCount;
    buf.append(_eeg(0, List<double>.filled(32, 2)));
    buf.append(_eeg(1, List<double>.filled(8, 3)));
    expect(buf.sampleCount, ram + 32);
    expect(buf.displayWindow, 0);
    expect(buf.cursor, 0);
    expect(buf.displaySample(0, 0), isNaN);
    expect(buf.displaySample(1, 0), isNaN);
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
