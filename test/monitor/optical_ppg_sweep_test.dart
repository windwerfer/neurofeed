import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/cache/optical_cache.dart';
import 'package:neurofeed/src/monitor/panes/optical_ppg_pane.dart';

void main() {
  test('ppgSweepSlot wraps inside the fixed window', () {
    const window = 10.0;
    final n = (window * OpticalCache.ppgSampleRate).round();
    expect(ppgSweepSlot(elapsed: 0, windowSeconds: window), 0);
    expect(
      ppgSweepSlot(elapsed: window, windowSeconds: window),
      0,
    );
    expect(
      ppgSweepSlot(elapsed: window + 1 / OpticalCache.ppgSampleRate, windowSeconds: window),
      1,
    );
    expect(
      ppgSweepSlot(elapsed: 25.5, windowSeconds: window),
      lessThan(n),
    );
  });

  test('ppgSweepCursorFraction is in 0..1 and moves with newest', () {
    const window = 10.0;
    final a = ppgSweepCursorFraction(newestElapsed: 10, windowSeconds: window);
    final b = ppgSweepCursorFraction(newestElapsed: 10.5, windowSeconds: window);
    expect(a, inInclusiveRange(0.0, 1.0));
    expect(b, inInclusiveRange(0.0, 1.0));
    expect(a, isNot(b));
  });
}
