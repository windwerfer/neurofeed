import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/split_pane_tick.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

EegDto _eeg(int electrode, List<double> samples, {double ts = 0}) => EegDto(
  index: 0,
  electrode: electrode,
  timestamp: ts,
  samples: Float64List.fromList(samples),
);

BandsDto _bands(int electrode, {double timestamp = 1000, double alpha = 3}) =>
    BandsDto(
      electrode: electrode,
      timestamp: timestamp,
      delta: 1,
      theta: 2,
      alpha: alpha,
      beta: 4,
      gamma: 5,
      lineNoiseRatio: 0,
    );

void _fillSeconds(SweepBuffer buf, double uv, {required int seconds}) {
  for (var s = 0; s < seconds; s++) {
    buf.append(_eeg(0, List<double>.filled(256, uv)));
  }
}

void main() {
  test('Follow sweep recomputes EEG; Inspect sweep does not', () {
    expect(shouldRecomputeEegOnSweep(mode: ViewportMode.follow), isTrue);
    expect(shouldRecomputeEegOnSweep(mode: ViewportMode.inspect), isFalse);

    final buf = SweepBuffer();
    _fillSeconds(buf, 10, seconds: 8);
    final newest = (buf.sampleCount - 1) / SweepBuffer.sampleRate;
    final tick = HistogramTick();
    expect(
      tick.onSweep(
        mode: ViewportMode.follow,
        buffer: buf,
        electrodes: {0},
        startElapsed: 0,
        endElapsed: 8,
        newestElapsed: newest,
        halfRange: 100,
      ),
      isTrue,
    );
    final followCounts = List<int>.from(tick.counts);
    expect(followCounts[histogramBinFor(10)], greaterThan(0));
    expect(followCounts[histogramBinFor(50)], 0);
    final followIdentity = tick.counts;

    _fillSeconds(buf, 50, seconds: 8);
    final later = (buf.sampleCount - 1) / SweepBuffer.sampleRate;
    expect(
      tick.onSweep(
        mode: ViewportMode.inspect,
        buffer: buf,
        electrodes: {0},
        startElapsed: 0,
        endElapsed: 8,
        newestElapsed: later,
        halfRange: 100,
      ),
      isFalse,
    );
    expect(identical(tick.counts, followIdentity), isTrue);
    expect(listEquals(tick.counts, followCounts), isTrue);

    tick.recomputeEeg(
      buffer: buf,
      electrodes: {0},
      startElapsed: 8,
      endElapsed: 16,
      newestElapsed: later,
      halfRange: 100,
    );
    expect(identical(tick.counts, followIdentity), isFalse);
    expect(tick.startElapsed, 8);
    expect(tick.endElapsed, 16);
    expect(tick.counts[histogramBinFor(50)], greaterThan(0));
    expect(tick.counts[histogramBinFor(10)], 0);
  });

  test('epoch pan recomputes histogram; strip rebuild does not', () {
    final buf = SweepBuffer();
    _fillSeconds(buf, 10, seconds: 8);
    _fillSeconds(buf, 50, seconds: 8);
    final newest = (buf.sampleCount - 1) / SweepBuffer.sampleRate;
    final tick = HistogramTick();
    tick.recomputeEeg(
      buffer: buf,
      electrodes: {0},
      startElapsed: 0,
      endElapsed: 8,
      newestElapsed: newest,
      halfRange: 100,
    );
    final early = List<int>.from(tick.counts);
    final cache = BandCache();
    cache.appendBands(_bands(0, timestamp: 1000, alpha: 100));
    tick.recomputeSeries(
      cache: cache,
      electrodes: {0},
      startElapsed: 0,
      endElapsed: 30,
      captureStartedAtMs: 0,
    );
    expect(tick.series[2], isNotEmpty);
    expect(listEquals(tick.counts, early), isTrue);

    tick.recomputeEeg(
      buffer: buf,
      electrodes: {0},
      startElapsed: 8,
      endElapsed: 16,
      newestElapsed: newest,
      halfRange: 100,
    );
    expect(listEquals(tick.counts, early), isFalse);
    expect(tick.counts[histogramBinFor(50)], greaterThan(0));
  });

  test(
    'PSD Inspect sweep keeps spectrum; epoch pan Welch-es the new window',
    () {
      final buf = SweepBuffer();
      List<double> sine(double hz) => [
        for (var i = 0; i < 256; i++) math.sin(2 * math.pi * hz * i / 256),
      ];
      for (var s = 0; s < 4; s++) {
        buf.append(_eeg(0, sine(10)));
      }
      final newest = (buf.sampleCount - 1) / SweepBuffer.sampleRate;
      final tick = PsdTick();
      expect(
        tick.onSweep(
          mode: ViewportMode.follow,
          buffer: buf,
          electrodes: {0},
          startElapsed: 0,
          endElapsed: 4,
          newestElapsed: newest,
        ),
        isTrue,
      );
      final followSpec = tick.spectrum;
      expect(followSpec, isNotNull);
      expect(tick.peak, closeTo(10, 1));

      for (var s = 0; s < 4; s++) {
        buf.append(_eeg(0, sine(20)));
      }
      final later = (buf.sampleCount - 1) / SweepBuffer.sampleRate;
      expect(
        tick.onSweep(
          mode: ViewportMode.inspect,
          buffer: buf,
          electrodes: {0},
          startElapsed: 0,
          endElapsed: 4,
          newestElapsed: later,
        ),
        isFalse,
      );
      expect(identical(tick.spectrum, followSpec), isTrue);
      expect(tick.peak, closeTo(10, 1));

      tick.recomputeEeg(
        buffer: buf,
        electrodes: {0},
        startElapsed: 4,
        endElapsed: 8,
        newestElapsed: later,
      );
      expect(identical(tick.spectrum, followSpec), isFalse);
      expect(tick.startElapsed, 4);
      expect(tick.endElapsed, 8);
      final moved = tick.spectrum!;
      expect(
        moved.power[freqBin(20, moved.n)],
        greaterThan(moved.power[freqBin(10, moved.n)]),
      );
    },
  );
}
