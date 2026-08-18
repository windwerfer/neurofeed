import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Shared machinery for a continuous feedback voice: owns a single SoLoud
/// handle for a looped source, optionally wires a per-voice resonant biquad
/// low-pass filter, and EMA-slews the cutoff toward a live target so reward
/// updates glide instead of zipper. Used by the modulated feedback channels
/// (music cutoff, rain intensity) and by static background music (filter off,
/// no modulation).
///
/// The 100 ms slew tick mirrors the classic reward-driven filter pattern:
/// targets change at ~10 Hz from the reward engine; the EMA smooths those
/// jumps into a clean cutoff glide.
class ModulatedVoice {
  ModulatedVoice({
    double initialCutoff = 0,
    this.muffleCutoff = 10,
    this.muffleVolume,
    this.slewSeconds = 1.2,
  }) : _targetCutoff = initialCutoff,
       _currentCutoff = initialCutoff;

  /// How often the cutoff slew is applied to the live filter (100 ms).
  static const Duration _slewTick = Duration(milliseconds: 100);

  /// Exponential smoothing time constant for cutoff changes (prevents zipper
  /// noise from the ~10 Hz reward updates). Reloaded from settings on
  /// [refreshSettings] by the owning controller.
  double slewSeconds;

  /// Cutoff glided toward while [setMuffle] is active (guardrail ducking).
  double muffleCutoff;

  /// Optional volume glided toward while muffled; null keeps the voice volume.
  double? muffleVolume;

  AudioSource? source;
  SoundHandle? handle;

  Timer? _slewTimer;
  bool _playing = false;
  bool _paused = false;
  bool _muffle = false;
  bool _filterWired = false;

  double _volume = 1.0;
  bool _slewingVolume = false;
  double _targetVolume = 1.0;
  late double _targetCutoff;
  late double _currentCutoff;

  bool get playing => _playing && !_paused;

  bool get paused => _paused;

  /// Currently applied cutoff in Hz (slewed), for recording traces.
  double get currentCutoff => _currentCutoff;

  /// True while a guardrail warning is forcing the filter (and optional
  /// volume) toward the muffle state.
  bool get muffleActive => _muffle;

  /// Volume the voice was last told to play at (useful to re-apply when a
  /// new source steps in for the same channel).
  double get voiceVolume => _volume;

  /// Starts (or restarts) playback of [src] at [volume], panned [pan]
  /// (−1 hard left … +1 hard right). When [activateFilter] is false the voice
  /// plays unprocessed (static background music, binaural ears — no slew).
  void play(
    AudioSource src, {
    required double volume,
    double pan = 0,
    bool activateFilter = true,
  }) {
    final newHandle = SoLoud.instance.play(src, volume: volume, pan: pan);
    if (activateFilter) {
      src.filters.biquadFilter.activate();
      src.filters.biquadFilter.type(soundHandle: newHandle).value = 0;
      src.filters.biquadFilter.wet(soundHandle: newHandle).value = 1.0;
      src.filters.biquadFilter.resonance(soundHandle: newHandle).value = 0.15;
      _filterWired = true;
      _applyCutoffImmediate(newHandle);
    }
    source = src;
    handle = newHandle;
    _volume = volume;
    _slewingVolume = false;
    _targetVolume = volume;
    _playing = true;
    _paused = false;
    _startSlew();
  }

  /// Pauses the live voice without tearing down the slew loop.
  void pause() {
    if (!playing) {
      return;
    }
    _paused = true;
    final h = handle;
    if (h != null) {
      try {
        SoLoud.instance.setPause(h, true);
      } catch (_) {}
    }
  }

  /// Resumes a paused voice.
  void resume() {
    if (!_playing || !_paused) {
      return;
    }
    final h = handle;
    if (h != null) {
      try {
        SoLoud.instance.setPause(h, false);
      } catch (_) {}
    }
    _paused = false;
  }

  /// Stops the voice and the slew loop; the source is left to the caller (so
  /// the caller can dispose it once at teardown, or keep it for a retrigger).
  void stop() {
    _playing = false;
    _paused = false;
    _stopSlew();
    final h = handle;
    if (h != null) {
      try {
        SoLoud.instance.stop(h);
      } catch (_) {}
    }
    handle = null;
  }

  /// Disposes the currently loaded source (including its filters).
  Future<void> disposeSource() async {
    final src = source;
    if (src != null) {
      try {
        await SoLoud.instance.disposeSource(src);
      } catch (_) {}
      source = null;
    }
  }

  /// Applies an absolute voice volume, overriding whatever was set in [play].
  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    _targetVolume = _volume;
    _slewingVolume = false;
    final h = handle;
    if (h != null) {
      try {
        SoLoud.instance.setVolume(h, _volume);
      } catch (_) {}
    }
  }

  /// Glides the voice volume toward [v] with the same EMA used for cutoffs
  /// (used by the rain channel, whose stage changes are volume steps).
  void slewVolumeTo(double v) {
    _slewingVolume = true;
    _targetVolume = v.clamp(0.0, 1.0);
  }

  /// Target cutoff for the reward; the EMA slew glides the live filter toward
  /// it. Values are clamped by the underlying biquad on apply.
  void setTargetCutoff(double hz) {
    _targetCutoff = hz.isFinite ? hz.clamp(10.0, 16000.0) : muffleCutoff;
  }

  /// Forces the filter (and optional volume) toward the muffle state while a
  /// guardrail warning is active; release restores the reward target.
  void setMuffle(bool on) {
    _muffle = on;
    final mv = muffleVolume;
    if (mv != null) {
      if (on) {
        _slewingVolume = true;
        _targetVolume = mv;
      } else {
        _targetVolume = _volume;
      }
    }
  }

  void _startSlew() {
    _stopSlew();
    _slewTimer = Timer.periodic(_slewTick, (_) => _applyCutoff());
  }

  void _stopSlew() {
    _slewTimer?.cancel();
    _slewTimer = null;
  }

  void _applyCutoff() {
    if (!_playing || !_filterWired) {
      if (_playing && _slewingVolume) {
        _applyVolumeStep();
      }
      return;
    }
    final h = handle;
    if (h == null) {
      return;
    }
    final target = _muffle ? muffleCutoff : _targetCutoff;
    final dt = _slewTick.inMilliseconds / 1000.0;
    final alpha = 1 - exp(-dt / slewSeconds);
    _currentCutoff += (target - _currentCutoff) * alpha;
    if ((target - _currentCutoff).abs() < 1.0) {
      _currentCutoff = target;
    }
    final clamped = _currentCutoff.clamp(10.0, 16000.0);
    final src = source;
    if (src != null) {
      try {
        src.filters.biquadFilter.frequency(soundHandle: h).value = clamped;
      } catch (e) {
        debugPrint('[modulated] cutoff apply failed: $e');
      }
    }
    if (_slewingVolume) {
      _applyVolumeStep();
    }
  }

  void _applyVolumeStep() {
    final h = handle;
    if (h == null) {
      return;
    }
    final dt = _slewTick.inMilliseconds / 1000.0;
    final alpha = 1 - exp(-dt / 0.5);
    _volume += (_targetVolume - _volume) * alpha;
    if ((_targetVolume - _volume).abs() < 0.005) {
      _volume = _targetVolume;
      _slewingVolume = false;
    }
    try {
      SoLoud.instance.setVolume(h, _volume);
    } catch (_) {}
  }

  void _applyCutoffImmediate(SoundHandle h) {
    final src = source;
    if (src == null) {
      return;
    }
    try {
      src.filters.biquadFilter.frequency(soundHandle: h).value = _currentCutoff
          .clamp(10.0, 16000.0);
    } catch (_) {}
  }
}
