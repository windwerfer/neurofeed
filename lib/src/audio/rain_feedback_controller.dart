import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:muse_ml/src/audio/modulated_voice.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';

/// Rain feedback channel: plays the bundled rain loop as a reward-modulated
/// soundscape. Five intensity stages (1 = heavy downpour far off-target …
/// 5 = calm, near-silent on-target); stage transitions slew the low-pass
/// cutoff smoothly and step the volume, so the rain reads as "getting closer"
/// when the user approaches the target.
///
/// Unlike [MusicFeedbackController] this is a single bundled loop, so it has
/// no playlist machinery — just a [ModulatedVoice] and a stage mapper.
class RainFeedbackController {
  RainFeedbackController();

  /// The bundled rain loop asset (same file the background "Rain" option
  /// uses — here it is modulated by the reward instead of playing flat).
  static const String rainAsset =
      'assets/audio/rain/346562__lebaston100__rain-without-thunder.opus';

  /// Stage tables: index 0 = heavy (stage 1) … index 4 = calm (stage 5).
  /// Percentile boundaries: pct >= 80 is the calmest stage.
  static const List<double> _stageVolumes = [1.0, 0.7, 0.45, 0.2, 0.04];
  static const List<double> _stageCutoffs = [9000, 5500, 3000, 1500, 900];
  static const List<double> _bounds = [20, 40, 60, 80];

  /// Deadband around a stage boundary (percentile points) before a transition
  /// is accepted — prevents stage flicker when the percentile sits on a bound.
  static const double _hysteresis = 3.0;

  final ModulatedVoice _voice = ModulatedVoice(
    initialCutoff: 900,
    muffleCutoff: 900,
    muffleVolume: 0.04,
    slewSeconds: 0.5,
  );

  AudioSource? _source;
  int _stage = 2; // moderate rain until the first real percentile arrives
  double _channelVolume = 1.0;
  bool _loaded = false;

  bool get isPlaying => _voice.playing;

  bool get muffleActive => _voice.muffleActive;

  /// Currently applied stage (1–5) for traces/debug.
  int get stage => _stage + 1;

  /// Currently applied (slewed) cutoff in Hz.
  double get currentCutoffHz => _voice.currentCutoff;

  /// Starts the modulated rain loop.
  Future<void> start() async {
    await SoLoudEngine.ensureInit();
    if (!_loaded) {
      try {
        _source = await SoLoud.instance.loadFile(
          rainAsset,
          mode: LoadMode.disk,
          autoDispose: false,
        );
        _loaded = true;
      } catch (e) {
        debugPrint('[rain] asset load failed: $e');
        return;
      }
    }
    final src = _source;
    if (src == null) {
      return;
    }
    _voice.play(
      src,
      volume: _volumeForStage(_stage, _channelVolume),
      activateFilter: true,
    );
    _voice.setTargetCutoff(_stageCutoffs[_stage]);
  }

  Future<void> pause() async => _voice.pause();

  Future<void> resume() async => _voice.resume();

  Future<void> stop() async {
    _voice.stop();
  }

  /// Effective channel volume (master × feedback channel). The live voice
  /// volume is stage-volume × channel volume, so a channel change re-applies.
  void setVolume(double v) {
    _channelVolume = v;
    _voice.setVolume(_volumeForStage(_stage, v));
  }

  /// Reward input: the session's percentile rank (0–100, 100 = best). Maps to
  /// a 5-stage intensity; close to target → quiet.
  void setTargetPercentile(double pct) {
    final clamped = pct.isFinite ? pct.clamp(0.0, 100.0) : 50.0;
    final target = _stageFor(clamped);
    if (target == _stage) {
      return;
    }
    final lower = target < _stage ? _bounds[target] : null;
    final upper = target > _stage ? _bounds[_stage] : null;
    if (target > _stage && upper != null && clamped < upper + _hysteresis) {
      return;
    }
    if (target < _stage && lower != null && clamped > lower - _hysteresis) {
      return;
    }
    _stage = target;
    _voice.setTargetCutoff(_stageCutoffs[_stage]);
    _voice.slewVolumeTo(_volumeForStage(_stage, _channelVolume));
    debugPrint(
      '[rain] stage ${_stage + 1} (pct ${clamped.toStringAsFixed(0)}%) '
      'cutoff=${_stageCutoffs[_stage].toStringAsFixed(0)} Hz '
      'volume=${_volumeForStage(_stage, _channelVolume).toStringAsFixed(2)}',
    );
  }

  /// Muffles the rain (guardrail warning): glides the filter toward the calm
  /// cutoff and ducks the volume so heavy rain softens.
  void setMuffle(bool on) => _voice.setMuffle(on);

  int _stageFor(double pct) {
    var stage = 0;
    for (final b in _bounds) {
      if (pct >= b) {
        stage++;
      }
    }
    return stage;
  }

  double _volumeForStage(int stage, double channel) =>
      (_stageVolumes[stage] * channel).clamp(0.0, 1.0);

  void dispose() {
    _voice.stop();
    unawaited(_voice.disposeSource());
  }
}
