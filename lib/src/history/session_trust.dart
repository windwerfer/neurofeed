import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/session_format/stats_assemble.dart';

/// History replay of one session: trust samples, gesture marks, and totals.
///
/// Percents are 0–100 over [frameSeconds] where `clean` is true and `t` is
/// not before training start. Null when that lane did not run or the clean
/// weight is 0. Chime counts cover the whole audio-event list.
class SessionTrust {
  const SessionTrust({
    required this.reward,
    required this.guard,
    required this.marks,
    required this.pctInZone,
    required this.pctInhibited,
    required this.pctWarning,
    required this.pctCeiling,
    required this.rewardChimes,
    required this.guardChimes,
  });

  final List<TrustRewardSample> reward;
  final List<TrustGuardSample> guard;
  final List<TrustGestureMark> marks;
  final double? pctInZone;
  final double? pctInhibited;
  final double? pctWarning;
  final double? pctCeiling;
  final int rewardChimes;
  final int guardChimes;
}

/// Builds [SessionTrust] from v6 computed frames. Does not use [TrustTrace].
SessionTrust readSessionTrust({
  required List<ffi.ComputedFrame> frames,
  double? trainingStartOffsetSecs,
  List<SessionAnnotation> annotations = const [],
  List<Map<String, Object?>> audioEvents = const [],
}) {
  final weights = frameSeconds(frames);
  final reward = <TrustRewardSample>[];
  final guard = <TrustGuardSample>[];
  double? lastCleanReward;
  double? lastCleanBeta;
  double? lastCleanDeltaRel;
  double? lastCleanGuard;
  double? lastCleanGuardDelta;
  var rewardClean = 0.0;
  var inZone = 0.0;
  var inhibited = 0.0;
  var guardClean = 0.0;
  var warning = 0.0;
  var ceiling = 0.0;

  for (var i = 0; i < frames.length; i++) {
    final frame = frames[i];
    final weight = weights[i];
    final counted = _inTraining(frame.t, trainingStartOffsetSecs);
    final fb = frame.feedback;
    final rewardCleanFlag = fb.clean;
    if (rewardCleanFlag != null) {
      final percentile = fb.percentile ?? 50.0;
      final betaRel = fb.betaRel;
      final deltaRel = fb.deltaRel;
      final double plot;
      final double? plotBeta;
      final double? plotDeltaRel;
      if (!rewardCleanFlag) {
        plot = lastCleanReward ?? percentile;
        plotBeta = lastCleanBeta ?? betaRel;
        plotDeltaRel = lastCleanDeltaRel ?? deltaRel;
      } else {
        lastCleanReward = percentile;
        if (betaRel != null) lastCleanBeta = betaRel;
        if (deltaRel != null) lastCleanDeltaRel = deltaRel;
        plot = percentile;
        plotBeta = betaRel ?? lastCleanBeta;
        plotDeltaRel = deltaRel ?? lastCleanDeltaRel;
      }
      reward.add(
        TrustRewardSample(
          t: frame.t,
          native: fb.ratio,
          percentile: percentile,
          thresholdPercentile: fb.thresholdPercentile ?? 0,
          inTarget: fb.inTarget,
          heldBack: fb.heldBack ?? false,
          inhibitTags: List<String>.of(fb.inhibitTags ?? const <String>[]),
          clean: rewardCleanFlag,
          dirtyReason: _dirtyReason(fb.dirtyReason),
          betaRel: betaRel,
          deltaRel: deltaRel,
          plotPercentile: plot,
          plotBetaRel: plotBeta,
          plotDeltaRel: plotDeltaRel,
        ),
      );
      if (counted && rewardCleanFlag) {
        rewardClean += weight;
        if (fb.inTarget) inZone += weight;
        if (fb.heldBack == true) inhibited += weight;
      }
    }

    final gr = frame.guardrail;
    final guardCleanFlag = gr.clean;
    if (guardCleanFlag != null) {
      final featurePercentile = gr.featurePercentile ?? 50.0;
      final lastDelta = gr.delta;
      final double plotPct;
      final double plotDelta;
      if (!guardCleanFlag) {
        plotPct = lastCleanGuard ?? featurePercentile;
        plotDelta = lastCleanGuardDelta ?? lastDelta;
      } else {
        lastCleanGuard = featurePercentile;
        lastCleanGuardDelta = lastDelta;
        plotPct = featurePercentile;
        plotDelta = lastDelta;
      }
      guard.add(
        TrustGuardSample(
          t: frame.t,
          featurePercentile: featurePercentile,
          warningActive: gr.warning,
          warnOver: gr.warnOver ?? false,
          ceilingOver: gr.ceilingOver ?? false,
          lastDelta: lastDelta,
          clean: guardCleanFlag,
          dirtyReason: _dirtyReason(gr.dirtyReason),
          plotFeaturePercentile: plotPct,
          plotDelta: plotDelta,
        ),
      );
      if (counted && guardCleanFlag) {
        guardClean += weight;
        if (gr.warning) warning += weight;
        if (gr.ceilingOver == true) ceiling += weight;
      }
    }
  }

  var rewardChimes = 0;
  var guardChimes = 0;
  for (final event in audioEvents) {
    final type = event['type'];
    if (type == 'reward_chime') {
      rewardChimes++;
    } else if (type == 'guard_chime') {
      guardChimes++;
    }
  }

  return SessionTrust(
    reward: reward,
    guard: guard,
    marks: _marks(annotations),
    pctInZone: _percent(inZone, rewardClean),
    pctInhibited: _percent(inhibited, rewardClean),
    pctWarning: _percent(warning, guardClean),
    pctCeiling: _percent(ceiling, guardClean),
    rewardChimes: rewardChimes,
    guardChimes: guardChimes,
  );
}

bool _inTraining(double t, double? trainingStartOffsetSecs) =>
    trainingStartOffsetSecs == null || t >= trainingStartOffsetSecs;

double? _percent(double part, double cleanWeight) =>
    cleanWeight <= 0 ? null : part * 100.0 / cleanWeight;

TrustDirtyReason? _dirtyReason(String? name) => switch (name) {
  'movement' => TrustDirtyReason.movement,
  'blink' => TrustDirtyReason.blink,
  'jaw' => TrustDirtyReason.jaw,
  'pads' => TrustDirtyReason.pads,
  _ => null,
};

List<TrustGestureMark> _marks(List<SessionAnnotation> annotations) {
  final marks = <TrustGestureMark>[];
  for (final annotation in annotations) {
    if (annotation.duration != 0) continue;
    final type = switch (annotation.type) {
      'double_blink' => GestureType.doubleBlink,
      'double_jaw_clench' => GestureType.doubleClench,
      _ => null,
    };
    if (type == null) continue;
    marks.add(TrustGestureMark(t: annotation.onset, type: type));
  }
  return marks;
}
