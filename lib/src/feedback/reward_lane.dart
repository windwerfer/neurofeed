import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/gate_electrodes.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

/// Snapshot of orchestrator session state for one reward-lane tick.
class RewardTick {
  const RewardTick({
    required this.phase,
    required this.collectingBaseline,
    required this.sampleIsClean,
    required this.quality,
    this.dirtyReason,
  });

  final FeedbackPhase phase;
  final bool collectingBaseline;
  final bool sampleIsClean;
  final List<double>? quality;
  final TrustDirtyReason? dirtyReason;
}

/// Reward lane: [FeatureDto] native value → threshold + inhibit AND-gate.
///
/// Missing [FeatureDto] this tick is a no-sample (hold last output, do not
/// [RatioEngine.recordEpoch]). Inhibit relative bands come from always-on
/// [BandsDto] via [RelativeBandAggregator]. Dirty (`!sampleIsClean` or
/// unusable gate pads) skips [RatioEngine.recordEpoch] and [RewardOutput.onSample].
class RewardLane {
  RewardLane({
    required this.engine,
    required this.output,
    required this.onStats,
    required this.onComputedFeedback,
    required this.onThresholdChanged,
  });

  final RatioEngine engine;
  RewardOutput output;
  final void Function(double value) onStats;
  final void Function({
    required double ratio,
    required double? threshold,
    required bool inTarget,
    required double inTargetPct,
  })
  onComputedFeedback;
  final void Function() onThresholdChanged;

  RelativeBandAggregator _bands = RelativeBandAggregator(
    museGateElectrodeNames,
    montageNames: museMontageNames,
  );
  List<TargetCondition> _inhibit = const [];
  String _featureId = 'band.atr';
  bool _hasReward = false;
  double? lastNative;
  double? lastPercentile;
  double lastThresholdPercentile = 0;
  bool lastInTarget = false;
  bool lastHeldBack = false;
  bool lastDirty = false;
  TrustDirtyReason? lastDirtyReason;
  List<String> lastInhibitTags = const [];
  RelativeTarget? lastRelative;

  bool get hasReward => _hasReward;

  String get featureId => _featureId;

  bool padsUsable(List<double>? quality) => _bands.evaluate(quality) != null;

  void configure({
    required bool hasReward,
    required String? featureId,
    required List<TargetCondition> inhibit,
    required List<String> electrodeNames,
    required List<String> montageNames,
  }) {
    _hasReward = hasReward;
    _featureId = featureId ?? 'band.atr';
    engine.featureId = _featureId;
    _inhibit = inhibit;
    _bands = RelativeBandAggregator(electrodeNames, montageNames: montageNames);
  }

  void setInhibit(List<TargetCondition> inhibit) {
    _inhibit = inhibit;
  }

  void onBands(BandsDto bands) {
    _bands.update(bands);
  }

  /// Consume one [FeatureSample]. Wrong id is ignored. Non-finite values are
  /// skipped (same as the old ATR `isFinite` guard).
  void onFeature(FeatureSample sample, RewardTick tick) {
    if (sample.id != _featureId) {
      return;
    }
    if (!sample.value.isFinite) {
      return;
    }
    if (tick.phase == FeedbackPhase.calibrating && tick.collectingBaseline) {
      if (_hasReward && tick.sampleIsClean) {
        engine.addBaselineSample(sample.value);
      }
      return;
    }
    if (tick.phase != FeedbackPhase.playing || !_hasReward) {
      return;
    }
    final rel = _bands.evaluate(tick.quality);
    final padsDown = rel == null;
    if (rel != null) {
      lastRelative = rel;
    }
    lastNative = sample.value;
    lastPercentile = engine.percentileOf(sample.value) ?? 50.0;
    final thr = engine.threshold;
    lastThresholdPercentile = thr == null ? 0 : engine.percentileOf(thr) ?? 0;
    final dirty = !tick.sampleIsClean || padsDown;
    lastDirty = dirty;
    lastDirtyReason = padsDown ? TrustDirtyReason.pads : tick.dirtyReason;
    if (dirty) {
      lastInTarget = false;
      lastHeldBack = false;
      lastInhibitTags = const [];
      engine.recordSessionSample(sample.value, clean: false);
      onStats(sample.value);
      return;
    }
    final bands = rel;
    final above = engine.isInTarget(sample.value);
    final failed = <String>[];
    for (final c in _inhibit) {
      if (!c.passes(
        deltaRel: bands.deltaRel,
        thetaRel: bands.thetaRel,
        alphaRel: bands.alphaRel,
        betaRel: bands.betaRel,
      )) {
        switch (c) {
          case BetaCeiling():
            failed.add('beta');
          case DeltaCeiling():
            failed.add('delta');
        }
      }
    }
    final inTarget = above && failed.isEmpty;
    lastInTarget = inTarget;
    lastHeldBack = above && failed.isNotEmpty;
    lastInhibitTags = failed;
    engine.recordEpoch(inTarget);
    engine.recordSessionSample(sample.value, clean: true);
    if (engine.useEmaAdapt) {
      engine.adaptEma(sample.value);
      onThresholdChanged();
    }
    onStats(sample.value);
    _emit(sample.value, inTarget: inTarget);
  }

  void _emit(double value, {required bool inTarget}) {
    final pct = engine.percentileOf(value) ?? 50.0;
    lastNative = value;
    lastPercentile = pct;
    lastInTarget = inTarget;
    output.onSample(percentile: pct, inTarget: inTarget);
    onComputedFeedback(
      ratio: value,
      threshold: engine.threshold,
      inTarget: inTarget,
      inTargetPct: engine.successRate ?? 0.0,
    );
  }

  void resetBands() {
    _bands.reset();
  }

  void reset() {
    engine.reset();
    _bands.reset();
    lastNative = null;
    lastPercentile = null;
    lastThresholdPercentile = 0;
    lastInTarget = false;
    lastHeldBack = false;
    lastDirty = false;
    lastDirtyReason = null;
    lastInhibitTags = const [];
    lastRelative = null;
  }
}
