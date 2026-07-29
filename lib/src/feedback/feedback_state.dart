import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

enum FeedbackPhase { idle, calibrating, ready, playing, paused, ended }

class FeedbackState {
  final FeedbackPhase phase;
  final ProtocolType protocol;
  final int durationMinutes;
  final String soundName;
  final int elapsedSeconds;
  final bool signalGood;

  const FeedbackState({
    this.phase = FeedbackPhase.idle,
    this.protocol = ProtocolType.alphaTheta,
    this.durationMinutes = 15,
    this.soundName = 'Harmonic Consonance',
    this.elapsedSeconds = 0,
    this.signalGood = false,
  });

  FeedbackState copyWith({
    FeedbackPhase? phase,
    ProtocolType? protocol,
    int? durationMinutes,
    String? soundName,
    int? elapsedSeconds,
    bool? signalGood,
  }) => FeedbackState(
    phase: phase ?? this.phase,
    protocol: protocol ?? this.protocol,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    soundName: soundName ?? this.soundName,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    signalGood: signalGood ?? this.signalGood,
  );
}

class FeedbackStateNotifier extends StateNotifier<FeedbackState> {
  FeedbackStateNotifier(this._ref) : super(const FeedbackState()) {
    _eventSub = _ref.read(appStateProvider.notifier).eventStream.listen(_onEvent);
  }

  final Ref _ref;
  StreamSubscription<MuseEventDto>? _eventSub;
  Timer? _ticker;

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

  /// Begin calibration: play 60s tone, then mark ready.
  Future<void> startCalibration() async {
    state = state.copyWith(phase: FeedbackPhase.calibrating, elapsedSeconds: 0);
    await _audio.playCalibration();
    if (state.phase == FeedbackPhase.calibrating) {
      state = state.copyWith(phase: FeedbackPhase.ready);
    }
  }

  /// Start the feedback loop.
  Future<void> startPlaying() async {
    state = state.copyWith(phase: FeedbackPhase.playing);
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

  Future<void> end() async {
    _ticker?.cancel();
    state = state.copyWith(phase: FeedbackPhase.ended);
    await _audio.stop();
    await _audio.playEndChime();
  }

  void reset() {
    _ticker?.cancel();
    _audio.stop();
    state = const FeedbackState();
  }

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

  void _onEvent(MuseEventDto event) {
    // Future: track signal quality for auto-start
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }
}

final feedbackStateProvider =
    StateNotifierProvider<FeedbackStateNotifier, FeedbackState>((ref) {
  return FeedbackStateNotifier(ref);
});
