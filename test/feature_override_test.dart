import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/feedback/feature_bus.dart';
import 'package:muse_ml/src/feedback/feature_override.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/gate_electrodes.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/rust/api/features.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class _RewardOut implements RewardOutput {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onSample({required double percentile, required bool inTarget}) {}

  @override
  void setMuffle(bool on) {}
}

class _GuardOut implements GuardOutput {
  bool? lastActive;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onGuard({required bool active, required double intensity}) {
    lastActive = active;
  }
}

void main() {
  group('FeatureOverride.apply', () {
    test('replaces matching FeatureDto when enabled', () {
      final ov = FeatureOverride()
        ..enabled = true
        ..set('band.tar', 0.8);
      final out = ov.apply(
        MuseEventDto.feature(
          const FeatureDto(id: 'band.tar', timestamp: 1, value: 0.1),
        ),
      );
      expect(out, isA<MuseEventDto_Feature>());
      final dto = (out as MuseEventDto_Feature).field0;
      expect(dto.id, 'band.tar');
      expect(dto.value, 0.8);
      expect(dto.timestamp, 1);
    });

    test('leaves live value when disabled', () {
      final ov = FeatureOverride()..set('band.tar', 0.8);
      final out = ov.apply(
        MuseEventDto.feature(
          const FeatureDto(id: 'band.tar', timestamp: 1, value: 0.1),
        ),
      );
      expect((out as MuseEventDto_Feature).field0.value, 0.1);
    });

    test('leaves unmatched ids and non-feature events', () {
      final ov = FeatureOverride()
        ..enabled = true
        ..set('band.tar', 0.8);
      final other = ov.apply(
        MuseEventDto.feature(
          const FeatureDto(id: 'band.atr', timestamp: 1, value: 2.0),
        ),
      );
      expect((other as MuseEventDto_Feature).field0.value, 2.0);
      expect(
        ov.apply(const MuseEventDto.disconnected()),
        isA<MuseEventDto_Disconnected>(),
      );
    });

    test('two ids latch independently', () {
      final ov = FeatureOverride()
        ..enabled = true
        ..set('band.tar', 0.8)
        ..set('band.delta', 0.9);
      expect(
        (ov.apply(
                  MuseEventDto.feature(
                    const FeatureDto(id: 'band.tar', timestamp: 1, value: 0),
                  ),
                )
                as MuseEventDto_Feature)
            .field0
            .value,
        0.8,
      );
      expect(
        (ov.apply(
                  MuseEventDto.feature(
                    const FeatureDto(id: 'band.delta', timestamp: 1, value: 0),
                  ),
                )
                as MuseEventDto_Feature)
            .field0
            .value,
        0.9,
      );
    });

    test('clear disables and drops values', () {
      final ov = FeatureOverride()
        ..enabled = true
        ..set('band.tar', 0.8)
        ..clear();
      expect(ov.enabled, isFalse);
      expect(ov.values, isEmpty);
    });
  });

  group('synthetic baseline', () {
    test('band.delta seed stays under the 0.25 ceiling', () {
      final samples = FeatureOverride.baselineSamples('band.delta');
      expect(samples, hasLength(FeatureOverride.baselineSampleCount));
      expect(samples.every((v) => v < guardrailDeltaCeiling), isTrue);
    });

    test('live-sim ATR baseline makes slider 0.8 miss; seed then hits', () {
      final engine = RatioEngine();
      for (var i = 0; i < 49; i++) {
        engine.addBaselineSample(20000 + i * 200);
      }
      engine.computeThreshold();
      expect(engine.isInTarget(0.8), isFalse);
      expect(engine.percentileOf(2.68), 0);

      engine.reset();
      for (final v in FeatureOverride.baselineSamples('band.atr')) {
        engine.addBaselineSample(v);
      }
      engine.computeThreshold();
      expect(engine.isInTarget(0.8), isTrue);
      expect(engine.percentileOf(2.68), 100);
    });

    test('reward 0.8 beats a TAR seed; 0.1 does not', () {
      final engine = RatioEngine();
      for (final v in FeatureOverride.baselineSamples('band.tar')) {
        engine.addBaselineSample(v);
      }
      engine.computeThreshold();
      expect(engine.threshold, isNotNull);
      expect(engine.isInTarget(0.8), isTrue);
      expect(engine.isInTarget(0.1), isFalse);
      expect(engine.percentileOf(0.8), 100);
    });

    test('guard 0.8 warns after a delta seed; 0.08 does not', () {
      final lane =
          GuardLane(guardOutput: _GuardOut(), rewardOutput: _RewardOut())
            ..configure(
              enabled: true,
              bandMath: true,
              featureId: 'band.delta',
              deltaElectrodes: defaultGateElectrodes,
            );
      lane.baselineSleepDir.addAll(
        FeatureOverride.baselineSamples('band.delta'),
      );
      lane.finalizeBaseline(warningThresholdPercentile: 75);
      expect(lane.threshold, isNotNull);
      expect(lane.threshold!, lessThan(guardrailDeltaCeiling));

      GuardTick tick() => GuardTick(
        phase: FeedbackPhase.playing,
        collectingBaseline: false,
        collectionEyes: null,
        muffleReward: false,
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
            }) {},
      );

      expect(
        lane.onFeature(
          const FeatureSample(id: 'band.delta', t: 0, value: 0.08),
          tick(),
        ),
        isTrue,
      );
      expect(lane.warningActive, isFalse);

      expect(
        lane.onFeature(
          const FeatureSample(id: 'band.delta', t: 1, value: 0.8),
          tick(),
        ),
        isTrue,
      );
      expect(lane.warningActive, isTrue);
    });
  });
}
