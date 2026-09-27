import 'dart:collection';

import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/rust/api/import_dsp.dart';

/// Rate every recording stores EEG at.
const int kNativeEegHz = 256;

/// Contiguous 256 Hz EEG for one electrode starting at [startMs].
class EegRun {
  const EegRun(this.startMs, this.samples);
  final double startMs;
  final List<double> samples;
}

/// True when [rateHz] needs resampling to the native rate.
bool needsResample(double rateHz) => rateHz.round() != kNativeEegHz;

/// [samples] at [rateHz] → 256 Hz (anti-aliased, rubato in Rust).
List<double> resampleToNative(List<double> samples, double rateHz) {
  if (!needsResample(rateHz) || samples.isEmpty) return samples;
  return resampleEeg(
    samples: samples,
    fromHz: rateHz.round(),
    toHz: kNativeEegHz,
  );
}

/// Pack runs as 256 Hz EEG packets.
List<int> encodeEegRuns(Map<int, List<EegRun>> runsByElectrode) {
  final events = <int>[];
  for (final e in runsByElectrode.entries) {
    var packets = 0;
    for (final run in e.value) {
      events.addAll(
        encodeEegPackets(
          samplesByElectrode: {e.key: run.samples},
          sampleRateHz: kNativeEegHz.toDouble(),
          startMs: run.startMs,
          firstIndex: packets,
        ),
      );
      packets += (run.samples.length / kEegPacketSamples).ceil();
    }
  }
  return events;
}

/// Band rows from our own FFT (the live band source): one record per
/// electrode per full second of each run, stamped at the end of that second.
List<BandInstant> fftBandRows(Map<int, List<EegRun>> runsByElectrode) {
  final byTs = SplayTreeMap<double, Map<int, BandValues>>();
  for (final e in runsByElectrode.entries) {
    for (final run in e.value) {
      final flat = eegSecondBands(samples: run.samples);
      for (var k = 0; k + 8 <= flat.length; k += 8) {
        final ts = run.startMs + (k ~/ 8 + 1) * 1000.0;
        byTs.putIfAbsent(ts, () => {})[e.key] = BandValues(
          delta: flat[k],
          theta: flat[k + 1],
          alpha: flat[k + 2],
          beta: flat[k + 3],
          gamma: flat[k + 4],
          lineNoise: flat[k + 7],
        );
      }
    }
  }
  return [
    for (final e in byTs.entries)
      BandInstant(timestampMs: e.key, byElectrode: e.value),
  ];
}
