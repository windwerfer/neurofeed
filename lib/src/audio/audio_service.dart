import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/settings.dart';

class AudioService {
  final FeedbackAudioController _controller;

  AudioService(Settings settings)
    : _controller = FeedbackAudioController(settings);

  static const Map<String, String?> soundAssets = {
    'Ambient Drone': FeedbackAudioController.feedbackDroneAsset,
    'Drone Loop': FeedbackAudioController.droneLoopAsset,
    'Rain': 'assets/audio/rain/346562__lebaston100__rain-without-thunder.opus',
    'No background': null,
  };

  List<String> get availableSounds => soundAssets.keys.toList();

  double get masterVolume => _controller.masterVolume;

  double get backgroundVolume => _controller.backgroundVolume;

  double get feedbackVolume => _controller.feedbackVolume;

  double get introVolume => _controller.introVolume;

  double get bellVolume => _controller.bellVolume;

  void setMasterVolume(double value) => _controller.setMasterVolume(value);

  void setBackgroundVolume(double value) =>
      _controller.setBackgroundVolume(value);

  void setFeedbackVolume(double value) => _controller.setFeedbackVolume(value);

  void setIntroVolume(double value) => _controller.setIntroVolume(value);

  void setBellVolume(double value) => _controller.setBellVolume(value);

  void resetVolumes() => _controller.resetVolumes();

  Future<void> playCalibration([String? assetPath]) =>
      _controller.playCalibration(assetPath);

  Future<void> playFeedback({String sound = 'Ambient Drone'}) {
    final path = soundAssets[sound];
    return _controller.startBackground(path);
  }

  Future<void> switchSound(String sound) {
    final path = soundAssets[sound];
    return _controller.switchBackground(path);
  }

  void onStateUpdate(bool inTarget) => _controller.onStateUpdate(inTarget);

  void onMovement() => _controller.onMovement();

  Future<void> playEndChime() => _controller.playEndChime();

  Future<void> playRecalibrateChime() => _controller.playRecalibrateChime();

  Future<void> playWarningChime() => _controller.playWarningChime();

  Future<void> pause() => _controller.pauseBackground();

  Future<void> resume() => _controller.resumeBackground();

  Future<void> stop() => _controller.stop();

  void dispose() => _controller.dispose();
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService(ref.read(settingsProvider));
  ref.onDispose(() => service.dispose());
  return service;
});
