import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

void main() {
  test('BandCache window is the 30 min tmp cap', () {
    expect(BandCache().maxTimeWindowSecs, 1800);
  });

  test('appendBands then getRange returns alpha for electrode 1', () {
    final cache = BandCache();
    cache.appendBands(
      const BandsDto(
        electrode: 1,
        timestamp: 1500,
        delta: 1,
        theta: 2,
        alpha: 3,
        beta: 4,
        gamma: 5,
        lineNoiseRatio: 0.05,
      ),
    );
    expect(cache.hasData, isTrue);
    final samples = cache.getRange(bandChannelId(1, 2), 0, 10);
    expect(samples, hasLength(1));
    expect(samples.first.t, closeTo(1.5, 1e-9));
    expect(samples.first.v, 3);
  });

  test('idle montage is Muse-4 until Crown', () {
    final muse = MonitorState.idle();
    expect(muse.kind, CaptureKind.idle);
    expect(muse.channelCount, 4);
    expect(muse.electrodeNames, kMuseElectrodeNames);

    final crown = MonitorState.idle(deviceKind: DeviceKind.neurosity);
    expect(crown.channelCount, 8);
    expect(crown.electrodeNames, kCrownElectrodeNames);
  });
}
