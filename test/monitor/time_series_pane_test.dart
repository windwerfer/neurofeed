import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

BandsDto _bands({
  required int electrode,
  required double timestamp,
  double delta = 1,
  double theta = 1,
  double alpha = 1,
  double beta = 1,
  double gamma = 1,
}) => BandsDto(
  electrode: electrode,
  timestamp: timestamp,
  delta: delta,
  theta: theta,
  alpha: alpha,
  beta: beta,
  gamma: gamma,
  lineNoiseRatio: 0,
);

void main() {
  test('five series; mean of selected electrodes in dB', () {
    final cache = BandCache();
    cache.appendBands(
      _bands(electrode: 0, timestamp: 1000, delta: 100, theta: 10),
    );
    cache.appendBands(
      _bands(electrode: 1, timestamp: 1000, delta: 10000, theta: 10),
    );

    final both = buildBandSeries(
      cache: cache,
      electrodes: {0, 1},
      startElapsed: 0,
      endElapsed: 10,
      captureStartedAtMs: 0,
    );
    expect(both, hasLength(bandNames.length));
    expect(both.length, 5);
    expect(both[0], hasLength(1));
    expect(both[0].first.db, closeTo(30, 1e-6));
    expect(
      both[0].first.db,
      isNot(closeTo(10 * math.log(5050) / math.ln10, 0.1)),
    );

    final only0 = buildBandSeries(
      cache: cache,
      electrodes: {0},
      startElapsed: 0,
      endElapsed: 10,
      captureStartedAtMs: 0,
    );
    expect(only0[0].first.db, closeTo(20, 1e-6));
  });

  test('10·log10 floor (ε) does not produce NaN', () {
    expect(linearToDb(0).isFinite, isTrue);
    expect(linearToDb(-1).isFinite, isTrue);
    expect(linearToDb(double.nan).isFinite, isTrue);
    expect(linearToDb(kBandsLogEpsilon), closeTo(-120, 1e-6));
    expect(linearToDb(0), closeTo(linearToDb(kBandsLogEpsilon), 1e-9));
  });

  test('null captureStartedAtMs is not unix epoch', () {
    final cache = BandCache();
    cache.appendBands(_bands(electrode: 0, timestamp: 2000, delta: 100));
    cache.appendBands(_bands(electrode: 0, timestamp: 3000, delta: 100));
    final series = buildBandSeries(
      cache: cache,
      electrodes: {0},
      startElapsed: -1,
      endElapsed: 10,
      captureStartedAtMs: null,
    );
    expect(series[0], hasLength(2));
    expect(series[0][0].elapsed, closeTo(0, 1e-9));
    expect(series[0][1].elapsed, closeTo(1, 1e-9));
  });
}
