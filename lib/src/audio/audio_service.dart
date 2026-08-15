import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/audio/music_feedback_controller.dart';
import 'package:muse_ml/src/settings.dart';

/// Sentinel sound name that activates music-feedback mode (user folder played
/// through the low-pass filter) instead of the ambient loop.
const String musicSoundName = 'Music from folder';

class AudioService {
  final FeedbackAudioController _controller;
  final MusicFeedbackController _music;

  AudioService(Settings settings)
    : _controller = FeedbackAudioController(settings),
      _music = MusicFeedbackController(settings) {
    _music
      ..refreshSettings()
      ..setVolume(_controller.masterVolume * _controller.feedbackVolume);
  }

  static const Map<String, String?> soundAssets = {
    'Ambient Drone': FeedbackAudioController.feedbackDroneAsset,
    'Drone Loop': FeedbackAudioController.droneLoopAsset,
    'Rain': 'assets/audio/rain/346562__lebaston100__rain-without-thunder.opus',
    'No background': null,
  };

  List<String> get availableSounds => [...soundAssets.keys, musicSoundName];

  static bool isMusicSound(String sound) => sound == musicSoundName;

  double get masterVolume => _controller.masterVolume;

  double get backgroundVolume => _controller.backgroundVolume;

  double get feedbackVolume => _controller.feedbackVolume;

  double get introVolume => _controller.introVolume;

  double get bellVolume => _controller.bellVolume;

  double get guardrailVolume => _controller.guardrailVolume;

  void setMasterVolume(double value) {
    _controller.setMasterVolume(value);
    _music.setVolume(masterVolume * feedbackVolume);
  }

  void setBackgroundVolume(double value) =>
      _controller.setBackgroundVolume(value);

  void setFeedbackVolume(double value) {
    _controller.setFeedbackVolume(value);
    _music.setVolume(masterVolume * feedbackVolume);
  }

  void setIntroVolume(double value) => _controller.setIntroVolume(value);

  void setBellVolume(double value) => _controller.setBellVolume(value);

  void setGuardrailVolume(double value) => _controller.setGuardrailVolume(value);

  void resetVolumes() {
    _controller.resetVolumes();
    _music.setVolume(masterVolume * feedbackVolume);
  }

  Future<void> playCalibration([String? assetPath]) =>
      _controller.playCalibration(assetPath);

  Future<void> playFeedback({String sound = 'Ambient Drone'}) {
    if (isMusicSound(sound)) {
      return _music.start();
    }
    final path = soundAssets[sound];
    return _controller.startBackground(path);
  }

  Future<void> switchSound(String sound) async {
    if (isMusicSound(sound)) {
      await _controller.startBackground(null);
      await _music.load();
      await _music.start();
      return;
    }
    await _music.stop();
    final path = soundAssets[sound];
    return _controller.switchBackground(path);
  }

  /// Music feedback channel: reloads the folder from settings and begins
  /// playback. Used when a folder is first chosen mid-session.
  Future<void> startMusic() async {
    await _music.load();
    await _music.start();
  }

  /// Reloads the track list from the current [Settings.musicFolder] without
  /// starting playback, and returns how many playable tracks were found (0
  /// when the folder is unset/empty). Lets settings UI preview the folder.
  Future<int> loadMusic() async {
    final ok = await _music.load();
    return ok ? _music.trackCount : 0;
  }

  /// Feeds the live reward percentile (0–100) to the music feedback filter.
  void setMusicCutoffHz(double hz) => _music.setTargetCutoff(hz);

  /// Whether the music feedback channel is actively playing.
  bool get musicPlaying => _music.isPlaying;

  /// Current music track / cutoff, for the session UI and metadata.
  String? get musicTrackName => _music.currentTrackName;

  int get musicTrackCount => _music.trackCount;

  double get musicCutoffHz => _music.currentCutoffHz;

  void setMusicMuffle(bool on) => _music.setMuffle(on);

  void onStateUpdate(bool inTarget) => _controller.onStateUpdate(inTarget);

  void onMovement() => _controller.onMovement();

  Future<void> playEndChime() => _controller.playEndChime();

  Future<void> playRecalibrateChime() => _controller.playRecalibrateChime();

  Future<void> playWarningChime() => _controller.playWarningChime();

  Future<void> pause() async {
    await _controller.pauseBackground();
    await _music.pause();
  }

  Future<void> resume() async {
    await _controller.resumeBackground();
    await _music.resume();
  }

  Future<void> stop() async {
    await _music.stop();
    await _controller.stop();
  }

  void dispose() {
    _music.dispose();
    _controller.dispose();
  }
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService(ref.read(settingsProvider));
  ref.onDispose(() => service.dispose());
  return service;
});