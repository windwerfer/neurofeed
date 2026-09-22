import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/cache/band_cache.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

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

  test('sticky unusable stamped at append from quality', () {
    final cache = BandCache();
    cache.setSelectedElectrodes({0, 1});
    cache.appendBands(
      const BandsDto(
        electrode: 0,
        timestamp: 1000,
        delta: 1,
        theta: 1,
        alpha: 1,
        beta: 1,
        gamma: 1,
        lineNoiseRatio: 0,
      ),
      signalQuality: [10, 90, 90, 90],
    );
    cache.appendBands(
      const BandsDto(
        electrode: 1,
        timestamp: 1000,
        delta: 2,
        theta: 2,
        alpha: 2,
        beta: 2,
        gamma: 2,
        lineNoiseRatio: 0,
      ),
      signalQuality: [10, 90, 90, 90],
    );
    final bad = cache.getRange(bandChannelId(0, 0), 0, 10);
    final good = cache.getRange(bandChannelId(1, 0), 0, 10);
    expect(bad.single.unusable, isTrue);
    expect(good.single.unusable, isFalse);
  });

  test('all-selected-dirty stamps selected pads', () {
    final cache = BandCache();
    cache.setSelectedElectrodes({0, 1});
    cache.appendBands(
      const BandsDto(
        electrode: 0,
        timestamp: 2000,
        delta: 1,
        theta: 1,
        alpha: 1,
        beta: 1,
        gamma: 1,
        lineNoiseRatio: 0,
      ),
      signalQuality: [5, 5, 90, 90],
    );
    expect(cache.getRange(bandChannelId(0, 2), 0, 10).single.unusable, isTrue);
  });
}
