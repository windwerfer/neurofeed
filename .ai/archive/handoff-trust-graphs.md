# Handoff — trust graphs PR 1 + PR 2

| Field | Value |
|---|---|
| Date | 2026-09-14 |
| Spec | [trust-graphs.md](trust-graphs.md) (this file is PR 1+2 history) |
| Status | **PR 1 and PR 2 landed.** Inhibit pane follow-up landed after; live spec [../trust-graphs.md](../trust-graphs.md). |
| Do not mix | Crown Start, pipeline-contract Key Decisions, Connect UX, monitor GraphShell/Inspect, RatioEngine 80/40, `guardrailDeltaCeiling` 0.25 |

**Follow-up:** gray wash + inhibit pane replaced the held-back gray
stroke. Reward stroke stays series color. `beta high` / `delta high`
labels moved to the inhibit pane. Do not follow the PR 1 “gray stroke /
below-the-line is not gray” encoding.

---

## Landed (PR 1)

Live Reward / Guard / More chips on the feedback session. Graphs + More only
while **playing** and **paused**. Calibration hides graphs/More; chips may
still show. Guide sits under Pause/End. Science-icon nerd sheet (PR 2) replaces the bubble.

- Follow-only viewport: default **75 s**, pinch-X and Ctrl+scroll **15–300 s**,
  1 s Follow lead. Shared window. Not persisted. No Inspect, no on-screen
  zoom hint.
- Reward pane: 0–100 percentile, threshold line, dirty dotted (hold last
  clean Y), held-back gray stroke + fill (`kTrustHeldBackFill`), run labels
  (`beta high` / `delta high` / `beta · delta`; dirty `pads`/`movement` or
  ≥2 s). Blink/Jaw marks on every visible pane.
- Guard: two panes (percentile warn + native δ ceiling 0–0.5 / line 0.25).
  Held-back does not apply. One More block under both.
- Dirty plumbing: skip `recordEpoch`, skip reward `onSample`, skip guard
  `evaluateWarning`. Chime hold resets on blink/clench/pads as well as IMU.
- Live gesture ring even when persist is off; persist still gates `end()`
  metadata. Eye up/down not drawn.

Tests: `flutter analyze lib/src` clean.
`flutter test test/trust_graphs_test.dart test/trust_dirty_test.dart test/feedback_pipeline_test.dart`.

## Leftover

None in this series. Do not reopen: two guard panes, held-back gray fill,
dirty plumbing, Follow-only zoom.

## Landed (PR 2)

Science-icon sheet replaces `_NerdStatsBubble`. Native pile histogram + live
triangle + threshold tick; relative δ θ α β γ stack with inhibit ceilings;
(i) rows. Guard block only if the lane ran. Cooldown 20 s is nerd-only.
Feature probe stays debug+sim, not in the sheet.

Tests: `flutter analyze lib/src` clean.
`flutter test test/nerd_sheet_test.dart`.

## Files

New:

- `lib/src/feedback/trust/` — `trust_trace.dart`, `trust_viewport.dart`,
  `trust_chips.dart`, `trust_runs.dart`, `trust_gestures.dart`,
  `trust_pane.dart`, `trust_more.dart`, `trust_graphs.dart`
- `lib/src/charts/dashed_polyline.dart`
- `test/trust_graphs_test.dart`, `test/trust_dirty_test.dart`

Edited:

- `lib/src/feedback/reward_lane.dart` — dirty skip; last relative / inhibit
  tags / held-back
- `lib/src/feedback/guard_lane.dart` — `sampleIsClean` on `GuardTick`;
  `percentileOf`; skip `evaluateWarning` when dirty
- `lib/src/feedback/target_state.dart` — `baselineSamples` getter
- `lib/src/feedback/feedback_state.dart` — `TrustTrace`, live marks, pads
  dirty, chime on artifact
- `lib/src/settings.dart` — three chip bools
- `lib/src/views/feedback_session.dart` — chips + graphs + Guide at bottom
- `.ai/ui-map.md`, `.ai/test-matrix.md`

PR 2:

- `lib/src/feedback/trust/nerd_model.dart`, `nerd_sheet.dart`
- `test/nerd_sheet_test.dart`
- `lib/src/views/feedback_session.dart` — science icon opens sheet; bubble gone
- `lib/src/feedback/feedback_state.dart` — `rewardLane` / `guardLane` getters;
  `showNerdStats` removed
- `.ai/ui-map.md`, `.ai/test-matrix.md`

Not in this series: catalog/protocol/engine math, monitor widgets, Crown.
