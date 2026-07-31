import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';

class AudioService {
  final FeedbackAudioController _controller = FeedbackAudioController();

  static const Map<String, String> soundAssets = {
    'Ambient Drone':
        'assets/audio/drone/859763__kkenny101__drone-loop-ambient-background-texture.opus',
    'Rain': 'assets/audio/rain/346562__lebaston100__rain-without-thunder.opus',
  };

  List<String> get availableSounds => soundAssets.keys.toList();

  Future<void> playCalibration() => _controller.playCalibration();

  Future<void> playConfirmation() => _controller.playConfirmation();

  Future<void> playFeedback({String sound = 'Ambient Drone'}) {
    final path = soundAssets[sound] ?? soundAssets.values.first;
    return _controller.startBackground(path);
  }

  void onStateUpdate(bool inTarget) => _controller.onStateUpdate(inTarget);

  void onMovement() => _controller.onMovement();

  Future<void> playEndChime() => _controller.playEndChime();

  Future<void> pause() => _controller.pauseBackground();

  Future<void> resume() => _controller.resumeBackground();

  Future<void> stop() => _controller.stop();

  void dispose() => _controller.dispose();
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});
