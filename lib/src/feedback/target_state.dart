import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/feedback/feedback_engine.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

const int electrodeAf7 = 1;
const int electrodeAf8 = 2;

/// A per-pad signal-quality score at or above this value is treated as a
/// "good" electrode and contributes to the live ATR computation. Pads below
/// it are dropped for that sample. Kept in sync with [signalGoodThreshold]
/// so the calibration gate and the live autodrop use the same notion of a
/// good contact. (Future feedback options may add per-pad weighting here.)
const double atrUsableSignalThreshold = 80.0;

const double movementGateThreshold = 0.05;

class RelativeTarget {
  const RelativeTarget({
    required this.alphaRel,
    required this.thetaRel,
    required this.betaRel,
    required this.gammaRel,
  });

  final double alphaRel;
  final double thetaRel;
  final double betaRel;
  final double gammaRel;

  /// Alpha/Theta power ratio (ATR). Since both powers are relative to the
  /// same total, this equals alpha/theta of the absolute powers and cancels
  /// global amplitude drift.
  double get atr {
    if (thetaRel <= 0) {
      return double.infinity;
    }
    return alphaRel / thetaRel;
  }

  /// Theta/Alpha power ratio (TAR) — the reciprocal of [atr]. Used by
  /// protocols whose [RewardMetric] rewards theta dominance (a data-only
  /// flip of the same ratio engine).
  double get tar {
    if (alphaRel <= 0) {
      return double.infinity;
    }
    return thetaRel / alphaRel;
  }
}

/// Continuous band-ratio uptraining engine.
///
/// The engine is direction-agnostic: it collects samples of a scalar ratio,
/// derives the session threshold from a configurable percentile of that
/// baseline distribution, and rewards the user while the live value beats the
/// threshold. The [metric] tag says which ratio feeds it ([RewardMetric]
/// lives on the protocol spec — changing a protocol's metric is a data-only
/// change: same engine, flipped extraction).
///
/// During calibration it collects clean ratio samples. The session threshold is
/// the configurable percentile of that baseline distribution (e.g. 40th),
/// which gives an initial reward rate of ~60%. During the session it adapts
/// the threshold based on the recent success rate so the user stays in the
/// learning zone.
class RatioEngine implements FeedbackEngine {
  /// Direction-agnostic ratio engine, tagged with the [RewardMetric] the
  /// caller is currently extracting. Updated on protocol selection; the
  /// extraction lane ([FeedbackStateNotifier._metricOf]) feeds matching
  /// values.
  RewardMetric metric;

  /// Success-rate window in feedback epochs (~10 Hz, so this covers ~30 s).
  static const int epochWindow = 300;
  static const double highSuccessRate = 0.8;
  static const double lowSuccessRate = 0.4;

  /// Ceiling for dynamic adaptation, relative to the baseline stats.
  static const double ceilingStddevs = 1.5;

  /// Rolling window of recent session ratio samples (with a movement/artifact
  /// flag), used for in-flight recalibration.
  static const Duration recentWindow = Duration(seconds: 90);

  int percentile;
  final List<double> _baseline = [];
  final List<bool> _epochs = [];
  final List<({DateTime time, double value, bool clean})> _recent = [];
  double? _threshold;
  double? _initialThreshold;
  bool _dynamicAdapt = true;
  double _responsiveness = 0.5;

  RatioEngine({
    this.percentile = 40,
    this.metric = RewardMetric.alphaOverTheta,
  });

  @override
  bool get hasBaseline => _baseline.isNotEmpty;

  @override
  int get baselineCount => _baseline.length;

  @override
  int get baselinePercentile => percentile;

  @override
  double? get threshold => _threshold;

  @override
  bool get dynamicAdapt => _dynamicAdapt;

  @override
  double get responsiveness => _responsiveness;

  /// Raise/lower step derived from the responsiveness setting (gentle →
  /// responsive: raise 1.01–1.03, lower 0.97–0.90).
  (double raise, double lower) get _steps {
    final r = _responsiveness.clamp(0.0, 1.0).toDouble();
    return (1.01 + 0.02 * r, 1.0 - (0.03 + 0.07 * r));
  }

  /// Mean of the baseline ratio samples.
  @override
  double? get baselineMean {
    if (_baseline.isEmpty) {
      return null;
    }
    return _baseline.reduce((a, b) => a + b) / _baseline.length;
  }

  /// Standard deviation of the baseline ratio samples.
  @override
  double? get baselineStddev {
    if (_baseline.length < 2) {
      return null;
    }
    final mean = baselineMean!;
    final variance =
        _baseline.fold<double>(0, (a, s) => a + pow(s - mean, 2).toDouble()) /
        _baseline.length;
    return sqrt(variance);
  }

  /// Success rate over the current rolling epoch window, or null when the
  /// window is not full yet.
  @override
  double? get successRate {
    if (_epochs.length < epochWindow) {
      return null;
    }
    return _epochs.where((b) => b).length / _epochs.length;
  }

  @override
  void reset() {
    _baseline.clear();
    _epochs.clear();
    _recent.clear();
    _threshold = null;
    _initialThreshold = null;
  }

  @override
  void setDynamicAdapt(bool enabled) {
    _dynamicAdapt = enabled;
  }

  @override
  void setBaselinePercentile(int percentile) {
    this.percentile = percentile;
  }

  @override
  void setResponsiveness(double value) {
    _responsiveness = value.clamp(0.0, 1.0).toDouble();
  }

  @override
  void addBaselineSample(double atr) {
    _baseline.add(atr);
  }

  /// Sorts the baseline samples and picks the configured percentile as the
  /// initial threshold. Returns null if there is no baseline data.
  @override
  double? computeThreshold() {
    if (_baseline.isEmpty) {
      return null;
    }
    final sorted = [..._baseline]..sort();
    final idx = ((percentile / 100) * (sorted.length - 1)).round().clamp(
      0,
      sorted.length - 1,
    );
    _threshold = sorted[idx];
    _initialThreshold ??= _threshold;
    return _threshold;
  }

  @override
  bool isInTarget(double atr) {
    final t = _threshold;
    if (t == null) {
      return atr > 1.0;
    }
    return atr > t;
  }

  /// Percentile rank of [value] within the baseline distribution, or null if
  /// there is no baseline yet.
  @override
  double? percentileOf(double value) {
    if (_baseline.isEmpty) {
      return null;
    }
    final below = _baseline.where((s) => s < value).length;
    return (below / _baseline.length) * 100;
  }

  @override
  void recordEpoch(double value) {
    _epochs.add(isInTarget(value));
    if (_epochs.length > epochWindow) {
      _epochs.removeAt(0);
    }
  }

  /// Records a live session sample for in-flight recalibration. Samples
  /// older than [recentWindow] are pruned.
  @override
  void recordSessionSample(double value, {required bool clean}) {
    final now = DateTime.now();
    _recent.add((time: now, value: value, clean: clean));
    _recent.removeWhere((s) => now.difference(s.time) > recentWindow);
  }

  /// Re-anchors the baseline from the clean samples in the recent rolling
  /// window, recomputing the threshold at [percentile] and resetting the
  /// success-rate window. Returns false when fewer than [minSamples] clean
  /// samples are available.
  @override
  bool recalibrateFromRecent({int minSamples = 30}) {
    final now = DateTime.now();
    final clean = _recent
        .where((s) => now.difference(s.time) <= recentWindow && s.clean)
        .map((s) => s.value)
        .toList();
    if (clean.length < minSamples) {
      return false;
    }
    _baseline
      ..clear()
      ..addAll(clean);
    _epochs.clear();
    _initialThreshold = null;
    computeThreshold();
    return true;
  }

  /// Adjusts the threshold based on the recent success rate (rolling window of
  /// [epochWindow] epochs). Success above [highSuccessRate] means the task is
  /// too easy (threshold raised); below [lowSuccessRate] too hard (threshold
  /// lowered). The threshold is clamped between the baseline percentile and
  /// baselineMean + [ceilingStddevs] standard deviations so it can never race
  /// beyond what the user can physically produce, and a zero-success window
  /// immediately resets it to the baseline percentile (circuit breaker).
  @override
  void adapt() {
    if (!_dynamicAdapt) {
      return;
    }
    final t = _threshold;
    final initial = _initialThreshold;
    if (t == null || initial == null || _epochs.length < epochWindow) {
      return;
    }
    final mean = baselineMean;
    final sd = baselineStddev;
    final (raise, lower) = _steps;
    final maxAllowed = mean == null || sd == null
        ? t * raise
        : mean + ceilingStddevs * sd;
    final success = _epochs.where((b) => b).length / _epochs.length;
    if (success == 0.0) {
      _threshold = initial;
      debugPrint(
        '[atr] adapt: success=0.0 — circuit breaker, '
        'threshold $t -> $initial',
      );
    } else if (success > highSuccessRate) {
      final next = (t * raise).clamp(initial, maxAllowed).toDouble();
      _threshold = next;
      debugPrint(
        '[atr] adapt: success=$success > $highSuccessRate '
        'threshold $t -> $next (ceiling $maxAllowed)',
      );
    } else if (success < lowSuccessRate) {
      final next = (t * lower).clamp(initial, maxAllowed).toDouble();
      _threshold = next;
      debugPrint(
        '[atr] adapt: success=$success < $lowSuccessRate '
        'threshold $t -> $next (floor $initial)',
      );
    } else {
      debugPrint(
        '[atr] adapt: success=$success in zone, '
        'threshold stays $t',
      );
    }
  }
}

class TargetStateAggregator {
  final Map<int, _ChannelBands> _latest = {};

  void update(BandsDto bands) {
    if (bands.electrode == electrodeAf7 || bands.electrode == electrodeAf8) {
      _latest[bands.electrode] = _ChannelBands(
        timestamp: bands.timestamp,
        delta: bands.delta,
        theta: bands.theta,
        alpha: bands.alpha,
        beta: bands.beta,
        gamma: bands.gamma,
      );
    }
  }

  void reset() {
    _latest.clear();
  }

  /// Resolves the combined per-sample relative bands from the two frontal
  /// pads, dropping any pad whose signal quality is currently below
  /// [atrUsableSignalThreshold] instead of averaging corrupted data into the
  /// result. Uses the single usable pad when the other is bad, and returns
  /// null only when neither pad is usable.
  RelativeTarget? evaluate([List<double>? quality]) {
    final af7 = _latest[electrodeAf7];
    final af8 = _latest[electrodeAf8];
    final picked = <_RelativeBands>[];
    if (af7 != null && _padUsable(quality, electrodeAf7)) {
      final rel = af7.relative();
      if (rel != null) picked.add(rel);
    }
    if (af8 != null && _padUsable(quality, electrodeAf8)) {
      final rel = af8.relative();
      if (rel != null) picked.add(rel);
    }
    if (picked.isEmpty) {
      return null;
    }
    return RelativeTarget(
      alphaRel: _avg(picked.map((r) => r.alpha)),
      thetaRel: _avg(picked.map((r) => r.theta)),
      betaRel: _avg(picked.map((r) => r.beta)),
      gammaRel: _avg(picked.map((r) => r.gamma)),
    );
  }

  static bool _padUsable(List<double>? quality, int electrode) {
    if (quality == null || electrode >= quality.length) return false;
    return quality[electrode] >= atrUsableSignalThreshold;
  }

  static double _avg(Iterable<double> values) {
    var sum = 0.0;
    var count = 0;
    for (final v in values) {
      sum += v;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }
}

class _ChannelBands {
  const _ChannelBands({
    required this.timestamp,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
  });

  final double timestamp;
  final double delta;
  final double theta;
  final double alpha;
  final double beta;
  final double gamma;

  _RelativeBands? relative() {
    final total = delta + theta + alpha + beta + gamma;
    if (total <= 0) {
      return null;
    }
    return _RelativeBands(
      alpha: alpha / total,
      theta: theta / total,
      beta: beta / total,
      gamma: gamma / total,
    );
  }
}

class _RelativeBands {
  const _RelativeBands({
    required this.alpha,
    required this.theta,
    required this.beta,
    required this.gamma,
  });

  final double alpha;
  final double theta;
  final double beta;
  final double gamma;
}
