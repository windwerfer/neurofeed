import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/feedback/feature_bus.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/gate_electrodes.dart';
import 'package:muse_ml/src/feedback/guardrail_mode.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/reve.dart' as frb;

/// Classical frontal-delta hard rail for the sleep guardrail (normalized FFT
/// band power of the AF7/AF8 average). Overridden by the baseline percentile
/// once real-device data is available — needs tuning.
///
/// The comment claims normalized power; the code compares absolute µV²/Hz.
/// Do not silently switch the rail to relative-δ.
const double guardrailDeltaCeiling = 0.25;

/// `percentileWarn` split: band-math scores native `band.delta`; AI scores
/// `sleep_dir` and still rails on absolute frontal delta from always-on bands.
bool percentileWarnOver({
  required bool bandMath,
  required double lastDelta,
  required double lastSleepDir,
  required double threshold,
}) {
  if (bandMath) {
    return lastDelta > threshold || lastDelta > guardrailDeltaCeiling;
  }
  return lastSleepDir > threshold || lastDelta > guardrailDeltaCeiling;
}

/// Minimum gap between guardrail warning chimes while drifting into sleep.
const Duration warningChimeCooldown = Duration(seconds: 20);

class GuardTick {
  const GuardTick({
    required this.phase,
    required this.collectingBaseline,
    required this.collectionEyes,
    required this.muffleReward,
    required this.sessionStartAt,
    required this.writeWarningMetadata,
    required this.updateComputed,
  });

  final FeedbackPhase phase;
  final bool collectingBaseline;
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
  })
  updateComputed;
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
  bool warningActive = false;
  DateTime lastWarningChimeAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, double> _frontalDelta = {};
  String featureId = guardFeatureBandDelta;
  List<int> deltaElectrodes = defaultGateElectrodes;

  void configure({
    required bool enabled,
    required bool bandMath,
    required String featureId,
    required List<int> deltaElectrodes,
  }) {
    this.enabled = enabled;
    this.bandMath = bandMath;
    this.featureId = featureId;
    this.deltaElectrodes = deltaElectrodes.isEmpty
        ? defaultGateElectrodes
        : deltaElectrodes;
  }

  void resetSession() {
    enabled = false;
    clearCaptured = false;
    sleepCaptured = false;
    threshold = null;
    baselineSleepDir.clear();
    warningActive = false;
    bandMath = false;
    _frontalDelta.clear();
    lastSleepDir = 0;
    lastDelta = 0;
    lastClarity = 1;
  }

  /// Always-on bands: absolute frontal delta rail (AI percentileWarn) and
  /// V_clear capture during the eyes-open stage.
  void onBands(BandsDto bands, GuardTick tick) {
    _frontalDelta[bands.electrode] = bands.delta;
    lastDelta = _frontalDeltaAverage();
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
          tick.collectingBaseline &&
          tick.collectionEyes == 'closed') {
        baselineSleepDir.add(sample.value);
        return false;
      }
      if (tick.phase == FeedbackPhase.playing && threshold != null) {
        evaluateWarning(tick);
        return true;
      }
      return false;
    }
    lastSleepDir = sample.value;
    if (!clearCaptured) {
      return false;
    }
    if (tick.phase == FeedbackPhase.calibrating &&
        tick.collectingBaseline &&
        tick.collectionEyes == 'closed') {
      baselineSleepDir.add(sample.value);
      return false;
    }
    if (tick.phase == FeedbackPhase.playing && threshold != null) {
      evaluateWarning(tick);
      return true;
    }
    return false;
  }

  /// Computed-frame extras only. Does not drive the warn decision.
  void onReveExtras(ReveDto r, GuardTick tick) {
    lastClarity = r.clarity;
    tick.updateComputed(
      sleepDir: r.sleepDir,
      clarity: r.clarity,
      delta: r.delta,
      warning: warningActive,
      threshold: threshold,
    );
  }

  void finalizeBaseline({required int warningThresholdPercentile}) {
    final list = List<double>.of(baselineSleepDir)..sort();
    if (list.isNotEmpty) {
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

  void recomputeThreshold(int percentile) {
    if (baselineSleepDir.isEmpty) {
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
        'delta ceiling=$guardrailDeltaCeiling',
      );
    }
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
