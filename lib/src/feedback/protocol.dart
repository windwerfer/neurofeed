import 'package:flutter/material.dart';

/// `focus` and `relaxation` remain in the enum only so sessions recorded under
/// the old placeholder protocols still parse; they were never backed by a real
/// engine (everything ran the ATR engine) and are not selectable — see
/// [ProtocolInfo.forType].
enum ProtocolType { alphaTheta, focus, relaxation, drowsiness }

/// Which directional band ratio the reward engine optimizes.
///
/// `alphaOverTheta` (ATR = alpha ÷ theta) is what the engine runs today for
/// both protocols — the reward fires when ATR stays above the baseline
/// percentile, i.e. the brain is coached to keep alpha dominant over theta
/// (calm but awake). `thetaOverAlpha` (TAR) is reserved: switching a protocol
/// to it is a data-only change (same ratio engine, flipped criterion).
enum RewardMetric { alphaOverTheta, thetaOverAlpha }

/// How a protocol's AI sleep guardrail behaves in music-feedback mode. The
/// guardrail only ever warns on non-music (chime) feedback; with music it can
/// either stay a pure chime (the filter keeps following the ratio reward) or
/// additionally muffle the music while the sleep-drift warning is active.
enum GuardrailFeedback {
  /// Warning chime only — the music filter is untouched by the guardrail.
  chimeOnly,

  /// While a warning is active the low-pass filter is forced fully closed
  /// (deep muffle) and returns to the ratio-driven cutoff after it clears.
  muffleWhileWarning,
}

class ProtocolInfo {
  final ProtocolType type;
  final String title;
  final String subtitle;
  final String guideText;
  final String algorithmDescription;
  final String expectedDelay;
  final Color color;
  final RewardMetric rewardMetric;

  /// Whether this protocol layers the on-device sleep guardrail (LUNA/REVE)
  /// on top of the reward engine. The guardrail only warns — it never
  /// modulates the reward.
  final bool aiSleepGuardrail;

  /// How the guardrail behaves when music feedback is active (see
  /// [GuardrailFeedback]). Consulted only when [aiSleepGuardrail] is true.
  final GuardrailFeedback guardrailFeedback;

  const ProtocolInfo({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.guideText,
    required this.algorithmDescription,
    required this.expectedDelay,
    required this.color,
    required this.rewardMetric,
    required this.aiSleepGuardrail,
    required this.guardrailFeedback,
  });

  static const ProtocolInfo _alphaTheta = ProtocolInfo(
    type: ProtocolType.alphaTheta,
    title: 'Alpha over Theta (ATR uptraining)',
    subtitle:
        'Guides you into a calm, wakeful resting state: the reward fires when '
        'Alpha power stays above Theta on the frontal electrodes — eyes '
        'closed, body settled, awareness still online.',
    guideText:
        'What to Meditate On\n'
        'Practice non-striving. Close your eyes, let the body and mind settle, '
        'and stay a quiet observer of whatever thoughts or feelings '
        'arise — no effort, no control.\n'
        '\n'
        'Ultimate Goal\n'
        'A state of calm, wakeful relaxation: the mind is quiet and the body '
        'rests, but awareness stays present. The target is resting attention, '
        'not sleep.\n'
        '\n'
        'Mind & State Effects\n'
        'Shifts the nervous system into parasympathetic recovery: slower, '
        'calmer mentation and reduced cognitive chatter. The reward '
        'encourages the relaxed-but-awake pattern — eyes closed and settled, '
        'without drifting off.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Alpha (8–13 Hz) and Theta (4–8 Hz) on the frontal '
        'electrodes (AF7/AF8).\n'
        '- The Mechanism: closing the eyes typically raises Alpha power — a '
        'calm, awake observation rhythm. Theta rises as drowsiness deepens.\n'
        '- The Reward Criterion: the Alpha/Theta ratio (ATR = alpha ÷ theta) '
        'is rewarded while it stays above your personal baseline percentile. '
        'In plain terms the training encourages relaxed-but-alert rather than '
        'sleepy.\n'
        '\n'
        'Target Meditation Styles\n'
        'Yoga Nidra (staying aware), Open Monitoring, Passive Awareness.\n'
        '\n'
        'Who It Helps\n'
        '- Overactive minds that struggle to "turn off": a concrete target to '
        'rest into.\n'
        '- Stress and burnout recovery: regular, restorative rest states.\n'
        '- Practitioners learning to stay awake and aware during rest.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Habitual meditation sleepers: if you reliably fall asleep the '
        'moment your eyes close, start with an alertness-building practice — '
        'this protocol will not keep you awake on its own.\n'
        '- Anyone who finds the eyes-closed state dissociating.',
    algorithmDescription:
        'Computes the Alpha/Theta ratio (ATR = alpha power ÷ theta power) on '
        'the AF7/AF8 average. The reward fires while ATR is above a threshold '
        'derived from your personal baseline: a configurable percentile '
        '(default p40) of the 90-second eyes-closed calibration — about a 60% '
        'initial reward rate. The threshold adapts during the session to keep '
        'you in the learning zone.',
    expectedDelay: '~1s (live band stream)',
    color: Color(0xFF7C4DFF),
    rewardMetric: RewardMetric.alphaOverTheta,
    aiSleepGuardrail: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _drowsiness = ProtocolInfo(
    type: ProtocolType.drowsiness,
    title: 'Sleep-Edge Rest — Alpha over Theta with a sleep guardrail',
    subtitle:
        'The same Alpha-over-Theta reward as the base protocol, plus an '
        'on-device AI layer (LUNA/REVE) that watches a rolling 4–5 second '
        'window of raw EEG each second for the signatures of actually falling '
        'asleep, and plays a soft warning chime when you drift — so the rest '
        'stays awake.',
    guideText:
        'What to Meditate On\n'
        'Same as the Alpha-over-Theta protocol: gentle, non-striving '
        'attention with the eyes closed.\n'
        '\n'
        'Ultimate Goal\n'
        'To rest at the edge of sleep and remain aware. The AI guardrail is a '
        'tripwire, not a driver: when the live EEG looks like sleep — not just '
        'drowsiness — a soft chime invites you back. It never rewards or '
        'punishes; it informs.\n'
        '\n'
        'Mind & State Effects\n'
        'The reward drives the same calm-awake training as the base protocol. '
        'The guardrail tries to catch the moment of falling asleep and sounds '
        'a gentle wake note so the session stays a rest, not a nap.\n'
        '\n'
        'Scientific Explanation\n'
        '- Reward: identical to Alpha-over-Theta — ATR (alpha ÷ theta) on the '
        'AF7/AF8 average. The guardrail never changes the reward.\n'
        '- Guardrail: the on-device model (LUNA or REVE, RLX CPU engine) '
        'embeds a rolling window of raw EEG at 256 Hz, once per second (LUNA '
        'epochs are 5 s / 1280 samples; REVE 4 s / 1024 samples). During '
        'calibration it records an eyes-open "clear" anchor and an eyes-closed '
        'rest distribution. During the session a warning fires when the live '
        'sleep-direction measure is above the session warning threshold '
        '(default: 75th percentile of your eyes-closed rest baseline) or the '
        'frontal delta is above a ceiling. The model is a statistical '
        'estimate, not a medical device — false alarms are possible.\n'
        '\n'
        'Target Meditation Styles\n'
        'Yoga Nidra, deep rest practice, sleep-adjacent meditations where '
        'staying aware matters.\n'
        '\n'
        'Who It Helps\n'
        '- Practitioners who want the restoring depth of near-sleep rest while '
        'keeping a thread of awareness.\n'
        '- People who reliably doze off in meditation and want a gentle '
        'tripwire.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone who needs guaranteed wakefulness: the guardrail is an '
        'approximate cue, not a safety device.',
    algorithmDescription:
        'ATR reward exactly as in Alpha-over-Theta, plus the LUNA/REVE AI '
        'sleep guardrail: a per-second model score over a rolling EEG window '
        '(LUNA 5 s / 1280 samples, REVE 4 s / 1024 samples). During '
        'calibration it captures an eyes-open "V_clear" anchor and a rest '
        '(eyes-closed) sleep-direction distribution. During '
        'training a warning chime fires when the live sleep direction exceeds '
        'the Warning Threshold (default 75th percentile of your rest baseline) '
        'or the frontal delta exceeds the ceiling. Guardrail only — the ATR '
        'reward is never affected.',
    expectedDelay: '~1s (ATR) + ~1s (AI model window)',
    color: Color(0xFF1E88E5),
    rewardMetric: RewardMetric.alphaOverTheta,
    aiSleepGuardrail: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const List<ProtocolInfo> all = [_alphaTheta, _drowsiness];

  /// Legacy sessions stored under the removed placeholder protocols
  /// (`focus`/`relaxation`) mapped to the ATR info since that is the engine
  /// they actually ran under.
  static ProtocolInfo forType(ProtocolType type) =>
      all.firstWhere((p) => p.type == type, orElse: () => _alphaTheta);
}
