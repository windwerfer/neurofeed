import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/cache/sliding_spectrum.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

bool shouldRecomputeEegOnSweep({required ViewportMode mode}) =>
    mode != ViewportMode.inspect;

List<List<BandPoint>> emptyBandSeries() => [
  for (var i = 0; i < bandNames.length; i++) <BandPoint>[],
];

class HistogramTick {
  final SlidingHistogram _sliding = SlidingHistogram();
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
    return _apply(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      halfRange: halfRange,
      forceFull: false,
    );
  }

  void recomputeEeg({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
  }) {
    _apply(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      halfRange: halfRange,
      forceFull: true,
    );
  }

  bool _apply({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
    required bool forceFull,
  }) {
    this.startElapsed = startElapsed;
    this.endElapsed = endElapsed;
    final changed = _sliding.update(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      halfRange: halfRange,
      forceFull: forceFull,
    );
    if (changed || forceFull) {
      counts = _sliding.counts;
    }
    return changed;
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
  final SlidingWelch _sliding = SlidingWelch();
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
    return _apply(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      forceFull: false,
    );
  }

  void recomputeEeg({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
  }) {
    _apply(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      forceFull: true,
    );
  }

  bool _apply({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required bool forceFull,
  }) {
    this.startElapsed = startElapsed;
    this.endElapsed = endElapsed;
    final changed = _sliding.update(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      forceFull: forceFull,
    );
    if (changed || forceFull) {
      spectrum = _sliding.spectrum;
      peak = spectrum == null ? null : alphaPeakHz(spectrum!);
    }
    return changed;
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
