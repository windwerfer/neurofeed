import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feedback_recorder.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

enum FeedbackPhase { idle, calibrating, ready, playing, paused, interrupted, ended }

enum FeedbackInterruptKind { disconnect, badSignal }

const double signalGoodThreshold = 80.0;
const double signalCriticalThreshold = 40.0;
const int autoStartSeconds = 4;
const int badSignalPauseSeconds = 10;
const int interruptionGraceSeconds = 10;
const int signalWaitResetSeconds = 10;
const List<int> neededElectrodes = [1, 2];
const Duration calibrationNarratorDuration = Duration(seconds: 7);
const Duration confirmationChimeDuration = Duration(seconds: 1);
const Duration calibrationAudioTimeout = Duration(seconds: 8);
const Duration confirmationAudioTimeout = Duration(seconds: 3);

class FeedbackState {
  final FeedbackPhase phase;
  final ProtocolType protocol;
  final int durationMinutes;
  final String soundName;
  final int elapsedSeconds;
  final bool signalGood;
  final int signalStableSeconds;
  final String? interruptMessage;
  final int? interruptionSecondsLeft;
  final bool waitingForSignal;
  final bool startAnywayAvailable;

  const FeedbackState({
    this.phase = FeedbackPhase.idle,
    this.protocol = ProtocolType.alphaTheta,
    this.durationMinutes = 15,
    this.soundName = 'Ambient Drone',
    this.elapsedSeconds = 0,
    this.signalGood = false,
    this.signalStableSeconds = 0,
    this.interruptMessage,
    this.interruptionSecondsLeft,
    this.waitingForSignal = false,
    this.startAnywayAvailable = false,
  });

  static const Object _sentinel = Object();

  FeedbackState copyWith({
    FeedbackPhase? phase,
    ProtocolType? protocol,
    int? durationMinutes,
    String? soundName,
    int? elapsedSeconds,
    bool? signalGood,
    int? signalStableSeconds,
    Object? interruptMessage = _sentinel,
    Object? interruptionSecondsLeft = _sentinel,
    bool? waitingForSignal,
    bool? startAnywayAvailable,
  }) => FeedbackState(
    phase: phase ?? this.phase,
    protocol: protocol ?? this.protocol,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    soundName: soundName ?? this.soundName,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    signalGood: signalGood ?? this.signalGood,
    signalStableSeconds: signalStableSeconds ?? this.signalStableSeconds,
    interruptMessage: identical(interruptMessage, _sentinel)
        ? this.interruptMessage
        : interruptMessage as String?,
    interruptionSecondsLeft: identical(interruptionSecondsLeft, _sentinel)
        ? this.interruptionSecondsLeft
        : interruptionSecondsLeft as int?,
    waitingForSignal: waitingForSignal ?? this.waitingForSignal,
    startAnywayAvailable: startAnywayAvailable ?? this.startAnywayAvailable,
  );
}

class FeedbackStateNotifier extends StateNotifier<FeedbackState> {
  FeedbackStateNotifier(this._ref) : super(const FeedbackState()) {
    _eventSub = _ref.read(appStateProvider.notifier).eventStream.listen(_onEvent);
    _appSub = _ref.listen<AppUiState>(appStateProvider, _onAppState);
  }

  final Ref _ref;
  StreamSubscription<MuseEventDto>? _eventSub;
  ProviderSubscription<AppUiState>? _appSub;
  Timer? _ticker;
  Timer? _interruptTimer;
  FeedbackInterruptKind? _interruptKind;
  bool _interruptWasPlaying = false;
  int _interruptionLeft = interruptionGraceSeconds;
  int _badSignalSeconds = 0;
  String? _lastQualityKey;
  int _waitingSeconds = 0;
  bool _bypassSignalGate = false;
  final TargetStateAggregator _target = TargetStateAggregator();
  final FeedbackRecorder _recorder = FeedbackRecorder();

  AudioService get _audio => _ref.read(audioServiceProvider);

  void selectProtocol(ProtocolType type) {
    state = state.copyWith(protocol: type);
  }

  void selectDuration(int minutes) {
    state = state.copyWith(durationMinutes: minutes);
  }

  void selectSound(String name) {
    state = state.copyWith(soundName: name);
  }

  /// Begin calibration: play narrator, confirm with chime, then wait for a
  /// stable signal to auto-start feedback. Opens the connect window if the
  /// Muse is not connected. Calibration only proceeds once all electrodes
  /// are green; with a defective electrode the user can start anyway after
  /// the signal has not changed for [signalWaitResetSeconds].
  Future<void> startCalibration() async {
    if (!_ref.read(appStateProvider).status.connected) {
      _ref.read(appStateProvider.notifier).openConnectWindowAndScan();
      return;
    }
    state = state.copyWith(
      phase: FeedbackPhase.calibrating,
      elapsedSeconds: 0,
      signalStableSeconds: 0,
      waitingForSignal: false,
      startAnywayAvailable: false,
    );
    await _runCalibration();
  }

  Future<void> _runCalibration() async {
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    final quality = _ref.read(appStateProvider).signalQuality;
    if (!_allGreen(quality)) {
      _lastQualityKey = _qualityKey(quality);
      _waitingSeconds = 0;
      state = state.copyWith(waitingForSignal: true, startAnywayAvailable: false);
      return;
    }
    await _audio.playCalibration().timeout(
      calibrationAudioTimeout,
      onTimeout: () {},
    );
    await Future<void>.delayed(calibrationNarratorDuration);
    await _audio.playConfirmation().timeout(
      confirmationAudioTimeout,
      onTimeout: () {},
    );
    await Future<void>.delayed(confirmationChimeDuration);
    if (state.phase != FeedbackPhase.calibrating) {
      return;
    }
    if (_bypassSignalGate) {
      _bypassSignalGate = false;
      state = state.copyWith(
        phase: FeedbackPhase.ready,
        signalStableSeconds: 0,
        waitingForSignal: false,
      );
      return;
    }
    final qualityAfter = _ref.read(appStateProvider).signalQuality;
    if (_allGreen(qualityAfter)) {
      state = state.copyWith(
        phase: FeedbackPhase.ready,
        signalStableSeconds: 0,
        waitingForSignal: false,
      );
    } else {
      _lastQualityKey = _qualityKey(qualityAfter);
      _waitingSeconds = 0;
      state = state.copyWith(waitingForSignal: true, startAnywayAvailable: false);
    }
  }

  /// Bypasses the all-green calibration gate (used when the user opts to
  /// start anyway after a long-unchanged signal with a working electrode).
  void startAnyway() {
    if (state.phase != FeedbackPhase.calibrating ||
        !state.startAnywayAvailable) {
      return;
    }
    _bypassSignalGate = true;
    _runCalibration();
  }

  /// Start the feedback loop: record the session and begin the background
  /// audio layer.
  Future<void> startPlaying() async {
    if (!_ref.read(appStateProvider).status.connected) {
      _ref.read(appStateProvider.notifier).openConnectWindowAndScan();
      return;
    }
    state = state.copyWith(phase: FeedbackPhase.playing, signalStableSeconds: 0);
    _target.reset();
    await _recorder.startSession();
    await _audio.playFeedback(sound: state.soundName);
    _startTicker();
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
    state = state.copyWith(phase: FeedbackPhase.ended);
    await _recorder.flushSession();
    await _audio.stop();
    await _audio.playEndChime();
  }

  void reset() {
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _interruptTimer = null;
    _lastQualityKey = null;
    _waitingSeconds = 0;
    _bypassSignalGate = false;
    _audio.stop();
    _recorder.discardSession();
    state = const FeedbackState();
  }

  String? get sessionFilePath => _recorder.currentFilePath;

  Future<File?> saveSession() => _recorder.saveSession();

  Future<void> discardSession() => _recorder.discardSession();

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.elapsedSeconds >= state.durationMinutes * 60) {
        end();
        return;
      }
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  /// Pauses the session on a disconnect or persistent bad signal instead of
  /// ending it, then ends it if the interruption is not resolved within
  /// [interruptionGraceSeconds]. A later, more severe interruption kind
  /// supersedes the current one without restarting the grace countdown.
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
      _startInterruptTimer();
    }
    _interruptKind = kind;
    state = state.copyWith(
      phase: FeedbackPhase.interrupted,
      interruptMessage: message,
      interruptionSecondsLeft: _interruptionLeft,
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
    state = state.copyWith(interruptMessage: null, interruptionSecondsLeft: null);
  }

  /// Resumes the session after an interruption resolved. If the session was
  /// running when interrupted it resumes playing; a user-initiated pause is
  /// restored otherwise.
  void _recoverInterruption() {
    final wasPlaying = _interruptWasPlaying;
    _clearInterruption();
    if (wasPlaying) {
      state = state.copyWith(phase: FeedbackPhase.playing, signalStableSeconds: 0);
      _audio.resume();
      _startTicker();
    } else {
      state = state.copyWith(phase: FeedbackPhase.paused, signalStableSeconds: 0);
    }
  }

  /// Tracks signal quality for the ready-phase auto-start and the playing
  /// phase bad-signal interruption. Requires all four channels to stay at or
  /// above [signalGoodThreshold] for [autoStartSeconds] consecutive 1Hz
  /// updates before auto-starting.
  void _onAppState(AppUiState? prev, AppUiState next) {
    if (prev == null || identical(prev.signalQuality, next.signalQuality)) {
      return;
    }
    final quality = next.signalQuality;

    if (state.phase == FeedbackPhase.calibrating && state.waitingForSignal) {
      final key = _qualityKey(quality);
      if (_allGreen(quality)) {
        state = state.copyWith(
          waitingForSignal: false,
          startAnywayAvailable: false,
        );
        unawaited(_runCalibration());
        return;
      }
      if (key != _lastQualityKey) {
        _lastQualityKey = key;
        _waitingSeconds = 0;
        if (state.startAnywayAvailable) {
          state = state.copyWith(startAnywayAvailable: false);
        }
        return;
      }
      _waitingSeconds++;
      if (_waitingSeconds >= signalWaitResetSeconds &&
          _hasNeededElectrode(quality) &&
          !state.startAnywayAvailable) {
        state = state.copyWith(startAnywayAvailable: true);
      }
      return;
    }

    if (state.phase == FeedbackPhase.ready) {
      final stable = quality != null &&
          quality.length >= 4 &&
          quality.every((s) => s >= signalGoodThreshold);
      if (!stable) {
        if (state.signalStableSeconds != 0) {
          state = state.copyWith(signalStableSeconds: 0);
        }
        return;
      }
      final count = state.signalStableSeconds + 1;
      state = state.copyWith(signalStableSeconds: count);
      if (count >= autoStartSeconds) {
        startPlaying();
      }
      return;
    }

    if (state.phase == FeedbackPhase.playing) {
      final critical = quality != null &&
          quality.length >= 4 &&
          quality.any((s) => s < signalCriticalThreshold);
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
      final recovered = quality != null &&
          quality.length >= 4 &&
          quality.every((s) => s >= signalGoodThreshold);
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
    if (state.phase != FeedbackPhase.playing) {
      return;
    }
    _target.update(bands);
    final target = _target.evaluate();
    if (target == null) {
      return;
    }
    _audio.onStateUpdate(isAlphaThetaTarget(
      alphaRel: target.alphaRel,
      thetaRel: target.thetaRel,
    ));
  }

  void _onMovement(MovementDto movement) {
    if (state.phase != FeedbackPhase.playing) {
      return;
    }
    if (movement.score > movementGateThreshold) {
      _audio.onMovement();
    }
  }

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
    return neededElectrodes
        .any((i) => i < quality.length && quality[i] >= signalGoodThreshold);
  }

  String _qualityKey(List<double>? quality) {
    if (quality == null) {
      return 'null';
    }
    return quality.map((q) => q.toStringAsFixed(2)).join(',');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _interruptTimer?.cancel();
    _eventSub?.cancel();
    _appSub?.close();
    super.dispose();
  }
}

final feedbackStateProvider =
    StateNotifierProvider<FeedbackStateNotifier, FeedbackState>((ref) {
  return FeedbackStateNotifier(ref);
});
