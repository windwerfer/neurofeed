import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/panes/time_series_pane.dart';
import 'package:neurofeed/src/monitor/views/recording_dashboard.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';

ComputedFrame _frame(double t, List<List<double>> bands) {
  return ComputedFrame(
    t: t,
    bands: [for (final b in bands) Float32List.fromList(b)],
    lineNoise: Float32List(bands.length),
    signalQuality: Uint8List(bands.length),
    guardrail: const GuardrailInfo(
      sleepDir: 0,
      clarity: 0,
      warning: false,
      delta: 0,
    ),
    feedback: const FeedbackInfo(
      ratio: 0,
      threshold: 0,
      inTarget: false,
      pct: 0,
    ),
    gestures: const [],
  );
}

void main() {
  test('bandSeriesFromComputed averages selected electrodes in dB', () {
    // linear 100 → ~20 dB; linear 10000 → 40 dB; mean of one electrode.
    final frames = [
      _frame(1.0, [
        [100, 100, 100, 100, 100],
        [10000, 10000, 10000, 10000, 10000],
      ]),
      _frame(2.0, [
        [100, 100, 100, 100, 100],
        [10000, 10000, 10000, 10000, 10000],
      ]),
    ];
    final series = bandSeriesFromComputed(
      frames: frames,
      electrodes: const [0],
      startElapsed: 0,
      endElapsed: 10,
    );
    expect(series.length, 5);
    expect(series[0].length, 2);
    expect(series[0][0].elapsed, closeTo(1.0, 1e-9));
    expect(series[0][0].db, closeTo(linearToDb(100), 1e-6));
    expect(series[0][1].db, closeTo(linearToDb(100), 1e-6));

    final both = bandSeriesFromComputed(
      frames: frames,
      electrodes: const [0, 1],
      startElapsed: 0,
      endElapsed: 10,
    );
    final expected =
        (linearToDb(100) + linearToDb(10000)) / 2;
    expect(both[2][0].db, closeTo(expected, 1e-6));
  });

  test('bandSeriesFromComputed skips frames outside window', () {
    final frames = [
      _frame(0.0, [
        [100, 100, 100, 100, 100],
      ]),
      _frame(50.0, [
        [100, 100, 100, 100, 100],
      ]),
    ];
    final series = bandSeriesFromComputed(
      frames: frames,
      electrodes: const [0],
      startElapsed: 40,
      endElapsed: 60,
    );
    expect(series[0].length, 1);
    expect(series[0][0].elapsed, closeTo(50.0, 1e-9));
  });
}
