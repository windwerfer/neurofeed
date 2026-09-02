import 'dart:async';

import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';

/// Same gap as [warningChimeCooldown] in the guard lane (metadata uses that
/// copy). One-shots re-fire while [active] stays true.
const Duration _oneShotCooldown = Duration(seconds: 20);

/// Guard-lane audio. [intensity] is reserved (alarm ramps internally).
/// v1 one-shots ignore it; [alarm] uses [active] to start/stop the ramp.
abstract class GuardOutput {
  Future<void> start();
  Future<void> stop();
  void onGuard({required bool active, required double intensity});
}

/// Wraps the existing [FeedbackAudioController] warning path. Reads the
/// live [GuardrailSound] so a gear-dialog change does not need a swap.
class AudioGuardOutput implements GuardOutput {
  AudioGuardOutput(this._controller);

  final FeedbackAudioController _controller;
  DateTime _lastOneShotAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    _controller.stopWarningAlarm();
  }

  @override
  void onGuard({required bool active, required double intensity}) {
    final sound = _controller.warningSound;
    if (sound == GuardrailSound.none) {
      if (!active) {
        _controller.stopWarningAlarm();
      }
      return;
    }
    if (sound.playsContinuously) {
      if (active) {
        unawaited(_controller.startWarningAlarm());
      } else {
        _controller.stopWarningAlarm();
      }
      return;
    }
    if (!active) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastOneShotAt) < _oneShotCooldown) {
      return;
    }
    _lastOneShotAt = now;
    unawaited(_controller.playWarningChime());
  }
}

GuardOutput guardOutputFor({
  required FeedbackAudioController controller,
}) => AudioGuardOutput(controller);

class NoneGuardOutput implements GuardOutput {
  const NoneGuardOutput();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onGuard({required bool active, required double intensity}) {}
}
