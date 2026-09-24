import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/computed_sampler.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/gate_electrodes.dart';
import 'package:neurofeed/src/feedback/reward_lane.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/monitor/recording/monitor_sampler.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart';

void main() {
  test('dirty playing second writes clean:false + finite dirty percentile', () {
    final frames = <ComputedFrame>[];
    final start = DateTime.utc(2026, 9, 24);
    final sampler = ComputedSampler(
      onFrame: frames.add,
      recordingStart: start,
      now: () => start.add(const Duration(seconds: 1)),
    );

    final engine = RatioEngine();
    engine
      ..addBaselineSample(1.0)
      ..addBaselineSample(1.5)
      ..addBaselineSample(2.0)
      ..computeThreshold();

    Map<String, Object?>? lastFb;
    final lane = RewardLane(
      engine: engine,
      output: const NoneRewardOutput(),
      onStats: (_) {},
      onComputedFeedback: ({
        required ratio,
        required threshold,
        required inTarget,
        required inTargetPct,
        percentile,
        thresholdPercentile,
        heldBack,
        inhibitTags,
        clean,
        dirtyReason,
        betaRel,
        deltaRel,
      }) {
        lastFb = {
          'inTarget': inTarget,
          'percentile': percentile,
          'clean': clean,
          'dirtyReason': dirtyReason,
        };
        sampler.updateFeedback(
          ratio: ratio,
          threshold: threshold,
          inTarget: inTarget,
          inTargetPct: inTargetPct,
          percentile: percentile,
          thresholdPercentile: thresholdPercentile,
          heldBack: heldBack,
          inhibitTags: inhibitTags,
          clean: clean,
          dirtyReason: dirtyReason,
          betaRel: betaRel,
          deltaRel: deltaRel,
        );
      },
      onThresholdChanged: () {},
    );
    lane.configure(
      hasReward: true,
      featureId: 'band.atr',
      inhibit: const [],
      electrodeNames: museGateElectrodeNames,
      montageNames: museMontageNames,
    );
    for (final e in [0, 1, 2, 3]) {
      lane.onBands(
        BandsDto(
          electrode: e,
          timestamp: 0,
          delta: 1,
          theta: 1,
          alpha: 2,
          beta: 0.1,
          gamma: 0.1,
          lineNoiseRatio: 0,
        ),
      );
    }

    lane.onFeature(
      const FeatureSample(id: 'band.atr', t: 0, value: 1.2),
      const RewardTick(
        phase: FeedbackPhase.playing,
        collectingBaseline: false,
        sampleIsClean: false,
        quality: [100, 100, 100, 100],
        dirtyReason: TrustDirtyReason.movement,
      ),
    );

    expect(lastFb, isNotNull);
    expect(lastFb!['clean'], isFalse);
    expect(lastFb!['inTarget'], isFalse);
    expect(lastFb!['dirtyReason'], 'movement');
    expect(lastFb!['percentile'], isA<double>());
    expect((lastFb!['percentile'] as double).isFinite, isTrue);

    sampler.emitFrame();
    final fb = frames.single.feedback;
    expect(fb.clean, isFalse);
    expect(fb.inTarget, isFalse);
    expect(fb.percentile, isNotNull);
    expect(fb.percentile!.isFinite, isTrue);
    expect(fb.dirtyReason, 'movement');
    final json = frames.single.toJson()['feedback'] as Map<String, dynamic>;
    expect(json.containsKey('plotPercentile'), isFalse);
  });

  test('MonitorSampler omits NEW Trust extras', () {
    final frames = <ComputedFrame>[];
    final startMs = DateTime.utc(2026, 9, 24).millisecondsSinceEpoch;
    final mon = MonitorSampler(
      channelCount: 4,
      captureStartedAtMs: startMs,
      onFrame: frames.add,
      nowMs: () => startMs + 1000,
    );
    mon.emitFrame();
    final fb = frames.single.feedback;
    final gr = frames.single.guardrail;
    expect(fb.percentile, isNull);
    expect(fb.clean, isNull);
    expect(fb.heldBack, isNull);
    expect(gr.featurePercentile, isNull);
    expect(gr.clean, isNull);
    final json = frames.single.toJson();
    final fbJson = json['feedback'] as Map<String, dynamic>;
    final grJson = json['guardrail'] as Map<String, dynamic>;
    expect(fbJson.containsKey('percentile'), isFalse);
    expect(fbJson.containsKey('clean'), isFalse);
    expect(grJson.containsKey('featurePercentile'), isFalse);
    expect(grJson.containsKey('clean'), isFalse);
  });
}
