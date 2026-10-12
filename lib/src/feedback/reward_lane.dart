import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

/// Snapshot of orchestrator session state for one reward-lane tick.
class RewardTick {
  const RewardTick({
    required this.phase,
    required this.sampleIsClean,
    required this.quality,
    this.acceptBaselineSample = false,
    this.dirtyReason,
    this.guardBlocks = false,
  });

  /// Stability policy only: the sleep guard is warning, so a steady sample
  /// is held back (drowsy steadiness is not rewarded).
  final bool guardBlocks;

  final FeedbackPhase phase;
  final bool sampleIsClean;
  final bool acceptBaselineSample;
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
    double? percentile,
    double? thresholdPercentile,
    bool? heldBack,
    List<String>? inhibitTags,
    bool? clean,
    String? dirtyReason,
    double? betaRel,
    double? deltaRel,
  })
  onComputedFeedback;
  final void Function() onThresholdChanged;

  RelativeBandAggregator _bands = RelativeBandAggregator(
    const [],
    montageNames: const [],
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

  /// Whether the last [onFeature] produced a reward verdict worth plotting.
  /// False in stability warm-up (window not full) and for dirty stability
  /// samples before any ratio exists.
  bool lastProduced = false;

  bool get hasReward => _hasReward;

  bool get _stability => engine.stability != null;

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
    if (tick.phase == FeedbackPhase.calibrating) {
      if (tick.acceptBaselineSample && _hasReward) {
        engine.addBaselineSample(sample.value);
      }
      return;
    }
    if (tick.phase != FeedbackPhase.playing || !_hasReward) {
      return;
    }
    lastProduced = false;
    if (_stability) {
      _onStabilitySample(sample.value, tick);
      return;
    }
    lastProduced = true;
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
      // Trust fileformat: still update computed sampler (no audio / no recordEpoch).
      onComputedFeedback(
        ratio: sample.value,
        threshold: engine.threshold,
        inTarget: false,
        inTargetPct: engine.successRate ?? 0.0,
        percentile: lastPercentile,
        thresholdPercentile: lastThresholdPercentile,
        heldBack: false,
        inhibitTags: const [],
        clean: false,
        dirtyReason: lastDirtyReason?.name,
        betaRel: lastRelative?.betaRel,
        deltaRel: lastRelative?.deltaRel,
      );
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

  /// Experimental `bandStability`: clean samples feed the rolling window;
  /// the reward scalar is r = CV(window) ÷ baseline CV (lower = steadier).
  /// Dirty samples are excluded from the window (not counted as unstable),
  /// skip [RatioEngine.recordEpoch] and [RewardOutput.onSample].
  void _onStabilitySample(double raw, RewardTick tick) {
    final rel = _bands.evaluate(tick.quality);
    final padsDown = rel == null;
    if (rel != null) lastRelative = rel;
    final dirty = !tick.sampleIsClean || padsDown;
    lastDirty = dirty;
    lastDirtyReason = dirty
        ? (padsDown ? TrustDirtyReason.pads : tick.dirtyReason)
        : null;
    lastHeldBack = false;
    lastInhibitTags = const [];
    engine.recordSessionSample(raw, clean: !dirty);
    if (dirty) {
      lastInTarget = false;
      final r = lastNative;
      if (r == null) return;
      lastProduced = true;
      onComputedFeedback(
        ratio: r,
        threshold: engine.threshold,
        inTarget: false,
        inTargetPct: engine.successRate ?? 0.0,
        percentile: lastPercentile,
        thresholdPercentile: lastThresholdPercentile,
        heldBack: false,
        inhibitTags: const [],
        clean: false,
        dirtyReason: lastDirtyReason?.name,
        betaRel: lastRelative?.betaRel,
        deltaRel: lastRelative?.deltaRel,
      );
      return;
    }
    final r = engine.pushStabilitySample(raw);
    if (r == null) {
      // Warm-up: window not full yet. No verdict, no output, no epoch.
      lastInTarget = false;
      return;
    }
    lastProduced = true;
    final thr = engine.threshold;
    final steady = engine.isInTarget(r);
    final inTarget = steady && !tick.guardBlocks;
    lastHeldBack = steady && tick.guardBlocks;
    lastInhibitTags = lastHeldBack ? const ['guard'] : const [];
    final pct = stabilityOutputPercentile(r, thr);
    lastNative = r;
    lastPercentile = pct;
    lastThresholdPercentile = thr == null
        ? 0
        : stabilityOutputPercentile(thr, thr);
    lastInTarget = inTarget;
    engine.recordEpoch(inTarget);
    onStats(r);
    output.onSample(percentile: pct, inTarget: inTarget);
    onComputedFeedback(
      ratio: r,
      threshold: thr,
      inTarget: inTarget,
      inTargetPct: engine.successRate ?? 0.0,
      percentile: pct,
      thresholdPercentile: lastThresholdPercentile,
      heldBack: lastHeldBack,
      inhibitTags: List<String>.of(lastInhibitTags),
      clean: true,
      dirtyReason: null,
      betaRel: lastRelative?.betaRel,
      deltaRel: lastRelative?.deltaRel,
    );
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
      percentile: pct,
      thresholdPercentile: lastThresholdPercentile,
      heldBack: lastHeldBack,
      inhibitTags: List<String>.of(lastInhibitTags),
      clean: true,
      dirtyReason: null,
      betaRel: lastRelative?.betaRel,
      deltaRel: lastRelative?.deltaRel,
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
    lastProduced = false;
  }
}

/// Graded 0–100 "steadiness" for continuous outputs (rain, music, binaural)
/// in `bandStability`. r = CV ÷ baseline CV, [threshold] = current target
/// ratio. Piecewise linear: r ≥ 1.5 (50 % more fluctuation than baseline) →
/// 0; r = threshold → 60; r ≤ threshold − 0.3 (or 0) → 100. With the
/// default 10 % difficulty the baseline itself (r = 1) maps to 50 (rain
/// stage 3), the target to 60 (stage 4) and 25 % steadier than baseline to
/// 80 (stage 5, calmest).
double stabilityOutputPercentile(double r, double? threshold) {
  final thr = (threshold ?? 0.9).clamp(0.0, 1.4).toDouble();
  if (!r.isFinite) return 0;
  if (r >= thr) {
    return (60 * (1.5 - r) / (1.5 - thr)).clamp(0.0, 60.0).toDouble();
  }
  final span = thr < 0.3 ? thr : 0.3;
  if (span <= 0) return 100;
  return (60 + 40 * (thr - r) / span).clamp(60.0, 100.0).toDouble();
}
