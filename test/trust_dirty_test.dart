import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/feedback/feature_bus.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/gate_electrodes.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/reward_lane.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class _Out implements RewardOutput {
  int samples = 0;
  double lastPercentile = -1;
  bool lastInTarget = false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onSample({required double percentile, required bool inTarget}) {
    samples++;
    lastPercentile = percentile;
    lastInTarget = inTarget;
  }

  @override
  void setMuffle(bool on) {}
}

class _GuardOut implements GuardOutput {
  int calls = 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onGuard({required bool active, required double intensity}) {
    calls++;
  }
}

RewardLane _lane(RatioEngine engine, RewardOutput out) {
  final lane = RewardLane(
    engine: engine,
    output: out,
    onStats: (_) {},
    onComputedFeedback:
        ({
          required ratio,
          required threshold,
          required inTarget,
          required inTargetPct,
        }) {},
    onThresholdChanged: () {},
  );
  lane.configure(
    hasReward: true,
    featureId: 'band.atr',
    inhibit: const [],
    electrodeNames: museGateElectrodeNames,
    montageNames: museMontageNames,
  );
  engine
    ..addBaselineSample(1.0)
    ..addBaselineSample(1.5)
    ..computeThreshold();
  return lane;
}

BandsDto _pad(int electrode) => BandsDto(
  electrode: electrode,
  timestamp: 0,
  delta: 1,
  theta: 1,
  alpha: 2,
  beta: 0.1,
  gamma: 0.1,
  lineNoiseRatio: 0,
);

const _clean = RewardTick(
  phase: FeedbackPhase.playing,
  collectingBaseline: false,
  sampleIsClean: true,
  quality: [100, 100, 100, 100],
);

const _dirty = RewardTick(
  phase: FeedbackPhase.playing,
  collectingBaseline: false,
  sampleIsClean: false,
  quality: [100, 100, 100, 100],
  dirtyReason: TrustDirtyReason.movement,
);

void main() {
  test(
    'dirty is dotted (plot holds last clean) and skips recordEpoch',
    () async {
      final out = _Out();
      final engine = RatioEngine(epochWindow: const Duration(milliseconds: 20));
      final lane = _lane(engine, out);
      lane.onBands(_pad(1));
      lane.onBands(_pad(2));
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
        _dirty,
      );
      expect(out.samples, 0);
      expect(lane.lastDirty, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 1, value: 4.0),
        _dirty,
      );
      expect(engine.successRate, isNull);

      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 2, value: 4.0),
        _clean,
      );
      expect(out.samples, 1);
      expect(out.lastPercentile, 100);

      final trace = TrustTrace();
      trace.pushReward(
        TrustRewardSample(
          t: 0,
          native: 4,
          percentile: 100,
          thresholdPercentile: 40,
          inTarget: true,
          heldBack: false,
          inhibitTags: const [],
          clean: true,
        ),
      );
      trace.pushReward(
        TrustRewardSample(
          t: 1,
          native: 0.5,
          percentile: 0,
          thresholdPercentile: 40,
          inTarget: false,
          heldBack: false,
          inhibitTags: const [],
          clean: false,
          dirtyReason: TrustDirtyReason.movement,
        ),
      );
      expect(trace.reward.last.plotPercentile, 100);
    },
  );

  test('dirty does not advance rain/music percentile (no onSample)', () {
    final out = _Out();
    final engine = RatioEngine();
    final lane = _lane(engine, out);
    lane.onBands(_pad(1));
    lane.onBands(_pad(2));
    lane.onFeature(
      const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
      _clean,
    );
    expect(out.lastPercentile, 100);
    lane.onFeature(
      const FeatureSample(id: 'band.atr', t: 1, value: 0.2),
      _dirty,
    );
    expect(out.lastPercentile, 100);
    expect(out.samples, 1);
  });

  test('dirty skips guard evaluateWarning and holds warningActive', () {
    final reward = _Out();
    final guard = _GuardOut();
    final lane = GuardLane(guardOutput: guard, rewardOutput: reward)
      ..bandMath = true
      ..enabled = true
      ..featureId = 'band.delta'
      ..threshold = 0.5
      ..lastDelta = 0.9;
    GuardTick over() => GuardTick(
      phase: FeedbackPhase.playing,
      collectingBaseline: false,
      collectionEyes: null,
      muffleReward: false,
      sessionStartAt: null,
      sampleIsClean: true,
      writeWarningMetadata:
          ({
            required sleepDir,
            required delta,
            required threshold,
            required bandMath,
          }) {},
      updateComputed:
          ({
            required sleepDir,
            required clarity,
            required delta,
            required warning,
            threshold,
          }) {},
    );
    GuardTick dirtyTick() => GuardTick(
      phase: FeedbackPhase.playing,
      collectingBaseline: false,
      collectionEyes: null,
      muffleReward: false,
      sessionStartAt: null,
      sampleIsClean: false,
      writeWarningMetadata:
          ({
            required sleepDir,
            required delta,
            required threshold,
            required bandMath,
          }) {},
      updateComputed:
          ({
            required sleepDir,
            required clarity,
            required delta,
            required warning,
            threshold,
          }) {},
    );
    expect(
      lane.onFeature(
        const FeatureSample(id: 'band.delta', t: 0, value: 0.9),
        over(),
      ),
      isTrue,
    );
    expect(lane.warningActive, isTrue);
    final calls = guard.calls;
    lane.lastDelta = 0.1;
    expect(
      lane.onFeature(
        const FeatureSample(id: 'band.delta', t: 1, value: 0.1),
        dirtyTick(),
      ),
      isTrue,
    );
    expect(lane.warningActive, isTrue);
    expect(guard.calls, calls);
  });

  test('held back: above line + inhibit fail; below is not held back', () {
    final out = _Out();
    final engine = RatioEngine();
    final lane = RewardLane(
      engine: engine,
      output: out,
      onStats: (_) {},
      onComputedFeedback:
          ({
            required ratio,
            required threshold,
            required inTarget,
            required inTargetPct,
          }) {},
      onThresholdChanged: () {},
    );
    lane.configure(
      hasReward: true,
      featureId: 'band.atr',
      inhibit: const [BetaCeiling(0.01)],
      electrodeNames: museGateElectrodeNames,
      montageNames: museMontageNames,
    );
    engine
      ..addBaselineSample(1.0)
      ..addBaselineSample(1.5)
      ..computeThreshold();
    lane.onBands(_pad(1));
    lane.onBands(_pad(2));
    lane.onFeature(
      const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
      _clean,
    );
    expect(lane.lastHeldBack, isTrue);
    expect(lane.lastInhibitTags, ['beta']);
    expect(out.lastInTarget, isFalse);
    expect(out.samples, 1);

    lane.onFeature(
      const FeatureSample(id: 'band.atr', t: 1, value: 0.5),
      _clean,
    );
    expect(lane.lastHeldBack, isFalse);
    expect(lane.lastInTarget, isFalse);
  });
}
