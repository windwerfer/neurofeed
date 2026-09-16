import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/calibration_clips.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/feedback/calibration_runner.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/last_calibration_baseline.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onGuard({required bool active, required double intensity}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('debugSkipCalibrationVisible', () {
    test('hidden when debug is off', () {
      expect(
        debugSkipCalibrationVisible(
          debugEnabled: false,
          simulatedDevice: true,
          hasLastBaseline: true,
        ),
        isFalse,
      );
    });

    test('shown for simulated device when debug is on', () {
      expect(
        debugSkipCalibrationVisible(
          debugEnabled: true,
          simulatedDevice: true,
          hasLastBaseline: false,
        ),
        isTrue,
      );
    });

    test('shown for real device only when a last baseline exists', () {
      expect(
        debugSkipCalibrationVisible(
          debugEnabled: true,
          simulatedDevice: false,
          hasLastBaseline: false,
        ),
        isFalse,
      );
      expect(
        debugSkipCalibrationVisible(
          debugEnabled: true,
          simulatedDevice: false,
          hasLastBaseline: true,
        ),
        isTrue,
      );
    });
  });

  group('LastCalibrationBaseline', () {
    test('json round-trip', () {
      const original = LastCalibrationBaseline(
        rewardFeatureId: 'band.atr',
        rewardSamples: [0.4, 0.5, 0.6],
        guardFeatureId: 'band.delta',
        guardSamples: [0.08, 0.10, 0.12],
      );
      final restored = LastCalibrationBaseline.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.rewardFeatureId, 'band.atr');
      expect(restored.rewardSamples, [0.4, 0.5, 0.6]);
      expect(restored.guardFeatureId, 'band.delta');
      expect(restored.guardSamples, [0.08, 0.10, 0.12]);
    });

    test('fromJson rejects malformed payloads', () {
      expect(LastCalibrationBaseline.fromJson(null), isNull);
      expect(LastCalibrationBaseline.fromJson(<String, Object?>{}), isNull);
      expect(
        LastCalibrationBaseline.fromJson({
          'rewardFeatureId': 'band.atr',
          'rewardSamples': 'nope',
        }),
        isNull,
      );
    });

    test('applyReward seeds the ratio engine', () {
      final engine = RatioEngine(percentile: 40, featureId: 'band.atr');
      const LastCalibrationBaseline(
        rewardFeatureId: 'band.atr',
        rewardSamples: [0.4, 0.5, 0.6, 0.7, 0.8],
      ).applyReward(engine);
      expect(engine.hasBaseline, isTrue);
      expect(engine.baselineCount, 5);
      expect(engine.threshold, isNotNull);
    });

    test('applyGuard seeds sleep-dir without capturing an anchor', () {
      final guard =
          GuardLane(guardOutput: _GuardOut(), rewardOutput: _RewardOut())
            ..configure(
              enabled: true,
              bandMath: true,
              featureId: 'band.delta',
              deltaElectrodes: const [1, 2],
            );
      const LastCalibrationBaseline(
        rewardFeatureId: 'band.atr',
        rewardSamples: [0.5],
        guardFeatureId: 'band.delta',
        guardSamples: [0.05, 0.10, 0.15, 0.20],
      ).applyGuard(guard, warningThresholdPercentile: 75);
      expect(guard.baselineSleepDir, [0.05, 0.10, 0.15, 0.20]);
      expect(guard.threshold, isNotNull);
      expect(guard.sleepCaptured, isTrue);
    });
  });

  group('Settings last calibration baseline', () {
    test('persists and reloads', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await Settings.load();
      expect(settings.lastCalibrationBaseline, isNull);
      await settings.setLastCalibrationBaseline(
        const LastCalibrationBaseline(
          rewardFeatureId: 'band.tar',
          rewardSamples: [1.1, 1.2],
        ),
      );
      expect(settings.lastCalibrationBaseline?.rewardFeatureId, 'band.tar');
      expect(settings.lastCalibrationBaseline?.rewardSamples, [1.1, 1.2]);

      final reloaded = await Settings.load();
      expect(reloaded.lastCalibrationBaseline?.rewardFeatureId, 'band.tar');
      expect(reloaded.lastCalibrationBaseline?.rewardSamples, [1.1, 1.2]);
    });

    test('corrupt pref is treated as missing', () async {
      SharedPreferences.setMockInitialValues({
        'last_calibration_baseline': '{not json',
      });
      final settings = await Settings.load();
      expect(settings.lastCalibrationBaseline, isNull);
    });
  });

  group('CalibrationRunner skip abort', () {
    test('inactive playAndBaseline does not finish', () async {
      var finished = false;
      final runner = CalibrationRunner(
        loadManifest: () async => throw StateError('should not load'),
        playClip: (_) async {},
        writeMetadata: (_) {},
        updateUi: (_) {},
        isActive: () => false,
        protocolOf: () => 'drowsiness',
        sessionStartAt: () => null,
        onCollectionEyes: (_) {},
        onFinished: () => finished = true,
      );
      await runner.playAndBaseline(plan: CalibrationPlan.baselineOnly);
      expect(finished, isFalse);
    });

    test('cancel during collection does not finish', () async {
      var active = true;
      var finished = false;
      final runner = CalibrationRunner(
        loadManifest: () async => const CalibrationManifest(
          version: 2,
          calibrations: {},
          protocolCalibration: {},
        ),
        playClip: (_) async {},
        writeMetadata: (_) {},
        updateUi: (_) {},
        isActive: () => active,
        protocolOf: () => 'drowsiness',
        sessionStartAt: () => null,
        onCollectionEyes: (_) {},
        onFinished: () => finished = true,
      );
      final future = runner.playAndBaseline(plan: CalibrationPlan.baselineOnly);
      await Future<void>.delayed(Duration.zero);
      active = false;
      runner.cancelTimers();
      await future;
      expect(finished, isFalse);
    });
  });
}
