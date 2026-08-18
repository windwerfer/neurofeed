import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/binaural_beat_controller.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/music_feedback_controller.dart';
import 'package:muse_ml/src/audio/rain_feedback_controller.dart';
import 'package:muse_ml/src/settings.dart';

/// Sentinel sound name that activates music-feedback mode (user folder played
/// through the low-pass filter) instead of the ambient loop.
const String musicSoundName = 'Music from folder';

/// Orchestrates the two audio layers of a feedback session:
///
///  * **Background** — a flat, unmodulated loop (ambient drone, drone loop,
///    rain, static folder music, or nothing). Selected via [Settings.soundName]
///    and routed through `FeedbackAudioController` (assets) or
///    `MusicFeedbackController` in static mode (folder).
///  * **Feedback** — the reward channel: bowl chimes on-target, a rain loop
///    whose intensity follows the reward ([RainFeedbackController]), the
///    folder through a reward-driven low-pass filter
///    ([MusicFeedbackController] modulated), synthesized binaural beats whose
///    volume follows the reward ([BinauralBeatController]), or none.
///
/// Selecting Rain or Music as the feedback sound suppresses the background
/// (the modulated loop becomes the whole soundscape); Binaural Beats layer on
/// top of it instead (the beats sit *under* the background blend).
class AudioService {
  final Settings _settings;
  final FeedbackAudioController _controller;
  final MusicFeedbackController _music;
  final RainFeedbackController _rain;
  final BinauralBeatController _binaural;

  AudioService(Settings settings)
    : _settings = settings,
      _controller = FeedbackAudioController(settings),
      _music = MusicFeedbackController(settings),
      _rain = RainFeedbackController(),
      _binaural = BinauralBeatController() {
    _music.refreshSettings();
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBinauralVolume();
  }

  static const Map<String, String?> soundAssets = {
    'Ambient Drone': FeedbackAudioController.feedbackDroneAsset,
    'Drone Loop': FeedbackAudioController.droneLoopAsset,
    'Rain': 'assets/audio/rain/346562__lebaston100__rain-without-thunder.opus',
    'No background': null,
  };

  List<String> get availableSounds => [...soundAssets.keys, musicSoundName];

  static bool isMusicSound(String sound) => sound == musicSoundName;

  /// True when [feedback] replaces the background layer with a modulated loop.
  static bool suppressesBackground(FeedbackMode feedback) =>
      feedback == FeedbackMode.rain || feedback == FeedbackMode.music;

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
    _refreshBinauralVolume();
  }

  void setBackgroundVolume(double value) {
    _controller.setBackgroundVolume(value);
    _refreshMusicVolume();
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
    _refreshBinauralVolume();
  }

  /// Music in static (background) mode rides the background channel; music
  /// and rain as the reward channel ride the feedback channel.
  void _refreshMusicVolume() {
    final v = _music.staticMode
        ? _controller.masterVolume * _controller.backgroundVolume
        : _controller.masterVolume * _controller.feedbackVolume;
    _music.setVolume(v);
  }

  void _refreshRainVolume() {
    _rain.setVolume(_controller.masterVolume * _controller.feedbackVolume);
  }

  void _refreshBinauralVolume() {
    _binaural.setGain(_controller.masterVolume * _controller.feedbackVolume);
  }

  /// Starts a session's audio: background loop (unless suppressed) plus the
  /// reward channel for [feedback].
  Future<void> playChannels({
    required String sound,
    required FeedbackMode feedback,
  }) async {
    await _stopChannels();
    final suppress = suppressesBackground(feedback);
    if (suppress) {
      _music.setStaticMode(false);
    } else if (isMusicSound(sound)) {
      _music.setStaticMode(true);
      await _music.load();
      await _music.start();
    } else {
      _music.setStaticMode(false);
      await _controller.startBackground(soundAssets[sound]);
    }
    if (feedback == FeedbackMode.music) {
      _music.setStaticMode(false);
      await _music.load();
      await _music.start();
    } else if (feedback == FeedbackMode.rain) {
      await _rain.start();
    } else if (feedback == FeedbackMode.binaural) {
      await _binaural.start(
        carrierHz: _binauralCarrierHz,
        beatHz: _binauralBeatHz,
      );
    }
    _refreshMusicVolume();
    _refreshRainVolume();
    _refreshBinauralVolume();
  }

  /// Current binaural carrier / beat from settings.
  double get _binauralCarrierHz => _settings.binauralCarrierHz;

  double get _binauralBeatHz => _settings.binauralBeatHz;

  /// Mid-session sound/feedback change: tears down and restarts both layers
  /// with the new selection (used by the pre-session keep-phase fast path).
  Future<void> switchChannels({
    required String sound,
    required FeedbackMode feedback,
  }) async {
    await _stopChannels();
    await playChannels(sound: sound, feedback: feedback);
  }

  /// Legacy alias: plays [sound] as a static background loop with the classic
  /// bowl-chime feedback (settings test button).
  Future<void> playFeedback({String sound = 'Ambient Drone'}) =>
      playChannels(sound: sound, feedback: FeedbackMode.bowlChimes);

  /// Legacy alias: mid-session sound swap with bowl-chime feedback.
  Future<void> switchSound(String sound) =>
      switchChannels(sound: sound, feedback: FeedbackMode.bowlChimes);

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

  /// True while music (or rain) plays unmodulated as the background layer —
  /// shown as "(background)" in the session UI.
  bool get musicIsStatic => _music.staticMode;

  /// Whether the modulated rain channel is actively playing.
  bool get rainPlaying => _rain.isPlaying;

  /// Feeds the live reward percentile (0–100) to the rain intensity stage.
  void setRainPercentile(double pct) => _rain.setTargetPercentile(pct);

  /// Whether the binaural-beat layer is actively playing.
  bool get binauralPlaying => _binaural.isPlaying;

  /// Feeds the live reward percentile (0–100) to the binaural volume — full
  /// fade at zero (off-target), full channel gain at the 100th percentile.
  void setBinauralPercentile(double pct) => _binaural.setPercentile(pct);

  /// Retunes the binaural voices (used when a preset or tuning slider
  /// changes mid-session).
  void setBinauralFrequencies({
    required double carrierHz,
    required double beatHz,
  }) => _binaural.setFrequencies(carrierHz: carrierHz, beatHz: beatHz);

  /// Ducks whichever modulated channel is active during a guardrail warning.
  void setMusicMuffle(bool on) {
    _music.setMuffle(on);
    _rain.setMuffle(on);
    _binaural.setMuffle(on);
  }

  /// Guardrail warning state.
  bool get mufflesForWarning => _music.muffleActive || _rain.muffleActive;

  set mufflesForWarning(bool on) => setMusicMuffle(on);

  void onStateUpdate(bool inTarget) => _controller.onStateUpdate(inTarget);

  void onMovement() => _controller.onMovement();

  Future<void> playCalibration([String? assetPath]) =>
      _controller.playCalibration(assetPath);

  Future<void> playEndChime() => _controller.playEndChime();

  Future<void> playRecalibrateChime() => _controller.playRecalibrateChime();

  Future<void> playWarningChime() => _controller.playWarningChime();

  /// Selects the guardrail warning sound (bell variants / alarm / none) and
  /// restarts a running alarm with it.
  void setWarningSound(GuardrailSound sound) =>
      _controller.setWarningSound(sound);

  /// Starts the continuous ramping alarm used while a warning stays active.
  Future<void> startWarningAlarm() => _controller.startWarningAlarm();

  /// Stops the continuous alarm (also stops it in [stop]).
  void stopWarningAlarm() => _controller.stopWarningAlarm();

  Future<void> pause() async {
    await _controller.pauseBackground();
    _music.pause();
    _rain.pause();
    _binaural.pause();
  }

  Future<void> resume() async {
    await _controller.resumeBackground();
    _music.resume();
    _rain.resume();
    _binaural.resume();
  }

  Future<void> stop() async {
    await _music.stop();
    await _rain.stop();
    await _binaural.stop();
    await _controller.stop();
  }

  Future<void> _stopChannels() async {
    await _music.stop();
    await _rain.stop();
    await _binaural.stop();
    await _controller.stop();
  }

  void dispose() {
    _music.dispose();
    _rain.dispose();
    _binaural.dispose();
    _controller.dispose();
  }
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService(ref.read(settingsProvider));
  ref.onDispose(() => service.dispose());
  return service;
});
