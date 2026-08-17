import 'package:flutter/foundation.dart';

/// Guardrail warning sounds. Placeholder asset names — the actual audio files
/// land later; missing assets fail a load gracefully and the warning just
/// stays silent that session.
enum GuardrailSound {
  softBowl(
    label: 'Soft bowl',
    // Current warning bell (864397__valerie-vivegnis__2607) until the user
    // drops in a dedicated guardrail-softBowl-01 file.
    assetPath: 'assets/audio/bell/864397__valerie-vivegnis__2607.opus',
    playsContinuously: false,
  ),
  chime(
    label: 'Bell chime',
    assetPath: 'assets/audio/guardrail-chime-01.opus',
    playsContinuously: false,
  ),
  cough(
    label: 'Cough',
    assetPath: 'assets/audio/guardrail-cough-01.opus',
    playsContinuously: false,
  ),
  alarm(
    label: 'Alarm clock',
    assetPath: 'assets/audio/guardrail-alarm-01.opus',
    playsContinuously: true,
  ),
  none(label: 'None', assetPath: null, playsContinuously: false);

  const GuardrailSound({
    required this.label,
    required this.assetPath,
    required this.playsContinuously,
  });

  final String label;

  /// Bundle asset for this sound, or null for none.
  final String? assetPath;

  /// True when the sound is a continuous alarm: while a warning is active it
  /// repeats itself with a volume ramp over the first minute (instead of the
  /// cooldown-gated one-shot chime).
  final bool playsContinuously;

  /// Parses a stored preference name, defaulting to [GuardrailSound.softBowl].
  static GuardrailSound fromName(String? name) {
    for (final sound in values) {
      if (sound.name == name) {
        return sound;
      }
    }
    if (kDebugMode) {
      debugPrint('[guardrail-sound] unknown sound name $name — using softBowl');
    }
    return GuardrailSound.softBowl;
  }
}