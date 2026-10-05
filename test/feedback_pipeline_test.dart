import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/calibration_clips.dart';
import 'package:neurofeed/src/audio/guard_output.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/reward_lane.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/rust/api/features.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

class RecordingRewardOutput implements RewardOutput {
  int samples = 0;
  double lastPercentile = 0;
  bool lastInTarget = false;
  bool? muffle;

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
  void setMuffle(bool on) => muffle = on;
}

class RecordingGuardOutput implements GuardOutput {
  int calls = 0;
  bool? lastActive;
  double? lastIntensity;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onGuard({required bool active, required double intensity}) {
    calls++;
    lastActive = active;
    lastIntensity = intensity;
  }
}

const _museMontage = ['TP9', 'AF7', 'AF8', 'TP10'];
const _museFrontal = ['AF7', 'AF8'];

void main() {
  group('FeatureBus', () {
    test('publish FeatureDto and of(id) delivers the sample', () {
      final bus = FeatureBus();
      addTearDown(bus.dispose);
      FeatureSample? got;
      bus.of('band.atr').listen((s) => got = s);
      bus.publish(
        MuseEventDto.feature(
          const FeatureDto(id: 'band.atr', timestamp: 1, value: 2.5),
        ),
      );
      expect(got, isNotNull);
      expect(got!.id, 'band.atr');
      expect(got!.value, 2.5);
      expect(bus.latest('band.atr')?.value, 2.5);
    });

    test('non-Feature events are ignored', () {
      final bus = FeatureBus();
      addTearDown(bus.dispose);
      var n = 0;
      bus.of('band.atr').listen((_) => n++);
      bus.publish(const MuseEventDto.disconnected());
      expect(n, 0);
      expect(bus.latest('band.atr'), isNull);
    });
  });

  group('RatioEngine wall-clock window', () {
    test('epochWindowSeconds is 75', () {
      expect(RatioEngine.epochWindowSeconds, 75);
    });

    test('successRate stays null until the wall-clock window fills', () async {
      final engine = RatioEngine(epochWindow: const Duration(milliseconds: 80));
      engine.addBaselineSample(1.0);
      engine.addBaselineSample(2.0);
      engine.computeThreshold();
      engine.recordEpoch(true);
      expect(engine.successRate, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(engine.successRate, 1.0);
    });
  });

  group('RelativeBandAggregator', () {
    test('averages named pads and autodrops by quality', () {
      final agg = RelativeBandAggregator([
        'AF7',
        'AF8',
      ], montageNames: _museMontage);
      agg.update(
        const BandsDto(
          electrode: 1,
          timestamp: 0,
          delta: 1,
          theta: 1,
          alpha: 2,
          beta: 1,
          gamma: 1,
          signalQuality: 0,
          lineNoiseRatio: 0,
        ),
      );
      agg.update(
        const BandsDto(
          electrode: 2,
          timestamp: 0,
          delta: 1,
          theta: 1,
          alpha: 2,
          beta: 1,
          gamma: 1,
          signalQuality: 0,
          lineNoiseRatio: 0,
        ),
      );
      expect(agg.evaluate([100, 100, 100, 100]), isNotNull);
      expect(agg.evaluate(null), isNull);
      expect(agg.evaluate([100, 10, 10, 100]), isNull);
      final one = agg.evaluate([100, 100, 10, 100]);
      expect(one, isNotNull);
      expect(one!.alphaRel, closeTo(2 / 6, 1e-9));
    });
  });

  group('RewardLane', () {
    RewardLane laneWith(
      RatioEngine engine, {
      required RewardOutput output,
      void Function(double value)? onStats,
      List<TargetCondition> inhibit = const [],
      bool seedBaseline = true,
    }) {
      final lane = RewardLane(
        engine: engine,
        output: output,
        onStats: onStats ?? (_) {},
        onComputedFeedback:
            ({
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
            }) {},
        onThresholdChanged: () {},
      );
      lane.configure(
        hasReward: true,
        featureId: 'band.atr',
        inhibit: inhibit,
        electrodeNames: _museFrontal,
        montageNames: _museMontage,
      );
      if (seedBaseline) {
        engine
          ..addBaselineSample(1.0)
          ..addBaselineSample(1.5)
          ..computeThreshold();
      }
      return lane;
    }

    BandsDto pad(int electrode) => BandsDto(
      electrode: electrode,
      timestamp: 0,
      delta: 1,
      theta: 1,
      alpha: 2,
      beta: 0.1,
      gamma: 0.1,
      signalQuality: 0,
      lineNoiseRatio: 0,
    );

    test('calibration stores a sample only for an accepted baseline frame', () {
      final engine = RatioEngine();
      final lane = laneWith(
        engine,
        output: const NoneRewardOutput(),
        seedBaseline: false,
      );
      const sample = FeatureSample(id: 'band.atr', t: 0, value: 1.25);
      const keptOut = RewardTick(
        phase: FeedbackPhase.calibrating,
        sampleIsClean: true,
        quality: [90, 90, 90, 90],
      );
      lane.onFeature(sample, keptOut);
      expect(engine.baselineSamples, isEmpty);
      lane.onFeature(
        FeatureSample(id: 'band.atr', t: 0, value: double.nan),
        const RewardTick(
          phase: FeedbackPhase.calibrating,
          sampleIsClean: true,
          acceptBaselineSample: true,
          quality: [90, 90, 90, 90],
        ),
      );
      expect(engine.baselineSamples, isEmpty);
      lane.onFeature(
        sample,
        const RewardTick(
          phase: FeedbackPhase.calibrating,
          sampleIsClean: true,
          acceptBaselineSample: true,
          quality: [90, 90, 90, 90],
        ),
      );
      expect(engine.baselineSamples, [1.25]);
      lane.onFeature(sample, keptOut);
      expect(engine.baselineSamples, [1.25]);
    });

    test('missing relative bands is dirty: no onSample, no recordEpoch', () {
      final out = RecordingRewardOutput();
      final engine = RatioEngine(epochWindow: const Duration(milliseconds: 1));
      final lane = laneWith(engine, output: out);
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 0, value: 3.0),
        const RewardTick(
          phase: FeedbackPhase.playing,
          sampleIsClean: true,
          quality: [100, 100, 100, 100],
        ),
      );
      expect(out.samples, 0);
      expect(lane.lastDirty, isTrue);
      expect(lane.lastDirtyReason, TrustDirtyReason.pads);
      expect(engine.successRate, isNull);
    });

    test('FeatureDto native scalar via onStats; onSample gets percentile', () {
      var lastNative = 0.0;
      final out = RecordingRewardOutput();
      final engine = RatioEngine();
      final lane = laneWith(
        engine,
        output: out,
        onStats: (v) => lastNative = v,
      );
      lane.onBands(pad(1));
      lane.onBands(pad(2));
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
        const RewardTick(
          phase: FeedbackPhase.playing,
          sampleIsClean: true,
          quality: [100, 100, 100, 100],
        ),
      );
      expect(lastNative, 4.0);
      expect(out.samples, 1);
      expect(out.lastInTarget, isTrue);
      expect(out.lastPercentile, 100.0);
    });

    test('wrong feature id is ignored', () {
      final out = RecordingRewardOutput();
      final engine = RatioEngine();
      final lane = laneWith(engine, output: out);
      lane.onBands(pad(1));
      lane.onBands(pad(2));
      lane.onFeature(
        const FeatureSample(id: 'band.tar', t: 0, value: 4.0),
        const RewardTick(
          phase: FeedbackPhase.playing,
          sampleIsClean: true,
          quality: [100, 100, 100, 100],
        ),
      );
      expect(out.samples, 0);
    });

    test('inhibit AND-gates inTarget but still records an epoch', () async {
      final out = RecordingRewardOutput();
      final engine = RatioEngine(epochWindow: const Duration(milliseconds: 20));
      final lane = laneWith(
        engine,
        inhibit: const [BetaCeiling(0.01)],
        output: out,
      );
      lane.onBands(pad(1));
      lane.onBands(pad(2));
      const tick = RewardTick(
        phase: FeedbackPhase.playing,
        sampleIsClean: true,
        quality: [100, 100, 100, 100],
      );
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
        tick,
      );
      expect(out.lastInTarget, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 1, value: 4.0),
        tick,
      );
      expect(engine.successRate, 0.0);
    });
  });

  group('GuardLane outputs', () {
    GuardTick tick({required bool muffleReward}) => GuardTick(
      phase: FeedbackPhase.playing,
      collectionEyes: null,
      muffleReward: muffleReward,
      sessionStartAt: DateTime.now(),
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
            featurePercentile,
            warnOver,
            ceilingOver,
            clean,
            dirtyReason,
          }) {},
    );

    test('over calls onGuard and setMuffle when muffleReward', () {
      final reward = RecordingRewardOutput();
      final guard = RecordingGuardOutput();
      final lane = GuardLane(guardOutput: guard, rewardOutput: reward)
        ..bandMath = false
        ..threshold = 0.5
        ..lastSleepDir = 0.9
        ..lastDelta = 0.1;
      lane.evaluateWarning(tick(muffleReward: true));
      expect(lane.warningActive, isTrue);
      expect(guard.lastActive, isTrue);
      expect(guard.lastIntensity, 1.0);
      expect(reward.muffle, isTrue);
    });

    test('under clears onGuard and un-muffles', () {
      final reward = RecordingRewardOutput();
      final guard = RecordingGuardOutput();
      final lane = GuardLane(guardOutput: guard, rewardOutput: reward)
        ..bandMath = false
        ..threshold = 0.5
        ..lastSleepDir = 0.1
        ..lastDelta = 0.1;
      lane.evaluateWarning(tick(muffleReward: true));
      expect(lane.warningActive, isFalse);
      expect(guard.lastActive, isFalse);
      expect(reward.muffle, isFalse);
    });

    test('eyes-closed baseline keeps one accepted finite sample', () {
      GuardTick closed({required bool accept}) => GuardTick(
        phase: FeedbackPhase.calibrating,
        collectionEyes: 'closed',
        muffleReward: false,
        sessionStartAt: null,
        acceptBaselineSample: accept,
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
              featurePercentile,
              warnOver,
              ceilingOver,
              clean,
              dirtyReason,
            }) {},
      );

      final band =
          GuardLane(
              guardOutput: RecordingGuardOutput(),
              rewardOutput: RecordingRewardOutput(),
            )
            ..enabled = true
            ..bandMath = true
            ..featureId = 'band.delta';
      band.onFeature(
        const FeatureSample(id: 'band.delta', t: 0, value: 0.2),
        closed(accept: false),
      );
      band.onFeature(
        FeatureSample(id: 'band.delta', t: 0, value: double.nan),
        closed(accept: true),
      );
      band.onFeature(
        const FeatureSample(id: 'band.delta', t: 0, value: 0.2),
        GuardTick(
          phase: FeedbackPhase.calibrating,
          collectionEyes: 'open',
          muffleReward: false,
          sessionStartAt: null,
          acceptBaselineSample: true,
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
                featurePercentile,
                warnOver,
                ceilingOver,
                clean,
                dirtyReason,
              }) {},
        ),
      );
      expect(band.baselineSleepDir, isEmpty);
      band.onFeature(
        const FeatureSample(id: 'band.delta', t: 0, value: 0.2),
        closed(accept: true),
      );
      expect(band.baselineSleepDir, [0.2]);

      final ai =
          GuardLane(
              guardOutput: RecordingGuardOutput(),
              rewardOutput: RecordingRewardOutput(),
            )
            ..enabled = true
            ..bandMath = false
            ..clearCaptured = true
            ..featureId = 'ai.drowsiness';
      ai.onFeature(
        const FeatureSample(id: 'ai.drowsiness', t: 0, value: 0.4),
        closed(accept: false),
      );
      expect(ai.baselineSleepDir, isEmpty);
      ai.onFeature(
        const FeatureSample(id: 'ai.drowsiness', t: 0, value: 0.4),
        closed(accept: true),
      );
      expect(ai.baselineSleepDir, [0.4]);
    });

    test('muffleReward false does not call setMuffle', () {
      final reward = RecordingRewardOutput();
      final guard = RecordingGuardOutput();
      final lane = GuardLane(guardOutput: guard, rewardOutput: reward)
        ..bandMath = false
        ..threshold = 0.5
        ..lastSleepDir = 0.9
        ..lastDelta = 0.1;
      lane.evaluateWarning(tick(muffleReward: false));
      expect(guard.lastActive, isTrue);
      expect(reward.muffle, isNull);
    });
  });

  group('percentileWarn', () {
    test('band-math uses native delta vs percentile and vs 0.25', () {
      expect(guardrailDeltaCeiling, 0.25);
      expect(
        percentileWarnOver(
          bandMath: true,
          lastDelta: 0.30,
          lastSleepDir: 0.0,
          threshold: 0.50,
        ),
        isTrue,
      );
      expect(
        percentileWarnOver(
          bandMath: true,
          lastDelta: 0.20,
          lastSleepDir: 0.99,
          threshold: 0.50,
        ),
        isFalse,
      );
      expect(
        percentileWarnOver(
          bandMath: true,
          lastDelta: 0.20,
          lastSleepDir: 0.0,
          threshold: 0.10,
        ),
        isTrue,
      );
    });

    test('AI uses sleep_dir vs percentile and absolute delta vs 0.25', () {
      expect(
        percentileWarnOver(
          bandMath: false,
          lastDelta: 0.30,
          lastSleepDir: 0.10,
          threshold: 0.50,
        ),
        isTrue,
      );
      expect(
        percentileWarnOver(
          bandMath: false,
          lastDelta: 0.10,
          lastSleepDir: 0.60,
          threshold: 0.50,
        ),
        isTrue,
      );
      expect(
        percentileWarnOver(
          bandMath: false,
          lastDelta: 0.10,
          lastSleepDir: 0.10,
          threshold: 0.50,
        ),
        isFalse,
      );
    });
  });

  group('CalibrationPlan', () {
    test('default follows the feature: bands are baseline only', () {
      expect(
        CalibrationPlan.fromEnabledFeatures([]),
        CalibrationPlan.baselineOnly,
      );
      expect(
        CalibrationPlan.fromEnabledFeatures(['band.atr']),
        CalibrationPlan.baselineOnly,
      );
      expect(
        CalibrationPlan.fromEnabledFeatures(['band.atr', 'band.delta']),
        CalibrationPlan.baselineOnly,
      );
    });

    test('default stages when S contains ai.*', () {
      final plan = CalibrationPlan.fromEnabledFeatures(['ai.drowsiness']);
      expect(plan.artifact, isTrue);
      expect(plan.challenge, isTrue);
      expect(plan.baseline, isTrue);
      expect(plan, CalibrationPlan.stagedAi);
    });

    test('AI + reward uses the same staged plan', () {
      expect(
        CalibrationPlan.fromEnabledFeatures(['band.atr', 'ai.drowsiness']),
        CalibrationPlan.stagedAi,
      );
    });

    test('always staged overrides a band-only feature', () {
      final plan = CalibrationPlan.fromEnabledFeatures([
        'band.atr',
      ], method: CalibrationMethod.alwaysStaged);
      expect(plan, CalibrationPlan.stagedAi);
    });

    test('always staged with AI and reward stays the staged plan', () {
      expect(
        CalibrationPlan.fromEnabledFeatures([
          'band.atr',
          'ai.drowsiness',
        ], method: CalibrationMethod.alwaysStaged),
        CalibrationPlan.stagedAi,
      );
    });
  });
}
