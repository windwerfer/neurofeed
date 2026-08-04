import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

const int electrodeAf7 = 1;
const int electrodeAf8 = 2;

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
}

/// Continuous Alpha/Theta ratio (ATR) uptraining engine.
///
/// During calibration it collects clean ATR samples. The session threshold is
/// the configurable percentile of that baseline distribution (e.g. 40th),
/// which gives an initial reward rate of ~60%. During the session it adapts
/// the threshold based on the recent success rate so the user stays in the
/// learning zone.
class AtrEngine {
  static const int epochWindow = 30;
  static const double highSuccessRate = 0.8;
  static const double lowSuccessRate = 0.4;
  static const double raiseFactor = 1.05;
  static const double lowerFactor = 0.95;

  /// Rolling window of recent session ATR samples (with a movement/artifact
  /// flag), used for in-flight recalibration.
  static const Duration recentWindow = Duration(seconds: 90);

  int percentile;
  final List<double> _baseline = [];
  final List<bool> _epochs = [];
  final List<({DateTime time, double atr, bool clean})> _recent = [];
  double? _threshold;

  AtrEngine({this.percentile = 40});

  bool get hasBaseline => _baseline.isNotEmpty;

  int get baselineCount => _baseline.length;

  double? get threshold => _threshold;

  /// Mean of the baseline ATR samples.
  double? get baselineMean {
    if (_baseline.isEmpty) {
      return null;
    }
    return _baseline.reduce((a, b) => a + b) / _baseline.length;
  }

  /// Standard deviation of the baseline ATR samples.
  double? get baselineStddev {
    if (_baseline.length < 2) {
      return null;
    }
    final mean = baselineMean!;
    final variance = _baseline
            .fold<double>(0, (a, s) => a + pow(s - mean, 2).toDouble()) /
        _baseline.length;
    return sqrt(variance);
  }

  /// Success rate over the current rolling epoch window, or null when the
  /// window is not full yet.
  double? get successRate {
    if (_epochs.length < epochWindow) {
      return null;
    }
    return _epochs.where((b) => b).length / _epochs.length;
  }

  void reset() {
    _baseline.clear();
    _epochs.clear();
    _recent.clear();
    _threshold = null;
  }

  void addBaselineSample(double atr) {
    _baseline.add(atr);
  }

  /// Sorts the baseline ATR samples and picks the configured percentile as the
  /// initial threshold. Returns null if there is no baseline data.
  double? computeThreshold() {
    if (_baseline.isEmpty) {
      return null;
    }
    final sorted = [..._baseline]..sort();
    final idx = ((percentile / 100) * (sorted.length - 1))
        .round()
        .clamp(0, sorted.length - 1);
    _threshold = sorted[idx];
    return _threshold;
  }

  bool isInTarget(double atr) {
    final t = _threshold;
    if (t == null) {
      return atr > 1.0;
    }
    return atr > t;
  }

  /// Percentile rank of [value] within the baseline distribution, or null if
  /// there is no baseline yet.
  double? percentileOf(double value) {
    if (_baseline.isEmpty) {
      return null;
    }
    final below = _baseline.where((s) => s < value).length;
    return (below / _baseline.length) * 100;
  }

  void recordEpoch(double atr) {
    _epochs.add(isInTarget(atr));
    if (_epochs.length > epochWindow) {
      _epochs.removeAt(0);
    }
  }

  /// Records a live session ATR sample for in-flight recalibration. Samples
  /// older than [recentWindow] are pruned.
  void recordSessionSample(double atr, {required bool clean}) {
    final now = DateTime.now();
    _recent.add((time: now, atr: atr, clean: clean));
    _recent.removeWhere((s) => now.difference(s.time) > recentWindow);
  }

  /// Re-anchors the baseline from the clean samples in the recent rolling
  /// window, recomputing the threshold at [percentile] and resetting the
  /// success-rate window. Returns false when fewer than [minSamples] clean
  /// samples are available.
  bool recalibrateFromRecent({int minSamples = 30}) {
    final now = DateTime.now();
    final clean = _recent
        .where((s) => now.difference(s.time) <= recentWindow && s.clean)
        .map((s) => s.atr)
        .toList();
    if (clean.length < minSamples) {
      return false;
    }
    _baseline
      ..clear()
      ..addAll(clean);
    _epochs.clear();
    computeThreshold();
    return true;
  }

  /// Adjusts the threshold based on the recent success rate (rolling window of
  /// [epochWindow] epochs). Success above [highSuccessRate] means the task is
  /// too easy (threshold raised); below [lowSuccessRate] too hard (threshold
  /// lowered).
  void adapt() {
    final t = _threshold;
    if (t == null || _epochs.length < epochWindow) {
      return;
    }
    final success = _epochs.where((b) => b).length / _epochs.length;
    if (success > highSuccessRate) {
      _threshold = t * raiseFactor;
      debugPrint('[atr] adapt: success=$success > $highSuccessRate '
          'threshold $t -> $_threshold');
    } else if (success < lowSuccessRate) {
      _threshold = t * lowerFactor;
      debugPrint('[atr] adapt: success=$success < $lowSuccessRate '
          'threshold $t -> $_threshold');
    } else {
      debugPrint('[atr] adapt: success=$success in zone, '
          'threshold stays $t');
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

  RelativeTarget? evaluate() {
    final af7 = _latest[electrodeAf7];
    final af8 = _latest[electrodeAf8];
    if (af7 == null || af8 == null) {
      return null;
    }
    final rel7 = af7.relative();
    final rel8 = af8.relative();
    if (rel7 == null || rel8 == null) {
      return null;
    }
    return RelativeTarget(
      alphaRel: (rel7.alpha + rel8.alpha) / 2,
      thetaRel: (rel7.theta + rel8.theta) / 2,
      betaRel: (rel7.beta + rel8.beta) / 2,
      gammaRel: (rel7.gamma + rel8.gamma) / 2,
    );
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
