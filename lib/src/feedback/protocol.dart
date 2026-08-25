import 'package:flutter/material.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';

enum ProtocolType {
  drowsiness,
  twilight,
  alertnessOpen,
  alertnessClosed,
  mindfulness,
  concentration,
  relaxedConcentration,

  /// Raw recording session: no reward engine, no guardrail. Calibration is
  /// optional (per-session skip button).
  recordOnly,

  /// Guardrail-only session: the 3-stage guardrail calibration, then the AI
  /// sleep guardrail warns without any reward layer.
  guardrailOnly,
}

/// Which directional band ratio the reward engine optimizes.
///
/// `alphaOverTheta` (ATR = alpha ÷ theta) is what the engine runs today for
/// both protocols — the reward fires when ATR stays above the baseline
/// percentile, i.e. the brain is coached to keep alpha dominant over theta
/// (calm but awake). `thetaOverAlpha` (TAR) is reserved: switching a protocol
/// to it is a data-only change (same ratio engine, flipped criterion).
/// `betaOverTheta` (BTR) is the classic alertness ratio; `alphaOnly` rewards
/// plain relative alpha without a ratio.
enum RewardMetric { alphaOverTheta, thetaOverAlpha, betaOverTheta, alphaOnly }

extension RewardMetricLabel on RewardMetric {
  /// Short display name used in the nerd-stats bubble and stats labels.
  String get shortLabel => switch (this) {
    RewardMetric.alphaOverTheta => 'ATR',
    RewardMetric.thetaOverAlpha => 'TAR',
    RewardMetric.betaOverTheta => 'BTR',
    RewardMetric.alphaOnly => 'α',
  };
}

/// A per-sample condition a composite protocol applies on top of the scalar
/// reward metric. The scalar must beat the baseline threshold AND every
/// condition must pass for the sample to count as in-target. All values are
/// relative band powers (fractions of total power, summing to 1 across the
/// five bands).
sealed class TargetCondition {
  const TargetCondition();

  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  });
}

/// Rewards only while relative beta stays at or below [maxBetaRel] — the
/// "beta inhibit" leg of calm-focus protocols (discourages elevated
/// high-frequency activity).
class BetaCeiling extends TargetCondition {
  const BetaCeiling(this.maxBetaRel);
  final double maxBetaRel;

  @override
  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  }) =>
      betaRel <= maxBetaRel;
}

/// Rewards only while relative delta stays at or below [maxDeltaRel] — keeps
/// the state out of deep-sleep territory on protocols near the sleep edge.
class DeltaCeiling extends TargetCondition {
  const DeltaCeiling(this.maxDeltaRel);
  final double maxDeltaRel;

  @override
  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  }) =>
      deltaRel <= maxDeltaRel;
}

/// How a protocol's AI sleep guardrail behaves in music-feedback mode. The
/// guardrail only ever warns on non-music (chime) feedback; with music it can
/// either stay a pure chime (the filter keeps following the ratio reward) or
/// additionally muffle the music while the sleep-drift warning is active.
enum GuardrailFeedback {
  /// Warning chime only — the music filter is untouched by the guardrail.
  chimeOnly,

  /// While a warning is active the low-pass filter is forced fully closed
  /// (deep muffle) and returns to the ratio-driven cutoff after it clears.
  muffleWhileWarning,
}

/// Structural protocol definition (colors, reward metric, conditions,
/// guardrail flags) and user-facing copy — all loaded from
/// `assets/protocols.json`, the single editable text source.
class ProtocolInfo {
  final ProtocolType type;

  /// Accent color shown in the protocol list.
  final Color color;
  final RewardMetric rewardMetric;

  /// Per-sample conditions applied on top of [rewardMetric] (see
  /// [TargetCondition]). Empty for pure scalar protocols.
  final List<TargetCondition> conditions;

  /// Whether the on-device sleep guardrail (LUNA/REVE) is on by default for
  /// this protocol. Every protocol can run the guardrail — the per-protocol
  /// setting (`Settings.guardrailEnabledFor`) overrides this default. The
  /// guardrail only warns — it never modulates the reward.
  final bool guardrailDefault;

  /// Whether the guardrail is offered at all for this protocol. False only for
  /// the eyes-open alertness protocol (no sleep drift to guard against); when
  /// false the guardrail UI is hidden and the layer never runs for it.
  final bool guardrailAllowed;

  /// How the guardrail behaves when music feedback is active (see
  /// [GuardrailFeedback]). Consulted only while the guardrail runs.
  final GuardrailFeedback guardrailFeedback;

  /// Whether this protocol runs a reward engine at all. False for pure
  /// recording ([ProtocolType.recordOnly]) and guardrail-only
  /// ([ProtocolType.guardrailOnly]) sessions — those hide the feedback-sound
  /// selection and never fire reward chimes/swell.
  final bool hasReward;

  /// Whether the session start offers a "skip calibration" shortcut next to
  /// the normal start button. True only for [ProtocolType.recordOnly].
  final bool calibrationSkippable;

  /// Electrode names required for this protocol. Must be a subset of
  /// `DeviceConfig.electrodeNames` for the device to be compatible.
  final List<String> requiredElectrodes;

  /// Device kinds this protocol is allowed on. Null means all devices.
  /// Values are `DeviceKind.name` strings: "muse", "neurosity",
  /// "simulatedMuse", "simulatedNeurosity".
  final List<String>? allowedDevices;

  /// User-facing copy fields from JSON.
  final String catchPhrase;
  final String title;
  final String subtitle;
  final String guideText;
  final String algorithmDescription;
  final String expectedDelay;
  final String calibration;
  final String? metadataDescription;
  final String guardrailDefaultMode;

  const ProtocolInfo({
    required this.type,
    required this.color,
    required this.rewardMetric,
    this.conditions = const [],
    required this.guardrailDefault,
    this.guardrailAllowed = true,
    required this.guardrailFeedback,
    this.hasReward = true,
    this.calibrationSkippable = false,
    required this.requiredElectrodes,
    this.allowedDevices,
    required this.catchPhrase,
    required this.title,
    required this.subtitle,
    required this.guideText,
    required this.algorithmDescription,
    required this.expectedDelay,
    required this.calibration,
    this.metadataDescription,
    required this.guardrailDefaultMode,
  });

  factory ProtocolInfo.fromJson(Map<String, Object?> json, String typeName) {
    final type = ProtocolType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => throw ArgumentError('Unknown ProtocolType: $typeName'),
    );

    final colorValue = json['color'] as int? ?? 0xFF000000;
    final rewardMetricName = json['rewardMetric'] as String? ?? 'alphaOverTheta';
    final rewardMetric = RewardMetric.values.firstWhere(
      (e) => e.name == rewardMetricName,
      orElse: () => RewardMetric.alphaOverTheta,
    );

    final conditions = <TargetCondition>[];
    final conditionsJson = json['conditions'] as List?;
    if (conditionsJson != null) {
      for (final c in conditionsJson) {
        if (c is Map<String, Object?>) {
          conditions.add(_parseCondition(c));
        }
      }
    }

    final guardrailFeedbackName = json['guardrailFeedback'] as String? ?? 'chimeOnly';
    final guardrailFeedback = GuardrailFeedback.values.firstWhere(
      (e) => e.name == guardrailFeedbackName,
      orElse: () => GuardrailFeedback.chimeOnly,
    );

    final requiredElectrodes = (json['requiredElectrodes'] as List?)?.cast<String>() ?? <String>[];
    final allowedDevices = (json['allowedDevices'] as List?)?.cast<String>();

    return ProtocolInfo(
      type: type,
      color: Color(colorValue),
      rewardMetric: rewardMetric,
      conditions: conditions,
      guardrailDefault: json['guardrailDefault'] as bool? ?? false,
      guardrailAllowed: json['guardrailAllowed'] as bool? ?? true,
      guardrailFeedback: guardrailFeedback,
      hasReward: json['hasReward'] as bool? ?? true,
      calibrationSkippable: json['calibrationSkippable'] as bool? ?? false,
      requiredElectrodes: requiredElectrodes,
      allowedDevices: allowedDevices,
      catchPhrase: json['catchPhrase'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      guideText: json['guideText'] as String? ?? '',
      algorithmDescription: json['algorithmDescription'] as String? ?? '',
      expectedDelay: json['expectedDelay'] as String? ?? '',
      calibration: json['calibration'] as String? ?? '',
      metadataDescription: json['metadataDescription'] as String?,
      guardrailDefaultMode: json['guardrailDefaultMode'] as String? ?? 'drowsinessMath',
    );
  }

  static TargetCondition _parseCondition(Map<String, Object?> c) {
    switch (c['type']) {
      case 'betaCeiling':
        return BetaCeiling((c['maxBetaRel'] as num).toDouble());
      case 'deltaCeiling':
        return DeltaCeiling((c['maxDeltaRel'] as num).toDouble());
      default:
        throw ArgumentError('Unknown condition type: ${c['type']}');
    }
  }

  /// Whether this protocol is compatible with the given device config.
  bool isCompatibleWith(DeviceConfig config) {
    // Check required electrodes
    for (final electrode in requiredElectrodes) {
      if (!config.electrodeNames.contains(electrode)) {
        return false;
      }
    }

    // Check allowed devices
    if (allowedDevices != null) {
      final kindName = config.kind.name;
      if (!allowedDevices!.contains(kindName)) {
        return false;
      }
    }

    return true;
  }
}