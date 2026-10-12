import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/audio/guard_output.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/feedback/session_store.dart';
import 'package:neurofeed/src/feedback/target_state.dart'
    show atrUsableSignalThreshold;
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/rust/api/reve.dart' as frb;

/// Frontal-delta hard rail for the sleep guardrail: **relative** delta
/// (δ ÷ total band power) of AF7/AF8, averaged over the pads that pass the
/// pad-quality gate ([atrUsableSignalThreshold], same gate as the reward).
/// No usable pad → no rail value → the rail cannot warn.
///
/// 2026-10: switched from absolute δ (µV²) > 0.25, which fired on ~100 % of
/// rows in every gym corpus. Ceiling from `feedback_gym/runners/
/// delta_rail_sweep.py` (see `feedback_gym/DELTA_RAIL_SWEEP.md`): 0.80 keeps
/// false alarms on Muse awake rest ≤ 1 % (artifact task 4 %). Relative
/// frontal δ does **not** separate wake from N1 (BA < 0.5 at every ceiling),
/// so the rail is a safety net only and catalog / new user protocols ship
/// with `deltaRail: false`.
const double guardrailDeltaCeiling = 0.80;

/// The pre-2026-10 rail: absolute frontal δ (µV²) above 0.25. Sessions whose
/// computed frames carry no `railDeltaRel` were recorded with it; history
/// charts compare their `delta` to this value.
const double legacyGuardrailDeltaCeilingAbs = 0.25;

/// `percentileWarn` split: band-math scores native `band.delta`; AI scores the
/// FeatureDto scalar (P(class1) from the selected head) and, when
/// [deltaRail] is on (protocol `guard.deltaRail`, default true), also rails
/// on relative frontal delta ([railDeltaRel], NaN = no usable pad) from
/// always-on bands. With [deltaRail] off only the threshold rule can warn.
bool percentileWarnOver({
  required bool bandMath,
  required double lastDelta,
  required double lastSleepDir,
  required double threshold,
  bool deltaRail = true,
  double railDeltaRel = double.nan,
}) {
  final rail = deltaRail && railDeltaRel > guardrailDeltaCeiling;
  if (bandMath) {
    return lastDelta > threshold || rail;
  }
  return lastSleepDir > threshold || rail;
}

/// Minimum gap between guardrail warning chimes while drifting into sleep.
const Duration warningChimeCooldown = Duration(seconds: 20);

class GuardTick {
  const GuardTick({
    required this.phase,
    required this.collectionEyes,
    required this.muffleReward,
    required this.sessionStartAt,
    required this.writeWarningMetadata,
    required this.updateComputed,
    this.sampleIsClean = true,
    this.acceptBaselineSample = false,
    this.quality,
  });

  /// Per-pad signal quality (0–100) for the δ-rail pad gate.
  final List<double>? quality;

  final FeedbackPhase phase;
  final String? collectionEyes;
  final bool muffleReward;
  final DateTime? sessionStartAt;
  final void Function({
    required double sleepDir,
    required double delta,
    required double threshold,
    required bool bandMath,
  })
  writeWarningMetadata;
  final void Function({
    required double sleepDir,
    required double clarity,
    required double delta,
    required bool warning,
    double? threshold,
    double? featurePercentile,
    bool? warnOver,
    bool? ceilingOver,
    double? railDeltaRel,
    bool? clean,
    String? dirtyReason,
  })
  updateComputed;
  final bool sampleIsClean;
  final bool acceptBaselineSample;
}

/// Guard lane: [FeatureDto] → percentileWarn. Never changes the reward scalar
/// or `inTarget`. [ReveDto] extras (`clarity` / `dim` / `kind`) feed computed
/// frames only — the warn path does not read `ReveDto.sleepDir`.
class GuardLane {
  GuardLane({required this.guardOutput, required this.rewardOutput});

  GuardOutput guardOutput;
  RewardOutput rewardOutput;

  bool enabled = false;
  bool bandMath = false;
  bool clearCaptured = false;
  bool sleepCaptured = false;
  double? threshold;
  final List<double> baselineSleepDir = [];
  double lastClarity = 1;
  double lastSleepDir = 0;
  double lastDelta = 0;

  /// Relative frontal δ for the rail (NaN while no frontal pad is usable).
  double lastDeltaRel = double.nan;
  bool warningActive = false;
  DateTime lastWarningChimeAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, double> _frontalDelta = {};
  final Map<int, BandsDto> _frontalBands = {};
  String featureId = guardFeatureBandDelta;
  List<int> deltaElectrodes = const [];

  /// Protocol `guard.deltaRail`: whether the relative frontal-delta ceiling
  /// may warn. [ceilingOver] is computed (and recorded) either way.
  bool deltaRail = true;

  String thresholdMode = guardThresholdModePercentile;
  double fixedThreshold = defaultAiGuardFixedThreshold;

  bool get fixedMode => !bandMath && thresholdMode == guardThresholdModeFixed;

  void configure({
    required bool enabled,
    required bool bandMath,
    required String featureId,
    required List<int> deltaElectrodes,
    bool deltaRail = true,
    String thresholdMode = guardThresholdModePercentile,
    double fixedThreshold = defaultAiGuardFixedThreshold,
  }) {
    final wasFixed = fixedMode;
    this.enabled = enabled;
    this.bandMath = bandMath;
    this.featureId = featureId;
    this.deltaElectrodes = deltaElectrodes;
    this.deltaRail = deltaRail;
    this.thresholdMode = resolveGuardThresholdMode(
      feature: featureId,
      declared: bandMath ? guardThresholdModePercentile : thresholdMode,
    );
    this.fixedThreshold = fixedThreshold;
    if (fixedMode) {
      threshold = fixedThreshold;
    } else if (wasFixed) {
      threshold = null;
    }
  }

  /// Switch percentile ↔ fixed mid-session. Band-math guards stay
  /// percentile. Percentile mode re-reads the captured baseline.
  void setThresholdMode(
    String mode, {
    required int warningThresholdPercentile,
  }) {
    thresholdMode = resolveGuardThresholdMode(
      feature: featureId,
      declared: bandMath ? guardThresholdModePercentile : mode,
    );
    if (fixedMode) {
      threshold = fixedThreshold;
    } else if (baselineSleepDir.isNotEmpty) {
      recomputeThreshold(warningThresholdPercentile);
    } else {
      threshold = null;
    }
  }

  void setFixedThreshold(double value) {
    fixedThreshold = value;
    if (fixedMode) {
      threshold = value;
      debugPrint('[guardrail] fixed threshold P > ${value.toStringAsFixed(2)}');
    }
  }

  void resetSession() {
    enabled = false;
    clearCaptured = false;
    sleepCaptured = false;
    threshold = null;
    baselineSleepDir.clear();
    warningActive = false;
    bandMath = false;
    thresholdMode = guardThresholdModePercentile;
    _frontalDelta.clear();
    _frontalBands.clear();
    lastDeltaRel = double.nan;
    lastSleepDir = 0;
    lastDelta = 0;
    lastClarity = 1;
  }

  /// Always-on bands: frontal delta (absolute, recorded) and the relative δ
  /// rail value behind the pad gate; V_clear capture during the eyes-open
  /// stage.
  void onBands(BandsDto bands, GuardTick tick) {
    _frontalDelta[bands.electrode] = bands.delta;
    _frontalBands[bands.electrode] = bands;
    lastDelta = _frontalDeltaAverage();
    lastDeltaRel = _frontalDeltaRel(tick.quality);
    if (tick.phase == FeedbackPhase.calibrating &&
        tick.collectionEyes == 'open') {
      unawaited(tryCaptureClearAnchor());
    }
  }

  /// Warn + baseline from [FeatureSample]. Wrong id is ignored.
  /// Returns true when a playing-phase drowsiness sample should be recorded.
  bool onFeature(FeatureSample sample, GuardTick tick) {
    if (!enabled || sample.id != featureId) {
      return false;
    }
    if (bandMath) {
      lastDelta = sample.value;
      if (tick.phase == FeedbackPhase.calibrating &&
          tick.acceptBaselineSample &&
          tick.collectionEyes == 'closed' &&
          sample.value.isFinite) {
        baselineSleepDir.add(sample.value);
        return false;
      }
      if (tick.phase == FeedbackPhase.playing && threshold != null) {
        if (tick.sampleIsClean) {
          evaluateWarning(tick);
        }
        return true;
      }
      return false;
    }
    lastSleepDir = sample.value;
    if (!clearCaptured) {
      return false;
    }
    if (tick.phase == FeedbackPhase.calibrating &&
        tick.acceptBaselineSample &&
        tick.collectionEyes == 'closed' &&
        sample.value.isFinite) {
      baselineSleepDir.add(sample.value);
      return false;
    }
    if (tick.phase == FeedbackPhase.playing && threshold != null) {
      if (tick.sampleIsClean) {
        evaluateWarning(tick);
      }
      return true;
    }
    return false;
  }

  /// Computed-frame extras only. Does not drive the warn decision.
  void onReveExtras(ReveDto r, GuardTick tick) {
    lastClarity = r.clarity;
    final native = bandMath ? lastDelta : lastSleepDir;
    tick.updateComputed(
      sleepDir: r.sleepDir,
      clarity: r.clarity,
      delta: r.delta,
      warning: warningActive,
      threshold: threshold,
      featurePercentile: percentileOf(native),
      warnOver: warnOver,
      ceilingOver: ceilingOver,
      railDeltaRel: railDeltaRelOrNull,
      clean: tick.sampleIsClean,
      dirtyReason: null,
    );
  }

  void finalizeBaseline({
    required int warningThresholdPercentile,
    bool captureAnchor = true,
  }) {
    final list = List<double>.of(baselineSleepDir)..sort();
    if (fixedMode) {
      threshold = fixedThreshold;
      debugPrint(
        '[guardrail] baseline n=${baselineSleepDir.length} '
        'fixed threshold P > ${fixedThreshold.toStringAsFixed(2)}',
      );
    } else if (list.isNotEmpty) {
      final idx = ((warningThresholdPercentile / 100) * (list.length - 1))
          .round();
      threshold = list[idx];
      debugPrint(
        '[guardrail] baseline n=${baselineSleepDir.length} '
        'p$warningThresholdPercentile threshold=${threshold?.toStringAsFixed(3)}',
      );
    }
    if (bandMath) {
      sleepCaptured = true;
      debugPrint('[guardrail] band math — no V_sleep anchor to capture');
      return;
    }
    if (!captureAnchor) {
      // Skip / last-baseline reuse: percentile warn only — no embedding anchors.
      clearCaptured = true;
      sleepCaptured = true;
      return;
    }
    unawaited(
      frb
          .guardrailCaptureAnchor(name: 'sleep')
          .then((msg) {
            sleepCaptured = true;
            debugPrint('[guardrail] $msg');
          })
          .catchError((Object e) {
            sleepCaptured = false;
            debugPrint('[guardrail] V_sleep capture failed: $e');
          }),
    );
  }

  double? percentileOf(double value) {
    if (baselineSleepDir.isEmpty) {
      return null;
    }
    final below = baselineSleepDir.where((s) => s < value).length;
    return (below / baselineSleepDir.length) * 100;
  }

  bool get warnOver {
    final t = threshold;
    if (t == null) return false;
    if (bandMath) return lastDelta > t;
    return lastSleepDir > t;
  }

  /// Relative frontal delta above [guardrailDeltaCeiling]. Recorded per
  /// computed frame even when [deltaRail] is off (then it never warns).
  bool get ceilingOver => lastDeltaRel > guardrailDeltaCeiling;

  double? get railDeltaRelOrNull => lastDeltaRel.isFinite ? lastDeltaRel : null;

  void recomputeThreshold(int percentile) {
    if (fixedMode || baselineSleepDir.isEmpty) {
      return;
    }
    final list = List<double>.of(baselineSleepDir)..sort();
    final idx = ((percentile / 100) * (list.length - 1)).round();
    threshold = list[idx];
    debugPrint(
      '[guardrail] threshold recomputed p$percentile = ${threshold?.toStringAsFixed(3)}',
    );
  }

  Future<void> tryCaptureClearAnchor() async {
    if (!enabled || clearCaptured) {
      return;
    }
    try {
      await frb.guardrailCaptureAnchor(name: 'clear');
      clearCaptured = true;
      debugPrint('[guardrail] V_clear captured');
    } catch (_) {}
  }

  void teardown() {
    if (enabled) {
      unawaited(frb.guardrailDisable());
    }
    resetSession();
  }

  void recordSample(List<DrowsinessSample> series, DateTime sessionStart) {
    series.add(
      DrowsinessSample(
        offsetSecs:
            DateTime.now().difference(sessionStart).inMilliseconds / 1000,
        sleepDir: lastSleepDir,
        delta: lastDelta,
        warning: warningActive,
      ),
    );
  }

  void evaluateWarning(GuardTick tick) {
    final t = threshold!;
    final over = percentileWarnOver(
      bandMath: bandMath,
      lastDelta: lastDelta,
      lastSleepDir: lastSleepDir,
      threshold: t,
      deltaRail: deltaRail,
      railDeltaRel: lastDeltaRel,
    );
    if (!over) {
      warningActive = false;
      if (tick.muffleReward) {
        rewardOutput.setMuffle(false);
      }
      guardOutput.onGuard(active: false, intensity: 0);
      return;
    }
    warningActive = true;
    if (tick.muffleReward) {
      rewardOutput.setMuffle(true);
    }
    guardOutput.onGuard(active: true, intensity: 1.0);
    final now = DateTime.now();
    if (now.difference(lastWarningChimeAt) >= warningChimeCooldown) {
      lastWarningChimeAt = now;
      tick.writeWarningMetadata(
        sleepDir: lastSleepDir,
        delta: lastDelta,
        threshold: t,
        bandMath: bandMath,
      );
      debugPrint(
        '[guardrail] WARNING sleep_dir=${lastSleepDir.toStringAsFixed(3)} '
        'delta=${lastDelta.toStringAsFixed(3)} '
        'thr=${t.toStringAsFixed(3)} '
        'delta ceiling=$guardrailDeltaCeiling${deltaRail ? '' : ' (rail off)'}',
      );
    }
  }

  /// Mean δ ÷ (δ+θ+α+β+γ) over frontal pads with quality ≥
  /// [atrUsableSignalThreshold]; NaN when none is usable.
  double _frontalDeltaRel(List<double>? quality) {
    var sum = 0.0;
    var n = 0;
    for (final i in deltaElectrodes) {
      final b = _frontalBands[i];
      if (b == null || quality == null || i >= quality.length) continue;
      if (quality[i] < atrUsableSignalThreshold) continue;
      final total = b.delta + b.theta + b.alpha + b.beta + b.gamma;
      if (!(total > 0)) continue;
      sum += b.delta / total;
      n++;
    }
    return n == 0 ? double.nan : sum / n;
  }

  double _frontalDeltaAverage() {
    final vals = <double>[];
    for (final i in deltaElectrodes) {
      final v = _frontalDelta[i];
      if (v != null) {
        vals.add(v);
      }
    }
    if (vals.isEmpty) {
      return lastDelta;
    }
    var sum = 0.0;
    for (final v in vals) {
      sum += v;
    }
    return sum / vals.length;
  }
}
