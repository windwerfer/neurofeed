import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/target_state.dart';

/// One global last successful calibration, reused by debug Skip on a real
/// device. Reward and guard sample lists may be empty independently.
class LastCalibrationBaseline {
  const LastCalibrationBaseline({
    required this.rewardFeatureId,
    required this.rewardSamples,
    this.guardFeatureId,
    this.guardSamples = const [],
  });

  final String rewardFeatureId;
  final List<double> rewardSamples;
  final String? guardFeatureId;
  final List<double> guardSamples;

  bool get isEmpty => rewardSamples.isEmpty && guardSamples.isEmpty;

  Map<String, Object?> toJson() => {
    'rewardFeatureId': rewardFeatureId,
    'rewardSamples': rewardSamples,
    'guardFeatureId': guardFeatureId,
    'guardSamples': guardSamples,
  };

  static LastCalibrationBaseline? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final map = Map<String, Object?>.from(json);
    final rewardId = map['rewardFeatureId'];
    final rewardRaw = map['rewardSamples'];
    if (rewardId is! String || rewardRaw is! List) {
      return null;
    }
    final rewardSamples = <double>[];
    for (final v in rewardRaw) {
      if (v is! num) {
        return null;
      }
      rewardSamples.add(v.toDouble());
    }
    final guardRaw = map['guardSamples'];
    final guardSamples = <double>[];
    if (guardRaw != null) {
      if (guardRaw is! List) {
        return null;
      }
      for (final v in guardRaw) {
        if (v is! num) {
          return null;
        }
        guardSamples.add(v.toDouble());
      }
    }
    final guardId = map['guardFeatureId'];
    if (guardId != null && guardId is! String) {
      return null;
    }
    return LastCalibrationBaseline(
      rewardFeatureId: rewardId,
      rewardSamples: rewardSamples,
      guardFeatureId: guardId as String?,
      guardSamples: guardSamples,
    );
  }

  void applyReward(RatioEngine engine) {
    for (final v in rewardSamples) {
      engine.addBaselineSample(v);
    }
    engine.computeThreshold();
  }

  void applyGuard(GuardLane guard, {required int warningThresholdPercentile}) {
    if (guardSamples.isEmpty) {
      return;
    }
    guard.baselineSleepDir
      ..clear()
      ..addAll(guardSamples);
    guard.finalizeBaseline(
      warningThresholdPercentile: warningThresholdPercentile,
      captureAnchor: false,
    );
  }
}

/// Debug Skip on the calibration screen: always for a simulated device,
/// otherwise only when a last baseline has been saved.
bool debugSkipCalibrationVisible({
  required bool debugEnabled,
  required bool simulatedDevice,
  required bool hasLastBaseline,
}) {
  if (!debugEnabled) {
    return false;
  }
  return simulatedDevice || hasLastBaseline;
}
