import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/feedback/feedback_engine.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

/// A per-pad signal-quality score at or above this value is treated as a
/// "good" electrode and contributes to inhibit relative-band aggregation.
/// Pads below it are dropped for that sample. Kept in sync with
/// [signalGoodThreshold] so the calibration gate and the live autodrop use
/// the same notion of a good contact.
const double atrUsableSignalThreshold = 80.0;

const double movementGateThreshold = 0.05;

class RelativeTarget {
  const RelativeTarget({
    required this.deltaRel,
    required this.alphaRel,
    required this.thetaRel,
    required this.betaRel,
    required this.gammaRel,
  });

  final double deltaRel;
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
  /// protocols whose reward feature is `band.tar` (a data-only flip of the
  /// same ratio engine).
  double get tar {
    if (alphaRel <= 0) {
      return double.infinity;
    }
    return thetaRel / alphaRel;
  }

  /// Beta/Theta power ratio (BTR) — the classic alertness ratio.
  double get betaTheta {
    if (thetaRel <= 0) {
      return double.infinity;
    }
    return betaRel / thetaRel;
  }
}

/// Continuous band-ratio uptraining engine.
///
/// The engine is direction-agnostic: it collects samples of a scalar ratio,
/// derives the session threshold from a configurable percentile of that
/// baseline distribution, and rewards the user while the live value beats the
/// threshold. The [featureId] tag says which ratio feeds it (`band.atr`
/// etc. — changing a protocol's feature is a data-only change: same engine,
/// flipped extraction).
///
/// During calibration it collects clean ratio samples. The session threshold is
/// the configurable percentile of that baseline distribution (e.g. 40th),
/// which gives an initial reward rate of ~60%. During the session it adapts
/// the threshold based on the recent success rate so the user stays in the
/// learning zone.
class RatioEngine implements FeedbackEngine {
  /// Direction-agnostic ratio engine, tagged with the reward feature id the
  /// caller is currently feeding ([FeatureDto.value]).
  String featureId;

  /// Wall-clock success-rate window. Equivalent of today's 300 epochs at
  /// ~4 Hz `_onBands` (not 30 one-Hz [FeatureDto] samples).
  static const int epochWindowSeconds = 75;
  static const double highSuccessRate = 0.8;
  static const double lowSuccessRate = 0.4;

  /// Ceiling for dynamic adaptation, relative to the baseline stats.
  static const double ceilingStddevs = 1.5;

  /// Rolling window of recent session ratio samples (with a movement/artifact
  /// flag), used for in-flight recalibration.
  static const Duration recentWindow = Duration(seconds: 90);

  /// EMA smoothing factor for continuous adaptation (0.0-1.0). Higher values
  /// adapt faster. Default 0.1 gives a time constant of ~10 samples.
  static const double defaultEmaAlpha = 0.1;

  int percentile;
  final List<double> _baseline = [];
  final List<({DateTime time, bool inTarget})> _epochs = [];
  final List<({DateTime time, double value, bool clean})> _recent = [];
  DateTime? _epochStartedAt;
  double? _threshold;
  double? _initialThreshold;
  bool _dynamicAdapt = true;
  double _responsiveness = 0.5;
  bool _useEmaAdapt = false;
  double _emaAlpha = defaultEmaAlpha;
  double? _emaThreshold;

  /// Experimental `bandStability` mode (null = normal uptrain). See
  /// [StabilityConfig]. In this mode the baseline pile holds the per-window
  /// fluctuation ratios r = CV(window) ÷ baseline CV, [threshold] is a ratio
  /// (in target when r ≤ threshold) and [adapt] steps it the other way.
  StabilityConfig? _stability;
  final List<double> _rawBaseline = [];
  final List<double> _liveWindow = [];
  double? _baselineCv;

  /// Wall-clock success window. Production is [epochWindowSeconds]; tests may
  /// pass a shorter duration.
  final Duration epochWindow;

  RatioEngine({
    this.percentile = 40,
    this.featureId = 'band.atr',
    Duration? epochWindow,
  }) : epochWindow = epochWindow ?? const Duration(seconds: epochWindowSeconds);

  StabilityConfig? get stability => _stability;

  /// Baseline fluctuation (median rolling-window CV of the calibration
  /// samples). Null outside stability mode or before [computeThreshold].
  double? get baselineCv => _baselineCv;

  /// Switch stability mode on ([config] non-null) or off. Clears the live
  /// window; the baseline is re-derived on the next [computeThreshold].
  void setStability(StabilityConfig? config) {
    final wasOn = _stability != null;
    _stability = config;
    _liveWindow.clear();
    if (config == null && wasOn) {
      _baselineCv = null;
    }
  }

  /// Change the difficulty mid-session: re-anchors the threshold at
  /// 1 − difficulty (the adaptive step may move it again).
  void setStabilityDifficulty(double difficulty) {
    final cfg = _stability;
    if (cfg == null) return;
    _stability = cfg.copyWith(difficulty: difficulty);
    if (_baselineCv != null) {
      _threshold = _stability!.initialThreshold;
      _initialThreshold = _threshold;
    }
  }

  /// Change the window mid-session: clears the live window and re-derives
  /// the baseline CV for the new length.
  void setStabilityWindow(int seconds) {
    final cfg = _stability;
    if (cfg == null) return;
    _stability = cfg.copyWith(windowSeconds: seconds);
    _liveWindow.clear();
    if (_rawBaseline.isNotEmpty) {
      _initialThreshold = null;
      computeThreshold();
    }
  }

  /// Push one **clean** 1 Hz band value into the rolling stability window.
  /// Returns r = CV(last N clean values) ÷ [baselineCv] once the window is
  /// full, else null (warm-up). Dirty samples must not be pushed: they are
  /// excluded, not counted as unstable.
  double? pushStabilitySample(double value) {
    final cfg = _stability;
    final base = _baselineCv;
    if (cfg == null || !value.isFinite) return null;
    _liveWindow.add(value);
    final n = cfg.effectiveWindow;
    while (_liveWindow.length > n) {
      _liveWindow.removeAt(0);
    }
    if (base == null || base <= 0 || _liveWindow.length < n) return null;
    final cv = coefficientOfVariation(_liveWindow);
    if (cv == null) return null;
    return cv / base;
  }

  /// Live-window fill (clean samples so far, window length).
  (int, int) get stabilityWindowFill =>
      (_liveWindow.length, _stability?.effectiveWindow ?? 0);

  @override
  bool get hasBaseline => _baseline.isNotEmpty;

  @override
  int get baselineCount => _baseline.length;

  /// Copy of the rest-pile samples. Getter only — no math change.
  List<double> get baselineSamples => List<double>.unmodifiable(_baseline);

  @override
  int get baselinePercentile => percentile;

  @override
  double? get threshold => _threshold;

  @override
  bool get dynamicAdapt => _dynamicAdapt;

  @override
  double get responsiveness => _responsiveness;

  /// Whether continuous EMA adaptation is enabled. When true, the threshold
  /// is updated on every clean sample using an exponential moving average
  /// toward the target percentile, providing smoother continuous adaptation
  /// compared to the window-based step adaptation.
  bool get useEmaAdapt => _useEmaAdapt;

  /// Sets whether to use continuous EMA adaptation.
  void setUseEmaAdapt(bool enabled) {
    _useEmaAdapt = enabled;
  }

  /// EMA smoothing factor (alpha). Higher values = faster adaptation.
  double get emaAlpha => _emaAlpha;

  /// Sets the EMA smoothing factor.
  void setEmaAlpha(double alpha) {
    _emaAlpha = alpha.clamp(0.0, 1.0).toDouble();
  }

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
  /// window is not full yet ([epochWindow] of wall-clock time).
  @override
  double? get successRate {
    if (!_epochWindowFull) {
      return null;
    }
    return _epochs.where((e) => e.inTarget).length / _epochs.length;
  }

  bool get _epochWindowFull {
    final start = _epochStartedAt;
    if (start == null || _epochs.isEmpty) {
      return false;
    }
    return DateTime.now().difference(start) >= epochWindow;
  }

  @override
  void reset() {
    _baseline.clear();
    _epochs.clear();
    _recent.clear();
    _epochStartedAt = null;
    _threshold = null;
    _initialThreshold = null;
    _emaThreshold = null;
    _rawBaseline.clear();
    _liveWindow.clear();
    _baselineCv = null;
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
    if (_stability != null) {
      _rawBaseline.add(atr);
      return;
    }
    _baseline.add(atr);
  }

  /// Stability mode: baseline CV = median of the rolling-window CVs over the
  /// clean calibration samples (same window as live, so live and baseline
  /// measure the same thing); the pile becomes those windows' ratios to it.
  double? _computeStabilityThreshold() {
    final cfg = _stability!;
    final cvs = rollingCvs(_rawBaseline, cfg.effectiveWindow);
    if (cvs.isEmpty) {
      _baselineCv = null;
      _threshold = null;
      return null;
    }
    final sorted = [...cvs]..sort();
    final median = sorted[sorted.length ~/ 2];
    if (!(median > 0)) {
      _baselineCv = null;
      _threshold = null;
      return null;
    }
    _baselineCv = median;
    _baseline
      ..clear()
      ..addAll([for (final c in cvs) c / median]);
    _threshold = cfg.initialThreshold;
    _initialThreshold ??= _threshold;
    return _threshold;
  }

  /// Sorts the baseline samples and picks the configured percentile as the
  /// initial threshold. Returns null if there is no baseline data.
  @override
  double? computeThreshold() {
    if (_stability != null) {
      return _computeStabilityThreshold();
    }
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
    if (_stability != null) {
      // Lower fluctuation ratio = steadier.
      final t = _threshold;
      return t != null && atr <= t;
    }
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
  void recordEpoch(bool inTarget) {
    final now = DateTime.now();
    _epochStartedAt ??= now;
    _epochs.add((time: now, inTarget: inTarget));
    _epochs.removeWhere((e) => now.difference(e.time) > epochWindow);
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
    if (_stability != null) {
      _rawBaseline
        ..clear()
        ..addAll(clean);
      _liveWindow.clear();
    } else {
      _baseline
        ..clear()
        ..addAll(clean);
    }
    _epochs.clear();
    _epochStartedAt = null;
    _initialThreshold = null;
    computeThreshold();
    return true;
  }

  /// Adjusts the threshold based on the recent success rate (rolling
  /// [epochWindow] of wall-clock time). Success above [highSuccessRate] means
  /// the task is too easy (threshold raised); below [lowSuccessRate] too hard
  /// (threshold lowered). The threshold is clamped between the baseline
  /// percentile and baselineMean + [ceilingStddevs] standard deviations so it
  /// can never race beyond what the user can physically produce, and a
  /// zero-success window immediately resets it to the baseline percentile
  /// (circuit breaker).
  @override
  void adapt() {
    if (!_dynamicAdapt) {
      return;
    }
    final t = _threshold;
    final initial = _initialThreshold;
    if (t == null || initial == null || !_epochWindowFull) {
      return;
    }
    if (_stability != null) {
      _adaptStability(t, initial);
      return;
    }
    final mean = baselineMean;
    final sd = baselineStddev;
    final (raise, lower) = _steps;
    final maxAllowed = mean == null || sd == null
        ? t * raise
        : mean + ceilingStddevs * sd;
    final success = _epochs.where((e) => e.inTarget).length / _epochs.length;
    if (success == 0.0) {
      _threshold = initial;
      _emaThreshold = initial;
      debugPrint(
        '[atr] adapt: success=0.0 — circuit breaker, '
        'threshold $t -> $initial',
      );
    } else if (success > highSuccessRate) {
      final next = (t * raise).clamp(initial, maxAllowed).toDouble();
      _threshold = next;
      _emaThreshold = next;
      debugPrint(
        '[atr] adapt: success=$success > $highSuccessRate '
        'threshold $t -> $next (ceiling $maxAllowed)',
      );
    } else if (success < lowSuccessRate) {
      final next = (t * lower).clamp(initial, maxAllowed).toDouble();
      _threshold = next;
      _emaThreshold = next;
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

  /// Downtrain mirror of [adapt]: too easy (> [highSuccessRate]) lowers the
  /// ratio threshold (needs steadier), too hard (< [lowSuccessRate]) raises
  /// it, clamped to [floor, initial] where floor = mean − [ceilingStddevs]·sd
  /// of the baseline window ratios (≥ [StabilityConfig.minThreshold]). Never
  /// easier than the difficulty the user set; zero success resets.
  void _adaptStability(double t, double initial) {
    final mean = baselineMean;
    final sd = baselineStddev;
    final (raise, lower) = _steps;
    // Allow at least 0.3 of headroom below the difficulty anchor even when
    // the baseline spread is ~0 (mean − 1.5 sd would sit above it).
    final spreadFloor = mean == null || sd == null
        ? initial * lower
        : mean - ceilingStddevs * sd;
    var floor = spreadFloor < initial - 0.3 ? spreadFloor : initial - 0.3;
    floor = floor.clamp(StabilityConfig.minThreshold, initial).toDouble();
    final success = _epochs.where((e) => e.inTarget).length / _epochs.length;
    if (success == 0.0) {
      _threshold = initial;
    } else if (success > highSuccessRate) {
      // raise step < 1 → (2 − raise) is the mirrored "harder" factor.
      _threshold = (t * (2 - raise)).clamp(floor, initial).toDouble();
    } else if (success < lowSuccessRate) {
      _threshold = (t * (2 - lower)).clamp(floor, initial).toDouble();
    }
    debugPrint(
      '[stability] adapt: success=$success threshold $t -> $_threshold '
      '(floor $floor, initial $initial)',
    );
  }

  /// Continuous EMA adaptation: updates the threshold toward the target
  /// percentile on each clean sample. This provides smoother, continuous
  /// adaptation compared to the window-based step adaptation.
  /// [value] is the current ratio sample (e.g., ATR value).
  /// Returns the updated threshold, or null if EMA adaptation is not enabled
  /// or no threshold exists yet.
  double? adaptEma(double value) {
    if (!_useEmaAdapt || !_dynamicAdapt || _stability != null) {
      return null;
    }
    final t = _threshold;
    final initial = _initialThreshold;
    if (t == null || initial == null) {
      return null;
    }
    final mean = baselineMean;
    final sd = baselineStddev;
    final maxAllowed = mean == null || sd == null
        ? t * (1.0 + _responsiveness * 0.02)
        : mean + ceilingStddevs * sd;

    _emaThreshold ??= t;

    // EMA: threshold += alpha * (value - threshold), clamped to
    // [initial, maxAllowed].
    final alpha = _emaAlpha;
    var next = _emaThreshold! + alpha * (value - _emaThreshold!);
    next = next.clamp(initial, maxAllowed);
    _emaThreshold = next;

    _threshold = next;

    debugPrint(
      '[atr] ema: value=${value.toStringAsFixed(3)} '
      'thr=${_threshold!.toStringAsFixed(3)} (alpha=$alpha)',
    );
    return _threshold;
  }
}

/// Settings of the experimental `bandStability` reward (policy
/// [stabilityPolicy]). Reward while the chosen band's coefficient of
/// variation over the last [windowSeconds] clean 1 Hz samples is at least
/// [difficulty] (fraction) below the calibration baseline CV.
@immutable
class StabilityConfig {
  const StabilityConfig({
    this.windowSeconds = defaultWindowSeconds,
    this.difficulty = defaultDifficulty,
  });

  static const int defaultWindowSeconds = 10;
  static const int minWindowSeconds = 1;
  static const int maxWindowSeconds = 30;
  static const double defaultDifficulty = 0.10;
  static const double maxDifficulty = 0.50;

  /// Lowest ratio threshold the adaptive step may reach.
  static const double minThreshold = 0.05;

  final int windowSeconds;
  final double difficulty;

  /// A CV needs ≥ 2 samples: a 1 s window is computed over 2 clean samples.
  int get effectiveWindow => windowSeconds < 2 ? 2 : windowSeconds;

  /// In target when r = CV ÷ baseline CV ≤ 1 − difficulty.
  double get initialThreshold => 1.0 - difficulty;

  StabilityConfig copyWith({int? windowSeconds, double? difficulty}) =>
      StabilityConfig(
        windowSeconds: clampStabilityWindow(
          windowSeconds ?? this.windowSeconds,
        ),
        difficulty: clampStabilityDifficulty(difficulty ?? this.difficulty),
      );
}

int clampStabilityWindow(int s) => s
    .clamp(StabilityConfig.minWindowSeconds, StabilityConfig.maxWindowSeconds)
    .toInt();

double clampStabilityDifficulty(double d) =>
    d.isFinite ? d.clamp(0.0, StabilityConfig.maxDifficulty).toDouble() : 0.1;

/// Population SD ÷ |mean|; null for < 2 values or a zero mean.
double? coefficientOfVariation(List<double> values) {
  if (values.length < 2) return null;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  final mean = sum / values.length;
  if (mean.abs() < 1e-12) return null;
  var ss = 0.0;
  for (final v in values) {
    ss += (v - mean) * (v - mean);
  }
  return sqrt(ss / values.length) / mean.abs();
}

/// CVs of every full rolling window of [window] consecutive [values]. When
/// there are fewer values than [window] (≥ 2), one CV over all of them.
List<double> rollingCvs(List<double> values, int window) {
  final w = window < 2 ? 2 : window;
  final out = <double>[];
  if (values.length < 2) return out;
  if (values.length < w) {
    final cv = coefficientOfVariation(values);
    if (cv != null) out.add(cv);
    return out;
  }
  for (var i = 0; i + w <= values.length; i++) {
    final cv = coefficientOfVariation(values.sublist(i, i + w));
    if (cv != null) out.add(cv);
  }
  return out;
}

/// Relative-band aggregator for **inhibit + nerd-stats**, not the reward
/// scalar. Reward native values come from [FeatureDto]. Electrodes are
/// montage **names** (Muse AF7/AF8); Dart's 4-slot quality autodrops pads.
class RelativeBandAggregator {
  RelativeBandAggregator(this.electrodeNames, {required this.montageNames});

  final List<String> electrodeNames;
  final List<String> montageNames;
  final Map<int, _ChannelBands> _latest = {};

  Set<int> get _indices {
    final out = <int>{};
    for (final name in electrodeNames) {
      final i = montageNames.indexOf(name);
      if (i >= 0) {
        out.add(i);
      }
    }
    return out;
  }

  void update(BandsDto bands) {
    if (_indices.contains(bands.electrode)) {
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

  /// Resolves the combined per-sample relative bands from the named pads,
  /// dropping any pad whose signal quality is currently below
  /// [atrUsableSignalThreshold] instead of averaging corrupted data into the
  /// result. Uses any remaining usable pad, and returns null only when none
  /// of the named pads are usable.
  RelativeTarget? evaluate([List<double>? quality]) {
    final picked = <_RelativeBands>[];
    for (final i in _indices) {
      final ch = _latest[i];
      if (ch == null || !_padUsable(quality, i)) {
        continue;
      }
      final rel = ch.relative();
      if (rel != null) {
        picked.add(rel);
      }
    }
    if (picked.isEmpty) {
      return null;
    }
    return RelativeTarget(
      deltaRel: _avg(picked.map((r) => r.delta)),
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
      delta: delta / total,
      alpha: alpha / total,
      theta: theta / total,
      beta: beta / total,
      gamma: gamma / total,
    );
  }
}

class _RelativeBands {
  const _RelativeBands({
    required this.delta,
    required this.alpha,
    required this.theta,
    required this.beta,
    required this.gamma,
  });

  final double delta;
  final double alpha;
  final double theta;
  final double beta;
  final double gamma;
}
