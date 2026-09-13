import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

bool shouldRecomputeEegOnSweep({required ViewportMode mode}) =>
    mode != ViewportMode.inspect;

List<List<BandPoint>> emptyBandSeries() => [
  for (var i = 0; i < bandNames.length; i++) <BandPoint>[],
];

class HistogramTick {
  List<int> counts = List<int>.filled(kHistogramBins, 0);
  List<List<BandPoint>> series = emptyBandSeries();
  double startElapsed = 0;
  double endElapsed = 0;

  bool onSweep({
    required ViewportMode mode,
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
  }) {
    if (!shouldRecomputeEegOnSweep(mode: mode)) return false;
    recomputeEeg(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      halfRange: halfRange,
    );
    return true;
  }

  void recomputeEeg({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
  }) {
    this.startElapsed = startElapsed;
    this.endElapsed = endElapsed;
    final samples = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
    );
    counts = histogramCounts(samples, halfRange: halfRange);
  }

  void recomputeSeries({
    required BandCache cache,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required int? captureStartedAtMs,
  }) {
    series = buildBandSeries(
      cache: cache,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      captureStartedAtMs: captureStartedAtMs,
    );
  }

  void clearSeries() {
    series = emptyBandSeries();
  }
}

class PsdTick {
  Spectrum? spectrum;
  double? peak;
  List<List<BandPoint>> series = emptyBandSeries();
  double startElapsed = 0;
  double endElapsed = 0;

  bool onSweep({
    required ViewportMode mode,
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
  }) {
    if (!shouldRecomputeEegOnSweep(mode: mode)) return false;
    recomputeEeg(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
    );
    return true;
  }

  void recomputeEeg({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
  }) {
    this.startElapsed = startElapsed;
    this.endElapsed = endElapsed;
    if (!buffer.hasData) {
      spectrum = null;
      peak = null;
      return;
    }
    final samples = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
    );
    spectrum = welch(samples);
    peak = alphaPeakHz(spectrum!);
  }

  void recomputeSeries({
    required BandCache cache,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required int? captureStartedAtMs,
  }) {
    series = buildBandSeries(
      cache: cache,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      captureStartedAtMs: captureStartedAtMs,
    );
  }

  void clearSeries() {
    series = emptyBandSeries();
  }
}
