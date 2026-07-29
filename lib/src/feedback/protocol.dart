import 'package:flutter/material.dart';

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

  static const List<ProtocolInfo> all = [
    ProtocolInfo(
      type: ProtocolType.alphaTheta,
      title: 'Alpha-Theta Crossover',
      subtitle: 'Train the transition between wakefulness and deep internal quiet',
      guideText: 'Let your mind settle naturally. The feedback rewards smooth transitions between '
          'alert awareness (Beta) and deep internal quiet (Theta). '
          'Best for: Jhana practice, deep meditation, lucid dreaming.\n\n'
          'Tip: Do not force thoughts away — let them pass like clouds.',
      algorithmDescription: 'Compares the moving average of Alpha+Theta power against Beta power. '
          'When Theta rises relative to Beta, harmony increases. '
          'Uses a 5-second rolling window to smooth artifacts.',
      expectedDelay: '~3s (rolling average window)',
      color: Color(0xFF7C4DFF),
    ),
    ProtocolInfo(
      type: ProtocolType.focus,
      title: 'Focus / Concentration',
      subtitle: 'Reward increased Beta while keeping Theta low',
      guideText: 'Maintain concentrated attention. The system rewards sustained Beta (12–20 Hz) '
          'while keeping Theta (4–8 Hz) suppressed.\n\n'
          'Best for: Deep work, studying, mindfulness of breath.\n\n'
          'Tip: Focus on a single object — your breath, a point, or a mantra.',
      algorithmDescription: 'Computes the Theta/Beta ratio per electrode. '
          'Lower ratio = better focus. Feedback scales inversely with the ratio, '
          'averaged over a 2-second window.',
      expectedDelay: '~1s (minimal smoothing)',
      color: Color(0xFFFF6D00),
    ),
    ProtocolInfo(
      type: ProtocolType.relaxation,
      title: 'Relaxation / Meditation',
      subtitle: 'Reward increased Alpha on frontal channels',
      guideText: 'Let your mind wander gently. The feedback rewards rising Alpha (8–12 Hz) '
          'on your frontal lobes (AF7/AF8) — the signature of calm, wakeful relaxation.\n\n'
          'Best for: Stress reduction, creativity, open monitoring.\n\n'
          'Tip: A warm, floating feeling in the forehead is a good sign.',
      algorithmDescription: 'Tracks Alpha power on AF7 and AF8 channels. '
          'Feedback is proportional to the average Alpha power across both channels, '
          'with a 3-second rolling average to reduce blink artifacts.',
      expectedDelay: '~2s (artifact smoothing)',
      color: Color(0xFF00BFA5),
    ),
  ];

  static ProtocolInfo forType(ProtocolType type) =>
      all.firstWhere((p) => p.type == type);
}
