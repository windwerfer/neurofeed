import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:muse_ml/src/audio/modulated_voice.dart';

/// Goal-based binaural-beat presets. Each preset picks the beat difference
/// (the perceived entrainment frequency) and a comfortable carrier tone.
enum BinauralPreset {
  deepSleep(
    'Deep Sleep & Recovery',
    'Slow-wave (delta) entrainment: 2.5 Hz beats for deep, stage-3-like rest.',
    2.5,
    120,
  ),
  thetaCalm(
    'Theta Calm',
    'Deep relaxation, imagery and REM-adjacent states: 6 Hz theta beats.',
    6.0,
    150,
  ),
  alphaFlow(
    'Alpha Flow & Calm',
    'Relaxed alertness and stress reduction: 10 Hz alpha beats.',
    10.0,
    200,
  ),
  focusBeta(
    'Focus & Sharpness',
    'Active problem solving and working memory: 15 Hz beta beats.',
    15.0,
    250,
  ),
  peakInsight(
    'Peak Insight',
    'High cognitive processing: 40 Hz gamma beats.',
    40.0,
    300,
  );

  const BinauralPreset(
    this.label,
    this.explanation,
    this.beatHz,
    this.carrierHz,
  );

  final String label;
  final String explanation;
  final double beatHz;
  final double carrierHz;

  /// The preset matching [id], or null when [id] is not a preset name
  /// (`'custom'` — slider values are user-owned then).
  static BinauralPreset? fromId(String? id) {
    for (final preset in values) {
      if (preset.name == id) {
        return preset;
      }
    }
    return null;
  }
}

/// The persisted id used when the user moved a tuning slider away from every
/// preset (slider values then come straight from settings).
const String binauralCustomPresetId = 'custom';

/// Synthesized binaural-beat layer: two in-memory sine voices, one per ear,
/// at carrier Hz (left) and carrier + beat Hz (right) — the classic
/// brainstem-entrainment setup. Frequencies are set on the synth sources
/// (the engine ramps them smoothly, no clicks), volume is the only
/// reward-modulated property: it scales with the live reward percentile and
/// fades fully when off-target (disappearing is the cue).
class BinauralBeatController {
  BinauralBeatController()
    : _left = ModulatedVoice(initialCutoff: 0),
      _right = ModulatedVoice(initialCutoff: 0);

  final ModulatedVoice _left;
  final ModulatedVoice _right;

  /// How much of the channel gain survives while a guardrail warning ducks
  /// the layer (the warning chime carries the message then).
  static const double muffleFactor = 0.05;

  AudioSource? _leftSource;
  AudioSource? _rightSource;

  double _gain = 0;
  double _percentile = 0;
  bool _muffle = false;

  bool get isPlaying => _left.playing || _right.playing;

  double get percentile => _percentile;

  Future<void> start({
    required double carrierHz,
    required double beatHz,
  }) async {
    _left.stop();
    _right.stop();
    if (_leftSource == null || _rightSource == null) {
      _leftSource = await SoLoud.instance.loadWaveform(
        WaveForm.sin,
        false,
        0,
        0,
      );
      _rightSource = await SoLoud.instance.loadWaveform(
        WaveForm.sin,
        false,
        0,
        0,
      );
    }
    _setFrequencies(carrierHz, beatHz);
    _left.play(_leftSource!, volume: 0, pan: -1, activateFilter: false);
    _right.play(
      _rightSource!,
      volume: 0,
      pan: 1,
      activateFilter: false,
    );
    _percentile = 0;
    _applyVolume();
  }

  /// Retunes the running (or next) voices. The synth sources ramp frequency
  /// smoothly on the engine side, so a live preset change glides instead of
  /// clicking.
  void setFrequencies({required double carrierHz, required double beatHz}) {
    _setFrequencies(carrierHz, beatHz);
  }

  void _setFrequencies(double carrierHz, double beatHz) {
    final left = _leftSource;
    final right = _rightSource;
    if (left != null) {
      SoLoud.instance.setWaveformFreq(left, carrierHz);
    }
    if (right != null) {
      SoLoud.instance.setWaveformFreq(right, carrierHz + beatHz);
    }
  }

  /// Channel gain the layer may reach at the 100th percentile
  /// (master × feedback).
  void setGain(double gain) {
    _gain = gain.clamp(0.0, 1.0);
    _applyVolume();
  }

  /// Live reward percentile (0–100) — maps to volume, full fade at zero.
  void setPercentile(double pct) {
    _percentile = pct.clamp(0.0, 100.0);
    _applyVolume();
  }

  /// Ducks the layer while a guardrail warning is active.
  void setMuffle(bool on) {
    _muffle = on;
    _applyVolume();
  }

  void _applyVolume() {
    final v = _gain * (_percentile / 100.0) * (_muffle ? muffleFactor : 1.0);
    _left.slewVolumeTo(v);
    _right.slewVolumeTo(v);
  }

  void pause() {
    _left.pause();
    _right.pause();
  }

  void resume() {
    _left.resume();
    _right.resume();
  }

  Future<void> stop() async {
    _left.stop();
    _right.stop();
  }

  Future<void> dispose() async {
    _left.stop();
    _right.stop();
    final left = _leftSource;
    final right = _rightSource;
    _leftSource = null;
    _rightSource = null;
    if (left != null) {
      try {
        await SoLoud.instance.disposeSource(left);
      } catch (_) {}
    }
    if (right != null) {
      try {
        await SoLoud.instance.disposeSource(right);
      } catch (_) {}
    }
  }
}