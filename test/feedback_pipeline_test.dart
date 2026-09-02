import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/feedback/feature_bus.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/gate_electrodes.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/reward_lane.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/rust/api/features.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

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

  group('gate electrodes', () {
    test('reward montage wins', () {
      expect(
        gateElectrodeNames(
          hasReward: true,
          guardOn: true,
          guardFeature: 'ai.drowsiness',
          rewardElectrodes: ['AF7', 'AF8'],
        ),
        ['AF7', 'AF8'],
      );
    });

    test('ai.drowsiness does not add TP9/TP10', () {
      expect(
        gateElectrodeNames(
          hasReward: false,
          guardOn: true,
          guardFeature: 'ai.drowsiness',
        ),
        museGateElectrodeNames,
      );
      expect(
        electrodeIndicesFor(
          gateElectrodeNames(
            hasReward: false,
            guardOn: true,
            guardFeature: 'ai.drowsiness',
          ),
          montageNames: museMontageNames,
        ),
        defaultGateElectrodes,
      );
    });

    test('band.delta guard uses frontal montage', () {
      expect(
        gateElectrodeNames(
          hasReward: false,
          guardOn: true,
          guardFeature: 'band.delta',
        ),
        museGateElectrodeNames,
      );
    });

    test('recordOnly falls back to AF7/AF8', () {
      expect(
        gateElectrodeNames(
          hasReward: false,
          guardOn: false,
          guardFeature: 'none',
        ),
        museGateElectrodeNames,
      );
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
      ], montageNames: museMontageNames);
      agg.update(
        const BandsDto(
          electrode: 1,
          timestamp: 0,
          delta: 1,
          theta: 1,
          alpha: 2,
          beta: 1,
          gamma: 1,
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
      required void Function(double value, {required bool inTarget}) onReward,
      List<TargetCondition> inhibit = const [],
    }) {
      final lane = RewardLane(
        engine: engine,
        onReward: onReward,
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
        inhibit: inhibit,
        electrodeNames: museGateElectrodeNames,
        montageNames: museMontageNames,
      );
      engine
        ..addBaselineSample(1.0)
        ..addBaselineSample(1.5)
        ..computeThreshold();
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
      lineNoiseRatio: 0,
    );

    test(
      'missing relative bands fails closed: inTarget false, no recordEpoch',
      () {
        var rewarded = 0;
        var inT = true;
        final engine = RatioEngine(
          epochWindow: const Duration(milliseconds: 1),
        );
        final lane = laneWith(
          engine,
          onReward: (_, {required inTarget}) {
            rewarded++;
            inT = inTarget;
          },
        );
        lane.onFeature(
          const FeatureSample(id: 'band.atr', t: 0, value: 3.0),
          const RewardTick(
            phase: FeedbackPhase.playing,
            collectingBaseline: false,
            sampleIsClean: true,
            quality: [100, 100, 100, 100],
          ),
        );
        expect(rewarded, 1);
        expect(inT, isFalse);
        expect(engine.successRate, isNull);
      },
    );

    test('FeatureDto drives the reward scalar', () {
      var last = 0.0;
      var inT = false;
      final engine = RatioEngine();
      final lane = laneWith(
        engine,
        onReward: (v, {required inTarget}) {
          last = v;
          inT = inTarget;
        },
      );
      lane.onBands(pad(1));
      lane.onBands(pad(2));
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
        const RewardTick(
          phase: FeedbackPhase.playing,
          collectingBaseline: false,
          sampleIsClean: true,
          quality: [100, 100, 100, 100],
        ),
      );
      expect(last, 4.0);
      expect(inT, isTrue);
    });

    test('wrong feature id is ignored', () {
      var rewarded = 0;
      final engine = RatioEngine();
      final lane = laneWith(
        engine,
        onReward: (_, {required inTarget}) {
          rewarded++;
        },
      );
      lane.onBands(pad(1));
      lane.onBands(pad(2));
      lane.onFeature(
        const FeatureSample(id: 'band.tar', t: 0, value: 4.0),
        const RewardTick(
          phase: FeedbackPhase.playing,
          collectingBaseline: false,
          sampleIsClean: true,
          quality: [100, 100, 100, 100],
        ),
      );
      expect(rewarded, 0);
    });

    test('inhibit AND-gates inTarget but still records an epoch', () async {
      var inT = true;
      final engine = RatioEngine(epochWindow: const Duration(milliseconds: 20));
      final lane = laneWith(
        engine,
        inhibit: const [BetaCeiling(0.01)],
        onReward: (_, {required inTarget}) {
          inT = inTarget;
        },
      );
      lane.onBands(pad(1));
      lane.onBands(pad(2));
      const tick = RewardTick(
        phase: FeedbackPhase.playing,
        collectingBaseline: false,
        sampleIsClean: true,
        quality: [100, 100, 100, 100],
      );
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 0, value: 4.0),
        tick,
      );
      expect(inT, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      lane.onFeature(
        const FeatureSample(id: 'band.atr', t: 1, value: 4.0),
        tick,
      );
      expect(engine.successRate, 0.0);
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
}
