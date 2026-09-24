import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/session_v5/stats_assemble.dart';

Float32List _f32(List<double> v) => Float32List.fromList(v);

ffi.ComputedFrame _frame({
  required double t,
  double? pulse,
  double? spo2,
  double? movement,
  double? peakHz,
  double? peakPower,
  List<int> quality = const [90, 90, 90, 90],
}) {
  return ffi.ComputedFrame(
    t: t,
    bands: [
      for (var i = 0; i < 4; i++) _f32([1.0, 2.0, 3.0, 4.0, 5.0]),
    ],
    pulse: pulse,
    movement: movement,
    peakAlpha: peakHz == null
        ? null
        : ffi.PeakAlphaInfo(freq: peakHz, power: peakPower ?? 1.0),
    spo2: spo2,
    lineNoise: _f32(const [0.1, 0.1, 0.1, 0.1]),
    signalQuality: Uint8List.fromList(quality),
    guardrail: const ffi.GuardrailInfo(
      sleepDir: 0.1,
      clarity: 0.5,
      warning: false,
      delta: 1.0,
    ),
    feedback: const ffi.FeedbackInfo(
      ratio: 1.0,
      threshold: 0.5,
      inTarget: true,
      pct: 50,
    ),
    gestures: const [],
  );
}

void main() {
  test('assembleAnnotations maps gestures to snake_case duration 0', () {
    final anns = assembleAnnotations(
      intervals: const [
        SessionAnnotation(onset: 200, duration: 10, type: 'pause'),
      ],
      gestures: const [
        GestureMarker(type: GestureType.doubleBlink, offsetSeconds: 45),
        GestureMarker(type: GestureType.doubleClench, offsetSeconds: 312),
      ],
    );
    expect(anns.map((a) => a.type).toList(), [
      'double_blink',
      'pause',
      'double_jaw_clench',
    ]);
    expect(anns.first.duration, 0);
  });

  test('mergeAdjacentIntervalAnnotations merges abutting pauses', () {
    final merged = mergeAdjacentIntervalAnnotations(const [
      SessionAnnotation(onset: 10, duration: 5, type: 'pause'),
      SessionAnnotation(onset: 15, duration: 3, type: 'pause'),
      SessionAnnotation(onset: 20, duration: 0, type: 'double_blink'),
    ]);
    expect(merged, hasLength(2));
    expect(merged.first.duration, 8);
    expect(merged.last.type, 'double_blink');
  });

  test('assembleBaseStats fills hr/spo2 min/max, peakAlpha.meanHz, stillness, quality', () {
    final frames = [
      _frame(t: 1, pulse: 60, spo2: 97, movement: 0.01, peakHz: 10, peakPower: 2),
      _frame(t: 2, pulse: 80, spo2: 99, movement: 0.2, peakHz: 11, peakPower: 5),
      _frame(
        t: 3,
        pulse: 70,
        spo2: 98,
        movement: 0.02,
        peakHz: 10.5,
        peakPower: 3,
        quality: const [50, 50, 50, 50],
      ),
    ];
    final stats = assembleBaseStats(frames: frames)!;
    final hr = stats['hr'] as Map;
    expect(hr['mean'], closeTo(70, 0.01));
    expect(hr['min'], 60);
    expect(hr['max'], 80);
    final spo2 = stats['spo2'] as Map;
    expect(spo2['min'], 97);
    expect(spo2['max'], 99);
    final pa = stats['peakAlpha'] as Map;
    expect(pa['meanHz'], closeTo(10.5, 0.01));
    expect(pa['maxPowerHz'], 11);
    expect(pa['maxPower'], 5);
    final mov = stats['movement'] as Map;
    expect(mov['stillnessPct'], closeTo(2 / 3 * 100, 0.1));
    final q = stats['quality'] as Map;
    expect(q['pctGood'], closeTo(2 / 3 * 100, 0.1));
  });

  test('annotationSecondsFrom sums interval types only', () {
    final secs = annotationSecondsFrom(const [
      SessionAnnotation(onset: 0, duration: 10, type: 'pause'),
      SessionAnnotation(onset: 20, duration: 5, type: 'bad_quality'),
      SessionAnnotation(onset: 30, duration: 0, type: 'double_blink'),
    ]);
    expect(secs, {'pause': 10.0, 'bad_quality': 5.0});
  });
}
