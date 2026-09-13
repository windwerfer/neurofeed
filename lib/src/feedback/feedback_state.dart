import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/audio/calibration_clips.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/connect_source.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/calibration_runner.dart';
import 'package:muse_ml/src/feedback/computed_sampler.dart';
import 'package:muse_ml/src/feedback/feature_bus.dart';
import 'package:muse_ml/src/feedback/feature_override.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/feedback_recorder.dart';
import 'package:muse_ml/src/feedback/gate_electrodes.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/guardrail_mode.dart';
import 'package:muse_ml/src/feedback/live_stats.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/feedback/reward_lane.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/feedback/session_chart_data.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/reve/models.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/features.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/reve.dart' as frb;
import 'package:muse_ml/src/settings.dart';

export 'package:muse_ml/src/feedback/feedback_phase.dart';
export 'package:muse_ml/src/feedback/gate_electrodes.dart'
    show defaultGateElectrodes;
export 'package:muse_ml/src/feedback/guard_lane.dart'
    show guardrailDeltaCeiling, warningChimeCooldown;

class FeedbackState {
  final FeedbackPhase phase;
  final String protocol;
  final int durationMinutes;
  final String soundName;

  /// Reward output id (`chime` / `musicFilter` / `rainStage` /
  /// `binauralSwell` / `none`). Rain/music suppress the background layer.
  final RewardOutputId rewardOutput;
  final int elapsedSeconds;
  final bool signalGood;
  final String? interruptMessage;
  final int? interruptionSecondsLeft;
  final bool waitingForSignal;
  final bool startAnywayAvailable;
  final int baselineSecondsLeft;
  final int baselinePercentile;
  final double? currentThreshold;
  final bool showNerdStats;
  final String? calibrationStepName;
  final int calibrationStepTotal;
  final String? calibrationChallengeHint;
  final String? calibrationChallengeText;
  final bool audioInitFailed;
  final bool featureOverrideEnabled;
  final Map<String, double> featureOverrides;

  const FeedbackState({
    this.phase = FeedbackPhase.idle,
    this.protocol = 'drowsiness',
    this.durationMinutes = 15,
    this.soundName = 'Ambient Drone',
    this.rewardOutput = RewardOutputId.chime,
    this.elapsedSeconds = 0,
    this.signalGood = false,
    this.interruptMessage,
    this.interruptionSecondsLeft,
    this.waitingForSignal = false,
    this.startAnywayAvailable = false,
    this.baselineSecondsLeft = 0,
    this.baselinePercentile = defaultBaselinePercentile,
    this.currentThreshold,
    this.showNerdStats = false,
    this.calibrationStepName,
    this.calibrationStepTotal = 0,
    this.calibrationChallengeHint,
    this.calibrationChallengeText,
    this.audioInitFailed = false,
    this.featureOverrideEnabled = false,
    this.featureOverrides = const {},
  });

  static const Object _sentinel = Object();

  FeedbackState copyWith({
    FeedbackPhase? phase,
    String? protocol,
    int? durationMinutes,
    String? soundName,
    RewardOutputId? rewardOutput,
    int? elapsedSeconds,
    bool? signalGood,
    Object? interruptMessage = _sentinel,
    Object? interruptionSecondsLeft = _sentinel,
    bool? waitingForSignal,
    bool? startAnywayAvailable,
    int? baselineSecondsLeft,
    int? baselinePercentile,
    Object? currentThreshold = _sentinel,
    bool? showNerdStats,
    Object? calibrationStepName = _sentinel,
    int? calibrationStepTotal,
    Object? calibrationChallengeHint = _sentinel,
    Object? calibrationChallengeText = _sentinel,
    bool? audioInitFailed,
    bool? featureOverrideEnabled,
    Map<String, double>? featureOverrides,
  }) => FeedbackState(
    phase: phase ?? this.phase,
    protocol: protocol ?? this.protocol,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    soundName: soundName ?? this.soundName,
    rewardOutput: rewardOutput ?? this.rewardOutput,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    signalGood: signalGood ?? this.signalGood,
    interruptMessage: identical(interruptMessage, _sentinel)
        ? this.interruptMessage
        : interruptMessage as String?,
    interruptionSecondsLeft: identical(interruptionSecondsLeft, _sentinel)
        ? this.interruptionSecondsLeft
        : interruptionSecondsLeft as int?,
    waitingForSignal: waitingForSignal ?? this.waitingForSignal,
    startAnywayAvailable: startAnywayAvailable ?? this.startAnywayAvailable,
    baselineSecondsLeft: baselineSecondsLeft ?? this.baselineSecondsLeft,
    baselinePercentile: baselinePercentile ?? this.baselinePercentile,
    currentThreshold: identical(currentThreshold, _sentinel)
        ? this.currentThreshold
        : currentThreshold as double?,
    showNerdStats: showNerdStats ?? this.showNerdStats,
    calibrationStepName: identical(calibrationStepName, _sentinel)
        ? this.calibrationStepName
        : calibrationStepName as String?,
    calibrationStepTotal: calibrationStepTotal ?? this.calibrationStepTotal,
    calibrationChallengeHint: identical(calibrationChallengeHint, _sentinel)
        ? this.calibrationChallengeHint
        : calibrationChallengeHint as String?,
    calibrationChallengeText: identical(calibrationChallengeText, _sentinel)
        ? this.calibrationChallengeText
        : calibrationChallengeText as String?,
    audioInitFailed: audioInitFailed ?? this.audioInitFailed,
    featureOverrideEnabled:
        featureOverrideEnabled ?? this.featureOverrideEnabled,
    featureOverrides: featureOverrides ?? this.featureOverrides,
  );
}

class FeedbackStateNotifier extends StateNotifier<FeedbackState> {
  FeedbackStateNotifier(this._ref) : super(const FeedbackState()) {
    final storageFuture = _ref.read(sessionStorageProvider.future);
    _recorder = FeedbackRecorder(storage: storageFuture);

    _rewardOutput = const NoneRewardOutput();
    _guardOutput = const NoneGuardOutput();
    _reward = RewardLane(
      engine: RatioEngine(),
      output: _rewardOutput,
      onStats: (value) =>
          _ref.read(liveStatsProvider).push(value, _engine.percentileOf),
      onComputedFeedback:
          ({
            required ratio,
            required threshold,
            required inTarget,
            required inTargetPct,
          }) {
            _computedSampler?.updateFeedback(
              ratio: ratio,
              threshold: threshold,
              inTarget: inTarget,
              inTargetPct: inTargetPct,
            );
          },
      onThresholdChanged: () {
        state = state.copyWith(currentThreshold: _engine.threshold);
      },
    );
    _guard = GuardLane(guardOutput: _guardOutput, rewardOutput: _rewardOutput);
    _calibration = CalibrationRunner(
      loadManifest: () => _ref.read(calibrationManifestProvider.future),
      playClip: (file) => _audio.playCalibration(file),
      writeMetadata: (meta) => _recorder.writeMetadata(meta),
      updateUi: _onCalibrationUi,
      phaseOf: () => state.phase,
      protocolOf: () => state.protocol,
      sessionStartAt: () => _sessionStartAt,
      onCollectionEyes: (eyes) => _collectionEyes = eyes,
      onFinished: _finishCalibration,
    );

    _eventSub = _ref
        .read(appStateProvider.notifier)
        .eventStream
        .listen(_onEvent);
    _appSub = _ref.listen<AppUiState>(appStateProvider, _onAppState);
    final settings = _ref.read(settingsProvider);
    _engine.setDynamicAdapt(settings.dynamicAdapt ?? true);
    _engine.setResponsiveness(settings.responsiveness ?? 0.5);
    _engine.setBaselinePercentile(settings.baselinePercentile);
    _recorder.setRecordStreams(settings.recordStreams);
    state = state.copyWith(
      soundName: settings.soundName ?? state.soundName,
      rewardOutput: settings.rewardOutput,
      durationMinutes: settings.durationMinutes ?? state.durationMinutes,
      baselinePercentile: settings.baselinePercentile,
    );
    _syncOutputs();
    unawaited(_clearEnabledFeatures());
  }

  final Ref _ref;
  StreamSubscription<MuseEventDto>? _eventSub;
  ProviderSubscription<AppUiState>? _appSub;
  Timer? _ticker;
  Timer? _interruptTimer;
  Timer? _gateTimer;
  FeedbackInterruptKind? _interruptKind;
  bool _interruptWasPlaying = false;
  int _interruptionLeft = interruptionGraceSeconds;
  int _badSignalSeconds = 0;
  int _greenSeconds = 0;
  int _faultyPadSeconds = 0;
  DateTime _lastMovementAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastGestureAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _prevEyeState = 0;
  final List<GestureMarker> _gestureMarkers = [];
  int _adaptTick = 0;
  late final RewardLane _reward;
  late final GuardLane _guard;
  late RewardOutput _rewardOutput;
  late GuardOutput _guardOutput;
  late final CalibrationRunner _calibration;
  final FeatureBus _bus = FeatureBus();
  final FeatureOverride _featureOverride = FeatureOverride();
  late final FeedbackRecorder _recorder;

  RatioEngine get _engine => _reward.engine;

  /// Per-second sleep-guardrail readings captured while playing (only when
  /// the guardrail is armed). Persisted as [SessionDrowsiness] metadata.
  final List<DrowsinessSample> _drowsinessSeries = [];

  /// Computed frame sampler (1 Hz) for v5 session format.
  ComputedSampler? _computedSampler;

  /// Wall-clock anchors for the calibration timeline. [_sessionStartAt] is set
  /// when the recorder starts (calibration start); [_trainingStartAt] when
  /// training/feedback begins. Their difference is the training-boundary
  /// offset used to trim the displayed window.
  DateTime? _sessionStartAt;
  DateTime? _trainingStartAt;
  bool _usedStartAnyway = false;
  SessionCalibration? _calibrationRecord;

  /// In-flight recalibrations that re-anchored the threshold mid-session.
  final List<SessionRecalibration> _recalibrations = [];

  /// Music feedback: per-second cutoff trace + track transitions recorded
  /// while playing. Persisted as [SessionMusic] metadata (tracks + 1 Hz series).
  final List<MusicCutoffSample> _musicSeries = [];
  final List<MusicTrackMarker> _musicTracks = [];

  /// Eye state of the active silent collection window, or null while a
  /// guidance clip plays.
  String? _collectionEyes;

  /// Features actually enabled for this session (`S`). Same set sent to
  /// [setEnabledFeatures]. Calibration compose reads this, not a model-ready
  /// boolean.
  List<String> _enabledFeatureIds = const [];

  List<int> _gateElectrodes = List.of(defaultGateElectrodes);
  bool _clenchWasActive = false;

  AudioService get _audio => _ref.read(audioServiceProvider);

  /// Gate electrodes for continue-anyway + playing-phase pause (Muse AF7/AF8
  /// until session start resolves names). AI window does not add TP9/TP10.
  List<int> get gateElectrodes => List.unmodifiable(_gateElectrodes);

  void selectProtocol(String protocolId) {
    final catalog = _ref.read(protocolCatalogProvider).valueOrNull;
    final info = catalog?.forName(protocolId);
    _engine.featureId = info?.reward?.feature ?? 'band.atr';
    final settings = _ref.read(settingsProvider);
    final output = resolveRewardOutputId(
      hasReward: info?.hasReward ?? false,
      storedPref: settings.rewardOutputPref,
      catalogOutput: info?.reward?.output,
    );
    state = state.copyWith(protocol: protocolId, rewardOutput: output);
    _syncOutputs();
  }

  void selectDuration(int minutes, {bool persist = true}) {
    state = state.copyWith(durationMinutes: minutes);
    if (persist) _ref.read(settingsProvider).setDurationMinutes(minutes);
  }

  void _setPhase(FeedbackPhase phase, {String? extra}) {
    final extraBit = extra == null ? '' : ' $extra';
    debugPrint('[feedback] phase=${phase.name}$extraBit');
    state = state.copyWith(phase: phase);
  }

  void selectSound(String name) {
    state = state.copyWith(soundName: name);
    _ref.read(settingsProvider).setSoundName(name);
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      unawaited(_switchChannelsWhileKeepingPhase());
    }
  }

  /// Selects the reward output (chime / rainStage / musicFilter /
  /// binauralSwell / none). Rain and Music suppress the background layer;
  /// Binaural Beats layer on top of it. Switching mid-session restarts the
  /// channels without leaving the current phase.
  void selectRewardOutput(RewardOutputId id) {
    if (id == RewardOutputId.binauralSwell) {
      _seedBinauralVolumes();
    }
    state = state.copyWith(rewardOutput: id);
    _ref.read(settingsProvider).setRewardOutput(id);
    _syncOutputs();
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      unawaited(_switchChannelsWhileKeepingPhase());
    }
  }

  /// First time binaural beats are picked, the shared feedback channel still
  /// sits at its generic 100% default — far too loud for a beat layer meant
  /// to blend under the background. Seed it to the 15% binaural standard
  /// unless the user has already tuned volumes.
  void _seedBinauralVolumes() {
    final settings = _ref.read(settingsProvider);
    if (settings.feedbackVolume == null) {
      _audio.setFeedbackVolume(0.15);
    }
  }

  void _syncOutputs() {
    _rewardOutput = _audio.rewardOutput(state.rewardOutput);
    _guardOutput = _audio.guardOutput();
    _reward.output = _rewardOutput;
    _guard.rewardOutput = _rewardOutput;
    _guard.guardOutput = _guardOutput;
    final catalog = _ref.read(protocolCatalogProvider).valueOrNull;
    final spec = catalog?.forName(state.protocol);
    final settings = _ref.read(settingsProvider);
    final guardId = resolveGuardOutputId(
      storedPref: settings.warningSoundPref,
      catalogOutput: spec?.guard?.output,
    );
    _audio.setWarningSound(GuardrailSound.fromName(guardId));
  }

  Future<void> _switchChannelsWhileKeepingPhase() async {
    await _audio.switchChannels(
      sound: state.soundName,
      reward: state.rewardOutput,
      output: _rewardOutput,
    );
    if (state.phase == FeedbackPhase.paused) {
      await _audio.pause();
    }
  }

  void selectPercentile(int percentile) {
    _engine.setBaselinePercentile(percentile);
    _ref.read(settingsProvider).setBaselinePercentile(percentile);
    state = state.copyWith(baselinePercentile: percentile);
    final stats = _ref.read(liveStatsProvider);
    stats.setBaseline(
      percentile: percentile,
      count: _engine.baselineCount,
      mean: _engine.baselineMean,
      stddev: _engine.baselineStddev,
    );
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      _engine.computeThreshold();
      state = state.copyWith(currentThreshold: _engine.threshold);
      stats.setThreshold(_engine.threshold);
    }
  }

  void toggleNerdStats() {
    state = state.copyWith(showNerdStats: !state.showNerdStats);
  }

  bool get featureProbeAvailable {
    if (!kDebugMode) {
      return false;
    }
    final app = _ref.read(appStateProvider);
    return app.status.connected && isSimDeviceId(app.status.id);
  }

  List<String> get probeFeatureIds {
    if (_enabledFeatureIds.isNotEmpty) {
      return List.unmodifiable(_enabledFeatureIds);
    }
    final catalog = _ref.read(protocolCatalogProvider).valueOrNull;
    final spec = catalog?.forName(state.protocol);
    final settings = _ref.read(settingsProvider);
    final ids = <String>[];
    final reward = spec?.reward?.feature;
    if (reward != null) {
      ids.add(reward);
    }
    if (spec?.guard != null && settings.guardrailEnabledFor(state.protocol)) {
      final guard = settings.guardFeatureFor(state.protocol);
      if (guard != guardFeatureNone && !ids.contains(guard)) {
        ids.add(guard);
      }
    }
    return ids;
  }

  double? get rewardLastNative => _reward.lastNative;

  double? get rewardLastPercentile => _reward.lastPercentile;

  bool get rewardLastInTarget => _reward.lastInTarget;

  bool get guardWarningActive => _guard.warningActive;

  double? get guardThreshold => _guard.threshold;

  void setFeatureOverrideEnabled(bool on) {
    if (on && !featureProbeAvailable) {
      return;
    }
    if (on) {
      for (final id in probeFeatureIds) {
        _featureOverride.setIfAbsent(id);
      }
    }
    _featureOverride.enabled = on;
    _syncOverrideState();
    if (!on) {
      return;
    }
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      _replaceBaselineForProbe();
      _emitOverrideTicks();
    }
    if (_sessionStartAt != null) {
      _recorder.writeMetadata({
        'type': 'feature_override',
        'enabled': true,
        'values': Map<String, double>.from(_featureOverride.values),
      });
    }
  }

  void setFeatureOverride(String id, double? value) {
    if (value != null && !featureProbeAvailable) {
      return;
    }
    _featureOverride.set(id, value);
    _syncOverrideState();
    if (value != null) {
      _emitOverrideTick(id, value);
    }
  }

  void _replaceBaselineForProbe() {
    _engine.reset();
    _seedSyntheticBaseline();
  }

  void _emitOverrideTicks() {
    for (final e in _featureOverride.values.entries) {
      _emitOverrideTick(e.key, e.value);
    }
  }

  void _emitOverrideTick(String id, double value) {
    if (!_featureOverride.enabled ||
        !featureProbeAvailable ||
        (state.phase != FeedbackPhase.playing &&
            state.phase != FeedbackPhase.paused)) {
      return;
    }
    debugPrint('[probe] $id=${value.toStringAsFixed(3)}');
    _onEvent(
      MuseEventDto.feature(
        FeatureDto(
          id: id,
          timestamp: DateTime.now().millisecondsSinceEpoch.toDouble(),
          value: value,
        ),
      ),
    );
  }

  void _syncOverrideState() {
    state = state.copyWith(
      featureOverrideEnabled: _featureOverride.enabled,
      featureOverrides: Map<String, double>.from(_featureOverride.values),
    );
  }

  MuseEventDto _maybeOverrideFeature(MuseEventDto event) {
    if (!_featureOverride.enabled ||
        !featureProbeAvailable ||
        (state.phase != FeedbackPhase.playing &&
            state.phase != FeedbackPhase.paused)) {
      return event;
    }
    return _featureOverride.apply(event);
  }

  void _seedSyntheticBaseline() {
    if (_reward.hasReward) {
      for (final v in FeatureOverride.baselineSamples(_reward.featureId)) {
        _engine.addBaselineSample(v);
      }
      final threshold = _engine.computeThreshold();
      state = state.copyWith(currentThreshold: threshold);
      _ref
          .read(liveStatsProvider)
          .setBaseline(
            percentile: _engine.baselinePercentile,
            count: _engine.baselineCount,
            mean: _engine.baselineMean,
            stddev: _engine.baselineStddev,
          );
      _ref.read(liveStatsProvider).setThreshold(threshold);
    }
    if (_guard.enabled) {
      _guard.baselineSleepDir
        ..clear()
        ..addAll(FeatureOverride.baselineSamples(_guard.featureId));
      _guard.finalizeBaseline(
        warningThresholdPercentile: warningThresholdPercentile,
      );
    }
    debugPrint(
      '[feedback] synthetic baseline seeded '
      'reward=${_reward.hasReward ? _reward.featureId : 'off'} '
      'guard=${_guard.enabled ? _guard.featureId : 'off'}',
    );
  }

  bool get dynamicAdapt => _engine.dynamicAdapt;

  double get responsiveness => _engine.responsiveness;

  void setDynamicAdapt(bool enabled) {
    _engine.setDynamicAdapt(enabled);
    _ref.read(settingsProvider).setDynamicAdapt(enabled);
  }

  void setResponsiveness(double value) {
    _engine.setResponsiveness(value);
    _ref.read(settingsProvider).setResponsiveness(value);
  }

  void resetTargetSettings() {
    setDynamicAdapt(true);
    setResponsiveness(0.5);
  }

  /// REVE sleep-guardrail warning threshold (percentile of the eyes-closed
  /// sleep-direction distribution). Only exposed when the selected protocol's
  /// spec offers the guardrail layer.
  int get warningThresholdPercentile =>
      _ref.read(settingsProvider).warningThresholdPercentile;

  void setWarningThresholdPercentile(int percentile) {
    _ref.read(settingsProvider).setWarningThresholdPercentile(percentile);
    if (_guard.baselineSleepDir.isNotEmpty &&
        (state.phase == FeedbackPhase.playing ||
            state.phase == FeedbackPhase.paused ||
            state.phase == FeedbackPhase.interrupted)) {
      _guard.recomputeThreshold(percentile);
    }
  }

  /// Begin calibration: play the voice intro, require all electrodes green
  /// for [greenStableSeconds] before starting a [calibrationBaselineSeconds]
  /// silent baseline, then start feedback automatically. Opens the connect
  /// window if the Muse is not connected. There is no gate after the
  /// baseline. If one pad never turns green for [faultyPadSeconds] while the
  /// needed frontal pads do, it is assumed faulty and a continue-anyway
  /// fallback is shown.
  ///
  /// With [skipCalibration] the signal gate and the baseline are skipped
  /// entirely: the recorder starts and the session goes straight to playing
  /// (used by the recordOnly protocol's "Start (skip calibration)" button).
  /// The ATR engine then has no baseline, which is fine — no-reward protocols
  /// never evaluate it.
  Future<void> startCalibration({bool skipCalibration = false}) async {
    final app = _ref.read(appStateProvider);
    if (!app.status.connected) {
      _ref.read(appStateProvider.notifier).openConnectWindowAndScan();
      return;
    }
    if (app.lastConnectedKind != null &&
        deviceKindIsCrown(app.lastConnectedKind!)) {
      debugPrint('[feedback] refusing Start on Crown');
      return;
    }
    final leased = await _ref
        .read(monitorControllerProvider.notifier)
        .acquireFeedbackLease();
    if (!leased) {
      debugPrint('[feedback] refusing Start: recording_active');
      return;
    }
    // Open the audio device before the calibration clip. On Android this
    // selects the "Reduce audio stutter" AAudio profile (and falls back to
    // low-latency if that HAL path cannot start). Elsewhere the flag is a
    // no-op. A failed open is logged; calibration still runs silently.
    var audioFailed = false;
    try {
      await _audio.ensureReady(reopenIfProfileDiffers: true);
    } catch (e) {
      debugPrint('[feedback] audio-init-failed: $e');
      audioFailed = true;
    }
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      _ticker?.cancel();
      _audio.stop();
    }
    state = state.copyWith(
      elapsedSeconds: 0,
      waitingForSignal: false,
      startAnywayAvailable: false,
      baselineSecondsLeft: 0,
      currentThreshold: null,
      audioInitFailed: audioFailed,
    );
    _setPhase(FeedbackPhase.calibrating, extra: 'protocol=${state.protocol}');
    _gestureMarkers.clear();
    _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
    _prevEyeState = 0;
    _clenchWasActive = false;
    _sessionStartAt = DateTime.now();
    _trainingStartAt = null;
    _usedStartAnyway = false;
    _calibrationRecord = null;
    _recalibrations.clear();
    _calibration.reset();
    _collectionEyes = null;
    _drowsinessSeries.clear();
    _musicSeries.clear();
    _musicTracks.clear();
    await _recorder.startSession();
    _computedSampler = ComputedSampler(
      onFrame: (frame) => _recorder.appendComputed(frame),
      recordingStart: _sessionStartAt!,
    );
    _computedSampler!.start();
    await _enableSessionFeatures();
    await _maybeEnableGuardrail();
    if (skipCalibration) {
      _engine.reset();
      if (featureProbeAvailable) {
        _seedSyntheticBaseline();
      }
      await startPlaying();
      return;
    }
    await _runCalibration();
  }

  /// True when this session intends to run the guardrail: the user has not
  /// disabled it for this protocol and a model is ready (or band-math).
  /// Feeds the enabled feature set `S` and [_maybeEnableGuardrail]. The
  /// async arm may still fail, in which case the session runs without
  /// warnings (a staged recipe still calibrates — it just has no scorer).
  bool get _guardrailIntent {
    final settings = _ref.read(settingsProvider);
    if (!settings.guardrailEnabledFor(state.protocol)) {
      return false;
    }
    if (settings.guardrailIsBandMathFor(state.protocol)) {
      return true;
    }
    return _ref.read(modelEngineNotifierProvider) is ModelEngineReady;
  }

  CalibrationPlan get _calibrationPlan =>
      CalibrationPlan.fromEnabledFeatures(_enabledFeatureIds);

  Future<void> _enableSessionFeatures() async {
    final app = _ref.read(appStateProvider);
    final kind = app.lastConnectedKind ?? DeviceKind.muse;
    var montage = museMontageNames;
    try {
      final config = await DeviceConfig.forKind(kind: kind);
      montage = config.electrodeNames;
    } catch (e) {
      debugPrint('[feature] DeviceConfig.forKind failed: $e');
    }

    final catalog = _ref.read(protocolCatalogProvider).valueOrNull;
    final spec = catalog?.forName(state.protocol);
    final settings = _ref.read(settingsProvider);
    final guardOn = _guardrailIntent;
    final guardFeature = settings.guardFeatureFor(state.protocol);

    List<FeatureInfo> infos = const [];
    try {
      infos = await availableFeatures(kind: kind);
      debugPrint(
        '[feature] available_features ${[for (final f in infos) '${f.id} available=${f.available} reason=${f.unavailableReason} electrodes=${f.defaultElectrodes}']}',
      );
    } catch (e) {
      debugPrint('[feature] available_features failed: $e');
    }
    final byId = {for (final f in infos) f.id: f};

    final rewardDefault = spec?.reward == null
        ? null
        : byId[spec!.reward!.feature]?.defaultElectrodes;
    final guardDefault = guardOn && guardFeature != guardFeatureNone
        ? byId[guardFeature]?.defaultElectrodes
        : null;

    final gateNames = gateElectrodeNames(
      hasReward: spec?.hasReward ?? false,
      guardOn: guardOn,
      guardFeature: guardFeature,
      rewardElectrodes: spec?.reward?.electrodes ?? rewardDefault,
      guardElectrodes: spec?.guard?.electrodes ?? guardDefault,
    );
    final resolved = electrodeIndicesFor(gateNames, montageNames: montage);
    _gateElectrodes = resolved.isEmpty
        ? List.of(defaultGateElectrodes)
        : resolved;

    final ids = <String>[];
    if (spec?.reward != null) {
      final id = spec!.reward!.feature;
      final override = spec.reward!.electrodes;
      if (override != null) {
        try {
          await setFeatureElectrodes(id: id, names: override);
          debugPrint('[feature] set_feature_electrodes $id $override');
        } catch (e) {
          debugPrint('[feature] set_feature_electrodes $id failed: $e');
        }
      }
      ids.add(id);
    }
    if (guardOn && guardFeature != guardFeatureNone) {
      final override = spec?.guard?.electrodes;
      if (override != null) {
        try {
          await setFeatureElectrodes(id: guardFeature, names: override);
          debugPrint(
            '[feature] set_feature_electrodes $guardFeature $override',
          );
        } catch (e) {
          debugPrint(
            '[feature] set_feature_electrodes $guardFeature failed: $e',
          );
        }
      }
      ids.add(guardFeature);
    }
    final unique = <String>[];
    for (final id in ids) {
      if (!unique.contains(id)) {
        unique.add(id);
      }
    }
    _enabledFeatureIds = unique;
    try {
      await setEnabledFeatures(ids: unique);
      debugPrint('[feature] set_enabled_features $unique');
    } catch (e) {
      debugPrint('[feature] set_enabled_features failed: $e');
    }

    final rewardNames =
        spec?.reward?.electrodes ?? rewardDefault ?? museGateElectrodeNames;
    _reward.configure(
      hasReward: spec?.hasReward ?? false,
      featureId: spec?.reward?.feature,
      inhibit: spec?.conditions ?? const [],
      electrodeNames: rewardNames,
      montageNames: montage,
    );
    final deltaIdx = electrodeIndicesFor(
      museGateElectrodeNames,
      montageNames: montage,
    );
    _guard.configure(
      enabled: false,
      bandMath: settings.guardrailIsBandMathFor(state.protocol),
      featureId: guardFeature == guardFeatureNone
          ? guardFeatureBandDelta
          : guardFeature,
      deltaElectrodes: deltaIdx.isEmpty ? defaultGateElectrodes : deltaIdx,
    );
  }

  Future<void> _clearEnabledFeatures() async {
    _enabledFeatureIds = const [];
    try {
      await setEnabledFeatures(ids: []);
      debugPrint('[feature] set_enabled_features []');
    } catch (e) {
      debugPrint('[feature] set_enabled_features [] failed: $e');
    }
  }

  /// Arm the REVE/LUNA sleep-guardrail scorer according to the per-protocol
  /// setting ([Settings.guardrailEnabledFor]), using the settings-selected
  /// foundation model. Scoring starts immediately in the forwarder (first
  /// embedding lands after ~5 s) so the calibration baseline can capture the
  /// clear anchor. No-op when disabled.
  Future<void> _maybeEnableGuardrail() async {
    _guard.resetSession();
    if (!_guardrailIntent) {
      return;
    }
    final settings = _ref.read(settingsProvider);
    if (settings.guardrailIsBandMathFor(state.protocol)) {
      _guard.configure(
        enabled: true,
        bandMath: true,
        featureId: guardFeatureBandDelta,
        deltaElectrodes: _guard.deltaElectrodes,
      );
      debugPrint('[guardrail] enabled (band math — no model)');
      return;
    }
    final engine = _ref.read(modelEngineNotifierProvider);
    if (engine is! ModelEngineReady) {
      debugPrint('[guardrail] model not ready — guardrail stays off');
      return;
    }
    final ffId = settings.guardModel ?? defaultModelKind.ffId;
    try {
      final ok = await frb.guardrailEnable(kind: ffId);
      _guard.configure(
        enabled: ok,
        bandMath: false,
        featureId: guardFeatureAiDrowsiness,
        deltaElectrodes: _guard.deltaElectrodes,
      );
      if (ok) {
        debugPrint('[guardrail] enabled ($ffId)');
      }
    } catch (e) {
      _guard.configure(
        enabled: false,
        bandMath: false,
        featureId: guardFeatureAiDrowsiness,
        deltaElectrodes: _guard.deltaElectrodes,
      );
      debugPrint('[guardrail] enable failed: $e');
    }
  }

  /// In-flight re-anchoring: rebuilds the baseline from the recent clean
  /// session ratio samples instead of running another silent calibration. Only
  /// valid during playing/paused; returns false when the session is too young
  /// or there are too few clean samples.
  bool recalibrate() {
    if (state.phase != FeedbackPhase.playing &&
        state.phase != FeedbackPhase.paused) {
      return false;
    }
    final ok = _engine.recalibrateFromRecent(minSamples: minRecalibrateSamples);
    if (!ok) {
      debugPrint(
        '[feedback] in-flight recalibrate skipped at t=${state.elapsedSeconds}s: '
        'fewer than $minRecalibrateSamples clean samples',
      );
      return false;
    }
    _adaptTick = 0;
    _recalibrations.add(
      SessionRecalibration(
        atSecs: state.elapsedSeconds.toDouble(),
        baseline: SessionBaselineStats(
          percentile: _engine.baselinePercentile.toDouble(),
          count: _engine.baselineCount,
          mean: _engine.baselineMean,
          stddev: _engine.baselineStddev,
        ),
      ),
    );
    if (_sessionStartAt != null) {
      _recorder.writeMetadata({
        'type': 'recalibration',
        'atSecs': state.elapsedSeconds.toDouble(),
        'threshold': _engine.threshold,
        'baselineCount': _engine.baselineCount,
        'baselinePercentile': _engine.baselinePercentile,
        'baselineMean': _engine.baselineMean,
        'baselineStddev': _engine.baselineStddev,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    final stats = _ref.read(liveStatsProvider);
    stats
      ..setBaseline(
        percentile: _engine.baselinePercentile,
        count: _engine.baselineCount,
        mean: _engine.baselineMean,
        stddev: _engine.baselineStddev,
      )
      ..setThreshold(_engine.threshold);
    debugPrint(
      '[feedback] in-flight recalibrate at t=${state.elapsedSeconds}s: '
      'threshold -> ${_engine.threshold} (p${_engine.baselinePercentile}, '
      'n=${_engine.baselineCount} clean samples, mean=${_engine.baselineMean}, '
      'sd=${_engine.baselineStddev})',
    );
    state = state.copyWith(currentThreshold: _engine.threshold);
    return true;
  }

  Future<void> _runCalibration() async {
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    _engine.reset();
    _greenSeconds = 0;
    _faultyPadSeconds = 0;
    state = state.copyWith(waitingForSignal: true, startAnywayAvailable: false);
    _startGateTimer();
  }

  /// Ticks once a second during the calibration signal gate. Starts the
  /// calibration (intro + baseline) once all pads have been green for
  /// [greenStableSeconds] continuously. Flags the faulty-pad fallback once a
  /// missing pad has persisted for [faultyPadSeconds] while the frontal pads
  /// are green.
  void _startGateTimer() {
    _gateTimer?.cancel();
    _gateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase != FeedbackPhase.calibrating) {
        _gateTimer?.cancel();
        return;
      }
      final quality = _ref.read(appStateProvider).signalQuality;
      if (_allGreen(quality)) {
        _greenSeconds++;
        if (_greenSeconds >= greenStableSeconds) {
          _gateTimer?.cancel();
          unawaited(_calibration.playAndBaseline(plan: _calibrationPlan));
        }
        return;
      }
      _greenSeconds = 0;
      if (_hasNeededElectrode(quality) && !state.startAnywayAvailable) {
        _faultyPadSeconds++;
        if (_faultyPadSeconds >= faultyPadSeconds) {
          state = state.copyWith(startAnywayAvailable: true);
        }
      }
    });
  }

  void _onCalibrationUi(CalibrationUi ui) {
    state = state.copyWith(
      waitingForSignal: ui.waitingForSignal ?? state.waitingForSignal,
      startAnywayAvailable:
          ui.startAnywayAvailable ?? state.startAnywayAvailable,
      baselineSecondsLeft: ui.baselineSecondsLeft ?? state.baselineSecondsLeft,
      calibrationStepName: ui.stepName ?? state.calibrationStepName,
      calibrationStepTotal: ui.stepTotal ?? state.calibrationStepTotal,
      calibrationChallengeHint: ui.clearChallenges
          ? null
          : (ui.challengeHint ?? state.calibrationChallengeHint),
      calibrationChallengeText: ui.clearChallenges
          ? null
          : (ui.challengeText ?? state.calibrationChallengeText),
    );
  }

  void _finishCalibration() {
    _calibration.cancelTimers();
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    final threshold = _engine.computeThreshold();
    debugPrint(
      '[feedback] baseline ratio threshold = $threshold '
      '(${_engine.baselineCount} samples, p${_engine.baselinePercentile})',
    );
    _ref
        .read(liveStatsProvider)
        .setBaseline(
          percentile: _engine.baselinePercentile,
          count: _engine.baselineCount,
          mean: _engine.baselineMean,
          stddev: _engine.baselineStddev,
        );
    _ref.read(liveStatsProvider).setThreshold(threshold);
    if (_guard.enabled && (_guard.clearCaptured || _guard.bandMath)) {
      _guard.finalizeBaseline(
        warningThresholdPercentile: warningThresholdPercentile,
      );
    }
    if (_sessionStartAt != null) {
      _recorder.writeMetadata({
        'type': 'calibration_complete',
        'threshold': threshold,
        'baselineCount': _engine.baselineCount,
        'baselinePercentile': _engine.baselinePercentile,
        'baselineMean': _engine.baselineMean,
        'baselineStddev': _engine.baselineStddev,
        'timestamp': DateTime.now().toIso8601String(),
        'elapsedSecs':
            DateTime.now().difference(_sessionStartAt!).inMilliseconds / 1000,
      });
    }
    _recordCalibration();
    state = state.copyWith(
      baselineSecondsLeft: 0,
      currentThreshold: threshold,
      calibrationChallengeHint: null,
      calibrationChallengeText: null,
    );
    unawaited(startPlaying());
  }

  /// Records how this calibration ran so a saved session is reproducible:
  /// timeline (calibration start/end, training start), the gate rejection
  /// criteria, the ATR baseline statistics, and every guidance clip that
  /// played (with its window marked so the raw EEG in those seconds is known).
  void _recordCalibration() {
    final now = DateTime.now();
    _trainingStartAt = now;
    final sessionStart = _sessionStartAt;
    _calibrationRecord = SessionCalibration(
      version: CalibrationManifest.currentVersion,
      kind: _calibration.kind,
      calibrationId: _calibration.calibrationId,
      calibrationJson: _calibration.calibrationJson,
      calibrationStartSecs: sessionStart == null
          ? null
          : sessionStart.millisecondsSinceEpoch / 1000,
      calibrationEndSecs: now.millisecondsSinceEpoch / 1000,
      trainingStartSecs: now.millisecondsSinceEpoch / 1000,
      usedStartAnyway: _usedStartAnyway,
      greenStableSeconds: greenStableSeconds,
      faultyPadSeconds: faultyPadSeconds,
      baseline: SessionBaselineStats(
        percentile: _engine.baselinePercentile.toDouble(),
        count: _engine.baselineCount,
        mean: _engine.baselineMean,
        stddev: _engine.baselineStddev,
      ),
      phases: List.of(_calibration.clipPhases),
      recalibrations: List.of(_recalibrations),
    );
  }

  /// Bypasses the calibration signal gate (used when the user opts to start
  /// anyway after a faulty pad has been detected). Plays the intro and starts
  /// the baseline immediately.
  void startAnyway() {
    if (state.phase != FeedbackPhase.calibrating ||
        !state.startAnywayAvailable) {
      return;
    }
    _usedStartAnyway = true;
    _gateTimer?.cancel();
    unawaited(_calibration.playAndBaseline(plan: _calibrationPlan));
  }

  /// Start the feedback loop: record the session and begin the background
  /// audio layer.
  Future<void> startPlaying() async {
    if (!_ref.read(appStateProvider).status.connected) {
      _ref.read(appStateProvider.notifier).openConnectWindowAndScan();
      return;
    }
    _setPhase(FeedbackPhase.playing);
    state = state.copyWith(currentThreshold: _engine.threshold);
    _reward.resetBands();
    _adaptTick = 0;
    _trainingStartAt ??= DateTime.now();
    _startTicker();
    _syncOutputs();
    try {
      await _audio.playChannels(
        sound: state.soundName,
        reward: state.rewardOutput,
        output: _rewardOutput,
      );
      if (state.audioInitFailed) {
        state = state.copyWith(audioInitFailed: false);
      }
    } catch (e) {
      debugPrint('[feedback] audio-init-failed: $e');
      state = state.copyWith(audioInitFailed: true);
    }
    if (_featureOverride.enabled && featureProbeAvailable) {
      _replaceBaselineForProbe();
      _emitOverrideTicks();
    }
  }

  Future<void> pause() async {
    _setPhase(FeedbackPhase.paused);
    _ticker?.cancel();
    await _audio.pause();
  }

  Future<void> resume() async {
    _setPhase(FeedbackPhase.playing);
    await _audio.resume();
    _startTicker();
  }

  /// End the session: assemble a scratch v5 **before** `phase = ended` (the
  /// session view navigates on that transition), then stop audio.
  Future<void> end() async {
    if (state.phase == FeedbackPhase.ended) {
      return;
    }
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _interruptTimer = null;
    _calibration.cancelTimers();
    _computedSampler?.stop();
    _guard.teardown();
    unawaited(_clearEnabledFeatures());
    await _recorder.flushSession();
    try {
      final path = await _recorder.assembleScratchV5(
        buildSessionMetadata().toJson(),
      );
      if (path == null) {
        debugPrint('[feedback] end: scratch v5 assemble failed; temps kept');
      }
    } catch (e, st) {
      debugPrint('[feedback] end: scratch v5 assemble failed: $e\n$st');
    }
    if (!_recorder.isRecording) {
      await _ref
          .read(monitorControllerProvider.notifier)
          .releaseFeedbackLease();
    }
    _setPhase(
      FeedbackPhase.ended,
      extra: 'scratch=${_recorder.scratchV5Path ?? 'null'}',
    );
    await _audio.stop();
    await _audio.playEndChime();
  }

  void reset() {
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _interruptTimer = null;
    _calibration.reset();
    _computedSampler?.stop();
    _gateTimer?.cancel();
    _gateTimer = null;
    _greenSeconds = 0;
    _faultyPadSeconds = 0;
    _adaptTick = 0;
    _lastMovementAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastGestureAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
    _prevEyeState = 0;
    _clenchWasActive = false;
    _gestureMarkers.clear();
    _guard.teardown();
    unawaited(_clearEnabledFeatures());
    _drowsinessSeries.clear();
    _musicSeries.clear();
    _musicTracks.clear();
    _audio.stop();
    unawaited(discardSession());
    _reward.reset();
    _bus.reset();
    _sessionStartAt = null;
    _trainingStartAt = null;
    _usedStartAnyway = false;
    _calibrationRecord = null;
    _recalibrations.clear();
    _collectionEyes = null;
    _gateElectrodes = List.of(defaultGateElectrodes);
    _featureOverride.clear();
    _ref.read(liveStatsProvider).reset();
    state = const FeedbackState();
    debugPrint('[feedback] phase=idle');
  }

  String? get sessionFilePath => _recorder.scratchV5Path;

  String? get scratchV5Path => _recorder.scratchV5Path;

  String? get sessionId => _recorder.sessionId;

  /// Recorded calibration record for the current session (timeline, gate,
  /// baseline stats, intro clip). Null until calibration completes.
  SessionCalibration? get calibration => _calibrationRecord;

  /// Seconds from recording start to the training boundary, or null when no
  /// calibration was recorded (e.g. legacy/unknown-session previews).
  double? get trainingStartOffsetSecs =>
      _calibrationRecord?.trainingStartOffsetSecs;

  /// Electrode indices that produced data in the current recording.
  Set<int> get recordedChannels => _recorder.recordedChannels;

  /// Streams enabled for this session's recording.
  Set<RecordingStream> get recordStreams => _recorder.streams;

  Future<void> discardSession() async {
    await _recorder.discardSession();
    await _ref.read(monitorControllerProvider.notifier).releaseFeedbackLease();
  }

  Future<void> deleteScratchV5() => _recorder.deleteScratchV5();

  /// Snapshot metadata for the scratch v5 at end() and the rewritten file
  /// on Save. No `summary` / 400-bucket fields. Drowsiness is scalars only.
  SessionMetadata buildSessionMetadata({
    String notes = '',
    SessionChartStats? stats,
  }) {
    final fb = state;
    final app = _ref.read(appStateProvider);
    final settings = _ref.read(settingsProvider);
    final catalog = _ref.read(protocolCatalogProvider).valueOrNull;
    final protocol = catalog?.forName(fb.protocol);
    final feature = settings.guardFeatureFor(fb.protocol);
    final model = settings.guardModel;
    final channels = recordedChannels.map(channelName).toList()..sort();
    final drowsy = sessionDrowsiness;
    return SessionMetadata(
      protocol: fb.protocol,
      durationMinutes: fb.durationMinutes,
      elapsedSeconds: fb.elapsedSeconds,
      durationS: fb.elapsedSeconds,
      sound: fb.soundName,
      feedbackSound: fb.rewardOutput.name,
      savedAt: DateTime.now().toIso8601String(),
      startedAt: _sessionStartAt?.toIso8601String(),
      notes: notes,
      sessionId: sessionId,
      stats: stats == null
          ? null
          : SessionStatsData(
              peakAlphaFreq: stats.peakAlphaFreq,
              peakAlphaPower: stats.peakAlphaPower,
              targetPct: stats.targetPct,
              stillnessPct: stats.stillnessPct,
              avgBpm: stats.avgBpm,
              avgAlphaRel: stats.avgAlphaRel,
            ),
      deviceName: app.status.connected ? app.status.name : null,
      deviceModel: app.status.connected ? app.status.firmware : null,
      deviceId: app.status.connected ? app.status.id : null,
      recordedChannels: channels,
      recordedData: recordStreams.map((s) => s.name).toList(),
      gestures: settings.markersInFeedbackEnabled ? gestureMarkers : const [],
      calibration: calibration,
      drowsiness: drowsy,
      music: sessionMusic,
      metadataDescription: protocol?.metadataDescription,
      protocolJson: protocol?.resolved(guardFeature: feature).toJson(),
      protocolVersion: '1',
      sessionSettings: SessionSettings(
        dynamicAdapt: dynamicAdapt,
        responsiveness: responsiveness,
        baselinePercentile: fb.baselinePercentile,
        guardrailEnabled: guardrailEnabled,
        guardrailEngine: guardrailEnabled
            ? guardrailEngineName(feature: feature, model: model)
            : 'none',
        guardFeature: feature,
        guardModel: model,
        warningThresholdPercentile: settings.warningThresholdPercentile,
        warningSound: settings.warningSoundName,
        musicFolder: settings.musicFolder,
        musicMinCutoffHz: settings.musicMinCutoffHz,
        musicMaxCutoffHz: settings.musicMaxCutoffHz,
        musicInvert: settings.musicInvertMapping,
        musicShuffle: settings.musicShuffle,
        binauralPresetId: settings.binauralPresetId,
        binauralCarrierHz: settings.binauralCarrierHz,
        binauralBeatHz: settings.binauralBeatHz,
        backgroundBinauralPresetId: settings.backgroundBinauralPresetId,
        backgroundBinauralCarrierHz: settings.backgroundBinauralCarrierHz,
        backgroundBinauralBeatHz: settings.backgroundBinauralBeatHz,
        markersInFeedbackEnabled: settings.markersInFeedbackEnabled,
        eyeMarkersEnabled: settings.eyeMarkersEnabled,
      ),
      avgSpo2: stats?.avgSpo2,
      peakAlphaHz: stats?.peakAlphaFreq,
      peakAlphaPower: stats?.peakAlphaPower,
      pctInTarget: stats?.targetPct,
      avgSleepDir: drowsy?.meanSleepDir,
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    debugPrint('[feedback] ticker started');
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.elapsedSeconds >= state.durationMinutes * 60) {
        end();
        return;
      }
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
      _adaptTick++;
      if (_adaptTick >= adaptIntervalSeconds) {
        _adaptTick = 0;
        _engine.adapt();
        state = state.copyWith(currentThreshold: _engine.threshold);
        _ref.read(liveStatsProvider).setThreshold(_engine.threshold);
      }
      final stats = _ref.read(liveStatsProvider);
      stats.setSuccessRate(_engine.successRate);
      if (_audio.musicPlaying) {
        _recordMusicSample();
      }
      if (state.elapsedSeconds % 10 == 0) {
        debugPrint(
          '[ratio] t=${state.elapsedSeconds}s '
          'metric=${_engine.featureId} '
          'value=${stats.currentAtr?.toStringAsFixed(3)} '
          'pct=${stats.currentPercentile?.toStringAsFixed(1)} '
          'thr=${_engine.threshold?.toStringAsFixed(3)} '
          'success=${_engine.successRate?.toStringAsFixed(2)} '
          'baseline n=${_engine.baselineCount} mean=${_engine.baselineMean?.toStringAsFixed(3)} '
          'sd=${_engine.baselineStddev?.toStringAsFixed(3)}',
        );
      }
    });
  }

  /// Pauses the session on a disconnect or persistent bad signal instead of
  /// ending it. Only a disconnect keeps a grace countdown (then ends if not
  /// resolved within [interruptionGraceSeconds]); a signal loss waits
  /// indefinitely and resumes automatically once the signal returns.
  void _interruptSession(
    String message, {
    required FeedbackInterruptKind kind,
  }) {
    if (state.phase != FeedbackPhase.playing &&
        state.phase != FeedbackPhase.paused &&
        state.phase != FeedbackPhase.interrupted) {
      return;
    }
    if (state.phase != FeedbackPhase.interrupted) {
      _interruptWasPlaying = state.phase == FeedbackPhase.playing;
      _ticker?.cancel();
      _audio.pause();
      if (kind == FeedbackInterruptKind.disconnect) {
        _startInterruptTimer();
      }
    }
    _interruptKind = kind;
    final showCountdown = kind == FeedbackInterruptKind.disconnect;
    state = state.copyWith(
      interruptMessage: message,
      interruptionSecondsLeft: showCountdown ? _interruptionLeft : null,
    );
    _setPhase(FeedbackPhase.interrupted);
  }

  void _startInterruptTimer() {
    _interruptTimer?.cancel();
    _interruptionLeft = interruptionGraceSeconds;
    _interruptTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _interruptionLeft--;
      if (_interruptionLeft <= 0) {
        _interruptTimer?.cancel();
        _interruptTimer = null;
        end();
        return;
      }
      state = state.copyWith(interruptionSecondsLeft: _interruptionLeft);
    });
  }

  void _clearInterruption() {
    _interruptTimer?.cancel();
    _interruptTimer = null;
    _interruptKind = null;
    _badSignalSeconds = 0;
    state = state.copyWith(
      interruptMessage: null,
      interruptionSecondsLeft: null,
    );
  }

  /// Resumes the session after an interruption resolved. If the session was
  /// running when interrupted it resumes playing; a user-initiated pause is
  /// restored otherwise.
  void _recoverInterruption() {
    final wasPlaying = _interruptWasPlaying;
    _clearInterruption();
    if (wasPlaying) {
      _setPhase(FeedbackPhase.playing);
      _audio.resume();
      _startTicker();
    } else {
      _setPhase(FeedbackPhase.paused);
    }
  }

  /// Tracks signal quality for the calibrating phase signal gate and the
  /// playing phase bad-signal interruption.
  void _onAppState(AppUiState? prev, AppUiState next) {
    if (prev == null || identical(prev.signalQuality, next.signalQuality)) {
      return;
    }
    final quality = next.signalQuality;

    if (state.phase == FeedbackPhase.playing) {
      final critical =
          quality == null ||
          _gateElectrodes
              .where((i) => i < quality.length)
              .every((i) => quality[i] < signalCriticalThreshold);
      if (!critical) {
        _badSignalSeconds = 0;
        return;
      }
      _badSignalSeconds++;
      if (_badSignalSeconds >= badSignalPauseSeconds) {
        _interruptSession(
          'Signal lost — check headband fit',
          kind: FeedbackInterruptKind.badSignal,
        );
      }
      return;
    }

    if (state.phase == FeedbackPhase.interrupted &&
        _interruptKind == FeedbackInterruptKind.badSignal) {
      final recovered = _hasNeededElectrode(quality);
      if (recovered) {
        _recoverInterruption();
      }
    }
  }

  void _onEvent(MuseEventDto event) {
    event = _maybeOverrideFeature(event);
    if (_recorder.isRecording) {
      _recorder.writeEvent(event);
    }
    _bus.publish(event);
    switch (event) {
      case MuseEventDto_Bands(:final field0):
        _onBands(field0);
      case MuseEventDto_Feature(:final field0):
        _onFeature(field0);
      case MuseEventDto_Movement(:final field0):
        _onMovement(field0);
      case MuseEventDto_Gestures(:final field0):
        _onGestures(field0);
      case MuseEventDto_Reve(:final field0):
        _guard.onReveExtras(field0, _guardTick());
      case MuseEventDto_Connected():
        if (state.phase == FeedbackPhase.interrupted &&
            _interruptKind == FeedbackInterruptKind.disconnect) {
          _recoverInterruption();
        }
      case MuseEventDto_Disconnected():
        if (state.phase == FeedbackPhase.playing ||
            state.phase == FeedbackPhase.paused ||
            (state.phase == FeedbackPhase.interrupted &&
                _interruptKind == FeedbackInterruptKind.badSignal)) {
          if (!_ref.read(appStateProvider.notifier).allowAutoReconnect) {
            unawaited(end());
          } else {
            _interruptSession(
              'Connection lost — reconnecting…',
              kind: FeedbackInterruptKind.disconnect,
            );
          }
        }
      default:
        break;
    }
  }

  /// Samples the music feedback channel once a second while playing: appends
  /// the current cutoff to the per-second trace and records a track marker
  /// whenever playback advances to a new track.
  void _recordMusicSample() {
    final sessionStart = _sessionStartAt;
    if (sessionStart == null) {
      return;
    }
    final offset =
        DateTime.now().difference(sessionStart).inMilliseconds / 1000;
    final track = _audio.musicTrackName;
    if (track != null &&
        (_musicTracks.isEmpty || _musicTracks.last.name != track)) {
      _musicTracks.add(MusicTrackMarker(offsetSecs: offset, name: track));
    }
    _musicSeries.add(
      MusicCutoffSample(offsetSecs: offset, cutoffHz: _audio.musicCutoffHz),
    );
  }

  /// Whole-session music feedback record (track list + 1 Hz cutoff series),
  /// or null when no music feedback ran.
  SessionMusic? get sessionMusic {
    final series = _musicSeries;
    if (series.isEmpty) {
      return null;
    }
    final settings = _ref.read(settingsProvider);
    final trackCount = _audio.musicTrackCount;
    return SessionMusic(
      trackCount: trackCount,
      tracks: List.of(_musicTracks),
      minCutoffHz: settings.musicMinCutoffHz,
      maxCutoffHz: settings.musicMaxCutoffHz,
      invert: settings.musicInvertMapping,
      shuffle: settings.musicShuffle,
      series: List.of(_musicSeries),
    );
  }

  RewardTick _rewardTick() => RewardTick(
    phase: state.phase,
    collectingBaseline:
        state.phase == FeedbackPhase.calibrating &&
        state.baselineSecondsLeft > 0,
    sampleIsClean: _sampleIsClean,
    quality: _ref.read(appStateProvider).signalQuality,
  );

  GuardTick _guardTick() {
    final catalog = _ref.read(protocolCatalogProvider).valueOrNull;
    final spec = catalog?.forName(state.protocol);
    return GuardTick(
      phase: state.phase,
      collectingBaseline:
          state.phase == FeedbackPhase.calibrating &&
          state.baselineSecondsLeft > 0,
      collectionEyes: _collectionEyes,
      muffleReward: spec?.guard?.muffleReward ?? false,
      sessionStartAt: _sessionStartAt,
      writeWarningMetadata:
          ({
            required sleepDir,
            required delta,
            required threshold,
            required bandMath,
          }) {
            if (_sessionStartAt == null) {
              return;
            }
            final now = DateTime.now();
            _recorder.writeMetadata({
              'type': 'guardrail_warning',
              'sleepDir': sleepDir,
              'delta': delta,
              'threshold': threshold,
              'mode': bandMath ? 'band_math' : 'ai',
              'timestamp': now.toIso8601String(),
              'elapsedSecs':
                  now.difference(_sessionStartAt!).inMilliseconds / 1000,
            });
          },
      updateComputed:
          ({
            required sleepDir,
            required clarity,
            required delta,
            required warning,
            threshold,
          }) {
            _computedSampler?.updateGuardrail(
              sleepDir: sleepDir,
              clarity: clarity,
              delta: delta,
              warning: warning,
              threshold: threshold,
            );
          },
    );
  }

  void _onFeature(FeatureDto dto) {
    final sample = _bus.latest(dto.id);
    if (sample == null) {
      return;
    }
    _reward.onFeature(sample, _rewardTick());
    if (_guard.onFeature(sample, _guardTick())) {
      final start = _sessionStartAt;
      if (start != null) {
        _guard.recordSample(_drowsinessSeries, start);
      }
    }
  }

  void _onBands(BandsDto bands) {
    _reward.onBands(bands);
    _guard.onBands(bands, _guardTick());
    if (state.phase == FeedbackPhase.calibrating &&
        state.baselineSecondsLeft > 0) {
      _computedSampler?.updateBands(bands.electrode, bands);
      return;
    }
    if (state.phase != FeedbackPhase.playing) {
      return;
    }
    _computedSampler?.updateBands(bands.electrode, bands);
    final signalQuality = _ref.read(appStateProvider).signalQuality;
    if (signalQuality != null) {
      for (int i = 0; i < signalQuality.length && i < 4; i++) {
        _computedSampler?.updateSignalQuality(i, signalQuality[i].round());
      }
    }
  }

  void _onMovement(MovementDto movement) {
    if (movement.score > movementGateThreshold) {
      _lastMovementAt = DateTime.now();
    }
    if (state.phase != FeedbackPhase.playing) {
      return;
    }
    if (movement.score > movementGateThreshold) {
      _audio.onMovement();
    }
    _computedSampler?.updateMovement(movement);
  }

  /// Gesture events arrive at 1 Hz from the Rust forwarder. Blink/clench
  /// activity marks the ATR sample window as contaminated (like movement);
  /// double-blink / double-clench and (optionally) eye up/down become
  /// persisted markers when a feedback session is running and the relevant
  /// settings toggle is on.
  void _onGestures(GestureDto g) {
    final now = DateTime.now();
    if (g.blinkCount > 0 || g.clench) {
      _lastGestureAt = now;
    }
    if (state.phase != FeedbackPhase.playing) {
      return;
    }
    if (!_ref.read(settingsProvider).markersInFeedbackEnabled) {
      return;
    }
    final gestures = <String>[];
    if (g.blinkCount >= 2) {
      _gestureMarkers.add(
        GestureMarker(
          type: GestureType.doubleBlink,
          offsetSeconds: state.elapsedSeconds,
        ),
      );
      _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
      gestures.add('blink');
    } else if (g.blinkCount > 0) {
      if (now.difference(_lastBlinkAt) <= const Duration(seconds: 2)) {
        _gestureMarkers.add(
          GestureMarker(
            type: GestureType.doubleBlink,
            offsetSeconds: state.elapsedSeconds,
          ),
        );
        _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
        gestures.add('blink');
      } else {
        _lastBlinkAt = now;
        gestures.add('blink');
      }
    }
    if (g.clench && !_clenchWasActive) {
      if (now.difference(_lastClenchAt) <= const Duration(seconds: 2)) {
        _gestureMarkers.add(
          GestureMarker(
            type: GestureType.doubleClench,
            offsetSeconds: state.elapsedSeconds,
          ),
        );
        _lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
        gestures.add('clench');
      } else {
        _lastClenchAt = now;
        gestures.add('clench');
      }
    }
    _clenchWasActive = g.clench;
    if (_ref.read(settingsProvider).eyeMarkersEnabled) {
      if (g.eye != _prevEyeState && g.eye != 0) {
        _gestureMarkers.add(
          GestureMarker(
            type: g.eye == 1 ? GestureType.eyeUp : GestureType.eyeDown,
            offsetSeconds: state.elapsedSeconds,
          ),
        );
        gestures.add(g.eye == 1 ? 'eyeUp' : 'eyeDown');
      }
      _prevEyeState = g.eye;
    }
    if (gestures.isNotEmpty) {
      _computedSampler?.updateGestures(gestures);
    }
  }

  /// True when the current ATR sample is clean of both head movement and
  /// blink/clench muscle artifacts (within [movementBuffer] of the last
  /// activity). Used to keep the baseline and the rolling clean-sample buffer
  /// uncontaminated.
  bool get _sampleIsClean {
    final now = DateTime.now();
    return now.difference(_lastMovementAt) >= movementBuffer &&
        now.difference(_lastGestureAt) >= movementBuffer;
  }

  /// Gesture markers accumulated during the current feedback session.
  List<GestureMarker> get gestureMarkers => List.unmodifiable(_gestureMarkers);

  /// Per-second sleep-guardrail trace captured during the session, or an
  /// empty list when the guardrail was off.
  List<DrowsinessSample> get drowsinessSamples =>
      List.unmodifiable(_drowsinessSeries);

  /// Whole-session sleep-guardrail record (drift score + mean sleep
  /// direction over the trace), or null when the guardrail produced no
  /// samples. Persisted as session metadata.
  SessionDrowsiness? get sessionDrowsiness {
    final series = _drowsinessSeries;
    if (series.isEmpty) {
      return null;
    }
    final warned = series.where((s) => s.warning).length;
    final mean =
        series.fold<double>(0, (a, s) => a + s.sleepDir) / series.length;
    return SessionDrowsiness(
      scoreTotalPct: warned * 100 / series.length,
      meanSleepDir: mean,
      threshold: _guard.threshold,
    );
  }

  /// Whether the REVE/LUNA sleep guardrail is actively scoring this session.
  bool get guardrailEnabled => _guard.enabled;

  /// Whether the deep-rest (V_sleep) anchor was captured at calibration end.
  bool get guardrailSleepCaptured => _guard.sleepCaptured;

  /// Whether the sleep-drift warning is currently firing.
  bool get guardrailWarningActive => _guard.warningActive;

  /// Latest guardrail readings from the 1 Hz forwarder feed.
  double get guardrailClarity => _guard.lastClarity;

  double get guardrailSleepDir => _guard.lastSleepDir;

  double get guardrailDelta => _guard.lastDelta;

  /// Baseline sleep-direction percentile threshold, or null before calibration
  /// completes (or when the guardrail is off).
  double? get guardrailThreshold => _guard.threshold;

  bool _allGreen(List<double>? quality) {
    if (quality == null || quality.length < 4) {
      return false;
    }
    return quality.every((s) => s >= signalGoodThreshold);
  }

  bool _hasNeededElectrode(List<double>? quality) {
    if (quality == null) {
      return false;
    }
    return _gateElectrodes.any(
      (i) => i < quality.length && quality[i] >= signalGoodThreshold,
    );
  }

  @override
  void dispose() {
    _guard.teardown();
    unawaited(_clearEnabledFeatures());
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _calibration.cancelTimers();
    _gateTimer?.cancel();
    _eventSub?.cancel();
    _appSub?.close();
    _bus.dispose();
    super.dispose();
  }
}

final feedbackStateProvider =
    StateNotifierProvider<FeedbackStateNotifier, FeedbackState>((ref) {
      return FeedbackStateNotifier(ref);
    });
