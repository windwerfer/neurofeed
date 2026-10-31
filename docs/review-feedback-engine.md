# Review: Dart feedback engine, protocols, calibration and Feedback UX

This is a review only. Nothing has been implemented yet.

- **Scope:** `lib/src/feedback/*` (about 6.5k LOC), the views `feedback_session` / `feedback_dashboard` / `feedback_list` / `protocol_builder` (about 5.4k LOC), `assets/protocols.json`, `assets/calibrations.json`, and `feedback_gym/`.
- **Status:** written 2026-10-29 for the Rust/egui port.

## 1. What the engine does

### Inputs
- These arrive at 1 Hz from Rust as `FeatureDto` (`band.atr|tar|btr|alpha|theta|beta|delta`, `ai.a_vig`).
- `BandsDto` arrives at about 4 Hz. It supplies relative bands for the inhibit checks.
- Other inputs:
  - signal quality for each pad;
  - movement, blink and jaw events, which make a sample "dirty" for `movementBuffer` = 1 s;
  - connection state.

### Protocol
A protocol is a `ProtocolDocument` (JSON, 7 built-ins plus `user.*`). It contains:
- copy text, colour and background sound;
- a calibration id;
- **reward lane:**
  - the feature;
  - the output: chime, music filter, rain stage, binaural swell or none;
  - the policy: `percentileUptrain` or `stabilityDowntrain`;
  - the inhibit conditions: `BetaCeiling` / `DeltaCeiling` on relative power;
  - the electrodes;
  - the locked fields;
- **guard lane:**
  - the feature (`ai.a_vig` or band.delta "band math");
  - the policy: `percentileWarn` only;
  - `muffleReward`, threshold mode / fixed threshold, and `requiresModel`.

### Calibration (`CalibrationRunner`)
- **Single:** 45 *valid* seconds of eyes closed or eyes open. The wall-clock maximum is 60 s.
- **Staged:** artifacts 15 s, then eyes-open counting, then eyes-closed rest.
  - It is used automatically when an `ai.*` feature is enabled.
- **Gates:**
  - all pads must have quality of at least 80 and stay green for 3 s;
  - after 20 s a "faulty pad" fallback is offered;
  - the audio intro times out after 15 s.
- `BaselineFrameClock` accepts each source second only once per feature.
- The previous baseline for the device can be re-applied, which lets the user skip calibration.

### Reward math (`RatioEngine`)
- **Threshold:** the P-th percentile of the baseline samples. P defaults to 40, giving about 60 % initial reward.
- **In-target test:** `value > thr`, AND every inhibit condition passes, AND the sample is clean (no movement, pads usable).
- **Success rate:** measured over a 75 s wall-clock window.
- **Adapt step (every 30 s):**

  | Success rate | Action |
  |---|---|
  | > 0.8 | threshold × (1.01..1.03) |
  | < 0.4 | threshold × (0.97..0.90) |
  | = 0 | circuit breaker: reset to the initial threshold |

  - The step size depends on `responsiveness`.
  - The threshold is clamped to `[initial, mean + 1.5·sd]`.
- **Optional EMA adaptation:** applied on every sample.
- **Recalibrate:** re-anchors from the last 90 s of clean samples (at least 30 needed).
- **Stability mode:**
  - r = CV(last N clean values) ÷ the median CV of the baseline windows;
  - in target when r ≤ 1 − difficulty;
  - dirty samples are skipped, not counted as failures.

### Guard math (`GuardLane`)
- The warn threshold comes from a baseline percentile of the guard feature, or a fixed threshold.
- When the value goes over the threshold:
  - the warning sound plays, with a 20 s cooldown;
  - the reward is optionally muffled (`guardBlocks`).
- The guard never changes the reward scalar.

### Outputs
- `RewardOutput.onSample(percentile, inTarget)` drives the audio.
- A `Trust*Sample` stream (native value, percentile, threshold, inTarget, heldBack, inhibit tags, clean/dirty reason) feeds the live "trust" graphs and the saved session file.

### Session flow
`idle → calibrating → playing ⇄ paused` and `→ interrupted → ended`.
- A disconnect gets a 10 s grace period and then ends the session.
- Bad signal for 10 s pauses the session, and it resumes automatically when the signal returns.
- Elapsed time comes from a 1 Hz `Timer` tick. That tick also drives `adapt()`.
- At the end, the user saves or discards the session and its notes on the dashboard.

## 2. Code-quality problems

1. **God object.** `FeedbackStateNotifier` is 2.6k lines.
   - It holds the phase machine, timers, audio, recording, the protocol catalogue, settings persistence, model loading, the device-connect UI, annotations, the feature probe and logging.
   - It makes about 90 `_ref.read(...)` calls.
   - No part of it can be tested without Riverpod and a fake world.
2. **Wall clock inside the math.**
   - `DateTime.now()` appears 32× in the logic (`RatioEngine` epochs, recent window, pauses, trust timing).
   - Effects:
     - success rate and adaptation depend on real time, not on sample time;
     - replaying a recorded session does not reproduce it;
     - tests need `epochWindow` hacks;
     - a pause still ages the epochs.
3. **Three clocks.**
   - The ticker counts elapsed seconds with `Timer.periodic`.
   - Features carry source time `t`.
   - The engine uses `DateTime.now()`.
   - These drift apart under load (desktop jank, web tab throttling).
4. **Lanes do their output through callbacks.**
   - `RewardLane` takes 4 callbacks, one of them with 12 named parameters.
   - It also exposes its result through about 12 `last*` mutable fields, which the notifier reads back to build `TrustRewardSample`.
   - So every result is carried twice (callback and fields), and the two paths can diverge.
5. **Duplicated dirty/emit paths.**
   - The uptrain-dirty, stability-dirty and clean paths each build the same 12-field record by hand.
   - The guard's dirty reason is computed again in the notifier (`artifactDirtyReason(now: DateTime.now() …)`).
6. **Modes are flags inside one mutable engine.**
   - `_stability != null` branches run through every method, and `useEmaAdapt` adds another mode on top.
   - Two policies share one class and one mutable `_baseline` list.
   - Stability mode *overwrites* `_baseline` with derived ratios, so `baselineMean` means different things in different modes.
7. **Settings sprawl.**
   - About 20 `set*` methods each write through to `settingsProvider` *and* the engine.
   - A protocol's `locked` list is enforced only in the UI.
8. **Smells and likely bugs:**
   - `isInTarget` with no threshold returns `atr > 1.0`, a magic fallback that is wrong for TAR/BTR/alpha.
   - The guard muffle check is applied only in stability mode (`tick.guardBlocks`). The uptrain path ignores `guardBlocks`, so `muffleReward` relies on the audio layer. That needs checking.
   - Percentile is computed as `below/n` with strict `<`, which is biased on ties. A recording-based fallback returns 50.
   - The calibration audio says "fifty seconds", but the window is 45 valid seconds with a 60 s maximum.
   - The comment "δ rail removed 2026-10" left a dead field (`ceilingOver: false`, `deltaRail`).
   - `debugPrint` logging is mixed into the hot paths.
9. **Feature definition is split across languages.**
   - The Rust aggregation averages relative powers across pads first, then takes the ratio.
   - `band.delta` is an *absolute* mean, while the other features are relative.
   - Inhibit conditions are evaluated in Dart from a separate `RelativeBandAggregator` with its own pad threshold.
   - So the reward and its inhibits can come from different pad sets.

## 3. UX/UI problems

1. **One long scrolling page** (`feedback_session.dart`, 2.8k lines, about 30 widget classes).
   - Settings cards, the guide, the debug probe, trust graphs, phase controls and the connect overlay all share one column.
   - The visible parts change with the phase via `if` chains.
   - There is no clear "what do I do now".
2. **Too many tuning knobs before the first session:**
   - percentile;
   - dynamic adapt and responsiveness;
   - EMA;
   - dwell;
   - inhibit ceilings;
   - stability window and difficulty;
   - guard mode and threshold;
   - binaural and music volumes.

   These are spread across about 12 dialogs. Novices see expert controls, and their protocol-level and session-level scope is unclear.
3. **Modal dialogs for everything.**
   - Examples: the music folder (asked twice), volume, the target-settings info screen and the guardrail scorer.
   - The flow gets interrupted, and on desktop the dialogs stack.
4. **Calibration is opaque.**
   - It shows "Calibrating…" with a countdown.
   - It does not say *why* it is waiting (pad 2 not green, movement) or show progress in valid seconds versus wall seconds.
   - Skip and Cancel sit next to each other.
5. **The reward state is hard to read live.**
   - Feedback is mostly audio, with graphs below the fold.
   - "Held back by beta inhibit", "dirty: movement" and "guard warning" exist in the data, but they are not surfaced as a clear status.
6. **Mixed terms:**
   - "program", "protocol" and "session" are used for the same thing;
   - reward and feedback sound;
   - guardrail and guard;
   - the builder exposes raw feature ids (`band.atr`).
7. **Post-session view.**
   - The dashboard reuses the live tabs (Raw/PSD/…) and puts notes and save at the top.
   - There is no session summary: time in target, threshold path, number of interruptions, comparison with past sessions.

## 4. Better design

### Engine, in our Command/Session core
- **`nf-dsp::feedback` (pure, no state machine, injected time).**
  - `Baseline::from(samples) -> {sorted, mean, sd}`.
  - `threshold(&Baseline, p)` and `percentile_rank(&Baseline, v)` (ties: mid-rank).
  - Policies as an enum:
    ```
    Policy::Uptrain { p, adapt: AdaptCfg }
    Policy::Stability { window, difficulty }
    ```
    Each has `fn step(&mut PolicyState, Sample{t, value, clean}) -> Verdict`.
  - The success window and recalibration window are keyed by **sample time `t`**, not by wall clock.
  - `Inhibit` is an enum evaluated on the *same* `RelBands` that produced the feature.
  - `Guard::PercentileWarn { … }` with a cooldown counted in sample time.
- **`Verdict` struct (one value, no callbacks or `last*` fields):**
  `{t, native, pct, thr, thr_pct, in_target, held_back: Vec<Reason>, dirty: Option<DirtyReason>, warn: bool}`.
  It is shared by the live view, the audio, the recording and the MCP.
- **`nf-core::feedback::Session` (state machine).**
  - Phases: `Idle → Calibrating{stage, valid_s, why_waiting} → Playing → Paused{reason} → Ended`.
  - It is driven only by `Session::tick(now)` and by the data it receives.
  - Commands (MCP and UI use the same set):
    - `feedback.select_protocol`, `feedback.start`, `feedback.skip_calibration`, `feedback.pause`, `feedback.resume`, `feedback.recalibrate`, `feedback.end`;
    - `feedback.set {param}`, which checks protocol `locked` and returns a disabled reason.
  - Queries:
    - `feedback.state`;
    - `feedback.verdicts{since}`;
    - `feedback.summary`.
  - The revision counter covers all of these.
- **Settings resolution.**
  - Resolve once into an immutable `EffectiveConfig`: protocol defaults, then the user overrides, then the locked fields.
  - A change creates a new config value that is applied at the next tick.
- **Audio output.** It is a consumer of `Verdict` in the app layer (`RewardOutput` trait). The core does not know about audio.
- **Replay.** Re-feed a recorded session through the same `Session` with its source time to get identical verdicts. These replays double as the golden tests.

### UX flow (egui, desktop and web)
1. **Choose.**
   - Protocol cards in plain language: goal, eyes open or closed, duration.
   - Advanced settings are collapsed on the card and show which settings are locked.
2. **Fit check (one screen).**
   - A head diagram with pad colours shows the live signal check.
   - The text says what to fix ("TP9 not touching: wet it / adjust").
   - "Continue" is enabled when the check is green. The disabled reason is shown when it is not.
3. **Calibrate.**
   - A stage strip (artifacts → open → closed).
   - A progress bar in *valid* seconds, plus a live reason when it is not collecting ("moving", "pad 2").
   - The option "Use last baseline (3 days old)" is offered.
4. **Train.**
   - A calm full-screen view with one large in-target indicator and a percentile meter against the threshold line.
   - A status chip shows one of: In target, Held back (beta), Paused (movement) or Guard warning.
   - It shows time left. Graphs are optional in a side panel.
   - Live changes are limited to volume and difficulty (±), and a change applies at the next tick.
5. **Pause/interrupt.**
   - An overlay states the reason and shows auto-resume progress.
6. **Summary.**
   - Time in target, the threshold path, dirty %, events and notes.
   - A trend against past sessions.
   - Save/discard.
   - The analysis tabs (Raw/PSD/…) are linked from here.

Expert tuning lives in Protocol Builder ("Advanced"), not in the session screen.

## 5. Recommendation: hybrid

| Option | What | Effort | + | − |
|---|---|---|---|---|
| A. 1:1 translate, redesign later | Port notifier, lanes, engine and dialogs as they are | ~3 wk now + ~3–4 wk redesign later | The current behaviour is the oracle; low decision load now | We would port a 2.6k-line god object and wall-clock bugs into Rust and then rewrite the state/UI a second time. egui has no Riverpod, so "1:1" already means redesigning the state |
| B. Full redesign during the port | New math, state and UX | ~5–6 wk | Clean result | No oracle; any change in reward behaviour is invisible and the `feedback_gym` stats are invalidated |
| **C. Hybrid (recommended)** | Port the **math** faithfully with golden tests; redesign the **state + UX** now | **~3.5–4.5 wk** | Behaviour is kept where it matters (thresholds, adaptation, stability, inhibit, guard); the state and UX are built once on our Command/Session core | Short-term risk while the golden tests are built; the time base has to change (see the exception below) |

### Plan for option C
1. **Golden fixtures (2–3 d).**
   - A small Dart test harness dumps `(input samples with t, config) → verdicts` for each policy and edge case: circuit breaker, clamp, stability warm-up, inhibit, recalibrate, guard cooldown.
   - It uses a faked clock so the wall time equals `t`.
   - The output is committed as JSON.
2. **`nf-dsp::feedback` pure math, passing the golden tests (4–5 d).**
3. **`nf-core` Session machine plus commands/queries/MCP, with an injected clock (4–5 d).**
4. **egui flow: choose, fit, calibrate, train, summary (5–7 d).**
5. **Audio outputs (chime, then the others) (3–5 d).** The AI guard (`ai.a_vig`, which needs the REVE model) is deferred.

### Faithfulness exceptions
These are deliberate fixes, each recorded in decisions.md and covered by its own test:
- epochs keyed by sample time instead of wall time;
- no `>1.0` fallback without a threshold;
- inhibits computed from the same pads as the reward;
- guard muffle applied in both policies.

All the golden tests must keep passing at a steady 1 Hz, where wall time equals sample time.

### Decision needed
1. Approve the hybrid.
2. Choose whether to keep the 40th-percentile / 75 s / 30 s constants as defaults. The recommendation is yes.
3. Decide whether the audio outputs beyond the chime are in scope for the first port.
