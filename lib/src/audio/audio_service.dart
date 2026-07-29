import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  bool get isPlaying => _player.playing;
  bool get isPaused => _player.playing == false && _player.processingState == ProcessingState.ready;

  static const Map<String, String?> soundAssets = {
    'Harmonic Consonance': 'assets/audio/harmonic_consonance.opus',
    'your music (low pass)': null,
    'bowl chiming': null,
    'rain': null,
  };

  List<String> get availableSounds =>
      soundAssets.entries.where((e) => e.value != null).map((e) => e.key).toList();

  /// Play the 60s calibration tone. Returns when playback completes.
  Future<void> playCalibration() async {
    await _player.stop();
    try {
      await _player.setAsset('assets/audio/calibration.opus');
      await _player.setLoopMode(LoopMode.off);
      await _player.play();
    } catch (e) {
      debugPrint('[audio] calibration playback failed: $e');
    }
  }

  /// Play the feedback sound in a continuous loop.
  Future<void> playFeedback({String sound = 'Harmonic Consonance'}) async {
    await _player.stop();
    final path = soundAssets[sound] ?? soundAssets.values.firstWhere((v) => v != null);
    if (path == null) {
      debugPrint('[audio] no feedback sound available');
      return;
    }
    try {
      await _player.setAsset(path);
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e) {
      debugPrint('[audio] feedback playback failed: $e');
    }
  }

  /// Play the end-of-session bowl chime.
  Future<void> playEndChime() async {
    await _player.stop();
    try {
      await _player.setAsset('assets/audio/end_chime.opus');
      await _player.setLoopMode(LoopMode.off);
      await _player.play();
    } catch (e) {
      debugPrint('[audio] end chime playback failed: $e');
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();

  Future<void> stop() async {
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});
