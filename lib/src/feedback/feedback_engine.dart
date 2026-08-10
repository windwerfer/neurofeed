/// Pluggable feedback reward engine.
///
/// [FeedbackStateNotifier] delegates the entire reward lane here: collecting
/// the calibration baseline, computing/adapting the reward threshold, deciding
/// whether a sample is "in target", and exposing the stats shown in the nerd
/// bubble. Adding a new feedback option means writing one more implementation
/// of this interface — the session lifecycle (signal gate, calibration timing,
/// recorder, pause/resume, interruptions) is protocol-agnostic.
///
/// Signal extraction (turning raw band/EEG/REVE events into the per-sample
/// value passed to [addBaselineSample]/[recordEpoch]/[isInTarget]) stays with
/// the caller because each protocol consumes a different event stream.
abstract class FeedbackEngine {
  /// Reset all engine state (baseline, threshold, epoch window, recent
  /// samples) for a new session or calibration. Does NOT reset anything the
  /// caller owns.
  void reset();

  bool get hasBaseline;

  /// Number of clean baseline samples collected during calibration.
  int get baselineCount;

  /// Percentile of the baseline distribution used as the initial threshold.
  int get baselinePercentile;

  /// Mean of the calibration baseline samples (null until a baseline exists).
  double? get baselineMean;

  /// Standard deviation of the calibration baseline samples.
  double? get baselineStddev;

  /// The current reward/decision threshold, or null until the baseline is
  /// computed.
  double? get threshold;

  /// Rolling success rate over the epoch window, or null until the window is
  /// full.
  double? get successRate;

  void setBaselinePercentile(int percentile);

  /// Derive the initial reward threshold from the baseline distribution.
  double? computeThreshold();

  /// Record one clean calibration sample.
  void addBaselineSample(double value);

  /// Whether [value] should be rewarded (i.e. it beats the threshold).
  bool isInTarget(double value);

  /// Percentile rank of [value] within the baseline distribution, or null when
  /// no baseline exists yet.
  double? percentileOf(double value);

  /// Record one live epoch for the rolling success-rate window.
  void recordEpoch(double value);

  /// Record a live sample for the in-flight recalibration recent window.
  void recordSessionSample(double value, {required bool clean});

  /// Periodically move the threshold based on the recent success rate.
  void adapt();

  /// Re-anchor the baseline from recent clean live samples.
  bool recalibrateFromRecent({int minSamples});

  bool get dynamicAdapt;

  double get responsiveness;

  void setDynamicAdapt(bool enabled);

  void setResponsiveness(double value);
}
