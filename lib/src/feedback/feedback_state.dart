import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/audio/calibration_clips.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feedback_engine.dart';
import 'package:muse_ml/src/feedback/feedback_recorder.dart';
import 'package:muse_ml/src/feedback/live_stats.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/reve.dart' as frb;
import 'package:muse_ml/src/settings.dart';

enum FeedbackPhase { idle, calibrating, playing, paused, interrupted, ended }

enum FeedbackInterruptKind { disconnect, badSignal }

const double signalGoodThreshold = 80.0;
const double signalCriticalThreshold = 40.0;
const int badSignalPauseSeconds = 10;
const int interruptionGraceSeconds = 10;

/// The calibration gate requires all pads green for this long before the
/// baseline starts (guards against a transient blink/loose contact).
const int greenStableSeconds = 3;

/// If one pad has not gone green for this long while the others are green, we
/// assume that pad is faulty and surface the continue-anyway fallback.
const int faultyPadSeconds = 20;

/// The program's frontal electrodes (AF7/AF8). These are the only pads whose
/// quality gates calibration (via the fallback bubble) and whose quality gates
/// the playing-phase bad-signal pause; rear pads never block feedback. When
/// future feedback options are added they should reuse this same "enough pads
/// for this program" model rather than requiring all four pads.
const List<int> neededElectrodes = [1, 2];
const int calibrationBaselineSeconds = 90;
const int adaptIntervalSeconds = 30;
const Duration movementBuffer = Duration(seconds: 1);
const Duration calibrationAudioTimeout = Duration(seconds: 15);
const int defaultBaselinePercentile = 40;
const int minRecalibrateSeconds = 60;
const int minRecalibrateSamples = 30;

/// Classical frontal-delta hard rail for the sleep guardrail (normalized FFT
/// band power of the AF7/AF8 average). Overridden by the baseline percentile
/// once real-device data is available — needs tuning.
const double guardrailDeltaCeiling = 0.25;

/// Minimum gap between guardrail warning chimes while drifting into sleep.
const Duration warningChimeCooldown = Duration(seconds: 20);

class FeedbackState {
  final FeedbackPhase phase;
  final ProtocolType protocol;
  final int durationMinutes;
  final String soundName;
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

  const FeedbackState({
    this.phase = FeedbackPhase.idle,
    this.protocol = ProtocolType.alphaTheta,
    this.durationMinutes = 15,
    this.soundName = 'Ambient Drone',
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
  });

  static const Object _sentinel = Object();

  FeedbackState copyWith({
    FeedbackPhase? phase,
    ProtocolType? protocol,
    int? durationMinutes,
    String? soundName,
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
  }) => FeedbackState(
    phase: phase ?? this.phase,
    protocol: protocol ?? this.protocol,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    soundName: soundName ?? this.soundName,
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
  );
}

class FeedbackStateNotifier extends StateNotifier<FeedbackState> {
  FeedbackStateNotifier(this._ref) : super(const FeedbackState()) {
    _eventSub = _ref
        .read(appStateProvider.notifier)
        .eventStream
        .listen(_onEvent);
    _appSub = _ref.listen<AppUiState>(appStateProvider, _onAppState);
    final settings = _ref.read(settingsProvider);
    _atr.setDynamicAdapt(settings.dynamicAdapt ?? true);
    _atr.setResponsiveness(settings.responsiveness ?? 0.5);
    _recorder.setRecordStreams(settings.recordStreams);
    state = state.copyWith(
      soundName: settings.soundName ?? state.soundName,
      durationMinutes: settings.durationMinutes ?? state.durationMinutes,
    );
  }

  final Ref _ref;
  StreamSubscription<MuseEventDto>? _eventSub;
  ProviderSubscription<AppUiState>? _appSub;
  Timer? _ticker;
  Timer? _interruptTimer;
  Timer? _baselineTimer;
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
  bool _guardrailEnabled = false;
  bool _clearCaptured = false;
  bool _sleepCaptured = false;
  final List<double> _baselineSleepDir = [];
  double? _guardrailThreshold;
  double _lastClarity = 1;
  double _lastSleepDir = 0;
  double _lastDelta = 0;
  bool _warningActive = false;
  DateTime _lastWarningChimeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _adaptTick = 0;
  final TargetStateAggregator _target = TargetStateAggregator();
  final FeedbackEngine _atr = AtrEngine();
  final FeedbackRecorder _recorder = FeedbackRecorder();

  /// Wall-clock anchors for the calibration timeline. [_sessionStartAt] is set
  /// when the recorder starts (calibration start); [_trainingStartAt] when
  /// training/feedback begins. Their difference is the training-boundary
  /// offset used to trim the displayed window.
  DateTime? _sessionStartAt;
  DateTime? _trainingStartAt;
  CalibrationClip? _introClip;
  DateTime? _introStartedAt;
  bool _usedStartAnyway = false;
  SessionCalibration? _calibration;

  AudioService get _audio => _ref.read(audioServiceProvider);

  void selectProtocol(ProtocolType type) {
    state = state.copyWith(protocol: type);
  }

  void selectDuration(int minutes) {
    state = state.copyWith(durationMinutes: minutes);
    _ref.read(settingsProvider).setDurationMinutes(minutes);
  }

  void selectSound(String name) {
    state = state.copyWith(soundName: name);
    _ref.read(settingsProvider).setSoundName(name);
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      unawaited(_switchSoundWhileKeepingPhase(name));
    }
  }

  Future<void> _switchSoundWhileKeepingPhase(String name) async {
    await _audio.switchSound(name);
    if (state.phase == FeedbackPhase.paused) {
      await _audio.pause();
    }
  }

  void selectPercentile(int percentile) {
    _atr.setBaselinePercentile(percentile);
    state = state.copyWith(baselinePercentile: percentile);
    final stats = _ref.read(liveStatsProvider);
    stats.setBaseline(
      percentile: percentile,
      count: _atr.baselineCount,
      mean: _atr.baselineMean,
      stddev: _atr.baselineStddev,
    );
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      _atr.computeThreshold();
      state = state.copyWith(currentThreshold: _atr.threshold);
      stats.setThreshold(_atr.threshold);
    }
  }

  void toggleNerdStats() {
    state = state.copyWith(showNerdStats: !state.showNerdStats);
  }

  bool get dynamicAdapt => _atr.dynamicAdapt;

  double get responsiveness => _atr.responsiveness;

  void setDynamicAdapt(bool enabled) {
    _atr.setDynamicAdapt(enabled);
    _ref.read(settingsProvider).setDynamicAdapt(enabled);
  }

  void setResponsiveness(double value) {
    _atr.setResponsiveness(value);
    _ref.read(settingsProvider).setResponsiveness(value);
  }

  void resetTargetSettings() {
    setDynamicAdapt(true);
    setResponsiveness(0.5);
  }

  /// REVE sleep-guardrail warning threshold (percentile of the eyes-closed
  /// sleep-direction distribution). Only consumed by the drowsiness protocol.
  int get warningThresholdPercentile =>
      _ref.read(settingsProvider).warningThresholdPercentile;

  void setWarningThresholdPercentile(int percentile) {
    _ref.read(settingsProvider).setWarningThresholdPercentile(percentile);
  }

  /// Begin calibration: play the voice intro, require all electrodes green
  /// for [greenStableSeconds] before starting a [calibrationBaselineSeconds]
  /// silent baseline, then start feedback automatically. Opens the connect
  /// window if the Muse is not connected. There is no gate after the
  /// baseline. If one pad never turns green for [faultyPadSeconds] while the
  /// needed frontal pads do, it is assumed faulty and a continue-anyway
  /// fallback is shown.
  Future<void> startCalibration() async {
    if (!_ref.read(appStateProvider).status.connected) {
      _ref.read(appStateProvider.notifier).openConnectWindowAndScan();
      return;
    }
    if (state.phase == FeedbackPhase.playing ||
        state.phase == FeedbackPhase.paused) {
      _ticker?.cancel();
      _audio.stop();
    }
    state = state.copyWith(
      phase: FeedbackPhase.calibrating,
      elapsedSeconds: 0,
      waitingForSignal: false,
      startAnywayAvailable: false,
      baselineSecondsLeft: 0,
      currentThreshold: null,
    );
    _gestureMarkers.clear();
    _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
    _prevEyeState = 0;
    _clenchWasActive = false;
    _sessionStartAt = DateTime.now();
    _trainingStartAt = null;
    _introClip = null;
    _introStartedAt = null;
    _usedStartAnyway = false;
    _calibration = null;
    await _recorder.startSession();
    unawaited(_maybeEnableGuardrail());
    await _runCalibration();
  }

  /// Arm the REVE/LUNA sleep-guardrail scorer for the Pure Jhana protocol
  /// using the settings-selected foundation model. Scoring starts immediately
  /// in the forwarder (first embedding lands after ~5 s) so the calibration
  /// baseline can capture the clear anchor. No-op otherwise.
  Future<void> _maybeEnableGuardrail() async {
    _guardrailEnabled = false;
    _clearCaptured = false;
    _sleepCaptured = false;
    _guardrailThreshold = null;
    _baselineSleepDir.clear();
    _warningActive = false;
    if (state.protocol != ProtocolType.drowsiness) {
      return;
    }
    final engine = _ref.read(modelEngineNotifierProvider);
    if (engine is! ModelEngineReady) {
      debugPrint('[guardrail] model not ready — guardrail stays off');
      return;
    }
    try {
      _guardrailEnabled = await frb.guardrailEnable(kind: engine.kind.ffId);
      if (_guardrailEnabled) {
        debugPrint('[guardrail] enabled (${engine.kind.ffId})');
      }
    } catch (e) {
      _guardrailEnabled = false;
      debugPrint('[guardrail] enable failed: $e');
    }
  }

  /// In-flight re-anchoring: rebuilds the baseline from the recent clean
  /// session ATR samples instead of running another silent calibration. Only
  /// valid during playing/paused; returns false when the session is too young
  /// or there are too few clean samples.
  bool recalibrate() {
    if (state.phase != FeedbackPhase.playing &&
        state.phase != FeedbackPhase.paused) {
      return false;
    }
    final ok = _atr.recalibrateFromRecent(minSamples: minRecalibrateSamples);
    if (!ok) {
      debugPrint(
        '[feedback] in-flight recalibrate skipped at t=${state.elapsedSeconds}s: '
        'fewer than $minRecalibrateSamples clean samples',
      );
      return false;
    }
    _adaptTick = 0;
    final stats = _ref.read(liveStatsProvider);
    stats
      ..setBaseline(
        percentile: _atr.baselinePercentile,
        count: _atr.baselineCount,
        mean: _atr.baselineMean,
        stddev: _atr.baselineStddev,
      )
      ..setThreshold(_atr.threshold);
    unawaited(_audio.playRecalibrateChime());
    debugPrint(
      '[feedback] in-flight recalibrate at t=${state.elapsedSeconds}s: '
      'threshold -> ${_atr.threshold} (p${_atr.baselinePercentile}, '
      'n=${_atr.baselineCount} clean samples, mean=${_atr.baselineMean}, '
      'sd=${_atr.baselineStddev})',
    );
    state = state.copyWith(currentThreshold: _atr.threshold);
    return true;
  }

  /// Start calibration: wait for all pads to be green for [greenStableSeconds]
  /// before playing the voice intro and starting the silent baseline, then
  /// begin feedback automatically. No post-baseline gate: once the baseline is
  /// captured feedback always starts. If one pad never reaches green while the
  /// needed frontal pads do, it is assumed faulty and the start-anyway
  /// fallback is surfaced after [faultyPadSeconds].
  Future<void> _runCalibration() async {
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    _atr.reset();
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
          unawaited(_playCalibrationAndBaseline());
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

  /// Plays the calibration voice intro (from the calibration manifest for the
  /// selected protocol), then starts the silent baseline. Used once the
  /// pre-calibration gate passes (or the user bypasses it).
  Future<void> _playCalibrationAndBaseline() async {
    state = state.copyWith(waitingForSignal: false);
    CalibrationClip? clip;
    try {
      final manifest = await _ref.read(calibrationManifestProvider.future);
      clip = manifest.introFor(state.protocol.name);
    } catch (e) {
      debugPrint('[feedback] calibration manifest unavailable: $e');
    }
    _introClip = clip;
    _introStartedAt = DateTime.now();
    await _audio
        .playCalibration(clip?.file)
        .timeout(calibrationAudioTimeout, onTimeout: () {});
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    _startBaseline();
  }

  void _startBaseline() {
    _gateTimer?.cancel();
    _baselineTimer?.cancel();
    state = state.copyWith(
      baselineSecondsLeft: calibrationBaselineSeconds,
      waitingForSignal: false,
      startAnywayAvailable: false,
    );
    _baselineTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.baselineSecondsLeft - 1;
      if (left <= 0) {
        _finishCalibration();
      } else {
        state = state.copyWith(baselineSecondsLeft: left);
      }
    });
  }

  void _finishCalibration() {
    _baselineTimer?.cancel();
    _baselineTimer = null;
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    final threshold = _atr.computeThreshold();
    debugPrint(
      '[feedback] baseline ATR threshold = $threshold '
      '(${_atr.baselineCount} samples, p${_atr.baselinePercentile})',
    );
    _ref
        .read(liveStatsProvider)
        .setBaseline(
          percentile: _atr.baselinePercentile,
          count: _atr.baselineCount,
          mean: _atr.baselineMean,
          stddev: _atr.baselineStddev,
        );
    _ref.read(liveStatsProvider).setThreshold(threshold);
    if (_guardrailEnabled && _clearCaptured) {
      _finalizeGuardrailBaseline();
    }
    _recordCalibration();
    state = state.copyWith(baselineSecondsLeft: 0, currentThreshold: threshold);
    unawaited(startPlaying());
  }

  /// Records how this calibration ran so a saved session is reproducible:
  /// timeline (calibration start/end, training start), the gate rejection
  /// criteria, the ATR baseline statistics, and the intro clip that played.
  void _recordCalibration() {
    final now = DateTime.now();
    _trainingStartAt = now;
    final sessionStart = _sessionStartAt;
    final intro = _introClip;
    final introAt = _introStartedAt;
    final phases = <SessionCalibrationPhase>[];
    if (intro != null && introAt != null && sessionStart != null) {
      phases.add(
        SessionCalibrationPhase(
          clipId: intro.id,
          clipFile: intro.file,
          spokenText: intro.text,
          eyes: intro.eyes,
          startSecs: introAt.difference(sessionStart).inMilliseconds / 1000,
          endSecs: now.difference(sessionStart).inMilliseconds / 1000,
        ),
      );
    }
    _calibration = SessionCalibration(
      version: CalibrationManifest.currentVersion,
      calibrationStartSecs: sessionStart == null
          ? null
          : sessionStart.millisecondsSinceEpoch / 1000,
      calibrationEndSecs: now.millisecondsSinceEpoch / 1000,
      trainingStartSecs: now.millisecondsSinceEpoch / 1000,
      usedStartAnyway: _usedStartAnyway,
      greenStableSeconds: greenStableSeconds,
      faultyPadSeconds: faultyPadSeconds,
      baseline: SessionBaselineStats(
        percentile: _atr.baselinePercentile,
        count: _atr.baselineCount,
        mean: _atr.baselineMean,
        stddev: _atr.baselineStddev,
      ),
      phases: phases,
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
    unawaited(_playCalibrationAndBaseline());
  }

  /// Locks in the sleep-guardrail threshold from the baseline sleep-direction
  /// distribution at the configured percentile, then captures the deep-rest
  /// anchor (deepest sample the Rust scorer tracked since the clear anchor).
  void _finalizeGuardrailBaseline() {
    final list = List<double>.of(_baselineSleepDir)..sort();
    if (list.isNotEmpty) {
      final pct = warningThresholdPercentile;
      final idx = ((pct / 100) * (list.length - 1)).round();
      _guardrailThreshold = list[idx];
      debugPrint(
        '[guardrail] baseline n=${_baselineSleepDir.length} '
        'p$pct threshold=${_guardrailThreshold?.toStringAsFixed(3)}',
      );
    }
    unawaited(
      frb
          .guardrailCaptureAnchor(name: 'sleep')
          .then((msg) {
            _sleepCaptured = true;
            debugPrint('[guardrail] $msg');
          })
          .catchError((Object e) {
            _sleepCaptured = false;
            debugPrint('[guardrail] V_sleep capture failed: $e');
          }),
    );
  }

  /// Captures the clear anchor from the first clean baseline sample once the
  /// forwarder has produced a live embedding. Best-effort: failures (no live
  /// embedding yet, model switch) are ignored and retried on the next clean
  /// sample.
  Future<void> _tryCaptureClearAnchor() async {
    if (!_guardrailEnabled || _clearCaptured) {
      return;
    }
    try {
      await frb.guardrailCaptureAnchor(name: 'clear');
      _clearCaptured = true;
      debugPrint('[guardrail] V_clear captured');
    } catch (_) {}
  }

  /// Tears down the guardrail scorer and its calibration state at session end.
  void _teardownGuardrail() {
    if (_guardrailEnabled) {
      unawaited(frb.guardrailDisable());
    }
    _guardrailEnabled = false;
    _clearCaptured = false;
    _sleepCaptured = false;
    _guardrailThreshold = null;
    _baselineSleepDir.clear();
    _warningActive = false;
  }

  /// Start the feedback loop: record the session and begin the background
  /// audio layer.
  Future<void> startPlaying() async {
    if (!_ref.read(appStateProvider).status.connected) {
      _ref.read(appStateProvider.notifier).openConnectWindowAndScan();
      return;
    }
    state = state.copyWith(
      phase: FeedbackPhase.playing,
      currentThreshold: _atr.threshold,
    );
    _target.reset();
    _adaptTick = 0;
    _trainingStartAt ??= DateTime.now();
    _startTicker();
    await _audio.playFeedback(sound: state.soundName);
  }

  Future<void> pause() async {
    state = state.copyWith(phase: FeedbackPhase.paused);
    _ticker?.cancel();
    await _audio.pause();
  }

  Future<void> resume() async {
    state = state.copyWith(phase: FeedbackPhase.playing);
    await _audio.resume();
    _startTicker();
  }

  /// End the session: flush the recording, stop audio, play the end chime.
  /// The temp recording stays on disk until the dashboard saves or discards it.
  Future<void> end() async {
    if (state.phase == FeedbackPhase.ended) {
      return;
    }
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _interruptTimer = null;
    _baselineTimer?.cancel();
    _baselineTimer = null;
    _teardownGuardrail();
    state = state.copyWith(phase: FeedbackPhase.ended);
    await _recorder.flushSession();
    await _audio.stop();
    await _audio.playEndChime();
  }

  void reset() {
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _interruptTimer = null;
    _baselineTimer?.cancel();
    _baselineTimer = null;
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
    _teardownGuardrail();
    _audio.stop();
    _recorder.discardSession();
    _atr.reset();
    _target.reset();
    _sessionStartAt = null;
    _trainingStartAt = null;
    _introClip = null;
    _introStartedAt = null;
    _usedStartAnyway = false;
    _calibration = null;
    _ref.read(liveStatsProvider).reset();
    state = const FeedbackState();
  }

  String? get sessionFilePath => _recorder.currentFilePath;

  /// Recorded calibration record for the current session (timeline, gate,
  /// baseline stats, intro clip). Null until calibration completes.
  SessionCalibration? get calibration => _calibration;

  /// Seconds from recording start to the training boundary, or null when no
  /// calibration was recorded (e.g. legacy/unknown-session previews).
  double? get trainingStartOffsetSecs => _calibration?.trainingStartOffsetSecs;

  /// Electrode indices that produced data in the current recording.
  Set<int> get recordedChannels => _recorder.recordedChannels;

  /// Streams enabled for this session's recording.
  Set<RecordingStream> get recordStreams => _recorder.streams;

  Future<File?> saveSession() => _recorder.saveSession();

  Future<void> discardSession() => _recorder.discardSession();

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
        _atr.adapt();
        state = state.copyWith(currentThreshold: _atr.threshold);
        _ref.read(liveStatsProvider).setThreshold(_atr.threshold);
      }
      final stats = _ref.read(liveStatsProvider);
      stats.setSuccessRate(_atr.successRate);
      if (state.elapsedSeconds % 10 == 0) {
        debugPrint(
          '[atr] t=${state.elapsedSeconds}s atr=${stats.currentAtr?.toStringAsFixed(3)} '
          'pct=${stats.currentPercentile?.toStringAsFixed(1)} '
          'thr=${_atr.threshold?.toStringAsFixed(3)} '
          'success=${_atr.successRate?.toStringAsFixed(2)} '
          'baseline n=${_atr.baselineCount} mean=${_atr.baselineMean?.toStringAsFixed(3)} '
          'sd=${_atr.baselineStddev?.toStringAsFixed(3)}',
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
      phase: FeedbackPhase.interrupted,
      interruptMessage: message,
      interruptionSecondsLeft: showCountdown ? _interruptionLeft : null,
    );
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
      state = state.copyWith(phase: FeedbackPhase.playing);
      _audio.resume();
      _startTicker();
    } else {
      state = state.copyWith(phase: FeedbackPhase.paused);
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
          neededElectrodes
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
    if (_recorder.isRecording) {
      _recorder.writeEvent(event);
    }
    switch (event) {
      case MuseEventDto_Bands(:final field0):
        _onBands(field0);
      case MuseEventDto_Movement(:final field0):
        _onMovement(field0);
      case MuseEventDto_Gestures(:final field0):
        _onGestures(field0);
      case MuseEventDto_Reve(:final field0):
        _onReve(field0);
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
          _interruptSession(
            'Connection lost — reconnecting…',
            kind: FeedbackInterruptKind.disconnect,
          );
        }
      default:
        break;
    }
  }

  void _onBands(BandsDto bands) {
    _target.update(bands);
    final target = _target.evaluate(_ref.read(appStateProvider).signalQuality);
    if (target == null) {
      return;
    }
    if (state.phase == FeedbackPhase.calibrating &&
        state.baselineSecondsLeft > 0) {
      if (_sampleIsClean) {
        final atr = target.atr;
        if (atr.isFinite) {
          _atr.addBaselineSample(atr);
        }
      }
      unawaited(_tryCaptureClearAnchor());
      return;
    }
    if (state.phase != FeedbackPhase.playing) {
      return;
    }
    final atr = target.atr;
    if (!atr.isFinite) {
      return;
    }
    _atr.recordEpoch(atr);
    _atr.recordSessionSample(atr, clean: _sampleIsClean);
    _ref.read(liveStatsProvider).push(atr, _atr.percentileOf);
    _audio.onStateUpdate(_atr.isInTarget(atr));
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
    // Double blink: >=2 blinks in one report, or two blink reports <=2 s apart.
    if (g.blinkCount >= 2) {
      _gestureMarkers.add(
        GestureMarker(
          type: GestureType.doubleBlink,
          offsetSeconds: state.elapsedSeconds,
        ),
      );
      _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
    } else if (g.blinkCount > 0) {
      if (now.difference(_lastBlinkAt) <= const Duration(seconds: 2)) {
        _gestureMarkers.add(
          GestureMarker(
            type: GestureType.doubleBlink,
            offsetSeconds: state.elapsedSeconds,
          ),
        );
        _lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        _lastBlinkAt = now;
      }
    }
    // Double clench: two clench onsets <=2 s apart.
    if (g.clench && !_clenchWasActive) {
      if (now.difference(_lastClenchAt) <= const Duration(seconds: 2)) {
        _gestureMarkers.add(
          GestureMarker(
            type: GestureType.doubleClench,
            offsetSeconds: state.elapsedSeconds,
          ),
        );
        _lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        _lastClenchAt = now;
      }
    }
    _clenchWasActive = g.clench;
    // Eye up/down transitions (experimental, off by default).
    if (_ref.read(settingsProvider).eyeMarkersEnabled) {
      if (g.eye != _prevEyeState && g.eye != 0) {
        _gestureMarkers.add(
          GestureMarker(
            type: g.eye == 1 ? GestureType.eyeUp : GestureType.eyeDown,
            offsetSeconds: state.elapsedSeconds,
          ),
        );
      }
      _prevEyeState = g.eye;
    }
  }

  /// Per-second sleep-guardrail readings from the forwarder. Collects the
  /// sleep-direction distribution during the calibration baseline (only after
  /// the clear anchor exists, since readings flow only once V_clear is set),
  /// then evaluates the drift warning while playing.
  void _onReve(ReveDto r) {
    _lastClarity = r.clarity;
    _lastSleepDir = r.sleepDir;
    _lastDelta = r.delta;
    if (!_guardrailEnabled || !_clearCaptured) {
      return;
    }
    if (state.phase == FeedbackPhase.calibrating &&
        state.baselineSecondsLeft > 0) {
      _baselineSleepDir.add(r.sleepDir);
      return;
    }
    if (state.phase == FeedbackPhase.playing && _guardrailThreshold != null) {
      _evaluateGuardrailWarning();
    }
  }

  /// Fires the sleep-guardrail warning: sleep-direction above the baseline
  /// threshold or classical frontal delta over the hard rail. Plays the soft
  /// warning chime, re-armed every [warningChimeCooldown] while the drift
  /// persists; the reward loop is never touched.
  void _evaluateGuardrailWarning() {
    final threshold = _guardrailThreshold!;
    final over =
        _lastSleepDir > threshold || _lastDelta > guardrailDeltaCeiling;
    if (!over) {
      _warningActive = false;
      return;
    }
    _warningActive = true;
    final now = DateTime.now();
    if (now.difference(_lastWarningChimeAt) >= warningChimeCooldown) {
      _lastWarningChimeAt = now;
      unawaited(_audio.playWarningChime());
      debugPrint(
        '[guardrail] WARNING sleep_dir=${_lastSleepDir.toStringAsFixed(3)} '
        'delta=${_lastDelta.toStringAsFixed(3)} '
        'thr=${threshold.toStringAsFixed(3)} '
        'delta ceiling=$guardrailDeltaCeiling',
      );
    }
  }

  bool _clenchWasActive = false;

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

  /// Whether the REVE/LUNA sleep guardrail is actively scoring this session.
  bool get guardrailEnabled => _guardrailEnabled;

  /// Whether the deep-rest (V_sleep) anchor was captured at calibration end.
  bool get guardrailSleepCaptured => _sleepCaptured;

  /// Whether the sleep-drift warning is currently firing.
  bool get guardrailWarningActive => _warningActive;

  /// Latest guardrail readings from the 1 Hz forwarder feed.
  double get guardrailClarity => _lastClarity;

  double get guardrailSleepDir => _lastSleepDir;

  double get guardrailDelta => _lastDelta;

  /// Baseline sleep-direction percentile threshold, or null before calibration
  /// completes (or when the guardrail is off).
  double? get guardrailThreshold => _guardrailThreshold;

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
    return neededElectrodes.any(
      (i) => i < quality.length && quality[i] >= signalGoodThreshold,
    );
  }

  @override
  void dispose() {
    _teardownGuardrail();
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _baselineTimer?.cancel();
    _gateTimer?.cancel();
    _eventSub?.cancel();
    _appSub?.close();
    super.dispose();
  }
}

final feedbackStateProvider =
    StateNotifierProvider<FeedbackStateNotifier, FeedbackState>((ref) {
      return FeedbackStateNotifier(ref);
    });
