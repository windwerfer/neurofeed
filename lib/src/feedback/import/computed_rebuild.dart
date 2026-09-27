import 'dart:math' as math;
import 'dart:typed_data';

import 'package:neurofeed/src/feedback/import/raw_body.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;

/// Heuristic: Mind Monitor absolute bands are Bels (~−2…3). Neurofeed-native
/// CSV / live FFT bands are linear µV²/Hz (often ≫ 10). ComputedFrame + charts
/// expect **linear** absolute power (see [MonitorSampler] / `linearToDb`).
bool bandsLookLikeBels(Iterable<double> values) {
  var any = false;
  for (final v in values) {
    if (v.isNaN) continue;
    any = true;
    if (v.abs() > 8.0) return false;
  }
  return any;
}

double bandToLinear(double v, {required bool fromBels}) {
  if (!fromBels) return v;
  return math.pow(10.0, v).toDouble();
}

/// Build 1 Hz FFI [ComputedFrame]s from absolute band rows (mean per second).
///
/// Guardrail / feedback fields are zeroed — imports never invent Trust protocol
/// state. [signalQuality] stays 0 (unknown) so experimental band stats that
/// require usable quality stay omitted unless quality is known.
List<ffi.ComputedFrame> rebuildComputedFromBands({
  required List<BandInstant> bandRows,
  required int channelCount,
  bool? treatAsBels,
}) {
  if (bandRows.isEmpty || channelCount <= 0) return const [];

  final sampleVals = <double>[];
  for (final row in bandRows) {
    for (final b in row.byElectrode.values) {
      sampleVals
        ..add(b.delta)
        ..add(b.theta)
        ..add(b.alpha)
        ..add(b.beta)
        ..add(b.gamma);
    }
  }
  final asBels = treatAsBels ?? bandsLookLikeBels(sampleVals);

  // Mean of every band row within each second (linear power), like the
  // live 1 Hz sampler. Seconds without rows get no frame.
  final sums = <int, Map<int, List<double>>>{};
  for (final row in bandRows) {
    final sec = (row.timestampMs / 1000.0).floor();
    final bySec = sums.putIfAbsent(sec, () => {});
    for (final e in row.byElectrode.entries) {
      if (e.key < 0 || e.key >= channelCount) continue;
      final b = e.value;
      final acc = bySec.putIfAbsent(e.key, () => List<double>.filled(7, 0));
      acc[0] += bandToLinear(b.delta, fromBels: asBels);
      acc[1] += bandToLinear(b.theta, fromBels: asBels);
      acc[2] += bandToLinear(b.alpha, fromBels: asBels);
      acc[3] += bandToLinear(b.beta, fromBels: asBels);
      acc[4] += bandToLinear(b.gamma, fromBels: asBels);
      acc[5] += b.lineNoise;
      acc[6] += 1;
    }
  }
  final secs = sums.keys.toList()..sort();
  final frames = <ffi.ComputedFrame>[];
  for (final sec in secs) {
    final bySec = sums[sec]!;
    final bands = <Float32List>[];
    final lineNoise = Float32List(channelCount);
    for (var e = 0; e < channelCount; e++) {
      final acc = bySec[e];
      if (acc == null) {
        bands.add(Float32List(5));
        continue;
      }
      final n = acc[6];
      bands.add(Float32List.fromList([for (var i = 0; i < 5; i++) acc[i] / n]));
      lineNoise[e] = acc[5] / n;
    }
    frames.add(
      ffi.ComputedFrame(
        t: sec.toDouble(),
        bands: bands,
        lineNoise: lineNoise,
        signalQuality: Uint8List(channelCount),
        guardrail: const ffi.GuardrailInfo(
          sleepDir: 0,
          clarity: 0,
          warning: false,
          delta: 0,
        ),
        feedback: const ffi.FeedbackInfo(
          ratio: 0,
          threshold: 0,
          inTarget: false,
          pct: 0,
        ),
        gestures: const [],
      ),
    );
  }
  return frames;
}
