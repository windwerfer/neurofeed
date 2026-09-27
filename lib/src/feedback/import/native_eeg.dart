import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/rust/api/eeg_conditioning.dart';
import 'package:neurofeed/src/rust/api/import_dsp.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';

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

/// [runsByElectrode] through the live EEG conditioning (high-pass + mains
/// notch; mains detected across all electrodes). Runs keep their shape.
({Map<int, List<EegRun>> runs, EegConditioning conditioning}) conditionRuns(
  Map<int, List<EegRun>> runsByElectrode,
) {
  final packets = <({int e, int run, int offset, EegSampleRecord rec})>[];
  for (final e in runsByElectrode.entries) {
    for (var r = 0; r < e.value.length; r++) {
      final run = e.value[r];
      for (var o = 0; o < run.samples.length; o += kEegPacketSamples) {
        final end = math.min(o + kEegPacketSamples, run.samples.length);
        packets.add((
          e: e.key,
          run: r,
          offset: o,
          rec: EegSampleRecord(
            timestamp: run.startMs + o * 1000.0 / kNativeEegHz,
            electrode: e.key,
            samples: Float32List.fromList(run.samples.sublist(o, end)),
          ),
        ));
      }
    }
  }
  packets.sort((a, b) {
    final t = a.rec.timestamp.compareTo(b.rec.timestamp);
    return t != 0 ? t : a.e.compareTo(b.e);
  });
  final out = conditionEeg(
    eeg: [for (final p in packets) p.rec],
    conditioning: null,
  );
  final runs = {
    for (final e in runsByElectrode.entries)
      e.key: [
        for (final run in e.value)
          EegRun(run.startMs, List<double>.filled(run.samples.length, 0)),
      ],
  };
  for (var i = 0; i < packets.length; i++) {
    final p = packets[i];
    runs[p.e]![p.run].samples.setAll(p.offset, out.eeg[i].samples);
  }
  return (runs: runs, conditioning: out.conditioning);
}

/// Band rows from our own FFT (the live band source) over the conditioned
/// signal: one record per electrode per full second of each run, stamped at
/// the end of that second.
({List<BandInstant> rows, EegConditioning conditioning}) fftBandRows(
  Map<int, List<EegRun>> rawRunsByElectrode,
) {
  final conditioned = conditionRuns(rawRunsByElectrode);
  final runsByElectrode = conditioned.runs;
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
  return (
    rows: [
      for (final e in byTs.entries)
        BandInstant(timestampMs: e.key, byElectrode: e.value),
    ],
    conditioning: conditioned.conditioning,
  );
}
