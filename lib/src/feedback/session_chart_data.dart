import 'package:muse_ml/src/charts/session_reader.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_summary.dart';
import 'package:muse_ml/src/feedback/target_state.dart';

/// Decimated, display-ready chart series for one session: the per-second
/// (or per-bucket) band-relative powers of the frontal AF7/AF8 average, the
/// movement trace, the heart-rate trace, the SpO2 trace, and the derived stats.
///
/// Built by [prepareChartData] (full `.muse` body) or
/// [prepareChartDataFromOverview] (decimated metadata head). Consumed by the
/// history dashboard, the PDF export, and the PNG chart renders.
class SessionChartData {
  final List<double> x;
  final List<double> alphaRel;
  final List<double> thetaRel;
  final List<double> deltaRel;
  final List<double> betaRel;
  final List<double> gammaRel;
  final List<double> movement;
  final List<double> movementX;
  final List<double> bpm;
  final List<double> bpmX;
  final List<double> spo2;
  final List<double> spo2X;
  final SessionChartStats stats;
  final int bandsCount;

  const SessionChartData({
    required this.x,
    required this.alphaRel,
    required this.thetaRel,
    required this.deltaRel,
    required this.betaRel,
    required this.gammaRel,
    required this.movement,
    required this.movementX,
    required this.bpm,
    required this.bpmX,
    required this.spo2,
    required this.spo2X,
    required this.stats,
    required this.bandsCount,
  });
}

/// Derived session statistics shown as chips on the detail view and written
/// into the session metadata on save.
class SessionChartStats {
  final double? peakAlphaFreq;
  final double? peakAlphaPower;
  final double targetPct;
  final double stillnessPct;
  final double? avgBpm;
  final double? avgSpo2;
  final double avgAlphaRel;

  const SessionChartStats({
    this.peakAlphaFreq,
    this.peakAlphaPower,
    required this.targetPct,
    required this.stillnessPct,
    this.avgBpm,
    this.avgSpo2,
    required this.avgAlphaRel,
  });
}

/// Build chart data from a parsed `.muse` body. When the session includes
/// calibration, the displayed window and metrics cover the training portion
/// only; the boundary is an offset from the first recorded event, so it works
/// regardless of device-clock drift.
SessionChartData prepareChartData(
  SessionData data, {
  double? trainingStartOffset,
  RewardMetric metric = RewardMetric.alphaOverTheta,
  List<TargetCondition> conditions = const [],
}) {
  double? cut;
  if (trainingStartOffset != null && trainingStartOffset > 0) {
    var allMin = double.infinity;
    for (final b in data.bands) {
      if (b.timestamp < allMin) allMin = b.timestamp;
    }
    for (final p in data.pulses) {
      if (p.timestamp < allMin) allMin = p.timestamp;
    }
    for (final m in data.movements) {
      if (m.timestamp < allMin) allMin = m.timestamp;
    }
    if (allMin.isFinite) {
      cut = allMin + trainingStartOffset;
    }
  }

  final bySecond = <int, Map<int, BandsRecord>>{};
  for (final b in data.bands) {
    bySecond.putIfAbsent(b.timestamp.floor(), () => {})[b.electrode] = b;
  }
  final seconds = bySecond.keys.toList()..sort();

  final x = <double>[];
  final alphaRel = <double>[];
  final thetaRel = <double>[];
  final deltaRel = <double>[];
  final betaRel = <double>[];
  final gammaRel = <double>[];
  var targetSeconds = 0;
  var alphaRelSum = 0.0;
  var startTs = seconds.isEmpty ? 0.0 : seconds.first.toDouble();
  if (cut != null && cut > startTs) {
    startTs = cut;
  }

  for (final s in seconds) {
    if (cut != null && s < cut) {
      continue;
    }
    final ch = bySecond[s]!;
    final all = _relativeAll(
      _afTuple(ch[electrodeAf7]),
      _afTuple(ch[electrodeAf8]),
    );
    if (all == null) {
      continue;
    }
    final aRel = all.$3;
    final tRel = all.$2;
    final dRel = all.$1;
    final bRel = all.$4;
    final gRel = all.$5;
    x.add(s - startTs);
    alphaRel.add(aRel);
    thetaRel.add(tRel);
    deltaRel.add(dRel);
    betaRel.add(bRel);
    gammaRel.add(gRel);
    alphaRelSum += aRel;
    if (_inTarget(dRel, tRel, aRel, bRel, metric, conditions)) {
      targetSeconds++;
    }
  }

  final movementX = <double>[];
  final movement = <double>[];
  var still = 0;
  for (final m in data.movements) {
    if (cut != null && m.timestamp < cut) {
      continue;
    }
    movementX.add(m.timestamp - startTs);
    movement.add(m.score);
    if (m.score <= movementGateThreshold) {
      still++;
    }
  }

  final bpmX = <double>[];
  final bpm = <double>[];
  var bpmSum = 0.0;
  for (final p in data.pulses) {
    if (p.confidence < 0.3) {
      continue;
    }
    if (cut != null && p.timestamp < cut) {
      continue;
    }
    bpmX.add(p.timestamp - startTs);
    bpm.add(p.bpm);
    bpmSum += p.bpm;
  }

  final spo2X = <double>[];
  final spo2 = <double>[];
  var spo2Sum = 0.0;
  for (final s in data.spo2S) {
    if (s.confidence < 0.3) {
      continue;
    }
    if (cut != null && s.timestamp < cut) {
      continue;
    }
    spo2X.add(s.timestamp - startTs);
    spo2.add(s.spo2);
    spo2Sum += s.spo2;
  }

  double? peakFreq;
  double? peakPower;
  for (final p in data.peakAlphas) {
    if (cut != null && p.timestamp < cut) {
      continue;
    }
    if (peakPower == null || p.power > peakPower) {
      peakPower = p.power;
      peakFreq = p.frequency;
    }
  }

  return SessionChartData(
    x: x,
    alphaRel: alphaRel,
    thetaRel: thetaRel,
    deltaRel: deltaRel,
    betaRel: betaRel,
    gammaRel: gammaRel,
    movement: movement,
    movementX: movementX,
    bpm: bpm,
    bpmX: bpmX,
    spo2: spo2,
    spo2X: spo2X,
    bandsCount: data.bands.length,
    stats: SessionChartStats(
      peakAlphaFreq: peakFreq,
      peakAlphaPower: peakPower,
      targetPct: x.isEmpty ? 0 : targetSeconds / x.length * 100,
      stillnessPct: data.movements.isEmpty
          ? 0
          : still / data.movements.length * 100,
      avgBpm: bpm.isEmpty ? null : bpmSum / bpm.length,
      avgSpo2: spo2.isEmpty ? null : spo2Sum / spo2.length,
      avgAlphaRel: alphaRel.isEmpty ? 0 : alphaRelSum / alphaRel.length,
    ),
  );
}

/// Build chart data from the decimated [SessionOverview] stored in the
/// metadata head, so the history detail renders without reading the `.muse`
/// body. Matches the full [SessionData] path bucket-for-bucket.
SessionChartData prepareChartDataFromOverview(
  SessionOverview overview, {
  RewardMetric metric = RewardMetric.alphaOverTheta,
  List<TargetCondition> conditions = const [],
}) {
  final n = overview.bucketCount;
  final width = overview.bucketWidthSecs > 0 ? overview.bucketWidthSecs : 1.0;
  final af7 = overview.bands[electrodeAf7];
  final af8 = overview.bands[electrodeAf8];

  final x = <double>[];
  final alphaRel = <double>[];
  final thetaRel = <double>[];
  final deltaRel = <double>[];
  final betaRel = <double>[];
  final gammaRel = <double>[];
  var targetSeconds = 0;
  var alphaRelSum = 0.0;

  for (var i = 0; i < n; i++) {
    final all = _relativeAll(_bandAt(af7, i), _bandAt(af8, i));
    if (all == null) {
      continue;
    }
    final aRel = all.$3;
    final tRel = all.$2;
    final dRel = all.$1;
    final bRel = all.$4;
    final gRel = all.$5;
    x.add(i * width);
    alphaRel.add(aRel);
    thetaRel.add(tRel);
    deltaRel.add(dRel);
    betaRel.add(bRel);
    gammaRel.add(gRel);
    alphaRelSum += aRel;
    if (_inTarget(dRel, tRel, aRel, bRel, metric, conditions)) {
      targetSeconds++;
    }
  }

  final movementX = <double>[];
  final movement = <double>[];
  var still = 0;
  for (var i = 0; i < n; i++) {
    if (i >= overview.movement.length || overview.movement[i] == null) {
      continue;
    }
    final m = overview.movement[i]!;
    movementX.add(i * width);
    movement.add(m);
    if (m <= movementGateThreshold) {
      still++;
    }
  }

  final bpmX = <double>[];
  final bpm = <double>[];
  var bpmSum = 0.0;
  for (var i = 0; i < n; i++) {
    if (i >= overview.pulse.length || overview.pulse[i] == null) {
      continue;
    }
    final b = overview.pulse[i]!;
    bpmX.add(i * width);
    bpm.add(b);
    bpmSum += b;
  }

  final spo2X = <double>[];
  final spo2 = <double>[];
  var spo2Sum = 0.0;
  for (var i = 0; i < n; i++) {
    if (i >= overview.spo2.length || overview.spo2[i] == null) {
      continue;
    }
    final s = overview.spo2[i]!;
    spo2X.add(i * width);
    spo2.add(s);
    spo2Sum += s;
  }

  double? peakFreq;
  double? peakPower;
  for (var i = 0; i < overview.peakAlphaPower.length; i++) {
    final p = overview.peakAlphaPower[i];
    if (p == null) {
      continue;
    }
    if (peakPower == null || p > peakPower) {
      peakPower = p;
      peakFreq = i < overview.peakAlphaFreq.length
          ? overview.peakAlphaFreq[i]
          : null;
    }
  }

  return SessionChartData(
    x: x,
    alphaRel: alphaRel,
    thetaRel: thetaRel,
    deltaRel: deltaRel,
    betaRel: betaRel,
    gammaRel: gammaRel,
    movement: movement,
    movementX: movementX,
    bpm: bpm,
    bpmX: bpmX,
    spo2: spo2,
    spo2X: spo2X,
    bandsCount: overview.bands.length,
    stats: SessionChartStats(
      peakAlphaFreq: peakFreq,
      peakAlphaPower: peakPower,
      targetPct: x.isEmpty ? 0 : targetSeconds / x.length * 100,
      stillnessPct: movement.isEmpty ? 0 : still / movement.length * 100,
      avgBpm: bpm.isEmpty ? null : bpmSum / bpm.length,
      avgSpo2: spo2.isEmpty ? null : spo2Sum / spo2.length,
      avgAlphaRel: alphaRel.isEmpty ? 0 : alphaRelSum / alphaRel.length,
    ),
  );
}

/// Per-electrode band powers for bucket [i] from a summary series: `(delta,
/// theta, alpha, beta, gamma)` or null when that electrode/bucket has no data.
(double, double, double, double, double)? _bandAt(BandPowerSeries? series, int i) {
  if (series == null ||
      i >= series.delta.length ||
      series.delta[i] == null ||
      series.theta[i] == null ||
      series.alpha[i] == null ||
      series.beta[i] == null ||
      series.gamma[i] == null) {
    return null;
  }
  return (
    series.delta[i]!,
    series.theta[i]!,
    series.alpha[i]!,
    series.beta[i]!,
    series.gamma[i]!,
  );
}

/// Convert a parsed band record (or null) to the `(delta, theta, alpha, beta,
/// gamma)` tuple form used by [_relativeAll].
(double, double, double, double, double)? _afTuple(BandsRecord? band) {
  if (band == null) {
    return null;
  }
  return (band.delta, band.theta, band.alpha, band.beta, band.gamma);
}

/// Combined relative band powers for one time point from the two frontal pads.
/// A pad with missing/zero total band power is dropped for that sample (matching
/// the ATR autodrop), so a session where only one AF pad was healthy still
/// builds the graph. Returns null only when neither pad is usable.
/// Tuple is (delta, theta, alpha, beta, gamma) fractions of total power.
(double, double, double, double, double)? _relativeAll(
  (double, double, double, double, double)? af7,
  (double, double, double, double, double)? af8,
) {
  final sums = List<double>.filled(5, 0);
  var count = 0;
  for (final band in [af7, af8]) {
    if (band == null) {
      continue;
    }
    final total = band.$1 + band.$2 + band.$3 + band.$4 + band.$5;
    if (total <= 0) {
      continue;
    }
    sums[0] += band.$1 / total;
    sums[1] += band.$2 / total;
    sums[2] += band.$3 / total;
    sums[3] += band.$4 / total;
    sums[4] += band.$5 / total;
    count++;
  }
  if (count == 0) {
    return null;
  }
  return (
    sums[0] / count,
    sums[1] / count,
    sums[2] / count,
    sums[3] / count,
    sums[4] / count,
  );
}

/// Rewarded-band criterion for [metric] on a per-second sample: alpha
/// dominance for the ATR engine, theta dominance for TAR, beta dominance
/// for BTR, plain relative alpha for the alpha-only metric. All protocol
/// [conditions] (e.g. beta/delta ceilings) must pass. Matches the reward
/// engine's `isInTarget` direction (without baseline percentile).
bool _inTarget(
  double deltaRel,
  double thetaRel,
  double alphaRel,
  double betaRel,
  RewardMetric metric,
  List<TargetCondition> conditions,
) {
  for (final c in conditions) {
    if (!c.passes(
      deltaRel: deltaRel,
      thetaRel: thetaRel,
      alphaRel: alphaRel,
      betaRel: betaRel,
    )) {
      return false;
    }
  }
  return switch (metric) {
    RewardMetric.alphaOverTheta => alphaRel > thetaRel,
    RewardMetric.thetaOverAlpha => thetaRel > alphaRel,
    RewardMetric.betaOverTheta => betaRel > thetaRel,
    RewardMetric.alphaOnly => alphaRel > thetaRel && alphaRel > betaRel,
  };
}
