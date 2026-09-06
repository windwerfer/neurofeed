import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/feedback/feature_bus.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/gate_electrodes.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Snapshot of orchestrator session state for one reward-lane tick.
class RewardTick {
  const RewardTick({
    required this.phase,
    required this.collectingBaseline,
    required this.sampleIsClean,
    required this.quality,
  });

  final FeedbackPhase phase;
  final bool collectingBaseline;
  final bool sampleIsClean;
  final List<double>? quality;
}

/// Reward lane: [FeatureDto] native value → threshold + inhibit AND-gate.
///
/// Missing [FeatureDto] this tick is a no-sample (hold last output, do not
/// [RatioEngine.recordEpoch]). Inhibit relative bands come from always-on
/// [BandsDto] via [RelativeBandAggregator]; a missing vector fails closed
/// (`inTarget = false`, no [RatioEngine.recordEpoch]).
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
  bool lastInTarget = false;

  bool get hasReward => _hasReward;

  String get featureId => _featureId;

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
    if (rel == null) {
      onStats(sample.value);
      _emit(sample.value, inTarget: false);
      return;
    }
    var inTarget = engine.isInTarget(sample.value);
    if (inTarget) {
      for (final c in _inhibit) {
        if (!c.passes(
          deltaRel: rel.deltaRel,
          thetaRel: rel.thetaRel,
          alphaRel: rel.alphaRel,
          betaRel: rel.betaRel,
        )) {
          inTarget = false;
          break;
        }
      }
    }
    engine.recordEpoch(inTarget);
    engine.recordSessionSample(sample.value, clean: tick.sampleIsClean);
    if (tick.sampleIsClean && engine.useEmaAdapt) {
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
    lastInTarget = false;
  }
}
