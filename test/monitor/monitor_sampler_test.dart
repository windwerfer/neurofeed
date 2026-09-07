import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/recording/monitor_sampler.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/session_v5/computed_frame.dart';

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
}
