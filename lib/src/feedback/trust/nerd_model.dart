import 'dart:math' as math;

import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/reward_lane.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/feedback/trust/trust_runs.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';

class NerdRowId {
  static const live = 'live';
  static const pOfPile = 'p-of-pile';
  static const threshold = 'threshold';
  static const mean = 'mean';
  static const spread = 'spread';
  static const samples = 'samples';
  static const success = 'success';
  static const guardLive = 'guard-live';
  static const pOfRest = 'p-of-rest';
  static const warnThr = 'warn-thr';
  static const guardMean = 'guard-mean';
  static const guardSpread = 'guard-spread';
  static const guardSamples = 'guard-samples';
  static const warningRate = 'warning-rate';
  static const warning = 'warning';
  static const cooldown = 'cooldown';
  static const liveDelta = 'live-delta';
  static const deltaCeiling = 'delta-ceiling';
}

enum NerdDiagramKind {
  live,
  percentile,
  threshold,
  mean,
  spread,
  samples,
  success,
  warning,
  cooldown,
}

class NerdHistogram {
  const NerdHistogram({
    required this.min,
    required this.max,
    required this.counts,
  });

  static const int defaultBins = 24;

  final double min;
  final double max;
  final List<int> counts;

  factory NerdHistogram.fromSamples(
    List<double> samples, {
    int bins = defaultBins,
    Iterable<double?> extras = const [],
  }) {
    final values = <double>[
      for (final s in samples)
        if (s.isFinite) s,
      for (final e in extras)
        if (e != null && e.isFinite) e,
    ];
    if (values.isEmpty) {
      return NerdHistogram(min: 0, max: 1, counts: List<int>.filled(bins, 0));
    }
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if ((hi - lo).abs() < 1e-12) {
      final pad = lo.abs() < 1e-9 ? 0.1 : lo.abs() * 0.1;
      lo -= pad;
      hi += pad;
    } else {
      final span = hi - lo;
      lo -= span * 0.05;
      hi += span * 0.05;
    }
    final counts = List<int>.filled(bins, 0);
    for (final s in samples) {
      if (!s.isFinite) continue;
      counts[binIndex(s, lo, hi, bins)]++;
    }
    return NerdHistogram(min: lo, max: hi, counts: counts);
  }

  double xFraction(double value) {
    final span = max - min;
    if (span <= 0) return 0.5;
    return ((value - min) / span).clamp(0.0, 1.0);
  }

  int binOf(double value) => binIndex(value, min, max, counts.length);

  static int binIndex(double value, double min, double max, int bins) {
    if (bins <= 0) return 0;
    final span = max - min;
    if (span <= 0) return 0;
    var i = ((value - min) / span * bins).floor();
    if (i < 0) return 0;
    if (i >= bins) return bins - 1;
    return i;
  }
}

class NerdPileView {
  const NerdPileView({
    required this.title,
    required this.samples,
    required this.histogram,
    this.live,
    this.threshold,
    this.thresholdLabel = 'release',
    this.extraTick,
    this.extraTickLabel,
  });

  final String title;
  final List<double> samples;
  final NerdHistogram histogram;
  final double? live;
  final double? threshold;
  final String thresholdLabel;
  final double? extraTick;
  final String? extraTickLabel;
}

class NerdBandStackView {
  const NerdBandStackView({
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
    this.betaCeiling,
    this.deltaCeiling,
  });

  final double delta;
  final double theta;
  final double alpha;
  final double beta;
  final double gamma;
  final double? betaCeiling;
  final double? deltaCeiling;

  List<double> get values => [delta, theta, alpha, beta, gamma];

  bool get hasCeiling => betaCeiling != null || deltaCeiling != null;
}

class NerdInfoRowData {
  const NerdInfoRowData({
    required this.id,
    required this.label,
    required this.value,
    required this.infoTitle,
    required this.infoBody,
    required this.diagram,
  });

  final String id;
  final String label;
  final String value;
  final String infoTitle;
  final String infoBody;
  final NerdDiagramKind diagram;
}

class NerdSheetSnapshot {
  const NerdSheetSnapshot({
    this.rewardPile,
    this.rewardRows = const [],
    this.bands,
    this.guardPile,
    this.guardRows = const [],
  });

  final NerdPileView? rewardPile;
  final List<NerdInfoRowData> rewardRows;
  final NerdBandStackView? bands;
  final NerdPileView? guardPile;
  final List<NerdInfoRowData> guardRows;

  bool get hasGuard => guardPile != null;
  bool get isEmpty => rewardPile == null && bands == null && guardPile == null;
}

Duration nerdChimeRemaining({
  required DateTime now,
  required DateTime lastChimeAt,
  Duration cooldown = warningChimeCooldown,
}) {
  final left = cooldown - now.difference(lastChimeAt);
  if (left.isNegative) return Duration.zero;
  return left;
}

(double?, double?) nerdMeanStd(List<double> xs) {
  if (xs.isEmpty) return (null, null);
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  if (xs.length < 2) return (mean, null);
  var acc = 0.0;
  for (final s in xs) {
    final d = s - mean;
    acc += d * d;
  }
  return (mean, math.sqrt(acc / xs.length));
}

NerdBandStackView? nerdBandStack(
  RelativeTarget? rel,
  List<TargetCondition> inhibit,
) {
  if (rel == null) return null;
  double? betaCeil;
  double? deltaCeil;
  for (final c in inhibit) {
    switch (c) {
      case BetaCeiling(:final maxBetaRel):
        betaCeil = maxBetaRel;
      case DeltaCeiling(:final maxDeltaRel):
        deltaCeil = maxDeltaRel;
    }
  }
  return NerdBandStackView(
    delta: rel.deltaRel,
    theta: rel.thetaRel,
    alpha: rel.alphaRel,
    beta: rel.betaRel,
    gamma: rel.gammaRel,
    betaCeiling: betaCeil,
    deltaCeiling: deltaCeil,
  );
}

String nerdFixed(double? v, {int digits = 2}) {
  if (v == null || !v.isFinite) return '—';
  return v.toStringAsFixed(digits);
}

String nerdRate(double? pct) {
  if (pct == null) return '—';
  return '${pct.round()}%';
}

NerdSheetSnapshot nerdSheetFromLanes({
  required RewardLane reward,
  required GuardLane guard,
  required List<TargetCondition> inhibit,
  required String rewardLabel,
  required String guardLabel,
  required TrustTrace trace,
  required DateTime now,
  required int warningThresholdPercentile,
}) {
  NerdPileView? rewardPile;
  var rewardRows = const <NerdInfoRowData>[];
  if (reward.hasReward) {
    final engine = reward.engine;
    final samples = List<double>.of(engine.baselineSamples);
    final live = reward.lastNative;
    final thr = engine.threshold;
    rewardPile = NerdPileView(
      title: 'Reward pile ($rewardLabel)',
      samples: samples,
      histogram: NerdHistogram.fromSamples(samples, extras: [live, thr]),
      live: live,
      threshold: thr,
      thresholdLabel: 'release',
    );
    final window = lastWindow(trace.reward);
    rewardRows = [
      NerdInfoRowData(
        id: NerdRowId.live,
        label: 'Live $rewardLabel',
        value: nerdFixed(live),
        infoTitle: 'Live metric',
        infoBody:
            'Native feature this second. Sound compares this to the threshold.',
        diagram: NerdDiagramKind.live,
      ),
      NerdInfoRowData(
        id: NerdRowId.pOfPile,
        label: 'p of pile',
        value: nerdFixed(reward.lastPercentile, digits: 0),
        infoTitle: 'p of pile',
        infoBody: 'Rank in the calibration pile. This is graph Y (0–100).',
        diagram: NerdDiagramKind.percentile,
      ),
      NerdInfoRowData(
        id: NerdRowId.threshold,
        label: 'Threshold',
        value: '${nerdFixed(thr)}  from p${engine.baselinePercentile}',
        infoTitle: 'Threshold',
        infoBody:
            'Which pick of the pile (reward default p40). '
            'Dynamic target may move this.',
        diagram: NerdDiagramKind.threshold,
      ),
      NerdInfoRowData(
        id: NerdRowId.mean,
        label: 'Mean',
        value: nerdFixed(engine.baselineMean),
        infoTitle: 'Mean',
        infoBody: 'Centre of the pile. Reward adapt ceiling is mean + 1.5·sd.',
        diagram: NerdDiagramKind.mean,
      ),
      NerdInfoRowData(
        id: NerdRowId.spread,
        label: 'Spread',
        value: nerdFixed(engine.baselineStddev),
        infoTitle: 'Spread',
        infoBody:
            'How messy calibration was. Wide sd = a moving line can travel farther.',
        diagram: NerdDiagramKind.spread,
      ),
      NerdInfoRowData(
        id: NerdRowId.samples,
        label: 'Samples n',
        value: '${engine.baselineCount}',
        infoTitle: 'Samples n',
        infoBody: 'Clean calibration samples. Small n = shaky line.',
        diagram: NerdDiagramKind.samples,
      ),
      NerdInfoRowData(
        id: NerdRowId.success,
        label: 'Success rate',
        value: nerdRate(inZonePercent(window)),
        infoTitle: 'Success rate',
        infoBody:
            'Share of the last 75 s in zone, excluding noisy seconds. '
            'Same idea as the More strip.',
        diagram: NerdDiagramKind.success,
      ),
    ];
  }

  NerdPileView? guardPile;
  var guardRows = const <NerdInfoRowData>[];
  if (guard.enabled) {
    final samples = List<double>.of(guard.baselineSleepDir);
    final live = guard.bandMath ? guard.lastDelta : guard.lastSleepDir;
    final thr = guard.threshold;
    final extra = guard.bandMath ? guardrailDeltaCeiling : null;
    final (gMean, gStd) = nerdMeanStd(samples);
    guardPile = NerdPileView(
      title: 'Guard pile ($guardLabel)',
      samples: samples,
      histogram: NerdHistogram.fromSamples(samples, extras: [live, thr, extra]),
      live: live,
      threshold: thr,
      thresholdLabel: 'warn',
      extraTick: extra,
      extraTickLabel: extra == null ? null : 'δ ceiling',
    );
    final window = lastGuardWindow(trace.guard);
    final remaining = nerdChimeRemaining(
      now: now,
      lastChimeAt: guard.lastWarningChimeAt,
    );
    guardRows = [
      NerdInfoRowData(
        id: NerdRowId.guardLive,
        label: 'Live $guardLabel',
        value: nerdFixed(live),
        infoTitle: 'Live metric',
        infoBody:
            'Native guard feature this second. Warning compares this to the warn threshold.',
        diagram: NerdDiagramKind.live,
      ),
      NerdInfoRowData(
        id: NerdRowId.pOfRest,
        label: 'p of rest',
        value: nerdFixed(guard.percentileOf(live), digits: 0),
        infoTitle: 'p of rest',
        infoBody:
            'Rank in the eyes-closed rest pile. This is warn-graph Y (0–100).',
        diagram: NerdDiagramKind.percentile,
      ),
      NerdInfoRowData(
        id: NerdRowId.warnThr,
        label: 'Warn thr',
        value: '${nerdFixed(thr)}  from p$warningThresholdPercentile',
        infoTitle: 'Warn threshold',
        infoBody:
            'Which pick of the rest pile (guard default p75). '
            'Over this line is the personal warn tripwire.',
        diagram: NerdDiagramKind.threshold,
      ),
      NerdInfoRowData(
        id: NerdRowId.guardMean,
        label: 'Mean',
        value: nerdFixed(gMean),
        infoTitle: 'Mean',
        infoBody: 'Centre of the rest pile.',
        diagram: NerdDiagramKind.mean,
      ),
      NerdInfoRowData(
        id: NerdRowId.guardSpread,
        label: 'Spread',
        value: nerdFixed(gStd),
        infoTitle: 'Spread',
        infoBody: 'How messy rest calibration was.',
        diagram: NerdDiagramKind.spread,
      ),
      NerdInfoRowData(
        id: NerdRowId.guardSamples,
        label: 'Samples n',
        value: '${samples.length}',
        infoTitle: 'Samples n',
        infoBody: 'Clean rest-pile samples. Small n = shaky warn line.',
        diagram: NerdDiagramKind.samples,
      ),
      NerdInfoRowData(
        id: NerdRowId.warningRate,
        label: 'Warning rate',
        value: nerdRate(warningPercent(window)),
        infoTitle: 'Warning rate',
        infoBody:
            'Share of the last 75 s in warning, excluding noisy seconds. '
            'Same idea as the More strip.',
        diagram: NerdDiagramKind.success,
      ),
      NerdInfoRowData(
        id: NerdRowId.warning,
        label: 'Warning',
        value: guard.warningActive ? 'on' : 'off',
        infoTitle: 'Warning',
        infoBody:
            'Continuous warningActive. The graph follows this, not the chime.',
        diagram: NerdDiagramKind.warning,
      ),
      NerdInfoRowData(
        id: NerdRowId.cooldown,
        label: 'Chime cooldown',
        value: remaining == Duration.zero
            ? 'ready'
            : '${remaining.inSeconds} s',
        infoTitle: 'Chime cooldown',
        infoBody:
            'Minimum 20 s between warning bowls. Sparse vs the continuous warning.',
        diagram: NerdDiagramKind.cooldown,
      ),
      if (!guard.bandMath) ...[
        NerdInfoRowData(
          id: NerdRowId.liveDelta,
          label: 'Live δ',
          value: nerdFixed(guard.lastDelta),
          infoTitle: 'Live δ',
          infoBody:
              'Native frontal AF7/AF8 δ. The hard rail, not the AI rest pile.',
          diagram: NerdDiagramKind.live,
        ),
        NerdInfoRowData(
          id: NerdRowId.deltaCeiling,
          label: 'δ ceiling',
          value: nerdFixed(guardrailDeltaCeiling),
          infoTitle: 'δ ceiling',
          infoBody:
              'Hard rail at $guardrailDeltaCeiling. Over this trips the ceiling warn.',
          diagram: NerdDiagramKind.threshold,
        ),
      ],
    ];
  }

  return NerdSheetSnapshot(
    rewardPile: rewardPile,
    rewardRows: rewardRows,
    bands: nerdBandStack(reward.lastRelative, inhibit),
    guardPile: guardPile,
    guardRows: guardRows,
  );
}
