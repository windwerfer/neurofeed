import 'package:flutter/material.dart';

/// `alphaTheta` (Calm Wakeful Rest) was folded into `drowsiness` (the same ATR
/// engine, guardrail now optional per protocol). Like `focus`/`relaxation`, it
/// remains in the enum only so sessions recorded under it still parse; it is
/// not selectable — see [ProtocolInfo.forType].
enum ProtocolType {
  alphaTheta,
  focus,
  relaxation,
  drowsiness,
  twilight,
  alertnessOpen,
  alertnessClosed,
  mindfulness,
  concentration,
  relaxedConcentration,

  /// Raw recording session: no reward engine, no guardrail. Calibration is
  /// optional (per-session skip button).
  recordOnly,

  /// Guardrail-only session: the 3-stage guardrail calibration, then the AI
  /// sleep guardrail warns without any reward layer.
  guardrailOnly,
}

/// Which directional band ratio the reward engine optimizes.
///
/// `alphaOverTheta` (ATR = alpha ÷ theta) is what the engine runs today for
/// both protocols — the reward fires when ATR stays above the baseline
/// percentile, i.e. the brain is coached to keep alpha dominant over theta
/// (calm but awake). `thetaOverAlpha` (TAR) is reserved: switching a protocol
/// to it is a data-only change (same ratio engine, flipped criterion).
/// `betaOverTheta` (BTR) is the classic alertness ratio; `alphaOnly` rewards
/// plain relative alpha without a ratio.
enum RewardMetric { alphaOverTheta, thetaOverAlpha, betaOverTheta, alphaOnly }

extension RewardMetricLabel on RewardMetric {
  /// Short display name used in the nerd-stats bubble and stats labels.
  String get shortLabel => switch (this) {
    RewardMetric.alphaOverTheta => 'ATR',
    RewardMetric.thetaOverAlpha => 'TAR',
    RewardMetric.betaOverTheta => 'BTR',
    RewardMetric.alphaOnly => 'α',
  };
}

/// A per-sample condition a composite protocol applies on top of the scalar
/// reward metric. The scalar must beat the baseline threshold AND every
/// condition must pass for the sample to count as in-target. All values are
/// relative band powers (fractions of total power, summing to 1 across the
/// five bands).
sealed class TargetCondition {
  const TargetCondition();

  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  });
}

/// Rewards only while relative beta stays at or below [maxBetaRel] — the
/// "beta inhibit" leg of calm-focus protocols (discourages elevated
/// high-frequency activity).
class BetaCeiling extends TargetCondition {
  const BetaCeiling(this.maxBetaRel);
  final double maxBetaRel;

  @override
  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  }) =>
      betaRel <= maxBetaRel;
}

/// Rewards only while relative delta stays at or below [maxDeltaRel] — keeps
/// the state out of deep-sleep territory on protocols near the sleep edge.
class DeltaCeiling extends TargetCondition {
  const DeltaCeiling(this.maxDeltaRel);
  final double maxDeltaRel;

  @override
  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  }) =>
      deltaRel <= maxDeltaRel;
}

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

  /// Catchy short phrase shown bold above the scientific [title] in the
  /// protocol list (the user-facing name).
  final String catchPhrase;
  final String title;
  final String subtitle;
  final String guideText;
  final String algorithmDescription;
  final String expectedDelay;
  final Color color;
  final RewardMetric rewardMetric;

  /// Per-sample conditions applied on top of [rewardMetric] (see
  /// [TargetCondition]). Empty for pure scalar protocols.
  final List<TargetCondition> conditions;

  /// Whether the on-device sleep guardrail (LUNA/REVE) is on by default for
  /// this protocol. Every protocol can run the guardrail — the per-protocol
  /// setting (`Settings.guardrailEnabledFor`) overrides this default. The
  /// guardrail only warns — it never modulates the reward.
  final bool guardrailDefault;

  /// Whether the guardrail is offered at all for this protocol. False only for
  /// the eyes-open alertness protocol (no sleep drift to guard against); when
  /// false the guardrail UI is hidden and the layer never runs for it.
  final bool guardrailAllowed;

  /// How the guardrail behaves when music feedback is active (see
  /// [GuardrailFeedback]). Consulted only while the guardrail runs.
  final GuardrailFeedback guardrailFeedback;

  /// Whether this protocol runs a reward engine at all. False for pure
  /// recording ([ProtocolType.recordOnly]) and guardrail-only
  /// ([ProtocolType.guardrailOnly]) sessions — those hide the feedback-sound
  /// selection and never fire reward chimes/swell.
  final bool hasReward;

  /// Whether the session start offers a "skip calibration" shortcut next to
  /// the normal start button. True only for [ProtocolType.recordOnly].
  final bool calibrationSkippable;

  const ProtocolInfo({
    required this.type,
    required this.catchPhrase,
    required this.title,
    required this.subtitle,
    required this.guideText,
    required this.algorithmDescription,
    required this.expectedDelay,
    required this.color,
    required this.rewardMetric,
    this.conditions = const [],
    required this.guardrailDefault,
    this.guardrailAllowed = true,
    required this.guardrailFeedback,
    this.hasReward = true,
    this.calibrationSkippable = false,
  });

  static const ProtocolInfo _drowsiness = ProtocolInfo(
    type: ProtocolType.drowsiness,
    catchPhrase: 'Sleep-Edge Rest',
    title: 'Alpha over Theta with a sleep guardrail',
    subtitle:
        'An Alpha-over-Theta rest reward, plus an on-device AI layer '
        '(LUNA/REVE) that watches a rolling 4–5 second window of raw EEG each '
        'second for the signatures of actually falling asleep, and plays a '
        'soft warning chime when you drift — so the rest stays awake. The '
        'guardrail is an option: switch it off to run the plain rest engine.',
    guideText:
        'What to Meditate On\n'
        'Gentle, non-striving attention with the eyes closed.\n'
        '\n'
        'Ultimate Goal\n'
        'To rest at the edge of sleep and remain aware. The AI guardrail is a '
        'tripwire, not a driver: when the live EEG looks like sleep — not just '
        'drowsiness — a soft chime invites you back. It never rewards or '
        'punishes; it informs.\n'
        '\n'
        'Mind & State Effects\n'
        'The reward drives calm-awake training; the guardrail tries to catch '
        'the moment of falling asleep and sounds a gentle wake note so the '
        'session stays a rest, not a nap.\n'
        '\n'
        'Scientific Explanation\n'
        '- Reward: the ATR rest metric — alpha ÷ theta on the AF7/AF8 average. '
        'The guardrail never changes the reward.\n'
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
        'ATR reward (alpha ÷ theta) plus the LUNA/REVE AI sleep guardrail: a '
        'per-second model score over a rolling EEG window '
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
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const ProtocolInfo _twilight = ProtocolInfo(
    type: ProtocolType.twilight,
    catchPhrase: "Sleep's Doorway",
    title: 'Theta over Alpha (TAR, hypnagogic rest)',
    subtitle:
        'Rewards rising Theta relative to Alpha on the frontal electrodes — '
        'training the twilight state between waking calm and sleep, the zone '
        'used for hypnagogic imagery and WILD-style lucid dreaming entry. '
        'The AI sleep guardrail keeps you from crossing into actual sleep.',
    guideText:
        'What to Meditate On\n'
        'Lie down or sit comfortably, close your eyes, and let the mind sink '
        'toward the threshold of sleep — heavy, dreamy, drifting. Keep just '
        'enough awareness to stay present; the reward encourages the theta-'
        'dominant borderland, not unconsciousness.\n'
        '\n'
        'Ultimate Goal\n'
        'A mind-awake, body-asleep state: deep hypnagogic relaxation where '
        'imagery and dreamlike thought arise while a thread of awareness '
        'stays online. This is the entry zone for WILD-style lucid dreaming '
        'and deeply restorative rest.\n'
        '\n'
        'Mind & State Effects\n'
        'Theta dominance is associated with drowsiness, hypnagogic imagery '
        'and the transition into sleep. Training it deliberately builds '
        'familiarity with the borderland — the reward rises as Theta '
        'overtakes Alpha on the frontal electrodes, while the guardrail '
        'warns when the signal moves toward actual sleep.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Theta (4–8 Hz) and Alpha (8–13 Hz) on the frontal '
        'electrodes (AF7/AF8).\n'
        '- The Mechanism: as relaxation deepens toward sleep, Theta power '
        'grows relative to Alpha. The ratio trains that direction.\n'
        '- The Reward Criterion: the Theta/Alpha ratio (TAR = theta ÷ alpha) '
        'is rewarded while it stays above your personal baseline percentile. '
        'In plain terms the training encourages the twilight state, not '
        'sleep.\n'
        '- Guardrail: the on-device AI layer (LUNA/REVE) and the frontal-'
        'delta ceiling warn when the state crosses into actual sleep — '
        'statistical estimates, not a medical device.\n'
        '\n'
        'Target Meditation Styles\n'
        'Hypnagogic exploration, Yoga Nidra, WILD-style lucid dreaming '
        'preparation, deep rest.\n'
        '\n'
        'Who It Helps\n'
        '- Practitioners working with lucid dreaming entry and hypnagogic '
        'imagery.\n'
        '- People who want the deep rest of the sleep border while keeping '
        'awareness.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone who needs guaranteed wakefulness: the guardrail is an '
        'approximate cue, not a safety device.\n'
        '- Those who find the hypnagogic state disorienting or who simply '
        'want to stay asleep — use a rest protocol without the sleep edge.',
    algorithmDescription:
        'Computes the Theta/Alpha ratio (TAR = theta power ÷ alpha power) on '
        'the AF7/AF8 average. The reward fires while TAR is above a threshold '
        'derived from your personal baseline: a configurable percentile of '
        'the calibration distribution. The threshold adapts during the '
        'session to keep you in the learning zone. The LUNA/REVE AI sleep '
        'guardrail warns (chime, plus music muffle) when the live sleep '
        'direction or frontal delta crosses into actual sleep.',
    expectedDelay: '~1s (TAR) + ~1s (AI model window)',
    color: Color(0xFF8E24AA),
    rewardMetric: RewardMetric.thetaOverAlpha,
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const ProtocolInfo _alertnessOpen = ProtocolInfo(
    type: ProtocolType.alertnessOpen,
    catchPhrase: 'Eyes-Open Alertness',
    title: 'Beta over Theta (BTR, eyes open)',
    subtitle:
        'Trains higher Beta relative to Theta with the eyes open — the '
        'classic alertness-and-attention ratio. Calibrates with an eyes-open '
        'baseline so the target matches how you actually practice.',
    guideText:
        'What to Meditate On\n'
        'Keep your eyes open. Settle into a soft, non-strained gaze and '
        'bring a gentle but continuous attention to the present — '
        'sensations, breath, or the room around you. This is an active, '
        'engaged state, not a sleepy one.\n'
        '\n'
        'Ultimate Goal\n'
        'A wakeful, alert state with the eyes open: higher relative Beta '
        '(engaged attention) and lower relative Theta (drowsiness, '
        'under-arousal). The reward rises as the ratio tips toward '
        'alertness.\n'
        '\n'
        'Mind & State Effects\n'
        'Beta-band activity is linked to active attention, thinking and '
        'focused engagement. Training the Beta/Theta ratio leans the state '
        'toward readiness and away from drowsiness — useful for seated '
        'attention practice and daytime alertness.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Beta (13–30 Hz) and Theta (4–8 Hz) on the frontal '
        'electrodes (AF7/AF8).\n'
        '- The Mechanism: with eyes open, relative Beta reflects engaged '
        'attention while Theta tracks drowsiness and under-arousal.\n'
        '- The Reward Criterion: the Beta/Theta ratio (BTR = beta ÷ theta) '
        'is rewarded while it stays above your personal baseline percentile. '
        'Eyes-open signal is noisier (blinks, muscle) — the movement gate '
        'drops contaminated samples.\n'
        '\n'
        'Target Meditation Styles\n'
        'Open-eyed attention, walking meditation, active mindfulness.\n'
        '\n'
        'Who It Helps\n'
        '- People who practice eyes-open meditation.\n'
        '- Anyone wanting to train alertness and reduce drowsy drift during '
        'sitting practice.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone seeking deep rest — this protocol rewards the opposite '
        'direction.',
    algorithmDescription:
        'Computes the Beta/Theta ratio (β ÷ θ) on the AF7/AF8 average. The '
        'reward fires while the ratio stays above a personal baseline '
        'percentile — training higher relative beta (alert, engaged) versus '
        'theta (drowsy, under-aroused). Calibrated eyes-open with a '
        'movement/artifact gate.',
    expectedDelay: '~1s (live band stream)',
    color: Color(0xFFFB8C00),
    rewardMetric: RewardMetric.betaOverTheta,
    guardrailDefault: false,
    guardrailAllowed: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _alertnessClosed = ProtocolInfo(
    type: ProtocolType.alertnessClosed,
    catchPhrase: 'Eyes-Closed Alertness',
    title: 'Beta over Theta (BTR, eyes closed)',
    subtitle:
        'The same Beta-over-Theta alertness reward with an eyes-closed '
        'calibration — a still, seated attention state without the visual '
        'input.',
    guideText:
        'What to Meditate On\n'
        'Close your eyes and hold a steady, wakeful attention — on the '
        'breath, on body sensations, on the space around you. Stay '
        'engaged: this is alertness training, not rest.\n'
        '\n'
        'Ultimate Goal\n'
        'A wakeful eyes-closed state: higher relative Beta (engaged '
        'attention) and lower relative Theta (drowsiness). The reward rises '
        'as the ratio tips toward alertness.\n'
        '\n'
        'Mind & State Effects\n'
        'Same ratio as the eyes-open variant, minus visual input: a still, '
        'focused attention that resists drowsy drift — useful for long '
        'seated practice where the mind tends to sag.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Beta (13–30 Hz) and Theta (4–8 Hz) on the frontal '
        'electrodes (AF7/AF8).\n'
        '- The Mechanism: eyes-closed Theta rises with drowsiness; keeping '
        'relative Beta high tracks sustained engagement.\n'
        '- The Reward Criterion: the Beta/Theta ratio (BTR = beta ÷ theta) '
        'is rewarded while it stays above your personal baseline percentile. '
        'The movement gate drops contaminated samples.\n'
        '\n'
        'Target Meditation Styles\n'
        'Seated attention, breath awareness, concentration practice with '
        'eyes closed.\n'
        '\n'
        'Who It Helps\n'
        '- Practitioners who train alertness with eyes closed.\n'
        '- Anyone who dozes off in eyes-closed sitting and wants a '
        'alertness-oriented target.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone seeking deep rest — this protocol rewards the opposite '
        'direction.',
    algorithmDescription:
        'Computes the Beta/Theta ratio (β ÷ θ) on the AF7/AF8 average. The '
        'reward fires while the ratio stays above a personal baseline '
        'percentile — training higher relative beta (alert, engaged) versus '
        'theta (drowsy, under-aroused). Calibrated eyes-closed with a '
        'movement/artifact gate.',
    expectedDelay: '~1s (live band stream)',
    color: Color(0xFF00897B),
    rewardMetric: RewardMetric.betaOverTheta,
    guardrailDefault: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _mindfulness = ProtocolInfo(
    type: ProtocolType.mindfulness,
    catchPhrase: 'Calm Awareness',
    title: 'Alpha Uptraining (open monitoring)',
    subtitle:
        'Rewards rising relative Alpha on the frontal electrodes — the '
        'calm, wakeful rhythm of open monitoring meditation. Simpler and '
        'gentler than the ratio protocols: just more Alpha, no ratio juggling.',
    guideText:
        'What to Meditate On\n'
        'Close your eyes and rest in open awareness: notice whatever arises '
        '— thoughts, sounds, sensations — without following or resisting. '
        'No effort, no control; just present attention.\n'
        '\n'
        'Ultimate Goal\n'
        'A stable, calm, aware state with elevated relative Alpha — the '
        'rhythm classically associated with relaxed wakefulness and open '
        'monitoring practice.\n'
        '\n'
        'Mind & State Effects\n'
        'Raising relative Alpha leans the nervous system toward calm, '
        'settled attention: less agitation, less drowsiness, a quiet '
        'observing mind.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Band: Alpha (8–13 Hz) on the frontal electrodes '
        '(AF7/AF8), as a fraction of total power.\n'
        '- The Mechanism: closing the eyes typically raises Alpha; '
        'open-monitoring practice is associated with sustained Alpha '
        'presence.\n'
        '- The Reward Criterion: relative Alpha is rewarded while it stays '
        'above your personal baseline percentile — no ratio, so the target '
        'is simply "more of the calm rhythm".\n'
        '\n'
        'Target Meditation Styles\n'
        'Open Monitoring, Mindfulness, Vipassana, passive awareness.\n'
        '\n'
        'Who It Helps\n'
        '- Beginners wanting a simple, forgiving target.\n'
        '- Practitioners of open-monitoring meditation.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone whose goal is alertness or engagement — this rewards calm, '
        'not activation.\n'
        '- Habitual meditation sleepers may drift: Alpha is a resting '
        'rhythm; there is no sleep guardrail here.',
    algorithmDescription:
        'Rewards relative Alpha power (alpha ÷ total band power) on the '
        'AF7/AF8 average. The reward fires while relative Alpha is above a '
        'threshold derived from your personal baseline: a configurable '
        'percentile of the calibration distribution. The threshold adapts '
        'during the session to keep you in the learning zone.',
    expectedDelay: '~1s (live band stream)',
    color: Color(0xFF43A047),
    rewardMetric: RewardMetric.alphaOnly,
    guardrailDefault: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _concentration = ProtocolInfo(
    type: ProtocolType.concentration,
    catchPhrase: 'Quiet Focus',
    title: 'Stable Alpha + Beta Inhibit',
    subtitle:
        'Rewards sustained relative Alpha while relative Beta stays low — '
        'a calm, stable attention with the busy high-frequency chatter '
        'dampened. Patterns associated with sustained attention in '
        'contemplative EEG work.',
    guideText:
        'What to Meditate On\n'
        'Close your eyes and place your attention on a single object — '
        'the breath, a mantra, a point of sensation. When the mind '
        'wanders, gently return. The reward wants both: calm Alpha '
        'presence and low Beta busyness.\n'
        '\n'
        'Ultimate Goal\n'
        'A stable, focused state: elevated relative Alpha (calm presence) '
        'together with low relative Beta (quieted discursive thought). '
        'The reward fires only when both hold at once.\n'
        '\n'
        'Mind & State Effects\n'
        'Sustained attention practice: the calm rhythm stays up while the '
        'high-frequency "thinking" markers stay down — a quiet, stable '
        'focus.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Alpha (8–13 Hz) and Beta (13–30 Hz) on the frontal '
        'electrodes (AF7/AF8).\n'
        '- The Mechanism: sustained attention is associated with stable '
        'Alpha; elevated Beta tracks active, often discursive thinking.\n'
        '- The Reward Criterion: relative Alpha is rewarded while it stays '
        'above your personal baseline percentile AND relative Beta stays at '
        'or below a fixed ceiling. Claims are limited to patterns '
        'associated with sustained attention — this is not a measurement '
        'of concentration itself.\n'
        '\n'
        'Target Meditation Styles\n'
        'Focused Attention, Samatha, breath meditation, mantra.\n'
        '\n'
        'Who It Helps\n'
        '- Practitioners of focused-attention meditation.\n'
        '- People wanting a "quiet mind" training target.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone seeking activation or alertness training.\n'
        '- Those who find goal-directed concentration effortful or '
        'counterproductive.',
    algorithmDescription:
        'Rewards relative Alpha (alpha ÷ total power) on the AF7/AF8 '
        'average while relative Beta stays ≤ 0.25 (the beta-inhibit leg). '
        'Alpha must beat the baseline percentile threshold AND the beta '
        'ceiling must hold — both conditions gate the reward. The Alpha '
        'threshold adapts during the session.',
    expectedDelay: '~1s (live band stream)',
    color: Color(0xFFD81B60),
    rewardMetric: RewardMetric.alphaOnly,
    conditions: [BetaCeiling(0.25)],
    guardrailDefault: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
  );

  static const ProtocolInfo _relaxedConcentration = ProtocolInfo(
    type: ProtocolType.relaxedConcentration,
    catchPhrase: 'Deep Stillness',
    title: 'Alpha over Theta + Rest Guard (access concentration)',
    subtitle:
        'A calm Alpha-over-Theta reward with extra guards: low Beta (quiet '
        'mind) and low Delta (no sleep), plus the AI sleep guardrail. A '
        'practical proxy used by practitioners approaching absorption — '
        'sustained calm frontal alpha with reduced high-frequency activity.',
    guideText:
        'What to Meditate On\n'
        'Settle into deep stillness: eyes closed, body motionless, '
        'attention softly absorbed in the present. Let the mind quiet '
        'completely — not sleepy, not busy, just still and absorbed.\n'
        '\n'
        'Ultimate Goal\n'
        'A deeply still, absorbed state: strong calm Alpha, minimal busy '
        'Beta, minimal slow-wave drift toward sleep. The rewards stack — '
        'Alpha/Theta high, Beta low, Delta low, body still.\n'
        '\n'
        'Mind & State Effects\n'
        'Deep calm with reduced mental chatter: the state practitioners '
        'describe approaching absorption. Science on true jhana EEG is '
        'sparse and mixed; this protocol stays descriptive — it trains a '
        'practical proxy, not a diagnosis.\n'
        '\n'
        'Scientific Explanation\n'
        '- Target Bands: Alpha (8–13 Hz), Theta (4–8 Hz), Beta (13–30 Hz) '
        'and Delta (1–4 Hz) on the frontal electrodes (AF7/AF8).\n'
        '- The Mechanism: absorption practices are described as sustained '
        'calm alpha with reduced high-frequency activity; sleep is '
        'characterized by rising delta.\n'
        '- The Reward Criterion: the Alpha/Theta ratio (ATR) must beat the '
        'baseline percentile AND relative Beta ≤ 0.25 AND relative Delta ≤ '
        '0.5. The AI guardrail additionally warns on sleep-direction '
        'drift — the delta condition and guardrail keep the stillness out '
        'of sleep.\n'
        '\n'
        'Target Meditation Styles\n'
        'Access concentration, absorption practice, deep Samatha.\n'
        '\n'
        'Who It Helps\n'
        '- Practitioners working toward absorption states.\n'
        '- People with a strong, established attention who want deeper '
        'stillness.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Beginners: the stacked conditions make the target harder to '
        'reach — start with Sleep-Edge Rest.\n'
        '- Anyone who needs guaranteed wakefulness: the guardrail is an '
        'approximate cue, not a safety device.',
    algorithmDescription:
        'Rewards the Alpha/Theta ratio (ATR = alpha ÷ theta) on the AF7/AF8 '
        'average while relative Beta ≤ 0.25 and relative Delta ≤ 0.5 — a '
        'calm, quiet, non-sleeping state. ATR must beat the baseline '
        'percentile threshold AND both conditions must hold; the LUNA/REVE '
        'AI sleep guardrail warns (chime, plus music muffle) on sleep drift. '
        'The ATR threshold adapts during the session.',
    expectedDelay: '~1s (ATR) + ~1s (AI model window)',
    color: Color(0xFF6D4C41),
    rewardMetric: RewardMetric.alphaOverTheta,
    conditions: [BetaCeiling(0.25), DeltaCeiling(0.5)],
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.muffleWhileWarning,
  );

  static const ProtocolInfo _recordOnly = ProtocolInfo(
    type: ProtocolType.recordOnly,
    catchPhrase: 'Record Only',
    title: 'Pure EEG Recording',
    subtitle:
        'Records the session without any reward engine, guardrail, or '
        'feedback sounds — a quiet, clean recording of your raw EEG and '
        'signals. Calibration is optional: start with the usual baseline, or '
        'skip it and just record.',
    guideText:
        'What to Meditate On\n'
        'Anything you like — this protocol only records. Meditate, rest, '
        'work, or simply sit; the raw EEG, bands, and signals are saved for '
        'later review.\n'
        '\n'
        'Ultimate Goal\n'
        'A clean, self-contained recording with no feedback shaping your '
        'state. Use it to capture practice for review or to collect data '
        'without any training signal.\n'
        '\n'
        'Mind & State Effects\n'
        'None by design: no reward chimes, no music filter, no guardrail '
        'warnings. What you do with the time is entirely up to you.\n'
        '\n'
        'Scientific Explanation\n'
        '- No reward metric runs; no threshold is derived.\n'
        '- Calibration (when kept) only establishes a baseline in the '
        'metadata — it does not gate any feedback.\n'
        '- The session still records every enabled stream and produces a '
        'full history entry with summary charts.\n'
        '\n'
        'Target Meditation Styles\n'
        'Unstructured practice, data collection, recording sessions you want '
        'to review later.\n'
        '\n'
        'Who It Helps\n'
        '- Anyone who wants the raw data without a training target.\n'
        '- Testers and reviewers comparing recordings across sessions.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone wanting live feedback or guidance — pick a training '
        'protocol instead.',
    algorithmDescription:
        'Recording only: every enabled stream (EEG, bands, PPG, pulse, IMU, '
        'movement, peak alpha, telemetry) is written to the session file. No '
        'reward metric, no ATR baseline evaluation, no guardrail layer, no '
        'feedback sounds. An optional calibration baseline is recorded in '
        'the metadata when the normal start is used.',
    expectedDelay: '—',
    color: Color(0xFF607D8B),
    rewardMetric: RewardMetric.alphaOverTheta,
    guardrailDefault: false,
    guardrailAllowed: false,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
    hasReward: false,
    calibrationSkippable: true,
  );

  static const ProtocolInfo _guardrailOnly = ProtocolInfo(
    type: ProtocolType.guardrailOnly,
    catchPhrase: 'Sleep Guard',
    title: 'AI Sleep Guardrail Only',
    subtitle:
        'No reward engine — just the on-device AI sleep guardrail. A '
        '3-stage calibration captures your clear and rest baselines, then '
        'the LUNA/REVE layer watches for the signature of actually falling '
        'asleep and warns you back. Rest without any training signal.',
    guideText:
        'What to Meditate On\n'
        'Rest, with the eyes closed. Drift toward sleep as far as you like — '
        'the guardrail will gently bring you back when the signal looks like '
        'you have actually fallen asleep.\n'
        '\n'
        'Ultimate Goal\n'
        'Deep, safe rest at the edge of sleep with no reward pressure: the '
        'guardrail is the only voice in the session, and it only warns.\n'
        '\n'
        'Mind & State Effects\n'
        'Rest and near-sleep exploration without any ratio training. The '
        'warning chime invites awareness back when sleep signs appear.\n'
        '\n'
        'Scientific Explanation\n'
        '- No reward metric runs — the session is scored only by the '
        'guardrail layer.\n'
        '- The 3-stage calibration records artifacts, an eyes-open clear '
        'anchor, and an eyes-closed rest distribution; the warning threshold '
        'derives from your own baseline.\n'
        '- During the session the on-device model (LUNA/REVE, RLX CPU) '
        'embeds a rolling EEG window each second; a warning fires when the '
        'sleep direction passes the threshold or frontal delta exceeds the '
        'ceiling. A statistical estimate, not a medical device.\n'
        '\n'
        'Target Meditation Styles\n'
        'Deep rest, Yoga Nidra, sleep-adjacent practice where only the '
        'tripwire matters.\n'
        '\n'
        'Who It Helps\n'
        '- People who doze off in rest practice and want a gentle wake note '
        'without any reward shaping.\n'
        '\n'
        'Who Should Avoid This\n'
        '- Anyone who needs guaranteed wakefulness: the guardrail is an '
        'approximate cue, not a safety device.',
    algorithmDescription:
        'Guardrail only: the 3-stage calibration (artifacts, eyes-open '
        'clear anchor, eyes-closed rest distribution) feeds the LUNA/REVE '
        'on-device scorer or the band-math fallback; the ATR reward engine '
        'and feedback sounds are disabled. A warning chime fires when the '
        'live sleep direction exceeds the warning threshold (default 75th '
        'percentile of the rest baseline) or frontal delta exceeds the '
        'ceiling.',
    expectedDelay: '~1s (AI model window)',
    color: Color(0xFF5E35B1),
    rewardMetric: RewardMetric.alphaOverTheta,
    guardrailDefault: true,
    guardrailFeedback: GuardrailFeedback.chimeOnly,
    hasReward: false,
  );

  static const List<ProtocolInfo> all = [
    _drowsiness,
    _twilight,
    _alertnessOpen,
    _alertnessClosed,
    _mindfulness,
    _concentration,
    _relaxedConcentration,
    _recordOnly,
    _guardrailOnly,
  ];

  /// Legacy sessions stored under the removed placeholder protocols
  /// (`focus`/`relaxation`) or the folded-in `alphaTheta` map to the ATR info
  /// since that is the engine they actually ran under.
  static ProtocolInfo forType(ProtocolType type) =>
      all.firstWhere((p) => p.type == type, orElse: () => _drowsiness);
}
