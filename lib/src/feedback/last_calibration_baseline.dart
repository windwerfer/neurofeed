import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/target_state.dart';

/// Last successful calibration for one device, reused by debug Skip on a
/// real headset. Reward and guard sample lists may be empty independently.
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

  static Map<String, LastCalibrationBaseline> decodeStore(Object? json) {
    if (json is! Map) {
      return const {};
    }
    final out = <String, LastCalibrationBaseline>{};
    for (final entry in json.entries) {
      final id = entry.key;
      if (id is! String || id.isEmpty) {
        continue;
      }
      final parsed = fromJson(entry.value);
      if (parsed == null || parsed.isEmpty) {
        continue;
      }
      out[id] = parsed;
    }
    return out;
  }

  static Map<String, Object?> encodeStore(
    Map<String, LastCalibrationBaseline> byDevice,
  ) => {for (final e in byDevice.entries) e.key: e.value.toJson()};

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
