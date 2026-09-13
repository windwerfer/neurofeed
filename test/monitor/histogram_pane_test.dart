import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

EegDto _eeg(int electrode, List<double> samples, {double ts = 0}) => EegDto(
  index: 0,
  electrode: electrode,
  timestamp: ts,
  samples: Float64List.fromList(samples),
);

void main() {
  test('histogram is 64 bins over own ±100 µV domain', () {
    expect(kHistogramBins, 64);
    expect(kHistogramDefaultHalfRange, 100);
    final counts = histogramCounts([
      0,
      0,
      50,
      -50,
      150,
      -150,
      double.nan,
    ], halfRange: 100);
    expect(counts, hasLength(64));
    expect(counts.reduce((a, b) => a + b), 4);
    expect(counts[histogramBinFor(0)], 2);
    expect(counts[histogramBinFor(50)], 1);
    expect(counts[histogramBinFor(-50)], 1);
    expect(histogramBinFor(150), 63);
    expect(histogramBinFor(-150), 0);

    final tight = histogramCounts([80], halfRange: 50);
    expect(tight.reduce((a, b) => a + b), 0);

    final wide = histogramCounts([80], halfRange: 200);
    expect(wide.reduce((a, b) => a + b), 1);
  });

  test('mean of selected electrodes via SweepBuffer.sampleAt', () {
    final buf = SweepBuffer();
    buf.append(_eeg(0, List<double>.filled(256, 10)));
    buf.append(_eeg(1, List<double>.filled(256, 30)));
    final newest = sweepNewestElapsed(buf, null);
    final both = meanEegWindow(
      buffer: buf,
      electrodes: {0, 1},
      startElapsed: 0,
      endElapsed: newest + 1 / SweepBuffer.sampleRate,
      newestElapsed: newest,
    );
    expect(both, isNotEmpty);
    expect(both.first, closeTo(20, 1e-9));

    final only0 = meanEegWindow(
      buffer: buf,
      electrodes: {0},
      startElapsed: 0,
      endElapsed: newest + 1 / SweepBuffer.sampleRate,
      newestElapsed: newest,
    );
    expect(only0.first, closeTo(10, 1e-9));
  });
}
