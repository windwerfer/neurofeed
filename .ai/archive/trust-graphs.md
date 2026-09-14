# Live reward/guard trust graphs

| Field | Value |
|---|---|
| **Status** | Spec frozen. **PR 1 and PR 2 landed.** |
| **Date** | 2026-09-14 |
| **Branch** | `refactor/monitor` (do not branch from `main`) |
| **Origin** | `.ai/archive/trust-graph-agent-prompt.md` plus the 2026-09-14 design thread |
| **Do not mix** | Pipeline-contract Key Decisions, Crown Start, Connect UX, v5 header, monitor GraphShell/Inspect, RatioEngine 80/40 / default p40, guard `percentileWarn` / `guardrailDeltaCeiling` 0.25, catalog protocols |

Display + plumbing. No new catalog rows or features.

**This series is two PRs.** The coding thread that reads this file does **PR 1 only**, then commits, writes the handoff, and prints the paste prompt at the bottom. Do not start PR 2 in the same thread.

---

## STOP — PR 1 agent

1. Read this file and the live files it names. Do not reopen dropped ideas (peek detector, peek banner, Inspect, extra ceiling tick *on* the percentile graph, 4th More “δ ceiling” meter).
2. Implement **PR 1 only** (scope below).
3. `flutter analyze lib/src` clean. Add tests listed under PR 1. Update `.ai/ui-map.md` and `.ai/test-matrix.md` in the same change.
4. **Commit** on this branch (human asked). Do not push / open a GitHub PR unless asked.
5. Write [handoff-trust-graphs.md](handoff-trust-graphs.md) (landed / leftover / files).
6. Print the **PR 2 paste prompt** at the bottom of this file. Stop.

---

## Product (as agreed)

During play/pause the session shows glanceable **reward** and **guard** graphs so the user can see: should I hear a sound, is inhibit blocking, is the sample dirty, which guard tripwire is up.

No peek detector. Hardware cannot do eyelids. **Dirty** (movement, blink/clench artifact, unusable gate pads) is the only special sample class besides inhibit **held back**.

---

## Chrome

Under the status bar, one `ToggleButtons` row, ~28 px, same language as Bands electrode chips (`lib/src/monitor/electrode_toggles.dart`). Depressed = on. No Hide button.

```
 [ Reward ] [ Guard ] [ More ]
    on          off      on      <- default if never set
```

- **Reward** — reward graph + (if More) its three readouts. **Omit the chip** when the protocol has no reward (`recordOnly`, `guardrailOnly`).
- **Guard** — two guard panes + (if More) one combined readout block. **Omit the chip** when the guard lane is not running: protocol has no guard (`alertnessOpen`, `recordOnly`), **or** the user set guard to `none` in Session Settings.
- **More** — readouts under the visible lane(s).
- `guardrailOnly`: omit Reward, default **Guard on**, More on.
- `recordOnly`: omit both graph chips (More alone is pointless — hide the whole row).
- Persist three bools in `Settings` (SharedPreferences). Restore next session.

Chips may render while idle/calibrating; **graphs and More render only in playing and paused**. Calibration: hide graphs and More.

---

## Layout (`feedback_session.dart`)

```
 status bar
 [ Reward ] [ Guard ] [ More ]
 graphs + More
 Session Settings
 [ Pause / Resume / End ]    3:12 / 15:00
 Guide                         <- bottom, under the buttons
```

Keep Session Settings and Pause/End visible. Do not hide them behind graphs. Feature probe stays debug + simulator, below settings is fine.

Science icon opens the nerd sheet (PR 2). Old bubble is gone.

---

## Viewport (both lanes)

- **Follow only.** Newest at the right. No Inspect, no pan into the past, no Follow/Inspect chrome.
- Default window **75 s**. Pinch-X and **Ctrl+scroll** zoom **15 s–5 min** (300 s). Shared window if both lanes are on. Not persisted. **No on-screen hint** for Ctrl+scroll.
- **Smooth scroll** like Bands: 1 s Follow lead + vsync ticker so 1 Hz samples slide (`ViewportController.bandsFollowLeadSeconds` pattern). Do **not** use `ViewportController` itself — `pinchX` there forces Inspect.
- New tiny controller under `lib/src/feedback/trust/` (Follow, `windowSeconds`, lead, pinch, pointer-scroll). Isolate paints (`RepaintBoundary` / `ListenableBuilder`). Do not rebuild the session scaffold on every tick.

---

## Do not reuse monitor graph widgets

Do **not** mount `TimeSeriesPane`, `GraphShell`, `BandCache`, or `ViewportController`.

New painters under `lib/src/feedback/trust/`.

May copy: `ToggleButtons` chip metrics; `buildSmoothPath` (`lib/src/charts/smooth_path.dart`); a small dashed-polyline helper (copy or lift to `lib/src/charts/` — do not couple to `overshoot_hold.dart` semantics; that dash means Y overshoot, not dirty).

---

## Reward graph (one pane)

Y = **0–100 percentile of this session’s reward pile** (`RatioEngine.percentileOf`). Label catalog `shortLabel` (`ATR` / `TAR` / `BTR` / `α`). Never “% calm”.

Horizontal line at `percentileOf(current threshold)` (moves with slider / EMA).

| Sample | Stroke | Fill | Counts as |
|---|---|---|---|
| Clean, above line, inhibit pass | solid, series color | none | in zone |
| Clean, below line | solid, series color | none | below |
| Clean, above line, inhibit fail | **gray solid** | **gray band** behind that x-span | held back |
| Dirty | dotted, hold last clean Y | none | noisy (not a hit or miss) |

Held-back fill: vertical band over the plot area for that time run (not the whole canvas). Opacity ~0.08–0.12 of `onSurface` (tune to theme). Stroke in that run is gray too. One const at the top of the painter:

```dart
const bool kTrustHeldBackFill = true;
```

Set `false` if the fill is too noisy — labels and gray stroke stay.

**Run labels** (text at the **start** of a stretch, scrolls with Follow):

- Held back: `beta high` / `delta high` / `beta · delta` (ceilings are **high**, never “too low”).
- Dirty runs: `pads` > `movement` > `jaw` > `blink` — **only** for `pads` and `movement`, or a dirty run ≥ 2 s. Isolated 1 s blink dirty = dotted, **no** text (Now already says `noisy`).

**Event marks** (intentional bookmarks, both visible lanes): vertical line + short label `Blink` / `Jaw`. See Gestures.

### Reward More (three distinct widgets, glued under the reward pane)

1. **Last 75 s strip** (engine window, not “last minute”). Glyphs from the first sample (no warming-up gate). Colored `█` in zone, gray `█` or `▒` held back, `░` below, `·` noisy. Percent = in-zone / counted seconds so far (exclude noisy).
2. **Now rail + needle** (required; not a bar copy of the strip). Tick at live release percentile. `●` clean, `○` dirty. Copy: `above` / `below` / `noisy` / `held back`, plus `chime` only when the bowl is eligible (clean, in zone, inhibit pass).
3. **Hold** — seconds in zone. Resets on dip, dirty, or held-back.

One verdict line above the three: `In zone` / `Below the line` / `Noisy — not counting` / `Held back`. Priority: noisy > held back > below > in zone.

---

## Guard — two panes, one More block

Two tripwires, OR’d (`percentileWarnOver` in `guard_lane.dart`). Not two drowsiness models.

| Pane | Y | Line | Over means |
|---|---|---|---|
| **1 Warn** | 0–100 percentile of the guard feature (`δ` or `AI sleep`) vs rest pile | p75 (live `percentileOf(threshold)`) | personal warn |
| **2 δ ceiling** | native frontal AF7/AF8 δ | `guardrailDeltaCeiling` **0.25** | hard rail |

Pane 2 Y domain: fixed **0–0.5** so 0.25 sits mid-scale. If live > 0.5, clamp the stroke and still show the numeric. Dirty: dotted, hold last clean native Y. Held-back does **not** apply to guard.

Why two panes: on AI, pane 1 is sleep-dir and pane 2 is δ — one axis cannot tell you what fired. On band-math both are δ but percentile vs native + different lines; still not a duplicate.

**More once**, below **both** panes (not per pane, not a 4th ceiling meter — pane 2 *is* that meter):

- Strip 75 s: `█` warning / `░` quiet / `·` noisy (combined `warningActive`).
- Now rail: tick at p75 of pane 1’s scale is optional here; prefer copy `warning` / `quiet` / `noisy` plus which tripwire: `warn` / `ceiling` / `both` when warning.
- Hold: seconds `warningActive` has been true (0 when quiet).

Verdict: `Warning` / `Quiet` / `Noisy`. Graph follows continuous `warningActive`, **not** the 20 s chime cooldown (cooldown stays nerd / PR 2).

---

## Dirty plumbing (PR 1)

Dirty ⇔ `!_sampleIsClean` **or** gate pads unusable (relative bands `null`). `_sampleIsClean` is already movement score > `movementGateThreshold` (0.05) or any blink/clench, sticky `movementBuffer` (1 s).

On dirty:

| Path | Behavior |
|---|---|
| Graph | dotted, hold last clean Y; not a hit and not a miss |
| `recordEpoch` | skip |
| EMA / adapt | skip (already) |
| Rain / music / binaural | **do not** `onSample` — hold last clean level |
| Chime | dirty does not count toward 2.5 s hold and does not fire. Same idea as `_audio.onMovement()` (extend to blink/clench/pads, not only IMU) |
| Guard | skip `evaluateWarning` — do not start, clear, or chime from that sample. Hold last `warningActive` |

Inhibit fail is **not** dirty. Live `onSample` with `inTarget: false`. Gray band on the reward graph.

---

## Gestures (already implemented)

Rust 1 Hz (`rust/src/analysis/gesture.rs`): frontal blink-like transients, posterior clench. Dart (`feedback_state.dart` `_onGestures`):

- **Blink mark** — `blinkCount >= 2` in one second, or two singles within 2 s. Enum stays `GestureType.doubleBlink`. Plot/spoken: `Blink` / **Blink mark**.
- **Jaw mark** — two clench onsets within 2 s. Enum `doubleClench`. Plot/spoken: `Jaw` / **Jaw mark**.

These are **bookmarks**, not peek. Eyes-closed lid squeezes still count.

Settings → Gesture markers: persist switch only affects save. Detection always runs. **Today** persist-off `return`s before filling `_gestureMarkers`. PR 1: keep a **live ring** for the visible window even when persist is off; persist still gates `end()` metadata.

Draw `Blink` / `Jaw` vertical + label on every visible trust pane. Do **not** draw eye up/down on the live graph.

A mark second is also dirty (artifact) — dotted + event line is correct.

---

## Data bus

Do not use `LiveStats`’s 2 s native average as graph Y. New `ChangeNotifier` under `trust/` (~1 Hz ring, cap ≥ 5 min).

Each sample:

- `t` elapsed seconds
- reward: native, percentile, thresholdPercentile, `inTarget`, `heldBack`, inhibit tags (`beta` / `delta`), `clean`, dirty reason (`movement` / `blink` / `jaw` / `pads`)
- guard: feature percentile, `warningActive`, `warnOver`, `ceilingOver`, `lastDelta` native, `clean`

Expose a copy of `RatioEngine` baseline list for PR 2 nerd (getter only, no math change). `GuardLane.baselineSleepDir` is already public. Add `GuardLane.percentileOf`, `sampleIsClean` on `GuardTick`.

`RewardLane`: last relative bands, which inhibit failed, skip dirty output as above.

---

## PR map

| PR | Scope | Depends |
|---|---|---|
| **1** | Plumbing + chips + layout + reward graph/More + guard two panes/More + dirty/held-back/marks + tests + ui-map | — |
| **2** | Nerd sheet replaces bubble (piles, band stack, (i) rows). Old bubble gone. | 1 |

### PR 1 — do this thread

Files (expected, names flexible):

- New: `lib/src/feedback/trust/` (`trust_trace.dart`, `trust_viewport.dart`, `trust_pane.dart`, `trust_chips.dart`, `trust_more.dart`, painters/labels)
- Edit: `reward_lane.dart`, `guard_lane.dart`, `target_state.dart` (baseline getter), `feedback_state.dart`, `settings.dart`, `feedback_session.dart`
- Docs: `.ai/ui-map.md` (session rows), `.ai/test-matrix.md`
- Tests: see below

Not in PR 1: nerd sheet, deleting `_NerdStatsBubble`, catalog/protocol/engine math, monitor widgets, Crown.

### PR 1 tests (pure Dart)

- Chip persist + defaults (Reward on, Guard off, More on); omit Reward without a reward lane; omit Guard without a live guard; `guardrailOnly` defaults Guard on; `recordOnly` hides the row.
- Dirty: dotted, not `recordEpoch`, rain/music percentile held, chime hold not advanced, guard `evaluateWarning` skipped.
- Held back: gray fill+stroke when above line + inhibit fail; label `beta high`; below-the-line is **not** gray; `kTrustHeldBackFill` gates the fill.
- Verdict priority noisy > held back > below > in zone.
- More glued to the visible lane(s); guard More is one block under both panes.
- Viewport: default 75 s, clamp 15–300, pinch and Ctrl+scroll stay Follow (right edge = now).
- Blink/Jaw marks appear on the live ring even if persist is off.
- Calibration phase: graphs/More not built.

### PR 2 — next thread only

Science icon opens a dialog/sheet. Bubble gone. Native pile histogram + live triangle + threshold tick; relative δ θ α β γ stack with inhibit ceilings; rows with (i). Guard block only if the lane ran. Cooldown 20 s is nerd-only. Feature probe stays debug+sim, not in the sheet.

---

## ASCII — default (Reward + More)

```
 Muse S   72%   /‾‾\
  [ Reward ] [ Guard ] [ More ]
     on          off      on

 ATR                                         75s
 100┤     ╭─╮  ┌ gray ┐  ╭──
    │    ╭╯ ╰  │beta  │ · ·╯     · dotted = dirty
  40┼──────────│ high │────────
    │ ╭─╯      └──────┘
   0┴──────│──────────────── now
           Blink

 ███▒▒██··██░     54% in zone
  0 ────────╂──────── 100
            40
         ● 67     held back
  in for  0 s     ░░░░░░░░

 Session Settings …
              [ Pause ]    3:12 / 15:00
 ┌ Guide ─────────────────────────┐
 └────────────────────────────────┘
```

## ASCII — Guard on + More

```
  [ Reward ] [ Guard ] [ More ]
     off         on       on

 δ                                          warn
 100┤           ╭──╮
  75┼──────────────
   0┴────────────── now

 δ ceiling                                  0.25
 0.50┤
 0.25┼──────────────
 0.00┴────────────── now

 ░░░░███░··░░░░░░     12% warning
  0 ────────╂──────── 100
      ● 41            quiet
  warning  0 s        ░░░░░░░░

              [ Pause ]
 ┌ Guide …
```

---

## Frozen / do not

- Peek detector, peek banner, peek freeze, “Peek — not counting”.
- Inspect / pan / GraphShell Follow chrome / window dropdown.
- UI copy that explains Ctrl+scroll.
- Gray-out of **below-the-line** reward (only held-back runs).
- Dual-Y one-pane guard; extra ceiling tick on the percentile pane; 4th More δ-ceiling widget.
- Eye up/down on the live graph.
- RatioEngine 80/40, p40, EMA formula, `guardrailDeltaCeiling` value, catalog JSON.
- `TimeSeriesPane` / `BandCache` as the session plot.
- Crown Start.

---

## After PR 1

1. Commit (explicitly requested). Suggested subject: `feat(feedback): live reward/guard trust graphs`.
2. Write `.ai/TODO/handoff-trust-graphs.md`: what landed, tests, leftover PR 2, file list.
3. Print this paste prompt and **stop**:

```
Implement PR 2 of `.ai/TODO/trust-graphs.md` (nerd sheet).
PR 1 is committed on this branch. Read `.ai/TODO/handoff-trust-graphs.md` and the spec. Do not reopen PR 1 graph decisions (two guard panes, held-back gray fill, dirty plumbing, Follow-only zoom). Replace the science-icon nerd bubble with the sheet (piles, band stack, (i) rows). Update ui-map + tests. flutter analyze lib/src clean. Commit when done. Do not start other queued work.
```
