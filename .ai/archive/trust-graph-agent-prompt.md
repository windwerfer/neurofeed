# Feature: live reward/guard trust graphs on the feedback session

Repo: https://github.com/windwerfer/flutter_muse-rs_ml
Start from branch: `refactor/monitor` (not `main`; last release is out of date).

This is a **display + plumbing** task. Do not change `RatioEngine` reward math, the 80/40 adapt, the default 40th percentile, guard `percentileWarn`, or catalog protocols.

---

## STOP — explain first, then wait

Before any implementation commit or PR of code:

1. Read the real session UI and lanes (files below).
2. Reply with a short plan in your own words: what you will build, what you will not touch, which types you will extend.
3. Print **ASCII mockups** that match this spec (chips, graphs, three distinct readouts, peek dashes, nerd sheet). If the live code disagrees with a detail here, say so and show the adjusted ASCII.
4. **Stop and wait** for the human to say the plan is OK.

Do not start coding until they confirm. If a later message already confirms a pasted mockup, that counts.

Investigate: `lib/src/views/feedback_session.dart`, `lib/src/feedback/live_stats.dart`, `reward_lane.dart`, `guard_lane.dart`, `target_state.dart`, `feedback_state.dart`, `lib/src/monitor/electrode_toggles.dart`, `.ai/feedback/architecture.md`, `.ai/feedback/pipeline-contract.md`, `.ai/ui-map.md`.

---

## Problem

During a session the user only hears a coarse chime (and maybe a guard bowl) and can open a science-icon nerd bubble of raw numbers. That does not answer: should I hear a sound right now, is the band off, did I just blink, or is the target wrong? We want glanceable graphs for the **reward** lane and the **guard** lane, plus compact readouts when asked.

---

## Chrome: three small chips

Under the status bar, one discrete row of chips, **not** big filled buttons. Match Bands electrode chips: `ToggleButtons`, ~28 px tall, depressed = on.

```
┌ Status  Muse S   72%   /‾‾\  pads
│
│  [ Reward ] [ Guard ] [ More ]
│     in          out       in     <- default: Reward + More on, Guard off
```

- **Reward** toggles the reward graph.
- **Guard** toggles the guard graph. **Omit** this chip when the protocol has no guard (`alertnessOpen`, `recordOnly`, or guard feature none).
- **More** toggles the three readouts **under each visible graph**. If both graphs are on, More shows two stacked readout groups, each glued to its graph.
- Persist the three flags across sessions (restore on the next feedback session). Default if never set: **Reward on, Guard off, More on**.
- No separate Hide button. Off = chip not depressed.

---

## Graphs (playing + paused only)

Place them high (under chips, above the long Guide card) so a peek does not require scrolling.

Shared rules for both graphs:

- Y = **0–100 percentile of this session’s baseline** for that lane. Label with the feature short name (ATR / TAR / BTR / α, or δ / sleep). Never “% calm”.
- One solid horizontal **release/warn line** at `percentileOf(current threshold)` (moves if the slider or dynamic target moved the native threshold).
- Scroll ~30–60 s, newest at the right. ~1 Hz is enough. Isolate paints (`RepaintBoundary` / `ListenableBuilder`); do not rebuild the whole session scaffold on every band tick.
- **Dirty / invalid signal: dotted or dashed stroke, not a solid dip.** Blink, jaw, movement gate, pad fail, peek/EOG. Those seconds are not a hit and not a miss. Hold last clean Y or break the stroke.
- **Peek freeze (not session pause).** If it looks like eyes-open / EOG: keep the session running; dashes; hold last clean Y; **do not chime**; **do not adapt** the reward line; do not fire a new guard warning from that sample. Optional banner: `Peek — not counting`. Manual Pause is only for real breaks. There is no eyelid sensor — this is a heuristic (blinks, frontal artifact, motion, pads), not auto-pause.

Reward graph:

- Line = reward threshold (default p40 of calibration pile).
- Clean sample above the line and inhibit passing = in zone (chime should be eligible).
- Inhibit fail (β/δ ceiling) is **held back**, not noisy.

Guard graph:

- Same visual language, flipped meaning. Line = warn threshold (default p75 of eyes-closed rest pile). Optional second tick for the hard frontal-δ ceiling (`guardrailDeltaCeiling` 0.25) if that is what can fire.
- Above the line = warning **active** (`warningActive`). Graph follows the continuous warning, **not** the 20 s chime cooldown (cooldown is nerd-only).
- Quiet (below the line, clean) is the good state.
- Guard never flips `inTarget`. Do not mix lanes.

---

## Three readouts — only if More is on

Glued directly under the graph they belong to. **Three distinct designs** so they do not look like one widget repeated.

### 1. Last minute — block strip (time)

Per-second mosaic + percent. Engine window is ~75 s; label “last minute”. Until full: `warming up…` not a fake 0%.

Reward:

```
████░░██··██████░░   62% in zone
█ in zone   ░ below the line   · noisy (not counted)
```

Guard (same questions, flipped):

```
░░░░███░··░░░░░░     12% warning
█ warning   ░ quiet   · noisy (not counted)
```

Optional `▒` for reward “held back” if you can keep it readable. Do not clutter.

### 2. Now — rail + needle (this second)

**This design is required** (not a bar copy of the strip):

Reward:

```
  0 ────────╂──────── 100
            40
         ● 67     above     chime
```

- `40` is the live release percentile (moves with the line).
- Filled `●` = clean. Hollow `○` = noisy / peek (not counting).
- Copy on the right: `above` / `below` / `noisy` / `held back`, plus `chime` when the reward sound should be eligible.

Guard:

```
  0 ────────╂──────── 100
            75
      ○ 41            quiet
```

- Tick at the warn percentile.
- Right copy: `warning` / `quiet` / `noisy`.

### 3. Hold — duration bar (long enough)

A growing fill + seconds. Reward hold resets on dip, noise, or held-back. Guard hold = how long `warningActive` has been true (0 when quiet).

Reward:

```
  in for  4.2 s   █████░░░
```

Guard:

```
  warning  0 s    ░░░░░░░░
```

Do **not** dump native ATR, mean±sd, n, or p40 in More. Those belong in the nerd sheet.

A one-line **verdict** may sit above the three readouts (exactly one): In zone / Below the line / Noisy — not counting / Held back (reward) or Warning / Quiet / Noisy (guard). Keep it short.

---

## ASCII — default (Reward + More)

```
 Muse S   72%   /‾‾\
  [ Reward ] [ Guard ] [ More ]
     on          off      on

 ATR
 100┤     ╭─╮     ╭──
    │    ╭╯ ╰ · ·╯          · dotted = invalid / peek
  40┼────────────────
    │ ╭─╯
   0┴──────────────── now
 Peek — not counting

 ████░░██··██████░░   62% in zone

  0 ────────╂──────── 100
            40
         ● 67     above     chime

  in for  4.2 s   █████░░░

              [ Pause ]    3:12 / 15:00
```

## ASCII — both graphs + More

```
  [ Reward ] [ Guard ] [ More ]
     on          on       on

 ATR                              reward
 100┤  ╭──╮    ╭─
  40┼──────────────
   0┴────────────── now
 ████░░██··██████     62% in zone
  0 ────────╂──────── 100
            40
         ● 67     above     chime
  in for  4.2 s   █████░░░

 δ / sleep                        guard
 100┤           ╭──╮
  75┼──────────────          warn
   0┴────────────── now
 ░░░░███░··░░░░░░     12% warning
  0 ────────╂──────── 100
            75
      ○ 41            quiet
  warning  0 s        ░░░░░░░░

              [ Pause ]
```

---

## Nerd sheet (keep the science icon)

Keep the existing science app-bar icon. It opens a dialog or bottom sheet. Do not show the old nerd **bubble** and this sheet at once. Feature-probe sliders stay debug/sim only.

Must visualize, not only print numbers:

1. Baseline histogram / sparkline in **native** units: pile, live triangle, threshold tick.
2. Relative band stack (δ θ α β γ) with inhibit ceilings on β / δ when the protocol has them.

Then the numbers, **each row with an (i)**. Tap (i) = short explanation of what it is, how calibration collected it, how it moves the line / chime / warning. Tiny diagram in the info, not a wall of prose.

```
┌ Nerd ─────────────────────────────────┐
│  Reward pile (ATR)                    │
│   ▁▂▃▅█▇▃▂▁                           │
│          ▲ now    ┃ release           │
│  Live ATR    1.23  (i)                │
│  p of pile    67   (i)                │
│  Threshold   1.05  (i)  from p40      │
│  Mean        0.98  (i)                │
│  Spread      0.21  (i)                │
│  Samples n    48   (i)                │
│                                       │
│  δ θ α β γ   ▓ ▓ ▓▓ ▓ ░               │
│              β ceiling if this program│
│                                       │
│  Guard pile (δ)   [only if guard on]  │
│   ▁▂▅█▃▂                              │
│        ▲ now   ┃ warn  ┃ δ ceiling    │
│  Live δ      0.11  (i)                │
│  p of rest    41   (i)                │
│  Warn thr    0.18  (i)  from p75      │
│  Mean / sd / n     (i)                │
│  Warning     off   (i)                │
│  Chime cooldown    (i)  20 s          │
└───────────────────────────────────────┘
```

(i) coverage:

| Row | Explain |
|---|---|
| Live metric | Native feature this second; sound compares this to threshold |
| p of pile | Rank in the calibration pile; this is graph Y (0–100) |
| Threshold + pN | Which pick of the pile (reward default 40, guard default 75). Dynamic target may move reward |
| Mean | Centre of the pile. Reward adapt ceiling is mean + 1.5·sd |
| Spread (sd) | How messy calibration was. Wide sd = a moving line can travel farther |
| n | Clean calibration samples. Small n = shaky line |
| Success / warning rate | Same idea as the last-minute strip |
| Guard warning + cooldown | Continuous `warningActive` vs the sparse bowl |

---

## Data

Already there (verify):

- `LiveStats`: `currentAtr`, `currentPercentile`, `threshold`, `baselinePercentile`, `baselineCount`, `baselineMean`, `baselineStddev`, `successRate` (computed, not shown today)
- `RewardLane.lastInTarget`, `lastNative`, `lastPercentile`
- `RatioEngine.percentileOf`, `isInTarget`, baseline list
- `sampleIsClean` / movement gate / pad quality
- Inhibit `TargetCondition`; relative bands
- `GuardLane`: `warningActive`, `threshold`, `lastDelta`, `lastSleepDir`, `bandMath`, rest pile, `guardrailDeltaCeiling`, `warningChimeCooldown`
- Computed 1 Hz feedback / drowsiness frames

Likely missing from `LiveStats` (add if needed, one bus): `inTarget`, `clean`, inhibit-fail reason, `thresholdPercentile`, relative band snapshot, guard live fields (`warningActive`, guard percentile, guard clean).

Hypothesis (discard if wrong): dirty play samples may still emit a reward verdict. **UI must still treat `!clean` as not counting.**

---

## Constraints

- Display + plumbing only. No new catalog protocols or features.
- Inhibit ≠ guard. Guard never flips `inTarget`.
- Crown Start remains refused. Graphs are for Muse sessions.
- Pipeline-contract frozen decisions stay frozen.
- Update `.ai/ui-map.md` spoken-name rows: Reward/Guard/More chips, graphs, three readouts, peek banner, nerd sheet.
- Tests: chip persist + default; More glues readouts to the visible graph(s); dirty/peek drawn dotted and not counted; verdict priority (noisy > held back > below > in-zone); guard chip omitted without a guard; nerd (i) rows present. Update test-matrix if that is the repo rule.
- Keep session settings and Pause / End. Do not hide them behind the graphs.

---

## Done when

- Playing/paused can show reward and/or guard graphs from small depressed chips.
- Default is Reward + More, Guard off, restored next session.
- More puts three **visually distinct** readouts under each visible graph (strip, now-rail, hold).
- Invalid/peek samples are dotted; peek freeze does not pause the session.
- Nerd sheet has piles + (i) numbers; old bubble is gone.
- You explained with ASCII and got confirmation before coding.
- Tests cover the above.

If the code disagrees with this prompt, say so in the explain step and follow the code plus the human’s ASCII.
