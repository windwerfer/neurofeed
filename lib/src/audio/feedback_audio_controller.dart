import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:muse_ml/src/settings.dart';

class FeedbackAudioController {
  static const Duration targetHoldDuration = Duration(milliseconds: 2500);
  static const Duration rewardCooldown = Duration(seconds: 8);
  static const Duration movementBuffer = Duration(seconds: 1);
  static const Duration chimeAttack = Duration(milliseconds: 100);
  static const int maxPolyphony = 10;
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

  final AudioPlayer _ambient = AudioPlayer();
  final AudioPlayer _calibration = AudioPlayer();
  final AudioPlayer _bell = AudioPlayer();
  final List<AudioPlayer> _chimes = List.generate(
    maxPolyphony,
    (_) => AudioPlayer(),
  );
  final List<StreamSubscription<ProcessingState>> _chimeSubs = [];

  DateTime? _inTargetSince;
  DateTime _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<AudioPlayer> _ramping = {};

  double _masterVolume = 1.0;
  double _backgroundVolume = droneVolume;
  double _feedbackVolume = 1.0;
  double _introVolume = 1.0;
  double _bellVolume = 1.0;

  FeedbackAudioController(Settings settings)
      : _settings = settings {
    _masterVolume = settings.masterVolume ?? 1.0;
    _backgroundVolume = settings.backgroundVolume ?? droneVolume;
    _feedbackVolume = settings.feedbackVolume ?? 1.0;
    _introVolume = settings.introVolume ?? 1.0;
    _bellVolume = settings.bellVolume ?? 1.0;
    for (final chime in _chimes) {
      _chimeSubs.add(
        chime.processingStateStream.listen((state) {
          if (state == ProcessingState.completed &&
              !_ramping.contains(chime)) {
            _resetChime(chime);
          }
        }),
      );
    }
  }

  final Settings _settings;

  double get masterVolume => _masterVolume;

  double get backgroundVolume => _backgroundVolume;

  double get feedbackVolume => _feedbackVolume;

  double get introVolume => _introVolume;

  double get bellVolume => _bellVolume;

  double get _ambientVolume => _masterVolume * _backgroundVolume;

  double get _feedbackVolumeTotal => _masterVolume * _feedbackVolume;

  double get _introVolumeTotal => _masterVolume * _introVolume;

  double get _bellVolumeTotal => _masterVolume * _bellVolume;

  void setMasterVolume(double value) {
    _masterVolume = value.clamp(0.0, 1.0);
    _settings.setMasterVolume(_masterVolume);
    _applyVolumes();
  }

  void setBackgroundVolume(double value) {
    _backgroundVolume = value.clamp(0.0, 1.0);
    _settings.setBackgroundVolume(_backgroundVolume);
    _ambient.setVolume(_ambientVolume);
  }

  void setFeedbackVolume(double value) {
    _feedbackVolume = value.clamp(0.0, 1.0);
    _settings.setFeedbackVolume(_feedbackVolume);
    _applyFeedbackVolumes();
  }

  void setIntroVolume(double value) {
    _introVolume = value.clamp(0.0, 1.0);
    _settings.setIntroVolume(_introVolume);
    _calibration.setVolume(_introVolumeTotal);
  }

  void setBellVolume(double value) {
    _bellVolume = value.clamp(0.0, 1.0);
    _settings.setBellVolume(_bellVolume);
    _bell.setVolume(_bellVolumeTotal);
  }

  void resetVolumes() {
    _masterVolume = 1.0;
    _backgroundVolume = droneVolume;
    _feedbackVolume = 1.0;
    _introVolume = 1.0;
    _bellVolume = 1.0;
    _settings
      ..setMasterVolume(_masterVolume)
      ..setBackgroundVolume(_backgroundVolume)
      ..setFeedbackVolume(_feedbackVolume)
      ..setIntroVolume(_introVolume)
      ..setBellVolume(_bellVolume);
    _applyVolumes();
  }

  void _applyVolumes() {
    _ambient.setVolume(_ambientVolume);
    _applyFeedbackVolumes();
    _calibration.setVolume(_introVolumeTotal);
    _bell.setVolume(_bellVolumeTotal);
  }

  void _applyFeedbackVolumes() {
    for (final chime in _chimes) {
      if (!_ramping.contains(chime)) {
        chime.setVolume(_feedbackVolumeTotal);
      }
    }
  }

  Future<void> playCalibration() async {
    await stop();
    try {
      await _calibration.setAsset(calibrationAsset);
      await _calibration.setLoopMode(LoopMode.off);
      await _calibration.setVolume(_introVolumeTotal);
      final done = _calibration.processingStateStream.firstWhere(
        (s) => s == ProcessingState.completed,
      );
      await _calibration.play();
      await done.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[audio] calibration playback failed: $e');
    }
  }

  Future<void> startBackground(String assetPath) async {
    _resetRewardState();
    try {
      await _ambient.setAsset(assetPath);
      await _ambient.setLoopMode(LoopMode.one);
      await _ambient.setVolume(_ambientVolume);
      await _ambient.play();
    } catch (e) {
      debugPrint('[audio] background playback failed: $e');
    }
  }

  Future<void> pauseBackground() => _ambient.pause();

  Future<void> resumeBackground() => _ambient.play();

  /// Switches the ambient loop to a different asset mid-session without
  /// touching the reward state machine.
  Future<void> switchBackground(String assetPath) async {
    try {
      await _ambient.setAsset(assetPath);
      await _ambient.setLoopMode(LoopMode.one);
      await _ambient.setVolume(_ambientVolume);
      await _ambient.play();
    } catch (e) {
      debugPrint('[audio] background switch failed: $e');
    }
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
    try {
      await _bell.setAsset(bellAsset);
      await _bell.setLoopMode(LoopMode.off);
      await _bell.setVolume(_bellVolumeTotal);
      await _bell.play();
    } catch (e) {
      debugPrint('[audio] end chime playback failed: $e');
    }
  }

  /// Soft, low indication that the threshold was re-anchored mid-session.
  Future<void> playRecalibrateChime() async {
    try {
      await _bell.setAsset(bowlLowAsset);
      await _bell.setLoopMode(LoopMode.off);
      await _bell.setVolume(_bellVolumeTotal * 0.6);
      await _bell.play();
    } catch (e) {
      debugPrint('[audio] recalibrate chime playback failed: $e');
    }
  }

  Future<void> stop() async {
    _resetRewardState();
    await Future.wait([
      _ambient.stop(),
      _calibration.stop(),
      _bell.stop(),
      for (final chime in _chimes) chime.stop(),
    ]);
  }

  void dispose() {
    for (final sub in _chimeSubs) {
      sub.cancel();
    }
    _ambient.dispose();
    _calibration.dispose();
    _bell.dispose();
    for (final chime in _chimes) {
      chime.dispose();
    }
  }

  void _resetRewardState() {
    _inTargetSince = null;
    _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
    _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _triggerChime() async {
    for (var i = 0; i < _chimes.length; i++) {
      final chime = _chimes[i];
      if (_ramping.contains(chime) ||
          chime.playing ||
          chime.processingState == ProcessingState.loading) {
        continue;
      }
      debugPrint(
        '[chime] player $i starting at ${DateTime.now().toIso8601String()}',
      );
      _ramping.add(chime);
      try {
        await chime.setAsset(bowlLowAsset);
        await chime.setLoopMode(LoopMode.off);
        final start = _feedbackVolumeTotal * 0.05;
        await chime.setVolume(start);
        await chime.play();
        await _rampVolume(chime, start, _feedbackVolumeTotal, chimeAttack);
        return;
      } catch (e) {
        debugPrint('[audio] chime playback failed: $e');
      } finally {
        _ramping.remove(chime);
      }
    }
    debugPrint('[chime] no free player at ${DateTime.now().toIso8601String()}');
  }

  Future<void> _resetChime(AudioPlayer chime) async {
    try {
      await chime.pause();
      await chime.seek(Duration.zero);
    } catch (e) {
      debugPrint('[audio] chime reset failed: $e');
    }
  }

  Future<void> _rampVolume(
    AudioPlayer player,
    double start,
    double target,
    Duration duration,
  ) async {
    const steps = 5;
    for (var i = 1; i <= steps; i++) {
      await player.setVolume(start + (target - start) * i / steps);
      await Future<void>.delayed(duration ~/ steps);
    }
  }
}
