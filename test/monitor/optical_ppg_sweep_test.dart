import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/charts/eeg_data_source.dart';
import 'package:neurofeed/src/monitor/cache/optical_cache.dart';
import 'package:neurofeed/src/monitor/panes/optical_ppg_pane.dart';

List<ChartSample> _ir({
  required int seconds,
  required double Function(double t) wave,
}) {
  final n = seconds * OpticalCache.ppgSampleRate.round();
  return [
    for (var i = 0; i < n; i++)
      ChartSample(
        i / OpticalCache.ppgSampleRate,
        wave(i / OpticalCache.ppgSampleRate),
      ),
  ];
}

void main() {
  test('ppg scale uses the screen plus 3s and pads the span', () {
    final scale = ppgDisplayScale(
      samples: [ChartSample(1, 0), ChartSample(5, 100), ChartSample(8, 40)],
      visStart: 6,
      visEnd: 10,
    );
    expect(scale, isNotNull);
    expect(scale!.min, 25);
    expect(scale.max, 115);

    final tight = ppgDisplayScale(
      samples: [ChartSample(1, 0), ChartSample(7, 20), ChartSample(8, 40)],
      visStart: 6,
      visEnd: 10,
    );
    expect(tight!.min, 15);
    expect(tight.max, 45);
  });

  test('pulse display drops slow drift and keeps the second peak', () {
    final filtered = ppgPulseDisplay(
      _ir(
        seconds: 12,
        wave: (t) =>
            200000 +
            16000 * math.sin(2 * math.pi * 0.2 * t) +
            2000 * math.sin(2 * math.pi * 1.2 * t),
      ),
    );
    final tail = [
      for (final s in filtered)
        if (s.t >= 8) s.v,
    ];
    var lo = tail.first;
    var hi = tail.first;
    for (final v in tail) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    expect(hi - lo, lessThan(9000));
    expect(hi - lo, greaterThan(2000));

    double beat(double phase) {
      final sys = math.exp(-math.pow((phase - 0.18) / 0.08, 2));
      final notch = 0.4 * math.exp(-math.pow((phase - 0.45) / 0.05, 2));
      return sys + notch;
    }

    final shaped = ppgPulseDisplay(
      _ir(
        seconds: 12,
        wave: (t) {
          final period = 1 / 1.1;
          final phase = (t % period) / period;
          return 180000 +
              12000 * math.sin(2 * math.pi * 0.2 * t) +
              4000 * beat(phase);
        },
      ),
    );
    final cycle = [
      for (final s in shaped)
        if (s.t >= 9.0 && s.t < 9.0 + 1 / 1.1) s.v,
    ];
    final peaks = <double>[];
    for (var i = 1; i < cycle.length - 1; i++) {
      if (cycle[i] > cycle[i - 1] && cycle[i] >= cycle[i + 1]) {
        peaks.add(cycle[i]);
      }
    }
    expect(peaks.length, greaterThanOrEqualTo(2));
    final ordered = [...peaks]..sort();
    expect(ordered.last, greaterThan(ordered[ordered.length - 2]));
  });

  test('ppgSweepSlot wraps inside the fixed window', () {
    const window = 10.0;
    final n = (window * OpticalCache.ppgSampleRate).round();
    expect(ppgSweepSlot(elapsed: 0, windowSeconds: window), 0);
    expect(ppgSweepSlot(elapsed: window, windowSeconds: window), 0);
    expect(
      ppgSweepSlot(
        elapsed: window + 1 / OpticalCache.ppgSampleRate,
        windowSeconds: window,
      ),
      1,
    );
    expect(ppgSweepSlot(elapsed: 25.5, windowSeconds: window), lessThan(n));
  });

  test('sweep head stays on the last PPG sample when newest jumps ahead', () {
    const window = 10.0;
    final rate = OpticalCache.ppgSampleRate;
    final samples = [
      for (var i = 0; i < 64; i++) ChartSample(100.0 + i / rate, i.toDouble()),
    ];
    final last = samples.last.t;
    final ahead = last + 0.04;
    final head = ppgSweepHeadElapsed(newestElapsed: ahead, samples: samples);

    expect(head, last);
    expect(
      ppgSweepSlot(elapsed: head, windowSeconds: window),
      ppgSweepSlot(elapsed: last, windowSeconds: window),
    );
    expect(
      ppgSweepSlot(elapsed: ahead, windowSeconds: window),
      isNot(ppgSweepSlot(elapsed: last, windowSeconds: window)),
    );
  });

  test('ppgSweepCursorFraction is in 0..1 and moves with newest', () {
    const window = 10.0;
    final a = ppgSweepCursorFraction(newestElapsed: 10, windowSeconds: window);
    final b = ppgSweepCursorFraction(
      newestElapsed: 10.5,
      windowSeconds: window,
    );
    expect(a, inInclusiveRange(0.0, 1.0));
    expect(b, inInclusiveRange(0.0, 1.0));
    expect(a, isNot(b));
  });
}
