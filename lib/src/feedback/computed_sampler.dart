import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/session_v5/computed_frame.dart';

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
  final List<String> _latestGestures = [];

  // Update methods called by FeedbackStateNotifier

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
  }) {
    _lastSleepDir = sleepDir;
    _lastClarity = clarity;
    _lastDelta = delta;
    _warningActive = warning;
  }

  void updateFeedback({
    required double ratio,
    required double? threshold,
    required bool inTarget,
    required double inTargetPct,
  }) {
    _lastRatio = ratio;
    _feedbackThreshold = threshold;
    _lastInTarget = inTarget;
    _inTargetPct = inTargetPct;
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

  /// Seconds from [recordingStart] using the injected clock.
  @visibleForTesting
  void emitFrame() => _emitFrame();

  void _emitFrame() {
    final t = _now().difference(_recordingStart).inMilliseconds / 1000.0;

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
      ),
      feedback: FeedbackInfo(
        ratio: _lastRatio,
        threshold: _feedbackThreshold ?? 0.0,
        inTarget: _lastInTarget,
        pct: _inTargetPct,
      ),
      gestures: List.from(_latestGestures),
    );

    onFrame(frame);
  }
}
