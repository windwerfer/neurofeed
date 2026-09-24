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

/// Build 1 Hz FFI [ComputedFrame]s from absolute band rows.
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

  // Last-of-second map → one frame per integer second that has bands.
  final bySec = <int, BandInstant>{};
  for (final row in bandRows) {
    final sec = (row.timestampMs / 1000.0).floor();
    bySec[sec] = row;
  }
  final secs = bySec.keys.toList()..sort();
  final frames = <ffi.ComputedFrame>[];
  for (final sec in secs) {
    final row = bySec[sec]!;
    final bands = <Float32List>[];
    final lineNoise = Float32List(channelCount);
    for (var e = 0; e < channelCount; e++) {
      final b = row.byElectrode[e];
      if (b == null) {
        bands.add(Float32List(5));
        continue;
      }
      bands.add(
        Float32List.fromList([
          bandToLinear(b.delta, fromBels: asBels),
          bandToLinear(b.theta, fromBels: asBels),
          bandToLinear(b.alpha, fromBels: asBels),
          bandToLinear(b.beta, fromBels: asBels),
          bandToLinear(b.gamma, fromBels: asBels),
        ]),
      );
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
