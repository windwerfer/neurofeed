import 'package:flutter/material.dart';

/// `focus` and `relaxation` remain in the enum only so sessions recorded under
/// the old placeholder protocols still parse; they were never backed by a real
/// engine (everything ran the ATR engine) and are not selectable — see
/// [ProtocolInfo.forType].
enum ProtocolType { alphaTheta, focus, relaxation, drowsiness }

class ProtocolInfo {
  final ProtocolType type;
  final String title;
  final String subtitle;
  final String guideText;
  final String algorithmDescription;
  final String expectedDelay;
  final Color color;

  const ProtocolInfo({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.guideText,
    required this.algorithmDescription,
    required this.expectedDelay,
    required this.color,
  });

  static const ProtocolInfo _alphaTheta = ProtocolInfo(
    type: ProtocolType.alphaTheta,
    title: 'Theta over Alpha (Alpha/Theta Ratio - ATR uptraining)',
    subtitle:
        'Guides your mind into the tranquil borderland between waking calm and deep sleep '
        'by training intuitive Theta waves to rise above conscious Alpha rhythm.',
    guideText:
        'What to Meditate On\n'
        'Practice radical non-striving. Rather than locking focus onto the breath, hold a gentle, '
        'peaceful intention at the start, then step back as a passive observer of whatever '
        'thoughts or feelings arise.\n'
        '\n'
        'Ultimate Goal\n'
        'To experience deep internal stillness while keeping a thread of conscious awareness '
        'alive—accessing the restorative benefits of sleep while remaining awake.\n'
        '\n'
        'Mind & State Effects\n'
        'Shifts the nervous system into parasympathetic recovery. By allowing Theta to overtake '
        'Alpha, the mind drops its protective armor, reducing cognitive chatter and inducing a '
        'state of silent awareness.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Alpha (8–12Hz) and Theta (4–8Hz).\n'
        '- The Mechanism: Closing your eyes increases Alpha waves, reflecting calm, awake '
        'observation. As you sink deeper, Theta waves originating from limbic structures involved '
        'in subconscious processing and memory surge.\n'
        '- The Crossover: This protocol rewards the brain when Theta amplitude exceeds Alpha '
        '(theta > alpha). Research by Peniston & Kulkosky (1989) shows this inversion marks the '
        'transition out of active sensory processing into deep somatic relaxation.\n'
        '\n'
        'Target Meditation Styles\n'
        'Yoga Nidra, Non-Dual Awareness, Open Monitoring, Hypnagogic Receptivity.\n'
        '\n'
        'Who It Helps\n'
        '- Chronic Ruminators: People who struggle to "turn off" an overactive mind.\n'
        '- Stress & Burnout Recovery: Anyone experiencing nervous system exhaustion.\n'
        '- Emotional Integration: Individuals looking to safely process subtle bodily tension.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Habitual Daytime/Meditation Sleepers: If you drift off the moment your eyes close, '
        'this mode will act as a lullaby. You need alertness-building protocols first.\n'
        '- People Prone to Dissociation: Those who struggle with feeling grounded, as heavy Theta '
        'can increase feelings of detachment.',
    algorithmDescription:
        'Computes the Alpha/Theta ratio (ATR = alpha power ÷ theta power) on the '
        'AF7/AF8 average. The feedback rewards the brain when Theta rises above Alpha '
        '(theta > alpha). A percentile of your 90-second baseline sets the initial reward '
        'threshold, which adapts to your performance during the session.',
    expectedDelay: '~1s (live band stream)',
    color: Color(0xFF7C4DFF),
  );

  static const ProtocolInfo _drowsiness = ProtocolInfo(
    type: ProtocolType.drowsiness,
    title: 'Pure Jhana — deep absorption with REVE sleep guardrail',
    subtitle:
        'The same ATR uptraining, plus a vision-transformer layer that '
        'watches for the deep-sleep harmonics (theta → delta) that mark '
        '"sleep", and calls you back with a soft warning instead of rewarding '
        'torpor.',
    guideText:
        'What to Meditate On\n'
        'Radical non-striving, exactly as in Theta-over-Alpha. Hold a gentle '
        'intention of loving stillness, then step back and let awareness '
        'settle without effort.\n'
        '\n'
        'Ultimate Goal\n'
        'A "Pure Jhana": profound absorption that keeps a thread of conscious '
        'awareness alive. You approach the sleep border but never cross it — '
        'the REVE layer is a gently prodding guardrail that wakes you from the '
        'torpor before it becomes sleep.\n'
        '\n'
        'Mind & State Effects\n'
        'The ATR reward drives the same parasympathetic restoration as the '
        'pure Alpha/Theta protocol. REVE classifies each second of EEG against '
        'deep-sleep harmonics; a drifting-into-sleep signal triggers it to '
        'play a soft, distinct warning chime so you can come back without '
        'breaking the state.\n'
        '\n'
        'Scientific Explanation\n'
        '- Reward: identical to Theta-over-Alpha — ATR (alpha ÷ theta) on the '
        'AF7/AF8 average.\n'
        '- Guardrail: a sleep-direction index from the REVE vision-transformer '
        '(a 1024-sample, 4 s window at 256 Hz, run once per second). When the '
        'live vector points toward your rest anchor "V_sleep" beyond the '
        'session warning threshold (75th percentile of your eyes-closed rest '
        'baseline), or the delta is above the ceiling, a soft warning chime '
        'fires. It never modulates the reward.\n'
        '\n'
        'Target Meditation Styles\n'
        'Yoga Nidra, Non-Dual Awareness, Open Monitoring, Deep Jhana practice '
        'with breath support.\n'
        '\n'
        'Who It Helps\n'
        '- Practitioners holding deep absorption who occasionally "doze off".\n'
        '- Anyone who wants the deep-rest benefits of falling toward sleep '
        'while keeping a safe thread of awareness.\n'
        '\n'
        'Who Should Avoid This\n'
        '- People for whom the ATR protocol acts as a lullaby (habitual '
        'meditation sleepers) — use alertness-building protocols first.\n'
        '- Those prone to dissociation who need grounded, eyes-open practice.',
    algorithmDescription:
        'ATR reward exactly as in Theta-over-Alpha, plus the '
        'REVE AI engine (a per-second vision-transformer over a 4 s, 1024-sample '
        'EEG window). During calibration it captures an eyes-open "V_clear" '
        'anchor from the cleanest rest samples; during training a warning chime '
        'fires when the live vector points toward deep sleep beyond the '
        'Warning Threshold — a guardrail only, the reward is never affected.',
    expectedDelay: '~1s (ATR) + ~1s (REVE per-second window)',
    color: Color(0xFF1E88E5),
  );

  static const List<ProtocolInfo> all = [_alphaTheta, _drowsiness];

  /// Legacy sessions stored under the removed placeholder protocols
  /// (`focus`/`relaxation`) mapped to the ATR info since that is the engine
  /// they actually ran under.
  static ProtocolInfo forType(ProtocolType type) =>
      all.firstWhere((p) => p.type == type, orElse: () => _alphaTheta);
}
