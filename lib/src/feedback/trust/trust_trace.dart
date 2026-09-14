import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';

enum TrustDirtyReason { movement, blink, jaw, pads }

enum TrustRewardVerdict { inZone, below, noisy, heldBack }

enum TrustGuardVerdict { warning, quiet, noisy }

class TrustRewardSample {
  const TrustRewardSample({
    required this.t,
    required this.native,
    required this.percentile,
    required this.thresholdPercentile,
    required this.inTarget,
    required this.heldBack,
    required this.inhibitTags,
    required this.clean,
    this.dirtyReason,
    this.plotPercentile,
    this.betaRel,
    this.deltaRel,
    this.plotBetaRel,
    this.plotDeltaRel,
  });

  final double t;
  final double native;
  final double percentile;
  final double thresholdPercentile;
  final bool inTarget;
  final bool heldBack;
  final List<String> inhibitTags;
  final bool clean;
  final TrustDirtyReason? dirtyReason;
  final double? plotPercentile;
  final double? betaRel;
  final double? deltaRel;
  final double? plotBetaRel;
  final double? plotDeltaRel;

  TrustRewardSample copyWith({
    double? plotPercentile,
    double? plotBetaRel,
    double? plotDeltaRel,
  }) => TrustRewardSample(
    t: t,
    native: native,
    percentile: percentile,
    thresholdPercentile: thresholdPercentile,
    inTarget: inTarget,
    heldBack: heldBack,
    inhibitTags: inhibitTags,
    clean: clean,
    dirtyReason: dirtyReason,
    plotPercentile: plotPercentile ?? this.plotPercentile,
    betaRel: betaRel,
    deltaRel: deltaRel,
    plotBetaRel: plotBetaRel ?? this.plotBetaRel,
    plotDeltaRel: plotDeltaRel ?? this.plotDeltaRel,
  );
}

class TrustGuardSample {
  const TrustGuardSample({
    required this.t,
    required this.featurePercentile,
    required this.warningActive,
    required this.warnOver,
    required this.ceilingOver,
    required this.lastDelta,
    required this.clean,
    this.dirtyReason,
    this.plotFeaturePercentile,
    this.plotDelta,
  });

  final double t;
  final double featurePercentile;
  final bool warningActive;
  final bool warnOver;
  final bool ceilingOver;
  final double lastDelta;
  final bool clean;
  final TrustDirtyReason? dirtyReason;
  final double? plotFeaturePercentile;
  final double? plotDelta;

  TrustGuardSample copyWith({
    double? plotFeaturePercentile,
    double? plotDelta,
  }) => TrustGuardSample(
    t: t,
    featurePercentile: featurePercentile,
    warningActive: warningActive,
    warnOver: warnOver,
    ceilingOver: ceilingOver,
    lastDelta: lastDelta,
    clean: clean,
    dirtyReason: dirtyReason,
    plotFeaturePercentile: plotFeaturePercentile ?? this.plotFeaturePercentile,
    plotDelta: plotDelta ?? this.plotDelta,
  );
}

class TrustGestureMark {
  const TrustGestureMark({required this.t, required this.type});

  final double t;
  final GestureType type;

  String get label => switch (type) {
    GestureType.doubleBlink => 'Blink',
    GestureType.doubleClench => 'Jaw',
    GestureType.eyeUp || GestureType.eyeDown => '',
  };
}

/// ~1 Hz ring for live trust graphs. Cap is 5 minutes. Do not use [LiveStats].
class TrustTrace extends ChangeNotifier {
  static const double capSeconds = 300;

  final List<TrustRewardSample> reward = [];
  final List<TrustGuardSample> guard = [];
  final List<TrustGestureMark> marks = [];

  double? _lastCleanRewardPlot;
  double? _lastCleanGuardPlot;
  double? _lastCleanDeltaPlot;
  double? _lastCleanBetaRelPlot;
  double? _lastCleanDeltaRelPlot;

  void pushReward(TrustRewardSample sample) {
    var plot = sample.percentile;
    var plotBeta = sample.betaRel;
    var plotDeltaRel = sample.deltaRel;
    if (!sample.clean) {
      plot = _lastCleanRewardPlot ?? sample.percentile;
      plotBeta = _lastCleanBetaRelPlot ?? sample.betaRel;
      plotDeltaRel = _lastCleanDeltaRelPlot ?? sample.deltaRel;
    } else {
      _lastCleanRewardPlot = sample.percentile;
      if (sample.betaRel != null) _lastCleanBetaRelPlot = sample.betaRel;
      if (sample.deltaRel != null) _lastCleanDeltaRelPlot = sample.deltaRel;
      plotBeta = sample.betaRel ?? _lastCleanBetaRelPlot;
      plotDeltaRel = sample.deltaRel ?? _lastCleanDeltaRelPlot;
    }
    reward.add(
      sample.copyWith(
        plotPercentile: plot,
        plotBetaRel: plotBeta,
        plotDeltaRel: plotDeltaRel,
      ),
    );
    _prune();
    notifyListeners();
  }

  void pushGuard(TrustGuardSample sample) {
    var plotPct = sample.featurePercentile;
    var plotDelta = sample.lastDelta;
    if (!sample.clean) {
      plotPct = _lastCleanGuardPlot ?? sample.featurePercentile;
      plotDelta = _lastCleanDeltaPlot ?? sample.lastDelta;
    } else {
      _lastCleanGuardPlot = sample.featurePercentile;
      _lastCleanDeltaPlot = sample.lastDelta;
    }
    guard.add(
      sample.copyWith(plotFeaturePercentile: plotPct, plotDelta: plotDelta),
    );
    _prune();
    notifyListeners();
  }

  void addMark(TrustGestureMark mark) {
    if (mark.type == GestureType.eyeUp || mark.type == GestureType.eyeDown) {
      return;
    }
    marks.add(mark);
    _prune();
    notifyListeners();
  }

  void reset() {
    reward.clear();
    guard.clear();
    marks.clear();
    _lastCleanRewardPlot = null;
    _lastCleanGuardPlot = null;
    _lastCleanDeltaPlot = null;
    _lastCleanBetaRelPlot = null;
    _lastCleanDeltaRelPlot = null;
    notifyListeners();
  }

  double newestElapsed() {
    var n = 0.0;
    if (reward.isNotEmpty && reward.last.t > n) n = reward.last.t;
    if (guard.isNotEmpty && guard.last.t > n) n = guard.last.t;
    if (marks.isNotEmpty && marks.last.t > n) n = marks.last.t;
    return n;
  }

  void _prune() {
    final newest = newestElapsed();
    final cut = newest - capSeconds;
    reward.removeWhere((s) => s.t < cut);
    guard.removeWhere((s) => s.t < cut);
    marks.removeWhere((s) => s.t < cut);
  }
}

TrustDirtyReason? dominantDirtyReason(Iterable<TrustDirtyReason> reasons) {
  const order = [
    TrustDirtyReason.pads,
    TrustDirtyReason.movement,
    TrustDirtyReason.jaw,
    TrustDirtyReason.blink,
  ];
  for (final r in order) {
    if (reasons.contains(r)) return r;
  }
  return null;
}

TrustDirtyReason? artifactDirtyReason({
  required DateTime now,
  required DateTime lastMovementAt,
  required DateTime lastJawAt,
  required DateTime lastBlinkAt,
  required Duration buffer,
}) {
  if (now.difference(lastMovementAt) < buffer) {
    return TrustDirtyReason.movement;
  }
  if (now.difference(lastJawAt) < buffer) {
    return TrustDirtyReason.jaw;
  }
  if (now.difference(lastBlinkAt) < buffer) {
    return TrustDirtyReason.blink;
  }
  return null;
}
