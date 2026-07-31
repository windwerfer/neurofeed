import 'package:muse_ml/src/rust/api/muse.dart';

const int electrodeAf7 = 1;
const int electrodeAf8 = 2;

const double movementGateThreshold = 0.05;

class BaselineProfile {
  const BaselineProfile({required this.alphaRel, required this.thetaRel});

  final double alphaRel;
  final double thetaRel;
}

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
}

/// v1 predicate: relative alpha power exceeds relative theta power on the
/// AF7/AF8 average. v1.1: pass a BaselineProfile for a personalized threshold.
bool isAlphaThetaTarget({
  required double alphaRel,
  required double thetaRel,
  BaselineProfile? baseline,
}) {
  if (baseline != null) {
    return alphaRel > baseline.alphaRel * 1.2;
  }
  return alphaRel > thetaRel;
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
