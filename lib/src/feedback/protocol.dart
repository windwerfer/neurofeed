import 'package:flutter/material.dart';

/// `focus` and `relaxation` remain in the enum only so sessions recorded under
/// the old placeholder protocols still parse; they were never backed by a real
/// engine (everything ran the ATR engine) and are not selectable — see
/// [ProtocolInfo.forType].
enum ProtocolType { alphaTheta, focus, relaxation }

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

  static const List<ProtocolInfo> all = [_alphaTheta];

  /// Legacy sessions stored under the removed placeholder protocols
  /// (`focus`/`relaxation`) mapped to the ATR info since that is the engine
  /// they actually ran under.
  static ProtocolInfo forType(ProtocolType type) =>
      all.firstWhere((p) => p.type == type, orElse: () => _alphaTheta);
}
