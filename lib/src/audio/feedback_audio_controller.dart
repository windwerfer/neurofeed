import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';
import 'package:muse_ml/src/settings.dart';

/// Ambient + one-shot feedback sounds on a single SoLoud engine.
///
/// Public surface mirrors the pre-SoLoud (just_audio) controller so
/// [AudioService] and the feedback notifier stay unchanged for chime/sound
/// feedback. Music feedback (folder + low-pass filter) lives in
/// [MusicController].
class FeedbackAudioController {
  static const Duration targetHoldDuration = Duration(milliseconds: 2500);
  static const Duration rewardCooldown = Duration(seconds: 8);
  static const Duration movementBuffer = Duration(seconds: 1);
  static const int maxPolyphony = 18;
  static const double backgroundVolumeDefault = 0.5;

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

  AudioSource? _bowlSource;
  int _bowlEpoch = -1;

  SoundHandle? _backgroundHandle;
  SoundHandle? _bellHandle;
  final List<SoundHandle> _chimeHandles = [];

  DateTime? _inTargetSince;
  DateTime _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Selected guardrail warning sound (bell variants / alarm / none).
  GuardrailSound _warningSound = GuardrailSound.softBowl;

  GuardrailSound get warningSound => _warningSound;

  /// Alarm-loop bookkeeping: the ramp grows over the first minute while a
  /// warning stays active, then holds at full volume.
  Timer? _alarmTimer;
  DateTime? _alarmSince;
  SoundHandle? _alarmHandle;

  double _masterVolume = 1.0;
  double _backgroundVolume = backgroundVolumeDefault;
  double _feedbackVolume = 1.0;
  double _introVolume = 1.0;
  double _bellVolume = 1.0;
  double _guardrailVolume = 0.5;

  FeedbackAudioController(Settings settings) : _settings = settings {
    _masterVolume = settings.masterVolume ?? 1.0;
    _backgroundVolume = settings.backgroundVolume ?? backgroundVolumeDefault;
    _feedbackVolume = settings.feedbackVolume ?? 1.0;
    _introVolume = settings.introVolume ?? 1.0;
    _bellVolume = settings.bellVolume ?? 1.0;
    _guardrailVolume = settings.guardrailVolume ?? 0.5;
    _warningSound = GuardrailSound.fromName(settings.warningSoundName);
  }

  double get masterVolume => _masterVolume;

  double get backgroundVolume => _backgroundVolume;

  double get feedbackVolume => _feedbackVolume;

  double get introVolume => _introVolume;

  double get bellVolume => _bellVolume;

  double get guardrailVolume => _guardrailVolume;

  double get _backgroundVolumeTotal => _masterVolume * _backgroundVolume;

  double get _feedbackVolumeTotal => _masterVolume * _feedbackVolume;

  double get _introVolumeTotal => _masterVolume * _introVolume;

  double get _bellVolumeTotal => _masterVolume * _bellVolume;

  double get _guardrailVolumeTotal => _masterVolume * _guardrailVolume;

  /// Loads a bundled asset through the engine cache. Streams long/looped
  /// audio from a temp file ([LoadMode.disk]); decodes short one-shots
  /// ([LoadMode.memory]) for instant low-latency triggers.
  Future<AudioSource> _sourceFor(String assetPath, {required bool stream}) =>
      SoLoudEngine.loadAsset(assetPath, stream: stream);

  /// Memory-loads [bowlLowAsset] so [_triggerChime] is cache-hit only.
  Future<void> preloadChime() async {
    await SoLoudEngine.ensureInit();
    try {
      _bowlSource = await SoLoudEngine.loadAsset(bowlLowAsset, stream: false);
      _bowlEpoch = SoLoudEngine.epoch;
    } catch (e) {
      debugPrint('[audio] chime skipped: bowl source not loaded');
      _bowlSource = null;
    }
  }

  /// Plays a one-shot voice and resolves when that exact voice ends. Used for
  /// the calibration clip (the notifier awaits it before the baseline starts).
  Future<void> _playAndAwaitEnd(
    AudioSource source, {
    required double volume,
  }) async {
    final handle = SoLoud.instance.play(source, volume: volume);
    final timeout = calibrationAwaitTimeout(_sourceLength(source));
    final completer = Completer<void>();
    final sub = source.soundEvents.listen((event) {
      if (event.event == SoundEventType.handleIsNoMoreValid &&
          event.handle == handle &&
          !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      try {
        SoLoud.instance.stop(handle);
      } catch (_) {}
    } finally {
      await sub.cancel();
    }
  }

  Duration _sourceLength(AudioSource source) {
    try {
      return SoLoud.instance.getLength(source);
    } catch (_) {
      return Duration.zero;
    }
  }

  /// Applies [action] to a possibly-stale handle. [onGone] runs if SoLoud
  /// throws for a vanished handle.
  void _safeHandle(
    SoundHandle handle,
    void Function(SoundHandle) action, {
    void Function()? onGone,
  }) {
    try {
      action(handle);
    } catch (_) {
      onGone?.call();
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
    final background = _backgroundHandle;
    if (background != null) {
      _safeHandle(
        background,
        (h) => SoLoud.instance.setVolume(h, _backgroundVolumeTotal),
        onGone: () => _backgroundHandle = null,
      );
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
      _safeHandle(
        bell,
        (h) => SoLoud.instance.setVolume(h, _bellVolumeTotal),
        onGone: () => _bellHandle = null,
      );
    }
  }

  void setGuardrailVolume(double value) {
    _guardrailVolume = value.clamp(0.0, 1.0);
    _settings.setGuardrailVolume(_guardrailVolume);
    final alarm = _alarmHandle;
    if (alarm != null) {
      _safeHandle(
        alarm,
        (h) =>
            SoLoud.instance.setVolume(h, _guardrailVolumeTotal * _alarmRamp()),
        onGone: () => _alarmHandle = null,
      );
    }
  }

  void resetVolumes() {
    _masterVolume = 1.0;
    _backgroundVolume = backgroundVolumeDefault;
    _feedbackVolume = 1.0;
    _introVolume = 1.0;
    _bellVolume = 1.0;
    _guardrailVolume = 0.5;
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
    final background = _backgroundHandle;
    if (background != null) {
      _safeHandle(
        background,
        (h) => SoLoud.instance.setVolume(h, _backgroundVolumeTotal),
        onGone: () => _backgroundHandle = null,
      );
    }
    _applyFeedbackVolumes();
    final bell = _bellHandle;
    if (bell != null) {
      _safeHandle(
        bell,
        (h) => SoLoud.instance.setVolume(h, _bellVolumeTotal),
        onGone: () => _bellHandle = null,
      );
    }
  }

  void _applyFeedbackVolumes() {
    for (final handle in List.of(_chimeHandles)) {
      _safeHandle(
        handle,
        (h) => SoLoud.instance.setVolume(h, _feedbackVolumeTotal),
        onGone: () => _chimeHandles.remove(handle),
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
    _stopBackground();
    if (assetPath == null) {
      return;
    }
    final source = await _sourceFor(assetPath, stream: true);
    _backgroundHandle = SoLoud.instance.play(
      source,
      volume: _backgroundVolumeTotal,
      looping: true,
    );
  }

  Future<void> pauseBackground() async {
    final handle = _backgroundHandle;
    if (handle != null) {
      _safeHandle(handle, (h) => SoLoud.instance.setPause(h, true));
    }
  }

  Future<void> resumeBackground() async {
    final handle = _backgroundHandle;
    if (handle != null) {
      _safeHandle(handle, (h) => SoLoud.instance.setPause(h, false));
    }
  }

  /// Switches the background loop to a different asset mid-session without
  /// touching the reward state machine. A null asset stops the loop.
  Future<void> switchBackground(String? assetPath) async {
    await SoLoudEngine.ensureInit();
    _stopBackground();
    if (assetPath == null) {
      return;
    }
    final source = await _sourceFor(assetPath, stream: true);
    _backgroundHandle = SoLoud.instance.play(
      source,
      volume: _backgroundVolumeTotal,
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

  /// Selects the guardrail warning sound. A running alarm restarts with the
  /// new sound immediately.
  void setWarningSound(GuardrailSound sound) {
    _warningSound = sound;
    if (sound != GuardrailSound.none && _alarmTimer != null) {
      stopWarningAlarm();
      unawaited(startWarningAlarm());
    }
  }

  /// One-shot warning sound (bell variants). Silent when the selected sound
  /// is none or a continuous alarm (that one loops via [startWarningAlarm]).
  Future<void> playWarningChime() async {
    final sound = _warningSound;
    if (sound == GuardrailSound.none || sound.playsContinuously) {
      return;
    }
    final asset = sound.assetPath;
    if (asset == null) {
      return;
    }
    await SoLoudEngine.ensureInit();
    final source = await _sourceFor(asset, stream: false);
    SoLoud.instance.play(source, volume: _guardrailVolumeTotal);
  }

  /// Starts the continuous alarm: repeats the alarm sound with a volume ramp
  /// over the first minute (0.12 → full), then holds. Idempotent.
  Future<void> startWarningAlarm() async {
    final sound = _warningSound;
    if (sound != GuardrailSound.alarm || _alarmTimer != null) {
      return;
    }
    await SoLoudEngine.ensureInit();
    final asset = sound.assetPath;
    if (asset == null) {
      return;
    }
    AudioSource? source;
    try {
      source = await _sourceFor(asset, stream: false);
    } catch (e) {
      debugPrint('[guardrail-sound] alarm asset load failed: $e');
      return;
    }
    _alarmSince = DateTime.now();
    void playTick() {
      final handle = SoLoud.instance.play(
        source!,
        volume: _guardrailVolumeTotal * _alarmRamp(),
      );
      final prev = _alarmHandle;
      _alarmHandle = handle;
      if (prev != null) {
        _safeHandle(prev, SoLoud.instance.stop);
      }
    }

    playTick();
    _alarmTimer = Timer.periodic(const Duration(seconds: 2), (_) => playTick());
  }

  double _alarmRamp() {
    final since = _alarmSince;
    if (since == null) {
      return 1.0;
    }
    final elapsed = DateTime.now().difference(since).inSeconds;
    return 0.12 + 0.88 * (elapsed / 60.0).clamp(0.0, 1.0);
  }

  /// Stops the continuous alarm and its handle.
  void stopWarningAlarm() {
    _alarmTimer?.cancel();
    _alarmTimer = null;
    _alarmSince = null;
    final handle = _alarmHandle;
    _alarmHandle = null;
    if (handle != null) {
      _safeHandle(handle, SoLoud.instance.stop);
    }
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
    stopWarningAlarm();
    _stopBackground();
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
    unawaited(stop());
  }

  void _stopBackground() {
    final handle = _backgroundHandle;
    if (handle != null) {
      _safeHandle(handle, SoLoud.instance.stop);
    }
    _backgroundHandle = null;
  }

  void _resetRewardState() {
    _inTargetSince = null;
    _lastRewardAt = DateTime.fromMillisecondsSinceEpoch(0);
    _movingUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _triggerChime() {
    final source = _bowlEpoch == SoLoudEngine.epoch ? _bowlSource : null;
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
    final handle = SoLoud.instance.play(source, volume: _feedbackVolumeTotal);
    _chimeHandles.add(handle);
    for (final h in List.of(_chimeHandles)) {
      if (!source.handles.contains(h)) {
        _chimeHandles.remove(h);
      }
    }
  }
}

/// Timeout for awaiting a calibration clip: [length] + 2s, floor 15s, cap 90s.
/// A zero (or unknown) length uses 60s — disk-stream [getLength] can be 0.
@visibleForTesting
Duration calibrationAwaitTimeout(Duration length) {
  if (length == Duration.zero) {
    return const Duration(seconds: 60);
  }
  final padded = length + const Duration(seconds: 2);
  if (padded < const Duration(seconds: 15)) {
    return const Duration(seconds: 15);
  }
  if (padded > const Duration(seconds: 90)) {
    return const Duration(seconds: 90);
  }
  return padded;
}
