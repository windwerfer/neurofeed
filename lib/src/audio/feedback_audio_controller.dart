import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';
import 'package:muse_ml/src/settings.dart';

/// Ambient + one-shot feedback sounds on a single SoLoud engine.
///
/// Public surface mirrors the pre-SoLoud (just_audio) controller so
/// [AudioService] and the feedback notifier stay unchanged for chime/sound
/// feedback. Music feedback (folder + low-pass filter) lives in
/// [MusicFeedbackController].
class FeedbackAudioController {
  static const Duration targetHoldDuration = Duration(milliseconds: 2500);
  static const Duration rewardCooldown = Duration(seconds: 8);
  static const Duration movementBuffer = Duration(seconds: 1);
  static const int maxPolyphony = 18;
  static const double droneVolume = 0.5;

  static const String calibrationAsset =
      'assets/audio/calibration/alpha-theta-ratio_short-clear.opus';
  static const String feedbackDroneAsset =
      'assets/audio/drone/845842__frame__complex-shifting-ambient-drone-8-1min.opus';
  static const String droneLoopAsset =
      'assets/audio/drone/859763__kkenny101__drone-loop-ambient-background-texture.opus';
  static const String bowlLowAsset =
      'assets/audio/bowl/bowl_low-531269__asuriya__aud-10-ancient-tibet-bowl-pure-vibrations.opus';
  static const String bellAsset =
      'assets/audio/bell/864397__valerie-vivegnis__2607.opus';

  final Settings _settings;

  /// Cache of loaded [AudioSource]s keyed by asset path, so loops and chimes
  /// reuse one native sound instead of re-decoding on every trigger.
  final Map<String, AudioSource> _sources = {};

  SoundHandle? _ambientHandle;
  SoundHandle? _bellHandle;
  final List<SoundHandle> _chimeHandles = [];

  DateTime? _inTargetSince;
  DateTime _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);

  double _masterVolume = 1.0;
  double _backgroundVolume = droneVolume;
  double _feedbackVolume = 1.0;
  double _introVolume = 1.0;
  double _bellVolume = 1.0;
  double _guardrailVolume = 1.0;

  FeedbackAudioController(Settings settings) : _settings = settings {
    _masterVolume = settings.masterVolume ?? 1.0;
    _backgroundVolume = settings.backgroundVolume ?? droneVolume;
    _feedbackVolume = settings.feedbackVolume ?? 1.0;
    _introVolume = settings.introVolume ?? 1.0;
    _bellVolume = settings.bellVolume ?? 1.0;
    _guardrailVolume = settings.guardrailVolume ?? 1.0;
  }

  double get masterVolume => _masterVolume;

  double get backgroundVolume => _backgroundVolume;

  double get feedbackVolume => _feedbackVolume;

  double get introVolume => _introVolume;

  double get bellVolume => _bellVolume;

  double get guardrailVolume => _guardrailVolume;

  double get _ambientVolume => _masterVolume * _backgroundVolume;

  double get _feedbackVolumeTotal => _masterVolume * _feedbackVolume;

  double get _introVolumeTotal => _masterVolume * _introVolume;

  double get _bellVolumeTotal => _masterVolume * _bellVolume;

  double get _guardrailVolumeTotal => _masterVolume * _guardrailVolume;

  /// Loads an asset once and caches the [AudioSource]. Streams long/looped
  /// audio from a temp file ([LoadMode.disk]); decodes short one-shots
  /// ([LoadMode.memory]) for instant low-latency triggers.
  Future<AudioSource> _sourceFor(String assetPath, {required bool stream}) {
    final existing = _sources[assetPath];
    if (existing != null) {
      return Future.value(existing);
    }
    return SoLoud.instance
        .loadAsset(
          assetPath,
          mode: stream ? LoadMode.disk : LoadMode.memory,
          autoDispose: false,
        )
        .then((source) {
          _sources[assetPath] = source;
          return source;
        });
  }

  /// Plays a one-shot voice and resolves when that exact voice ends. Used for
  /// the calibration clip (the notifier awaits it before the baseline starts).
  Future<void> _playAndAwaitEnd(
    AudioSource source, {
    required double volume,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final handle = SoLoud.instance.play(source, volume: volume);
    await _awaitHandleEnd(source, handle).timeout(timeout, onTimeout: () {});
  }

  Future<void> _awaitHandleEnd(AudioSource source, SoundHandle handle) {
    final completer = Completer<void>();
    final sub = source.soundEvents.listen((event) {
      if (event.event == SoundEventType.handleIsNoMoreValid &&
          event.handle == handle &&
          !completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future.whenComplete(sub.cancel);
  }

  /// Applies [action] to a possibly-stale handle, dropping it if the voice no
  /// longer exists (SoLoud throws for vanished handles). Used to keep volume
  /// changes and prunes cheap.
  void _safeHandle(SoundHandle handle, void Function(SoundHandle) action) {
    try {
      action(handle);
    } catch (_) {
      _chimeHandles.remove(handle);
    }
  }

  void setMasterVolume(double value) {
    _masterVolume = value.clamp(0.0, 1.0);
    _settings.setMasterVolume(_masterVolume);
    _applyVolumes();
  }

  void setBackgroundVolume(double value) {
    _backgroundVolume = value.clamp(0.0, 1.0);
    _settings.setBackgroundVolume(_backgroundVolume);
    final ambient = _ambientHandle;
    if (ambient != null) {
      _safeHandle(ambient, (h) => SoLoud.instance.setVolume(h, _ambientVolume));
    }
  }

  void setFeedbackVolume(double value) {
    _feedbackVolume = value.clamp(0.0, 1.0);
    _settings.setFeedbackVolume(_feedbackVolume);
    _applyFeedbackVolumes();
  }

  void setIntroVolume(double value) {
    _introVolume = value.clamp(0.0, 1.0);
    _settings.setIntroVolume(_introVolume);
    // Intro clips apply their volume at play time; nothing live to update.
  }

  void setBellVolume(double value) {
    _bellVolume = value.clamp(0.0, 1.0);
    _settings.setBellVolume(_bellVolume);
    final bell = _bellHandle;
    if (bell != null) {
      _safeHandle(bell, (h) => SoLoud.instance.setVolume(h, _bellVolumeTotal));
    }
  }

  void setGuardrailVolume(double value) {
    _guardrailVolume = value.clamp(0.0, 1.0);
    _settings.setGuardrailVolume(_guardrailVolume);
    final bell = _bellHandle;
    if (bell != null) {
      _safeHandle(
        bell,
        (h) => SoLoud.instance.setVolume(h, _guardrailVolumeTotal),
      );
    }
  }

  void resetVolumes() {
    _masterVolume = 1.0;
    _backgroundVolume = droneVolume;
    _feedbackVolume = 1.0;
    _introVolume = 1.0;
    _bellVolume = 1.0;
    _guardrailVolume = 1.0;
    _settings
      ..setMasterVolume(_masterVolume)
      ..setBackgroundVolume(_backgroundVolume)
      ..setFeedbackVolume(_feedbackVolume)
      ..setIntroVolume(_introVolume)
      ..setBellVolume(_bellVolume)
      ..setGuardrailVolume(_guardrailVolume);
    _applyVolumes();
  }

  void _applyVolumes() {
    final ambient = _ambientHandle;
    if (ambient != null) {
      _safeHandle(ambient, (h) => SoLoud.instance.setVolume(h, _ambientVolume));
    }
    _applyFeedbackVolumes();
    final bell = _bellHandle;
    if (bell != null) {
      _safeHandle(bell, (h) => SoLoud.instance.setVolume(h, _bellVolumeTotal));
    }
  }

  void _applyFeedbackVolumes() {
    for (final handle in List.of(_chimeHandles)) {
      _safeHandle(
        handle,
        (h) => SoLoud.instance.setVolume(h, _feedbackVolumeTotal),
      );
    }
  }

  Future<void> playCalibration([String? assetPath]) async {
    await stop();
    await SoLoudEngine.ensureInit();
    final source = await _sourceFor(
      assetPath ?? calibrationAsset,
      stream: true,
    );
    await _playAndAwaitEnd(source, volume: _introVolumeTotal);
  }

  Future<void> startBackground(String? assetPath) async {
    _resetRewardState();
    await SoLoudEngine.ensureInit();
    _stopAmbient();
    if (assetPath == null) {
      return;
    }
    final source = await _sourceFor(assetPath, stream: true);
    _ambientHandle = SoLoud.instance.play(
      source,
      volume: _ambientVolume,
      looping: true,
    );
  }

  Future<void> pauseBackground() async {
    final handle = _ambientHandle;
    if (handle != null) {
      _safeHandle(handle, (h) => SoLoud.instance.setPause(h, true));
    }
  }

  Future<void> resumeBackground() async {
    final handle = _ambientHandle;
    if (handle != null) {
      _safeHandle(handle, (h) => SoLoud.instance.setPause(h, false));
    }
  }

  /// Switches the ambient loop to a different asset mid-session without
  /// touching the reward state machine. A null asset stops the loop.
  Future<void> switchBackground(String? assetPath) async {
    await SoLoudEngine.ensureInit();
    _stopAmbient();
    if (assetPath == null) {
      return;
    }
    final source = await _sourceFor(assetPath, stream: true);
    _ambientHandle = SoLoud.instance.play(
      source,
      volume: _ambientVolume,
      looping: true,
    );
  }

  void onStateUpdate(bool inTarget) {
    if (!inTarget) {
      _inTargetSince = null;
      return;
    }
    final now = DateTime.now();
    _inTargetSince ??= now;
    if (now.isBefore(_movingUntil)) {
      return;
    }
    if (now.difference(_inTargetSince!) < targetHoldDuration) {
      return;
    }
    if (_lastRewardAt.isAfter(now.subtract(rewardCooldown))) {
      return;
    }
    _lastRewardAt = now;
    _triggerChime();
  }

  void onMovement() {
    _inTargetSince = null;
    _movingUntil = DateTime.now().add(movementBuffer);
  }

  Future<void> playEndChime() async {
    await _playBell(volume: _bellVolumeTotal);
  }

  Future<void> playRecalibrateChime() async {
    await _playBowl(volume: _bellVolumeTotal * 0.6);
  }

  Future<void> playWarningChime() async {
    await _playBell(volume: _guardrailVolumeTotal);
  }

  Future<void> _playBell({required double volume}) async {
    await SoLoudEngine.ensureInit();
    final source = await _sourceFor(bellAsset, stream: false);
    final bell = _bellHandle;
    if (bell != null) {
      _safeHandle(bell, SoLoud.instance.stop);
    }
    _bellHandle = SoLoud.instance.play(source, volume: volume);
  }

  Future<void> _playBowl({required double volume}) async {
    await SoLoudEngine.ensureInit();
    final source = await _sourceFor(bowlLowAsset, stream: false);
    SoLoud.instance.play(source, volume: volume);
  }

  Future<void> stop() async {
    _resetRewardState();
    _stopAmbient();
    final bell = _bellHandle;
    if (bell != null) {
      _safeHandle(bell, SoLoud.instance.stop);
      _bellHandle = null;
    }
    for (final handle in List.of(_chimeHandles)) {
      _safeHandle(handle, SoLoud.instance.stop);
    }
    _chimeHandles.clear();
  }

  void dispose() {
    _sources.clear();
    SoLoudEngine.deinit();
  }

  void _stopAmbient() {
    final handle = _ambientHandle;
    if (handle != null) {
      _safeHandle(handle, SoLoud.instance.stop);
    }
    _ambientHandle = null;
  }

  void _resetRewardState() {
    _inTargetSince = null;
    _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
    _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _triggerChime() {
    final source = _sources[bowlLowAsset];
    if (source == null) {
      debugPrint('[audio] chime skipped: bowl source not loaded');
      return;
    }
    // SoLoud has natural polyphony; cap at maxPolyphony by dropping the
    // oldest voice so a long burst can't pile up.
    if (_chimeHandles.length >= maxPolyphony) {
      final oldest = _chimeHandles.removeAt(0);
      _safeHandle(oldest, SoLoud.instance.stop);
    }
    final handle = SoLoud.instance.play(
      source,
      volume: _feedbackVolumeTotal,
    );
    _chimeHandles.add(handle);
    // Prune finished voices so the list stays short.
    final stale = _chimeHandles.where((h) => !source.handles.contains(h));
    for (final s in stale) {
      _chimeHandles.remove(s);
    }
  }
}