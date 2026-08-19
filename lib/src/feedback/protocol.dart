import 'package:flutter/material.dart';

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
/// guardrail flags). All user-facing copy — catch phrase, title, subtitle,
/// guide text, algorithm description, expected delay, calibration id and the
/// scientific metadata description — lives in `assets/protocols.json`, the
/// single editable text source loaded by `ProtocolCatalog`.
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
  });

  static const ProtocolInfo _drowsiness = ProtocolInfo(
    type: ProtocolType.drowsiness,
    color: Color(0xFF1E88E5),
    rewardMetric: RewardMetric.alphaOverTheta,
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const ProtocolInfo _twilight = ProtocolInfo(
    type: ProtocolType.twilight,
    color: Color(0xFF8E24AA),
    rewardMetric: RewardMetric.thetaOverAlpha,
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const ProtocolInfo _alertnessOpen = ProtocolInfo(
    type: ProtocolType.alertnessOpen,
    color: Color(0xFFFB8C00),
    rewardMetric: RewardMetric.betaOverTheta,
    guardrailDefault: false,
    guardrailAllowed: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _alertnessClosed = ProtocolInfo(
    type: ProtocolType.alertnessClosed,
    color: Color(0xFF00897B),
    rewardMetric: RewardMetric.betaOverTheta,
    guardrailDefault: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _mindfulness = ProtocolInfo(
    type: ProtocolType.mindfulness,
    color: Color(0xFF43A047),
    rewardMetric: RewardMetric.alphaOnly,
    guardrailDefault: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _concentration = ProtocolInfo(
    type: ProtocolType.concentration,
    color: Color(0xFFD81B60),
    rewardMetric: RewardMetric.alphaOnly,
    conditions: [BetaCeiling(0.25)],
    guardrailDefault: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _relaxedConcentration = ProtocolInfo(
    type: ProtocolType.relaxedConcentration,
    color: Color(0xFF6D4C41),
    rewardMetric: RewardMetric.alphaOverTheta,
    conditions: [BetaCeiling(0.25), DeltaCeiling(0.5)],
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const ProtocolInfo _recordOnly = ProtocolInfo(
    type: ProtocolType.recordOnly,
    color: Color(0xFF607D8B),
    rewardMetric: RewardMetric.alphaOverTheta,
    guardrailDefault: false,
    guardrailAllowed: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
    hasReward: false,
    calibrationSkippable: true,
  );

  static const ProtocolInfo _guardrailOnly = ProtocolInfo(
    type: ProtocolType.guardrailOnly,
    color: Color(0xFF5E35B1),
    rewardMetric: RewardMetric.alphaOverTheta,
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
    hasReward: false,
  );

  static const List<ProtocolInfo> all = [
    _drowsiness,
    _twilight,
    _alertnessOpen,
    _alertnessClosed,
    _mindfulness,
    _concentration,
    _relaxedConcentration,
    _recordOnly,
    _guardrailOnly,
  ];

  static ProtocolInfo forType(ProtocolType type) =>
      all.firstWhere((p) => p.type == type);
}