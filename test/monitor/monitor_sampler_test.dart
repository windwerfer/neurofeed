import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/recording/monitor_sampler.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart';

void main() {
  test(
    'N-length arrays, t elapsed from capture start, zeroed guard/feedback',
    () {
      const start = 1_000_000;
      var now = start;
      ComputedFrame? last;
      final sampler = MonitorSampler(
        channelCount: 8,
        captureStartedAtMs: start,
        nowMs: () => now,
        onFrame: (f) => last = f,
      );

      sampler.updateBands(
        7,
        const BandsDto(
          electrode: 7,
          timestamp: start + 500,
          delta: 1,
          theta: 2,
          alpha: 3,
          beta: 4,
          gamma: 5,
          signalQuality: 0,
          lineNoiseRatio: 0.1,
        ),
      );
      sampler.updateGestures(
        const GestureDto(
          timestamp: start + 500,
          blinkCount: 1,
          clench: true,
          eye: 1,
        ),
      );

      now = start + 2500;
      sampler.emitFrame();

      expect(last, isNotNull);
      expect(last!.t, closeTo(2.5, 0.001));
      expect(last!.bands, hasLength(8));
      expect(last!.bands[7], [1, 2, 3, 4, 5]);
      expect(last!.lineNoise, hasLength(8));
      expect(last!.lineNoise[7], closeTo(0.1, 1e-9));
      expect(last!.signalQuality, hasLength(8));
      expect(last!.guardrail.sleepDir, 0);
      expect(last!.guardrail.clarity, 0);
      expect(last!.guardrail.warning, isFalse);
      expect(last!.guardrail.delta, 0);
      expect(last!.feedback.ratio, 0);
      expect(last!.feedback.threshold, 0);
      expect(last!.feedback.inTarget, isFalse);
      expect(last!.feedback.pct, 0);
      expect(last!.gestures, ['blink', 'clench', 'eyeUp']);
    },
  );

  test('Muse-4 length', () {
    ComputedFrame? last;
    final sampler = MonitorSampler(
      channelCount: 4,
      captureStartedAtMs: 0,
      nowMs: () => 0,
      onFrame: (f) => last = f,
    );
    sampler.emitFrame();
    expect(last!.bands, hasLength(4));
    expect(last!.lineNoise, hasLength(4));
    expect(last!.signalQuality, hasLength(4));
  });

  test('averages all band updates within the second; repeats last if none', () {
    ComputedFrame? last;
    final sampler = MonitorSampler(
      channelCount: 4,
      captureStartedAtMs: 0,
      nowMs: () => 0,
      onFrame: (f) => last = f,
    );
    BandsDto b(double v, double noise) => BandsDto(
      electrode: 1,
      timestamp: 0,
      delta: v,
      theta: v,
      alpha: v,
      beta: v,
      gamma: v,
      signalQuality: 0,
      lineNoiseRatio: noise,
    );
    sampler.updateBands(1, b(1, 0.1));
    sampler.updateBands(1, b(2, 0.2));
    sampler.updateBands(1, b(6, 0.3));
    sampler.emitFrame();
    expect(last!.bands[1], [3, 3, 3, 3, 3]);
    expect(last!.lineNoise[1], closeTo(0.2, 1e-9));
    expect(last!.bands[0], [0, 0, 0, 0, 0]);
    sampler.emitFrame();
    expect(last!.bands[1], [3, 3, 3, 3, 3]);
    sampler.updateBands(1, b(10, 0.5));
    sampler.emitFrame();
    expect(last!.bands[1], [10, 10, 10, 10, 10]);
  });
}
