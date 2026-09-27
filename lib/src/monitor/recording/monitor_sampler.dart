import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/session_format/band_second_average.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart';

/// 1 Hz computed frames for monitor captures. N-channel; zeroed guard/feedback.
class MonitorSampler {
  MonitorSampler({
    required this.channelCount,
    required this.captureStartedAtMs,
    required this.onFrame,
    this.interval = const Duration(seconds: 1),
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _bands = BandSecondAverage(channelCount),
       _latestSignalQuality = List.filled(channelCount, 0);

  final int channelCount;
  int captureStartedAtMs;
  final void Function(ComputedFrame) onFrame;
  final Duration interval;
  final int Function() _nowMs;

  Timer? _timer;

  final BandSecondAverage _bands;
  final List<int> _latestSignalQuality;
  double? _latestPulse;
  double? _latestMovement;
  PeakAlphaDto? _latestPeakAlpha;
  double? _latestSpO2;
  List<String> _latestGestures = const [];
  QualitySource? _signalQualitySource;
  List<double>? _crownSignalQuality;

  void updateBands(int electrode, BandsDto bands) =>
      _bands.add(electrode, bands);

  void updatePulse(PulseDto pulse) => _latestPulse = pulse.bpm;

  void updateMovement(MovementDto movement) => _latestMovement = movement.score;

  void updatePeakAlpha(PeakAlphaDto peakAlpha) => _latestPeakAlpha = peakAlpha;

  void updateSpO2(SpO2Dto spo2) => _latestSpO2 = spo2.spo2;

  void updateSignalQuality(int electrode, int quality) {
    if (electrode < 0 || electrode >= channelCount) return;
    _latestSignalQuality[electrode] = quality;
  }

  /// Neurosity only: which score filled the latest pad quality, plus the
  /// Crown per-pad 1 Hz means when that source is Crown.
  void updateSignalQualitySource(QualitySource? source, List<double>? crown) {
    _signalQualitySource = source;
    _crownSignalQuality = crown;
  }

  void updateGestures(GestureDto g) {
    final names = <String>[];
    if (g.blinkCount > 0) names.add('blink');
    if (g.clench) names.add('clench');
    if (g.eye == 1) names.add('eyeUp');
    if (g.eye == 2) names.add('eyeDown');
    _latestGestures = names;
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _emitFrame());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  void emitFrame() => _emitFrame();

  void _emitFrame() {
    final t = (_nowMs() - captureStartedAtMs) / 1000.0;
    final second = _bands.take();
    onFrame(
      ComputedFrame(
        t: t,
        bands: second.bands,
        pulse: _latestPulse,
        movement: _latestMovement,
        peakAlpha: _latestPeakAlpha != null
            ? PeakAlphaInfo(
                freq: _latestPeakAlpha!.frequency,
                power: _latestPeakAlpha!.power,
              )
            : null,
        spo2: _latestSpO2,
        lineNoise: second.lineNoise,
        signalQuality: List<int>.from(_latestSignalQuality),
        signalQualitySource: _signalQualitySource?.name,
        crownSignalQuality: _crownSignalQuality,
        guardrail: const GuardrailInfo(
          sleepDir: 0,
          clarity: 0,
          warning: false,
          delta: 0,
        ),
        feedback: const FeedbackInfo(
          ratio: 0,
          threshold: 0,
          inTarget: false,
          pct: 0,
        ),
        gestures: List<String>.from(_latestGestures),
      ),
    );
  }
}
