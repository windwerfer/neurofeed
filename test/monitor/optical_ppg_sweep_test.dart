import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/charts/eeg_data_source.dart';
import 'package:neurofeed/src/monitor/cache/optical_cache.dart';
import 'package:neurofeed/src/monitor/panes/optical_ppg_pane.dart';

void main() {
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
