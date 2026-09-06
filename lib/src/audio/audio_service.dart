import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/binaural_beat_controller.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/music_controller.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/audio/rain_feedback_controller.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';
import 'package:muse_ml/src/settings.dart';

export 'package:muse_ml/src/audio/output_ids.dart'
    show binauralSoundName, musicSoundName, RewardOutputId;

/// Orchestrates the three audio layers of a feedback session:
///
///  * **Background** — a flat, unmodulated loop (ambient drone, drone loop,
///    rain, static folder music, or nothing). Selected via [Settings.soundName]
///    and routed through `FeedbackAudioController` (assets) or
///    `MusicController` in background mode (folder). Not an output method.
///  * **Reward** — [RewardOutput]: chime / rainStage / musicFilter /
///    binauralSwell / none.
///  * **Guard** — [GuardOutput]: existing [GuardrailSound] ids. Muffle is
///    [RewardOutput.setMuffle], not a guard output.
///
/// `rainStage` and `musicFilter` suppress the background (the modulated loop
/// becomes the whole soundscape); `binauralSwell` layers under it; `chime` /
/// `none` keep background.
class AudioService {
  final Settings _settings;
  final FeedbackAudioController _controller;
  final MusicController _backgroundMusic;
  final MusicController _feedbackMusic;
  final RainFeedbackController _rain;
  final BinauralBeatController _backgroundBinaural;
  final BinauralBeatController _binaural;

  AudioService(Settings settings)
    : _settings = settings,
      _controller = FeedbackAudioController(settings),
      _backgroundMusic = MusicController(
        settings,
        mode: MusicPlaybackMode.background,
        modulation: MusicModulation.none,
      ),
      _feedbackMusic = MusicController(
        settings,
        mode: MusicPlaybackMode.feedback,
        modulation: MusicModulation.filterCutoff,
      ),
      _rain = RainFeedbackController(),
      _backgroundBinaural = BinauralBeatController(),
      _binaural = BinauralBeatController() {
    _backgroundMusic.refreshSettings();
    _feedbackMusic.refreshSettings();
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBackgroundBinauralVolume();
    _refreshBinauralVolume();
  }

  static const Map<String, String?> soundAssets = {
    'Ambient Drone': FeedbackAudioController.feedbackDroneAsset,
    'Drone Loop': FeedbackAudioController.droneLoopAsset,
    'Rain': 'assets/audio/rain/346562__lebaston100__rain-without-thunder.opus',
    'No background': null,
  };

  List<String> get availableSounds => [
    ...soundAssets.keys,
    musicSoundName,
    binauralSoundName,
  ];

  static bool isMusicSound(String sound) => sound == musicSoundName;
  static bool isBinauralSound(String sound) => sound == binauralSoundName;

  /// True when [reward] replaces the background layer with a modulated loop.
  static bool suppressesBackground(RewardOutputId reward) =>
      reward.suppressesBackground;

  double get masterVolume => _controller.masterVolume;

  double get backgroundVolume => _controller.backgroundVolume;

  double get feedbackVolume => _controller.feedbackVolume;

  double get introVolume => _controller.introVolume;

  double get bellVolume => _controller.bellVolume;

  double get guardrailVolume => _controller.guardrailVolume;

  void setMasterVolume(double value) {
    _controller.setMasterVolume(value);
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBackgroundBinauralVolume();
    _refreshBinauralVolume();
  }

  void setBackgroundVolume(double value) {
    _controller.setBackgroundVolume(value);
    _refreshMusicVolume();
    _refreshBackgroundBinauralVolume();
  }

  void setFeedbackVolume(double value) {
    _controller.setFeedbackVolume(value);
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBinauralVolume();
  }

  void setIntroVolume(double value) => _controller.setIntroVolume(value);

  void setBellVolume(double value) => _controller.setBellVolume(value);

  void setGuardrailVolume(double value) =>
      _controller.setGuardrailVolume(value);

  void resetVolumes() {
    _controller.resetVolumes();
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBackgroundBinauralVolume();
    _refreshBinauralVolume();
  }

  /// Background music rides the background channel; feedback music rides the feedback channel.
  void _refreshMusicVolume() {
    final bgVolume = _controller.masterVolume * _controller.backgroundVolume;
    final fbVolume = _controller.masterVolume * _controller.feedbackVolume;
    _backgroundMusic.setVolume(bgVolume);
    _feedbackMusic.setVolume(fbVolume);
  }

  void _refreshRainVolume() {
    _rain.setVolume(_controller.masterVolume * _controller.feedbackVolume);
  }

  void _refreshBackgroundBinauralVolume() {
    _backgroundBinaural.setGain(
      _controller.masterVolume * _controller.backgroundVolume,
    );
  }

  void _refreshBinauralVolume() {
    _binaural.setGain(_controller.masterVolume * _controller.feedbackVolume);
  }

  Future<void> ensureReady({bool reopenIfProfileDiffers = false}) =>
      SoLoudEngine.ensureInit(
        stable: _settings.audioStableMode,
        reopenIfProfileDiffers: reopenIfProfileDiffers,
      );

  RewardOutput rewardOutput(RewardOutputId id) => rewardOutputFor(
    id,
    chime: _controller,
    music: _feedbackMusic,
    rain: _rain,
    binaural: _binaural,
    settings: _settings,
    onBackgroundBinauralMuffle: _backgroundBinaural.setMuffle,
  );

  GuardOutput guardOutput() => guardOutputFor(controller: _controller);

  /// Starts the unmapped background layer from a picker [sound] name.
  Future<void> startBackground(String sound) async {
    await ensureReady();
    if (isMusicSound(sound)) {
      await _backgroundMusic.load();
      await _backgroundMusic.start();
    } else if (isBinauralSound(sound)) {
      await _backgroundBinaural.start(
        carrierHz: _backgroundBinauralCarrierHz,
        beatHz: _backgroundBinauralBeatHz,
      );
      _backgroundBinaural.setPercentile(100);
    } else {
      await _controller.startBackground(soundAssets[sound]);
    }
    _refreshMusicVolume();
    _refreshBackgroundBinauralVolume();
  }

  Future<void> stopBackground() async {
    await _backgroundMusic.stop();
    await _backgroundBinaural.stop();
    await _controller.pauseBackground();
  }

  /// Starts a session's audio: background loop (unless suppressed) plus [output].
  Future<void> playChannels({
    required String sound,
    required RewardOutputId reward,
    RewardOutput? output,
  }) async {
    await ensureReady();
    await stop();
    if (!suppressesBackground(reward)) {
      await startBackground(sound);
    }
    await (output ?? rewardOutput(reward)).start();
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBackgroundBinauralVolume();
    _refreshBinauralVolume();
  }

  double get _backgroundBinauralCarrierHz =>
      _settings.backgroundBinauralCarrierHz;

  double get _backgroundBinauralBeatHz => _settings.backgroundBinauralBeatHz;

  /// Mid-session sound/feedback change: tears down and restarts both layers
  /// with the new selection (used by the pre-session keep-phase fast path).
  Future<void> switchChannels({
    required String sound,
    required RewardOutputId reward,
    RewardOutput? output,
  }) async {
    await playChannels(sound: sound, reward: reward, output: output);
  }

  /// Legacy alias: plays [sound] as a static background loop with the classic
  /// bowl-chime feedback (settings test button).
  Future<void> playFeedback({String sound = 'Ambient Drone'}) =>
      playChannels(sound: sound, reward: RewardOutputId.chime);

  /// Legacy alias: mid-session sound swap with bowl-chime feedback.
  Future<void> switchSound(String sound) =>
      switchChannels(sound: sound, reward: RewardOutputId.chime);

  /// Music feedback channel: reloads the folder from settings and begins
  /// playback. Used when a folder is first chosen mid-session.
  Future<void> startMusic() async {
    await ensureReady();
    await _feedbackMusic.load();
    await _feedbackMusic.start();
  }

  /// Reloads the track list from the current [Settings.musicFolder] without
  /// starting playback, and returns how many playable tracks were found (0
  /// when the folder is unset/empty). Lets settings UI preview the folder.
  Future<int> loadMusic() async {
    final ok = await _feedbackMusic.load();
    return ok ? _feedbackMusic.trackCount : 0;
  }

  /// Feeds the live reward percentile (0–100) to the music feedback filter.
  void setMusicCutoffHz(double hz) => _feedbackMusic.setTargetCutoff(hz);

  /// Whether the music feedback channel is actively playing.
  bool get musicPlaying => _feedbackMusic.isPlaying;

  /// Current music track / cutoff, for the session UI and metadata.
  String? get musicTrackName => _feedbackMusic.currentTrackName;

  int get musicTrackCount => _feedbackMusic.trackCount;

  double get musicCutoffHz => _feedbackMusic.currentCutoffHz;

  /// True while music plays unmodulated as the background layer —
  /// shown as "(background)" in the session UI.
  bool get musicIsStatic =>
      _backgroundMusic.isPlaying &&
      _backgroundMusic.mode == MusicPlaybackMode.background;

  /// Whether the modulated rain channel is actively playing.
  bool get rainPlaying => _rain.isPlaying;

  /// Feeds the live reward percentile (0–100) to the rain intensity stage.
  void setRainPercentile(double pct) => _rain.setTargetPercentile(pct);

  /// Whether the binaural background layer is actively playing.
  bool get backgroundBinauralPlaying => _backgroundBinaural.isPlaying;

  /// Whether the binaural feedback layer is actively playing.
  bool get binauralPlaying => _binaural.isPlaying;

  /// Retunes the background binaural voices.
  void setBackgroundBinauralFrequencies({
    required double carrierHz,
    required double beatHz,
  }) =>
      _backgroundBinaural.setFrequencies(carrierHz: carrierHz, beatHz: beatHz);

  /// Feeds the live reward percentile (0–100) to the binaural volume — full
  /// fade at zero (off-target), full channel gain at the 100th percentile.
  void setBinauralPercentile(double pct) => _binaural.setPercentile(pct);

  /// Retunes the binaural voices (used when a preset or tuning slider
  /// changes mid-session).
  void setBinauralFrequencies({
    required double carrierHz,
    required double beatHz,
  }) => _binaural.setFrequencies(carrierHz: carrierHz, beatHz: beatHz);

  void onStateUpdate(bool inTarget) => _controller.onStateUpdate(inTarget);

  void onMovement() => _controller.onMovement();

  Future<void> playCalibration([String? assetPath]) async {
    await ensureReady();
    await _controller.playCalibration(assetPath);
  }

  Future<void> playEndChime() async {
    await ensureReady();
    await _controller.playEndChime();
  }

  Future<void> playRecalibrateChime() => _controller.playRecalibrateChime();

  Future<void> playWarningChime() => _controller.playWarningChime();

  /// Selects the guardrail warning sound (bell variants / alarm / none) and
  /// restarts a running alarm with it.
  void setWarningSound(GuardrailSound sound) =>
      _controller.setWarningSound(sound);

  /// Starts the continuous ramping alarm used while a warning stays active.
  Future<void> startWarningAlarm() async {
    await ensureReady();
    await _controller.startWarningAlarm();
  }

  /// Stops the continuous alarm (also stops it in [stop]).
  void stopWarningAlarm() => _controller.stopWarningAlarm();

  Future<void> pause() async {
    _controller.stopWarningAlarm();
    await _controller.pauseBackground();
    _backgroundMusic.pause();
    _feedbackMusic.pause();
    _rain.pause();
    _backgroundBinaural.pause();
    _binaural.pause();
  }

  Future<void> resume() async {
    await _controller.resumeBackground();
    _backgroundMusic.resume();
    _feedbackMusic.resume();
    _rain.resume();
    _backgroundBinaural.resume();
    _binaural.resume();
  }

  Future<void> stop() async {
    await _backgroundMusic.stop();
    await _feedbackMusic.stop();
    await _rain.stop();
    await _backgroundBinaural.stop();
    await _binaural.stop();
    await _controller.stop();
  }

  void dispose() {
    unawaited(() async {
      try {
        await stop();
      } catch (_) {}
      await _backgroundMusic.dispose();
      await _feedbackMusic.dispose();
      _rain.dispose();
      await _backgroundBinaural.dispose();
      await _binaural.dispose();
      _controller.dispose();
      await SoLoudEngine.deinit();
    }());
  }
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService(ref.read(settingsProvider));
  ref.onDispose(() => service.dispose());
  return service;
});
