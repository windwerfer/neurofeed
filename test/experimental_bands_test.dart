import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/session_v5/stats_assemble.dart';

Float32List _f32(List<double> v) => Float32List.fromList(v);

ffi.ComputedFrame _frame({
  required double t,
  required List<List<double>> bands,
  List<int> quality = const [90, 90, 90, 90],
}) {
  return ffi.ComputedFrame(
    t: t,
    bands: [for (final b in bands) _f32(b)],
    pulse: null,
    movement: null,
    peakAlpha: null,
    spo2: null,
    lineNoise: _f32(const [0, 0, 0, 0]),
    signalQuality: Uint8List.fromList(quality),
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
  );
}

/// Per channel [δ,θ,α,β,γ]. AF7 α=e, AF8 α=e^0.2 → FAA = 0.2
List<List<double>> _symBands({double af7A = 1.0, double af8A = 1.0}) {
  return [
    [1, 1, 2, 1, 1], // TP9
    [1, 1, af7A, 1, 1], // AF7
    [1, 1, af8A, 1, 1], // AF8
    [1, 1, 2, 1, 1], // TP10
  ];
}

void main() {
  test('omit experimental when fewer than 30 usable seconds', () {
    final frames = [
      for (var i = 0; i < 10; i++)
        _frame(t: i.toDouble(), bands: _symBands()),
    ];
    expect(assembleExperimentalBands(frames), isNull);
  });

  test('Must keys: meanAlphaAbs, meanAlphaTheta, frontalAlphaAsym, crossChannelAlphaVar', () {
    final af7 = math.exp(1.0);
    final af8 = math.exp(1.2); // ln(af8)-ln(af7) = 0.2
    final frames = [
      for (var i = 0; i < 30; i++)
        _frame(
          t: i.toDouble(),
          bands: _symBands(af7A: af7, af8A: af8),
        ),
    ];
    final nest = assembleExperimentalBands(frames, includeSensible: false, includeCool: false)!;
    final bands = (nest['experimental'] as Map)['bands'] as Map;
    expect(bands.containsKey('meanAlphaAbs'), isTrue);
    expect(bands.containsKey('meanAlphaTheta'), isTrue);
    expect(bands['frontalAlphaAsym'], closeTo(0.2, 1e-6));
    expect(bands.containsKey('crossChannelAlphaVar'), isTrue);
    expect(bands.containsKey('meanAlphaRel'), isFalse);
  });

  test('Sensible/Cool keys included by default', () {
    final frames = [
      for (var i = 0; i < 30; i++)
        _frame(t: i.toDouble(), bands: _symBands()),
    ];
    final bands =
        ((assembleExperimentalBands(frames)!['experimental'] as Map)['bands']
            as Map);
    expect(bands.containsKey('meanAlphaRel'), isTrue);
    expect(bands.containsKey('meanBetaTheta'), isTrue);
    expect(bands.containsKey('meanThetaAbs'), isTrue);
    expect(bands.containsKey('meanBetaAbs'), isTrue);
  });

  test('unusable seconds excluded from gate', () {
    final frames = [
      for (var i = 0; i < 30; i++)
        _frame(
          t: i.toDouble(),
          bands: _symBands(),
          quality: const [10, 10, 10, 10],
        ),
    ];
    expect(assembleExperimentalBands(frames), isNull);
  });
}
