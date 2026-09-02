import 'package:muse_ml/src/audio/binaural_beat_controller.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/audio/music_controller.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/audio/rain_feedback_controller.dart';
import 'package:muse_ml/src/settings.dart';

/// Reward-lane audio. [onSample] gets percentile rank (0–100) and the
/// boolean in-target verdict. [setMuffle] is a no-op for chime.
abstract class RewardOutput {
  Future<void> start();
  Future<void> stop();
  void onSample({required double percentile, required bool inTarget});
  void setMuffle(bool on);
}

RewardOutput rewardOutputFor(
  RewardOutputId id, {
  required FeedbackAudioController chime,
  required MusicController music,
  required RainFeedbackController rain,
  required BinauralBeatController binaural,
  required Settings settings,
  void Function(bool on)? onMuffleExtras,
}) {
  switch (id) {
    case RewardOutputId.chime:
      return ChimeRewardOutput(chime);
    case RewardOutputId.musicFilter:
      return MusicFilterRewardOutput(
        music,
        settings,
        onMuffleExtras: onMuffleExtras,
      );
    case RewardOutputId.rainStage:
      return RainStageRewardOutput(rain, onMuffleExtras: onMuffleExtras);
    case RewardOutputId.binauralSwell:
      return BinauralSwellRewardOutput(
        binaural,
        settings,
        onMuffleExtras: onMuffleExtras,
      );
    case RewardOutputId.none:
      return const NoneRewardOutput();
  }
}

class ChimeRewardOutput implements RewardOutput {
  ChimeRewardOutput(this._chime);

  final FeedbackAudioController _chime;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onSample({required double percentile, required bool inTarget}) {
    _chime.onStateUpdate(inTarget);
  }

  @override
  void setMuffle(bool on) {}
}

class MusicFilterRewardOutput implements RewardOutput {
  MusicFilterRewardOutput(
    this._music,
    this._settings, {
    this.onMuffleExtras,
  });

  final MusicController _music;
  final Settings _settings;
  final void Function(bool on)? onMuffleExtras;

  @override
  Future<void> start() async {
    await _music.load();
    await _music.start();
  }

  @override
  Future<void> stop() => _music.stop();

  @override
  void onSample({required double percentile, required bool inTarget}) {
    final pct = percentile;
    final norm = _settings.musicInvertMapping ? 100 - pct : pct;
    final min = _settings.musicMinCutoffHz;
    final max = _settings.musicMaxCutoffHz;
    final cutoff = min + (norm / 100) * (max - min);
    _music.setTargetCutoff(cutoff);
  }

  @override
  void setMuffle(bool on) {
    _music.setMuffle(on);
    onMuffleExtras?.call(on);
  }
}

class RainStageRewardOutput implements RewardOutput {
  RainStageRewardOutput(this._rain, {this.onMuffleExtras});

  final RainFeedbackController _rain;
  final void Function(bool on)? onMuffleExtras;

  @override
  Future<void> start() => _rain.start();

  @override
  Future<void> stop() => _rain.stop();

  @override
  void onSample({required double percentile, required bool inTarget}) {
    _rain.setTargetPercentile(percentile);
  }

  @override
  void setMuffle(bool on) {
    _rain.setMuffle(on);
    onMuffleExtras?.call(on);
  }
}

class BinauralSwellRewardOutput implements RewardOutput {
  BinauralSwellRewardOutput(
    this._binaural,
    this._settings, {
    this.onMuffleExtras,
  });

  final BinauralBeatController _binaural;
  final Settings _settings;
  final void Function(bool on)? onMuffleExtras;

  @override
  Future<void> start() => _binaural.start(
    carrierHz: _settings.binauralCarrierHz,
    beatHz: _settings.binauralBeatHz,
  );

  @override
  Future<void> stop() => _binaural.stop();

  @override
  void onSample({required double percentile, required bool inTarget}) {
    _binaural.setPercentile(percentile);
  }

  @override
  void setMuffle(bool on) {
    _binaural.setMuffle(on);
    onMuffleExtras?.call(on);
  }
}

class NoneRewardOutput implements RewardOutput {
  const NoneRewardOutput();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onSample({required double percentile, required bool inTarget}) {}

  @override
  void setMuffle(bool on) {}
}
