import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/computed_sampler.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart';

void main() {
  test('pause stops timer; resume content clock excludes wall pause', () {
    var now = DateTime.utc(2026, 9, 24, 12, 0, 0);
    final frames = <ComputedFrame>[];
    final sampler = ComputedSampler(
      onFrame: frames.add,
      recordingStart: now,
      now: () => now,
    );

    sampler.emitFrame();
    expect(frames.single.t, closeTo(0.0, 1e-9));

    sampler.pause();
    now = now.add(const Duration(seconds: 10));
    // Timer is stopped — production path does not emit during pause.
    sampler.resume();
    frames.clear();
    sampler.emitFrame();
    expect(frames.single.t, closeTo(0.0, 0.05));
    expect(sampler.pauseAccumulatedSeconds, closeTo(10.0, 0.05));

    now = now.add(const Duration(seconds: 5));
    sampler.emitFrame();
    expect(frames.last.t, closeTo(5.0, 0.05));
  });

  test('pause annotation JSON shape', () {
    const a = SessionAnnotation(onset: 200, duration: 10, type: 'pause');
    expect(a.toJson(), {'onset': 200.0, 'duration': 10.0, 'type': 'pause'});
  });
}
