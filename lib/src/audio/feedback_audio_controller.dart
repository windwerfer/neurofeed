import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class FeedbackAudioController {
  static const Duration targetHoldDuration = Duration(milliseconds: 2500);
  static const Duration rewardCooldown = Duration(seconds: 8);
  static const Duration movementBuffer = Duration(seconds: 1);
  static const Duration chimeAttack = Duration(milliseconds: 100);
  static const int maxPolyphony = 4;
  static const double droneVolume = 0.35;

  static const String calibrationAsset =
      'assets/audio/calibration/grok_alpha_power-over-theta_power_01.opus';
  static const String bowlLowAsset =
      'assets/audio/bowl/bowl_low-531269__asuriya__aud-10-ancient-tibet-bowl-pure-vibrations.opus';
  static const String bellAsset =
      'assets/audio/bell/864397__valerie-vivegnis__2607.opus';

  final AudioPlayer _ambient = AudioPlayer();
  final AudioPlayer _calibration = AudioPlayer();
  final AudioPlayer _bell = AudioPlayer();
  final List<AudioPlayer> _chimes =
      List.generate(maxPolyphony, (_) => AudioPlayer());

  DateTime? _inTargetSince;
  DateTime _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<AudioPlayer> _ramping = {};

  Future<void> playCalibration() async {
    await stop();
    try {
      await _calibration.setAsset(calibrationAsset);
      await _calibration.setLoopMode(LoopMode.off);
      await _calibration.play();
    } catch (e) {
      debugPrint('[audio] calibration playback failed: $e');
    }
  }

  Future<void> startBackground(String assetPath) async {
    _resetRewardState();
    try {
      await _ambient.setAsset(assetPath);
      await _ambient.setLoopMode(LoopMode.one);
      await _ambient.setVolume(droneVolume);
      await _ambient.play();
    } catch (e) {
      debugPrint('[audio] background playback failed: $e');
    }
  }

  Future<void> pauseBackground() => _ambient.pause();

  Future<void> resumeBackground() => _ambient.play();

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
      await _bell.play();
    } catch (e) {
      debugPrint('[audio] end chime playback failed: $e');
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
    for (final chime in _chimes) {
      if (_ramping.contains(chime) ||
          chime.playing ||
          chime.processingState == ProcessingState.loading) {
        continue;
      }
      _ramping.add(chime);
      try {
        await chime.setAsset(bowlLowAsset);
        await chime.setLoopMode(LoopMode.off);
        await chime.setVolume(0);
        await chime.play();
        await _rampVolume(chime, 1.0, chimeAttack);
        return;
      } catch (e) {
        debugPrint('[audio] chime playback failed: $e');
      } finally {
        _ramping.remove(chime);
      }
    }
  }

  Future<void> _rampVolume(AudioPlayer player, double target, Duration duration) async {
    const steps = 5;
    for (var i = 1; i <= steps; i++) {
      await player.setVolume(target * i / steps);
      await Future<void>.delayed(duration ~/ steps);
    }
  }
}
