import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/session_v5/computed_frame.dart';

class ComputedSampler {
  ComputedSampler({
    required this.onFrame,
    required DateTime recordingStart,
    this.interval = const Duration(seconds: 1),
    DateTime Function()? now,
  })  : _recordingStart = recordingStart,
        _now = now ?? DateTime.now;

  final void Function(ComputedFrame) onFrame;
  final Duration interval;
  final DateTime _recordingStart;
  final DateTime Function() _now;

  Timer? _timer;
  Duration _pauseAccumulated = Duration.zero;
  DateTime? _pauseBegan;

  // Latest values from event stream (updated by FeedbackStateNotifier)
  // Bands per electrode (4 electrodes × 5 bands)
  final List<List<double>> _latestBands = List.generate(4, (_) => [0.0, 0.0, 0.0, 0.0, 0.0]);
  double? _latestPulse;
  double? _latestMovement;
  PeakAlphaDto? _latestPeakAlpha;
  double? _latestSpO2;
  final List<double> _latestLineNoise = List.filled(4, 0.0);
  final List<int> _latestSignalQuality = List.filled(4, 0);
  double _lastSleepDir = 0.0;
  double _lastClarity = 0.0;
  double _lastDelta = 0.0;
  bool _warningActive = false;
  double _lastRatio = 0.0;
  double? _feedbackThreshold;
  bool _lastInTarget = false;
  double _inTargetPct = 0.0;
  double? _feedbackPercentile;
  double? _feedbackThresholdPercentile;
  bool? _feedbackHeldBack;
  List<String>? _feedbackInhibitTags;
  bool? _feedbackClean;
  String? _feedbackDirtyReason;
  double? _feedbackBetaRel;
  double? _feedbackDeltaRel;
  double? _guardFeaturePercentile;
  bool? _guardWarnOver;
  bool? _guardCeilingOver;
  bool? _guardClean;
  String? _guardDirtyReason;
  final List<String> _latestGestures = [];

  void updateBands(int electrode, BandsDto bands) {
    if (electrode >= 0 && electrode < 4) {
      _latestBands[electrode] = [
        bands.delta,
        bands.theta,
        bands.alpha,
        bands.beta,
        bands.gamma,
      ];
      _latestLineNoise[electrode] = bands.lineNoiseRatio;
    }
  }

  void updatePulse(PulseDto pulse) => _latestPulse = pulse.bpm;

  void updateMovement(MovementDto movement) => _latestMovement = movement.score;

  void updatePeakAlpha(PeakAlphaDto peakAlpha) => _latestPeakAlpha = peakAlpha;

  void updateSpO2(SpO2Dto spo2) => _latestSpO2 = spo2.spo2;

  void updateSignalQuality(int electrode, int quality) {
    if (electrode >= 0 && electrode < 4) {
      _latestSignalQuality[electrode] = quality;
    }
  }

  void updateGuardrail({
    required double sleepDir,
    required double clarity,
    required double delta,
    required bool warning,
    double? threshold,
    double? featurePercentile,
    bool? warnOver,
    bool? ceilingOver,
    bool? clean,
    String? dirtyReason,
  }) {
    _lastSleepDir = sleepDir;
    _lastClarity = clarity;
    _lastDelta = delta;
    _warningActive = warning;
    if (featurePercentile != null) {
      _guardFeaturePercentile = featurePercentile;
    }
    if (warnOver != null) {
      _guardWarnOver = warnOver;
    }
    if (ceilingOver != null) {
      _guardCeilingOver = ceilingOver;
    }
    if (clean != null) {
      _guardClean = clean;
      if (clean) {
        _guardDirtyReason = null;
      } else if (dirtyReason != null) {
        _guardDirtyReason = dirtyReason;
      }
    } else if (dirtyReason != null) {
      _guardDirtyReason = dirtyReason;
    }
  }

  void updateFeedback({
    required double ratio,
    required double? threshold,
    required bool inTarget,
    required double inTargetPct,
    double? percentile,
    double? thresholdPercentile,
    bool? heldBack,
    List<String>? inhibitTags,
    bool? clean,
    String? dirtyReason,
    double? betaRel,
    double? deltaRel,
  }) {
    _lastRatio = ratio;
    _feedbackThreshold = threshold;
    _lastInTarget = inTarget;
    _inTargetPct = inTargetPct;
    _feedbackPercentile = percentile;
    _feedbackThresholdPercentile = thresholdPercentile;
    _feedbackHeldBack = heldBack;
    _feedbackInhibitTags = inhibitTags;
    _feedbackClean = clean;
    _feedbackDirtyReason = dirtyReason;
    _feedbackBetaRel = betaRel;
    _feedbackDeltaRel = deltaRel;
  }

  void updateGestures(List<String> gestures) {
    _latestGestures.clear();
    _latestGestures.addAll(gestures);
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _emitFrame());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stop emitting frames; content clock freezes (wall pause accumulates).
  void pause() {
    if (_pauseBegan != null) {
      return;
    }
    stop();
    _pauseBegan = _now();
  }

  /// Resume emitting; [t] continues from the pre-pause content clock.
  void resume() {
    if (_pauseBegan != null) {
      _pauseAccumulated += _now().difference(_pauseBegan!);
      _pauseBegan = null;
    }
    start();
  }

  /// Seconds of wall time excluded from the content clock so far.
  @visibleForTesting
  double get pauseAccumulatedSeconds =>
      _pauseAccumulated.inMilliseconds / 1000.0;

  /// Seconds from [recordingStart] using the injected clock.
  @visibleForTesting
  void emitFrame() => _emitFrame();

  void _emitFrame() {
    final wall = _now().difference(_recordingStart);
    final content = wall - _pauseAccumulated;
    final t = content.inMilliseconds / 1000.0;

    final frame = ComputedFrame(
      t: t,
      bands: List.from(_latestBands),
      pulse: _latestPulse,
      movement: _latestMovement,
      peakAlpha: _latestPeakAlpha != null
          ? PeakAlphaInfo(
              freq: _latestPeakAlpha!.frequency,
              power: _latestPeakAlpha!.power,
            )
          : null,
      spo2: _latestSpO2,
      lineNoise: List.from(_latestLineNoise),
      signalQuality: List.from(_latestSignalQuality),
      guardrail: GuardrailInfo(
        sleepDir: _lastSleepDir,
        clarity: _lastClarity,
        warning: _warningActive,
        delta: _lastDelta,
        featurePercentile: _guardFeaturePercentile,
        warnOver: _guardWarnOver,
        ceilingOver: _guardCeilingOver,
        clean: _guardClean,
        dirtyReason: _guardDirtyReason,
      ),
      feedback: FeedbackInfo(
        ratio: _lastRatio,
        threshold: _feedbackThreshold ?? 0.0,
        inTarget: _lastInTarget,
        pct: _inTargetPct,
        percentile: _feedbackPercentile,
        thresholdPercentile: _feedbackThresholdPercentile,
        heldBack: _feedbackHeldBack,
        inhibitTags: _feedbackInhibitTags,
        clean: _feedbackClean,
        dirtyReason: _feedbackDirtyReason,
        betaRel: _feedbackBetaRel,
        deltaRel: _feedbackDeltaRel,
      ),
      gestures: List.from(_latestGestures),
    );

    onFrame(frame);
  }
}
