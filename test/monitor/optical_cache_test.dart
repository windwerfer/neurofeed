import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/cache/optical_cache.dart';
import 'package:neurofeed/src/monitor/viewport_controller.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

void main() {
  test('OpticalCache keeps IR PPG, pulse, SpO2 and avg HR', () {
    final cache = OpticalCache();
    cache.appendPulse(PulseDto(timestamp: 1000, bpm: 60, confidence: 1));
    cache.appendPulse(PulseDto(timestamp: 2000, bpm: 80, confidence: 1));
    cache.appendSpO2(SpO2Dto(timestamp: 1500, spo2: 97, confidence: 1));
    cache.appendPpg(
      PpgDto(
        index: 0,
        channel: kPpgInfraredChannel,
        timestamp: 3000,
        samples: Float64List.fromList([1, 2, 3]),
      ),
    );
    cache.appendPpg(
      PpgDto(
        index: 1,
        channel: 0,
        timestamp: 3000,
        samples: Float64List.fromList([9, 9, 9]),
      ),
    );

    expect(cache.hasPulse, isTrue);
    expect(cache.hasSpo2, isTrue);
    expect(cache.hasPpg, isTrue);
    expect(cache.avgHr, 70);
    expect(cache.ppgIrRange(0, 10).length, 3);
    expect(cache.ppgIrRange(0, 10).map((s) => s.v), [1, 2, 3]);
    expect(cache.latestPpgTimestamp, 3.0);

    cache.appendPulse(PulseDto(timestamp: 5000, bpm: 72, confidence: 1));
    expect(cache.latestTimestamp, 5.0);
    expect(cache.latestPpgTimestamp, 3.0);

    cache.clear();
    expect(cache.hasData, isFalse);
    expect(cache.avgHr, isNull);
    expect(cache.latestMetricTimestamp, isNull);
  });

  test('metric time ignores PPG and a point just outside the window stays', () {
    final cache = OpticalCache();
    cache.appendPpg(
      PpgDto(
        index: 0,
        channel: kPpgInfraredChannel,
        timestamp: 9000,
        samples: Float64List.fromList([1]),
      ),
    );
    expect(cache.latestMetricTimestamp, isNull);
    expect(cache.latestTimestamp, 9.0);

    cache.appendPulse(PulseDto(timestamp: 1000, bpm: 60, confidence: 1));
    cache.appendPulse(PulseDto(timestamp: 2100, bpm: 62, confidence: 1));
    cache.appendPulse(PulseDto(timestamp: 3200, bpm: 64, confidence: 1));
    cache.appendSpO2(SpO2Dto(timestamp: 1000, spo2: 96, confidence: 1));
    cache.appendSpO2(SpO2Dto(timestamp: 2100, spo2: 97, confidence: 1));
    cache.appendSpO2(SpO2Dto(timestamp: 3200, spo2: 98, confidence: 1));

    expect(cache.latestMetricTimestamp, 3.2);
    expect(cache.latestTimestamp, 9.0);

    expect(cache.pulseRange(2.0, 3.2).map((s) => s.t), [2.1, 3.2]);
    final pulse = cache.pulseRangeWithNeighbors(2.0, 3.2);
    expect(pulse.map((s) => s.t), [1.0, 2.1, 3.2]);
    final spo2 = cache.spo2RangeWithNeighbors(2.0, 3.2);
    expect(spo2.map((s) => s.v), [96, 97, 98]);
  });

  test('clampDetailToOverview and alignDetailToOverview', () {
    final overview = ViewportController()
      ..windowSeconds = 30
      ..followLeadSeconds = 1;
    final detail = ViewportController()..windowSeconds = 10;

    overview.enterInspectStrip(newestElapsed: 100);
    alignDetailToOverview(
      detail: detail,
      overview: overview,
      newestElapsed: 100,
    );
    expect(detail.mode, ViewportMode.inspect);
    expect(
      detail.stripVisibleEnd(newestElapsed: 100),
      closeTo(overview.stripVisibleEnd(newestElapsed: 100), 1e-9),
    );

    detail.windowSeconds = 60;
    clampDetailToOverview(
      detail: detail,
      overview: overview,
      newestElapsed: 100,
    );
    expect(detail.windowSeconds, 30);

    overview.followStrip();
    alignDetailToOverview(
      detail: detail,
      overview: overview,
      newestElapsed: 100,
    );
    expect(detail.mode, ViewportMode.follow);
  });
}
