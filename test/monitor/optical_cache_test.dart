import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/optical_cache.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

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

    cache.clear();
    expect(cache.hasData, isFalse);
    expect(cache.avgHr, isNull);
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
