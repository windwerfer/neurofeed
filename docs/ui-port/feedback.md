# UI port: Feedback screens (Flutter → egui)

Status: **plan (2026-11-11); step 1 (compact fixes) landed 2026-11-11.** Steps 2–8 wait for the decisions below.
Scope: the Feedback section. Steps: protocol overview → session setup → calibration
(including fit/signal gate) → live session → end/summary, plus the dialogs in that flow.
Disk-backed loading stays on hold.

Visual target: Flutter 0.60.0 (tag `pre-rust-port`): `lib/src/views/feedback_list.dart`,
`feedback_session.dart` (2 822 lines: setup, calibration, live and in-session dialogs),
`feedback_dashboard.dart` (end screen), `feedback/calibration_runner.dart`,
`feedback/feedback_phase.dart`, `feedback/trust/*`, `assets/protocols.json`, `assets/calibrations.json`.
We copy the look and the interaction model, not the code.

Screenshots (box, not committed): `/workspace/ui-shots/feedback/`.
Flutter = 0.60.0 AppImage (extracted) on a private Xvfb, `sim:muse-s` (pref
`enable_simulated_devices`), driven with xdotool **inside that private display only**, light theme.
Rust = debug `neurofeed-egui` via `--bridge screenshot`, `sim:muse_s`, dark theme
(Trust/Nerd toggles clicked with xdotool inside the app's own xvfb-run display).
Regular = 1280×800, compact = 400×850. All data is **simulated**, not a real headset.
Flutter's feedback screens have no landscape/immersive handling, so no landscape shots.

| Step | Flutter | Rust | Compare |
|---|---|---|---|
| Overview | `flutter-overview-{regular,compact}.png`, `-regular-scrolled`, `flutter-protocol-info-regular.png` | `rust-overview-{regular,compact}.png` | `compare-overview-regular.png` |
| Session setup | `flutter-session-setup-{regular,compact}.png`, `flutter-session-setup-calrecord-compact.png`, `flutter-dialog-target-settings-regular.png` | (part of overview) | – |
| Fit / signal gate | `flutter-calibration-waiting-regular.png` | `rust-fitcheck-{regular,compact}.png` | – |
| Calibration | `flutter-calibration-{regular,compact}.png`, `flutter-calibration-staged-{artifacts,eyesopen,eyesclosed}-compact.png` | `rust-calibration-{regular,compact}.png`, `rust-calibration-staged-regular.png` | `compare-calibration-regular.png` |
| Live | `flutter-live-{regular,compact}.png`, `flutter-live-more-regular.png`, `flutter-live-paused-regular.png`, `flutter-live-calrecord-compact.png`, `flutter-dialog-nerd-regular.png` | `rust-live-{regular,compact}.png`, `rust-live-paused-regular.png`, `rust-live-trust-regular.png`, `rust-dialog-nerd-regular.png` | `compare-live-regular.png` |
| End / summary | `flutter-summary-{regular,compact}.png`, `flutter-summary-feedback-tab-regular.png` | `rust-summary-{regular,compact}.png` | – |

## Flow model

**Flutter**: two routes. `FeedbackListView` (in the shell, sidebar/drawer + status bar)
pushes a full-screen `FeedbackSessionView` (own AppBar: back arrow, protocol title, ⚗ Nerd,
ⓘ Guide; the device status bar under it). That one page morphs by `FeedbackPhase`
(`idle → calibrating → playing ⇄ paused → interrupted → ended`). On end it pushes
`FeedbackDashboardView` (Save / Discard, tabs). Back during a session asks via `SessionBackGuard`.

**Rust**: one in-shell view (`ui/views/feedback.rs`), sidebar stays visible, switching by
`Trainer.phase` (`Idle → FitCheck → Calibrating → Playing ⇄ Paused → Ended`). Setup lives on
the overview (length chips + Start). Fit check is its own explicit step (Flutter folds it into
calibration's "Waiting for good signal"). Recording auto-starts with `feedback.start`
(decision 2026-10-29), so the top bar shows the recording's Pause/Stop during the session.

## Step 1 — Protocol overview

**Flutter** (`feedback_list.dart`): `ListView`, padding 16.
- Headline "Biofeedback Protocols" (headlineSmall).
- **Recent**: up to 3 quick-start slots (catch phrase only, centred, 2 lines) from session history,
  oldest left. (Empty on the fresh box, so not in the shots.)
- "Saved programs" label + full-width outlined **＋ Create program** (→ protocol builder).
- One full-width **card per protocol** (surfaceContainerHighest, radius 12, padding 20):
  48 px tinted square with a `psychology` icon in the protocol colour, **catch phrase bold (+1 pt)
  — title regular**, subtitle bodySmall; trailing ⓘ (info dialog: title, subtitle, algorithm,
  "Delay: …", Got it). User programs add ✎ edit and 🗑 delete (confirm "Delete program?").
- List filtered by the connected/last device kind and installed AI models (`listedFor`).
- 0.60.0 lists 7: Sleep Guard, Rest Awake, Open Monitor, Alert Eyes Open, Alert Eyes Closed,
  Concentrate, Calibrate + Record (Band Stability hidden by the filter).
- Tap a card → setup page for that protocol (no selection state on the list).
- Compact: the same list, the cards just wrap text (titles go to 2–3 lines).

**Rust** (`protocols()`): header "Choose a protocol" + calibration hint; a **3-column grid** of
fixed-height (92 px) outlined cards (title, tags experimental/custom/needs AI model, summary,
"eyes · min"), selection = teal outline; "New protocol…" (builder window); guard row;
`Length 5/10/20/30 min` + **Start <protocol>** inline. 6 protocols (incl. Band Stability; no
Concentrate, no Calibrate + Record).

Gaps:
- **broken (compact)**: grid min width 200 × 3 overflows a 400 px screen; the cards and the Start button are clipped (`rust-overview-compact.png`).
- missing: Recent quick-start row; per-card ⓘ info dialog (algorithm, expected delay); protocol colour + icon; catch-phrase — title styling; edit/delete on custom cards (builder exists, entry differs).
- missing: Concentrate and Calibrate + Record protocols (engine/catalog work, not UI only) — see decisions.
- visual-only: card layout (list vs grid), "Saved programs" section label, full-width Create button.
- different by design: selection on the overview + Start, vs Flutter's tap → setup page.

## Step 1b — Session setup (Flutter idle page)

**Flutter** idle phase of `FeedbackSessionView`:
- Trust chip row `Reward | More` (which live graphs to show; saved).
- **Session Settings** card: Background Sound (name, 🔊 volume dialog: per-layer sliders, Reset);
  Feedback Sound (`Bowl chimes • 40th percentile`, ⚙ → **Target Settings** dialog: Dynamic target switch,
  Gentle↔Responsive slider, Reward threshold percentile slider (40 % default), Dwell/Inhibit ceilings
  for some protocols, ⓘ "What do these do?"); conditional Binaural/Music tiles; Guardrail tile
  (scorer engine, warning sound, Fixed|Percentile threshold); **Duration** chips 7/15/25/45 min + Custom… dialog.
- Full-width 56 px **▶ Start Session** (skip-calibration variant when allowed; model gate text for AI guards;
  "Muse not connected — Start Session will open the connect window").
- **Guide** card (first 2 paragraphs, "Tap for full guide" → dialog).
- Dialogs on start: "Recording in progress" (stop it first), "Music folder not set", model install gate.

**Rust**: lengths 5/10/20/30 and Start on the overview; reward sound/background/volumes/music live in
Settings → Sound (`sound::show`); `threshold.set` percentile exists as a command (live control) but has
no in-flow UI; guard opt-in row on the overview; Band Stability sliders in Settings.

Gaps:
- missing: a per-protocol setup step/panel (Session Settings card, Guide card, Start button full width).
- missing: Target Settings dialog in flow (percentile slider → `threshold.set`; dynamic target/adapt speed are
  engine-fixed today → decision); volume quick dialog; custom duration; guide text per protocol.
- different: durations 5/10/20/30 vs 7/15/25/45 (+custom) → decision.
- n/a by decision: "Recording in progress" dialog (Rust auto-records and reuses a running recording).

## Step 2 — Calibration (incl. fit gate)

**Flutter**:
- Signal gate inside calibration: orange `sensors_off` icon, "Waiting for good signal…", "All electrodes
  should be green for 3 s…", Cancel / Skip (Skip only with debug+sim+last baseline). After 20 s with one
  bad pad: tertiary "faulty pad" box (tier A/B copy) + full-width **Continue** (start anyway).
- Running: `graphic_eq` icon, **stage name** (Baseline / Artifacts / Eyes open / Eyes closed), optional
  **challenge card** (hint + large text, e.g. "Count backward from 100 in steps of 7."), "Sit quietly, let your
  mind wander. 40s of clean signal left", full-width linear progress; "Playing the calibration cue…" while the
  **voice prompt** plays (opus clips, random intro variant); Cancel / Skip. Guide card stays below.
- Staged (Sleep Guard, Calibrate + Record, or "always staged"): artifacts 15 s → eyes-open counting 30 s →
  eyes-closed 45 s; each with audio. (Seen quirk: the eyes-open challenge card stays visible in the eyes-closed stage.)
- No head diagram; status bar shows the device's 4-pad signal glyph.

**Rust**:
- Separate **Fit check**: top-down head with the target pads coloured (others grey), chip "Good fit, ready to
  calibrate" / "Hold still n/3" / "Adjust the headband", per-pad hints, Calibrate / Start anyway / Reuse last
  baseline / Cancel.
- **Calibrating**: instruction line (staged: "Step 1/3 …"), progress bar "n of 45 good seconds", "n s elapsed ·
  stops at 60 s", chip Collecting / Paused — reason; Start now / Reuse last baseline / Cancel. Sleep Guard
  "No awake reference" banner.

Gaps:
- **broken (compact)**: fit check is a horizontal row (head 260 px + buttons) and overflows 400 px (`rust-fitcheck-compact.png`).
- missing: stage title + challenge card (eyes-open task text), calibration **voice prompts** (decision 2026-10-30:
  clips not ported), "playing cue" state, Guide card.
- missing: faulty-pad fallback copy (tier A/B) — Rust has "Start anyway" always visible instead (behaviour ok, copy missing).
- visual-only: big centred icon + full-width progress; Rust progress bar is a fixed 520 px.
- Rust extra to keep: explicit head diagram + Reuse last baseline (better than Flutter's debug-only Skip).
- Staged progress shows "0 of 45 good seconds" during the artifacts stage → label should be per stage (broken-ish copy).

## Step 3 — Live session

**Flutter** (playing/paused, same page):
- **Trust graphs** column on top (chips `Reward | More` toggle lanes): reward lane = percentile trace 0–100
  with the threshold line, `75s` window, feature label (BTR); "More" adds the in-zone strip ("Below the line",
  per-second blocks, "65% in zone", "in for 0 s"); guard lane when a guard runs; stability chart for Band Stability.
- Session Settings card stays (sound/feedback tiles adjustable live; duration hidden).
- Controls row: ⟳ **Recalibrate** (from last 90 s clean; snackbars if < 60 s or not enough clean data),
  filled **Pause/Resume** 160×48, ⏹ **End session** (no confirm). Below: `0:18 / 15:00`.
- **Interrupted** state: wifi_off icon, message, "Ending in 10s if not recovered…" / "Waiting for the signal to
  return — resumes automatically", End session.
- AppBar ⚗ **Nerd** bottom sheet: reward pile histogram (release/now markers), Live value, p of pile, Threshold
  (from p40), Mean, Spread, n, Success rate (each with ⓘ), band bars δ θ α β γ.
- Debug + sim: Feature probe card (slider override). Audio is the main feedback; the screen is "calm".

**Rust**:
- Header: title, "9:32 left", thin progress, Trust / Nerd toggles (right). Debug override row.
- Big **glow circle** (green in target) + vertical percentile meter with threshold tick; status chip
  (Training / In target / Held back … / Paused …), drowsiness warning chip, "last second didn't count" line;
  Pause/Resume + End session.
- Trust toggle → right column `trust::pane` (totals, Percentile|Value, plot with calibration shading, state strip, legend).
- Nerd → floating "Nerd sheet" window (pile histogram, same stats).
- Top bar additionally shows the **recording** Pause/Stop (auto-recording).

Gaps:
- **broken (compact)**: live is usable but Trust/Nerd crowd the header; with Trust on, pane stacks under a circle sized for the full height.
- missing: Recalibrate button + command (the engine already has `Engine::recalibrate_from_recent`; legacy rule: last 90 s clean, min 60 s played / 30 samples);
  elapsed/total readout `0:18 / 15:00` (Rust shows time left only); live sound/target tiles in session;
  Interrupted screen (Rust shows "Paused – device disconnected" chip; grace countdown text missing); band bars in Nerd.
- different by design: Rust's glow circle + meter vs Flutter's graphs-first page; keep the circle (calm), make the
  Trust pane default-on in regular? → decision.
- **confusing**: two Pause buttons (recording Pause in the top bar = `stream.pause`, freezes views only; session Pause =
  `feedback.pause`). Respect Pause semantics decision; hide/disable the recording Pause while a feedback session owns the recording.
- visual-only: chip-row lane toggles instead of a single Trust toggle; in-zone strip styling.

## Step 4 — End / summary

**Flutter** `FeedbackDashboardView`: AppBar "<title> — Session", **Save | Discard** (unsaved-notes dialog on leave);
segmented tabs **Dashboard | Feedback | Bands | Raw EEG | Histogram | PSD | Spectrogram | HR+SpO2 | Movement**
(scrolls on compact). Dashboard: one stat line (`0:37 · 68% in zone · 44% good · 100% still · Peak α 10.0 Hz ·
72 bpm · SpO₂ 89% · 2 chimes`), "› More" expander, Notes field; music tracks and gesture markers sections when present.
Feedback tab: trust graph over the whole session + "68% in zone · 2 chimes · 0% inhibited".
Opening a protocol while `ended` returns to this dashboard.

**Rust** `summary()`: "Session complete · ended: stopped", 5 big stats (In zone, Clean, Held back, Trained, Rewards),
trust pane (Percentile|Value), threshold line text, Notes (Save/Revert, 0/4000), Train again / Choose protocol / Open History.
Auto-saved (top-bar "Discard last recording" per decision).

Gaps:
- **broken (compact)**: stat row and trust pane overflow 400 px horizontally (`rust-summary-compact.png`).
- missing: per-session monitor tabs (Bands/Raw/…/HR+SpO2/Movement over the recorded session) — reuse the monitor
  views in replay/Inspect mode; HR, SpO₂, still %, peak α in the stat line.
- by decision: Save/Discard modal replaced by auto-save + discard protection; keep that, but offer **Discard** on the summary
  itself (same protected command) so it is where Flutter users look.

## Shared widgets to reuse

- **Monitor toolbar / viewport** (`Follow | Inspect`, window menu): for the live trust graph (75 s Follow, drag → Inspect)
  and the summary's Feedback tab.
- **Graphs**: `trust::pane` already shared by live, summary and History; the summary monitor tabs should reuse
  Bands/Raw/Histogram/PSD/Spectrogram/HR views against the saved session (History detail already does part of this).
- **Overview minimap** (`ui/overview.rs`) for whole-session navigation on the summary Feedback tab.
- **Channel exclusion**: the fit check head diagram should grey out globally excluded pads and the reward must use the
  same exclusion (analysis-exclusion contract); show "excluded" instead of "bad".
- **Safe area** (`ui::show_with`) and **graph-only landscape**: phone landscape during a live session could show only the
  circle/trust graph full screen (like monitors), with Pause/End as in-graph controls.
- `layout::current().is_compact()` everywhere a row/grid is used today.

## Compact vs regular

- Regular: keep sidebar; overview as a 2–3 column grid is fine, but card content should follow Flutter (icon, catch phrase).
  Live: circle left, trust pane right (already), setup card to the right of the protocol list.
- Compact: single-column list of cards; setup becomes its own page (back arrow), like Flutter; fit check stacks head above
  buttons; calibration and live are single column with full-width buttons; summary stats wrap 2–3 per row, tabs scroll.
- Landscape phone: graph-only live view (new), others as compact.

## MCP / CLI implications

- Existing: `protocol.list/get/set/draft/save/delete`, `feedback.start/stop/pause/resume/status/result.get/trust/nerd/override`,
  `calibration.start/skip/reuse`, `threshold.set`, `guard.set`, `stability.set`, audio commands, `history.*`.
- New if adopted: `feedback.recalibrate` (enabled ≥ 60 s played, reason otherwise); `feedback.status` adds `stage`
  (`artifacts|eyes_open|eyes_closed|baseline`), `challenge` text and `elapsed_s` so agents/UI show the same copy;
  `protocol.info` (or fields in `protocol.get`): guide text, algorithm, expected delay, colour; durations list.
- A dedicated setup step in the UI needs **no** new command (it composes `protocol.set` + `threshold.set` + audio).
- Summary Discard reuses the existing protected discard command (no new unprotected path).
- Every new control documented in `docs/automation.md` + i18n (en/de).

## Progress

- **Step 1 done (2026-11-11)**: compact (≤ phone width, tested at 400 and 360 px) only; regular unchanged.
  Non-live phases scroll vertically; overview = one full-width card column, lengths wrap, Start full width
  below; fit check = head (scaled to width) above status/buttons, button rows wrap; calibration progress
  full width; live header splits into title/time + progress/toggles; summary/trust totals = 3-column grid,
  trust caption drops its parenthetical when the plot is narrow; button rows wrap.
  Tests: `feedback::compact_tests` (no text off-screen at 400/360 for overview, fit check, live, summary;
  regular keeps three columns), `trust::caption_tests`. After shots: `rust-*-compact-fixed{,-360}.png`,
  `compare-overview-compact.png`.

## Ordered plan (rough effort)

1. **Compact fixes** (overview single column, fit check stacked, summary wrap, header) — S, 0.5 d. Pure layout.
2. **Overview cards à la Flutter** (colour + icon, catch phrase — title, ⓘ info dialog, Recent row from History) — M, 1 d.
   Needs protocol colour/catch phrase/guide/algorithm/delay in the Rust catalog (copy from `protocols.json`).
3. **Setup panel/page** (Session Settings card: background + feedback sound with volume dialog, Target Settings dialog
   with percentile → `threshold.set`, duration chips, Guide card, full-width Start) — M, 1–1.5 d.
4. **Calibration screen** (stage title, challenge card, per-stage progress copy, faulty-pad copy, guide card; keep head
   diagram + reuse) — M, 1 d. Voice prompts optional (+0.5–1 d: port opus→ogg clips, play via `nf-audio`) → decision.
5. **Live session** (elapsed/total, Recalibrate + `feedback.recalibrate`, interrupted/grace text, Trust lanes default per
   decision, hide recording Pause during feedback, Nerd band bars) — M/L, 1.5–2 d.
6. **Summary** (stat line incl. HR/SpO₂/still/peak α, Discard button, Feedback tab with Follow/Inspect + overview,
   monitor tabs over the saved session) — L, 2–3 d (tabs reuse History/monitor views).
7. **Graph-only landscape live view** + safe area check on Android — S/M, 0.5–1 d.
8. Missing protocols (Concentrate, Calibrate + Record) — M each, engine + catalog + golden tests; only if decided.

Each step: tests for new commands/state, fmt/clippy/workspace tests/wasm/Android check, bridge screenshots
regular + compact, docs/i18n.

## Decisions for the user

1. **Flow shape**: keep Rust's in-shell single view with selection + Start on the overview (regular), and add a separate setup
   page only on compact — or copy Flutter fully (tap card → full-screen setup/session page with back arrow) on both?
2. **Live screen emphasis**: keep the calm glow circle as the main element with the trust graph as an option (today), or make
   the Flutter-style trust graphs default-on (circle smaller/side)?
3. **Durations**: Flutter 7/15/25/45 min + Custom, or Rust 5/10/20/30?
4. **Calibration voice prompts + challenge text**: port the opus clips (re-encode to ogg) and challenge texts, or text-only?
5. **Missing protocols**: port Concentrate and Calibrate + Record now, later, or drop them? (Band Stability stays as in Rust.)
