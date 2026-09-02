# Handoff — start PR 6 (calibration compose)

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Branch | `refactor/eeg_feature_implementation` (do not push unless asked) |
| Thought level | Contract frozen on xhigh. Implementation was high. Do not reopen Key Decisions. |
| Status | **PR 1 + PR 2 + PR 3 + PR 4 + PR 5 committed. Start PR 6. Do not start PR 7.** |

Read this file, then [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md). Key Decisions 1–19 and the 7-PR plan are the law. Do not re-design the pipeline.

---

## What this project is doing

Muse ML: Flutter UI + Rust BLE (`muse-rs` / btleplug) + on-device LUNA/REVE. The **feedback** stack is being restructured so catalog programs and later custom “bookmarks” share one pipeline:

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane / Background / Orchestrator
```

**Inhibit ≠ guard.** Background ≠ reward output ≠ guard output. JSON names IDs; Rust owns `(device, feature)` electrodes.

**Crown this series:** registry **produces** `device.focus` / `device.calm` and **can compute** `band.*`. Catalog **lists** band protocols when the selected kind is Crown. **Running** a catalog session on Crown is **out of scope**. **Crown Start stays refused in PR 6.**

Frozen spec: [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md).

PR order: **1 contract (done) → 2 feature bus (done) → 3 protocol documents (done) → 4 notifier split (done) → 5 audio outputs (done) → 6 calibration compose (this) → 7 custom builder last.**

---

## PR 6 scope (from the contract)

`feat(feedback): compose calibration stages from subscribed features`

**Deps:** PR 4 (audio split in PR 5 is already landed; do not reopen it).

Replace the boolean `useStaged` (“any `ai.*` enabled”) with the frozen compose table. Keep existing clips in `assets/calibrations.json` v2. Do not implement the custom builder (PR 7). Do not change v5 layout, SQLite schema, BLE, `DeviceConfig` FFI fields, or SoLoud engine internals. Do not unlock Crown sessions. Do not edit `session_chart_data.dart` `electrodeAf7` chart logic.

### Do

- Implement the compose table. Let `S` = features actually **enabled for this session** (reward.feature if the reward lane is present; guard.feature only when the guard is **on** — same set `_enableSessionFeatures` already sends to `set_enabled_features`):

| Condition | Stages |
|---|---|
| `S` empty (`recordOnly`) | skippable; if not skipped, `single` baseline only |
| any `ai.*` in `S` | `staged`: artifact + challenge (clear anchor) + baseline (rest / V_sleep + reward baseline) |
| else any lane present (band reward and/or `band.delta` guard) | `single` baseline only |

- `guardrailOnly` + AI model → all three stages. `guardrailOnly` + band-math → baseline only.
- `CalibrationManifest.recipeFor(protocolName, useStaged:)` becomes `recipeFor(calibrationId, {required CalibrationPlan plan})` where `plan` is `{artifact, challenge, baseline}` booleans.
- Eyes-open vs closed for the baseline still comes from the calibration id (`eyes-open-01` vs `eyes-closed-01`).
- Clip files stay those in `calibrations.json`. Do **not** retune 15 s → 12 s in the contract; PR 6 **may** adjust seconds. Adaptive 45 vs 60 s baseline is a **PR 6 recipe detail**, not JSON.
- Keep `skipCalibration` for `recordOnly` (“Start (skip calibration)” → `startCalibration(skipCalibration:)` goes straight to playing).
- Crown Start stays refused (`startCalibration` early return + `_refuseCrownStart` dialog).

### Do not

- Custom builder UI (PR 7).
- Unlock Crown Start.
- Change v5 body / computed columnar layout / SQLite schema / BLE / `DeviceConfig` FFI fields.
- Add fields to `FeatureDto`.
- Re-split audio outputs / reopen `FeedbackMode`.
- Leave AI scoring running in the live view (`set_enabled_features([])` at session end already landed).
- “Fix” the `guardrailDeltaCeiling` comment/code unit mismatch.
- Edit `session_chart_data.dart` `electrodeAf7`.

---

## Already landed (do not redo)

| Piece | Where | Notes |
|---|---|---|
| Contract | `.ai/feeback/pipeline-contract.md` | PR 1. Frozen. |
| Registry + FFI | `rust/src/api/features.rs` | 8 v1 IDs. Default enable set empty. |
| Protocol documents | `assets/protocols.json` v4, `assets/features.json` | String ids. `muffleReward` on `ProtocolGuard`. |
| Settings guard | `lib/src/settings.dart` | `guardFeatureFor` / `guardModel`. `feedback_mode` now stores `RewardOutputId` names. |
| List + Crown refuse | `feedback_list.dart`, `feedback_session.dart` `_refuseCrownStart`, `feedback_state.dart` `startCalibration` | Keep the refuse. |
| FeatureBus / lanes | `feature_bus.dart`, `reward_lane.dart`, `guard_lane.dart` | RewardLane calls `RewardOutput.onSample`; GuardLane calls `GuardOutput.onGuard` + `RewardOutput.setMuffle`. |
| Audio outputs (PR 5) | `lib/src/audio/{output_ids,reward_output,guard_output}.dart`, `audio_service.dart` | `RewardOutputId` / `GuardOutput` / unmapped `BackgroundKind`. Rain/music suppress background. Catalog `reward.output` / `guard.output` live. |
| CalibrationRunner | `lib/src/feedback/calibration_runner.dart` | Same clips. **`useStaged` is still “any `ai.*` enabled” — this PR replaces that.** |
| Orchestrator | `lib/src/feedback/feedback_state.dart` | `_stagedCalibrationIntent` + `_enableSessionFeatures`. Timer, pause, record, signal gate. |
| Tests | `test/feedback_pipeline_test.dart`, `test/output_ids_test.dart` | FeatureBus, gate electrodes, 75 s window, RewardLane `onSample`, GuardLane `onGuard`, output-id migrate. |

`features.rs` tests share process-global registry state; they take `TEST_LOCK` in `reset()`. Do not drop that.

Last commits: `f0f917c` PR 1, `43b42e5` PR 2, `00850db` PR 3, `83df86d` PR 4, `98097d7` PR 5.

---

## Resume here (current pointers)

| What | Where |
|---|---|
| Boolean `useStaged` (replace) | `calibration_clips.dart` `CalibrationManifest.recipeFor` ~239 |
| `Calibration.variant(bool useStaged)` | `calibration_clips.dart` ~176 |
| `_stagedCalibrationIntent` (AI model ready, not band-math) | `feedback_state.dart` ~512 |
| `_guardrailIntent` (guard on, including band-math) | `feedback_state.dart` ~497 |
| `_enableSessionFeatures` — this is `S` | `feedback_state.dart` ~523 (`ids` / `unique` → `setEnabledFeatures`) |
| `CalibrationRunner.playAndBaseline({required bool useStaged})` | `calibration_runner.dart` ~107 |
| Call sites | `feedback_state.dart` ~783 (after gate), ~905 (`startAnyway`) |
| `skipCalibration` early path | `feedback_state.dart` `startCalibration` ~431 / ~484 |
| Clip library (keep files) | `assets/calibrations.json` v2: `eyes-closed-01` / `eyes-open-01`; staged stages `reve-artifacts` 15 s, `reve-eyes-open-counting` 30 s, `reve-eyes-closed-drifting` 45 s; `single` baseline 50 s |
| Recipe tests (must grow) | `test/calibration_assets_test.dart` ~107 (`recipe selection: AI guardrail → staged, otherwise single`) |
| Crown refuse (keep) | `startCalibration` ~437; `_refuseCrownStart` `feedback_session.dart` ~2152 |

Today `_stagedCalibrationIntent` is **not** “any `ai.*` in `S`”: it is “guardrail enabled **and** AI model ready **and not** band-math”. Band-math uses `single`. `recordOnly` has no guard / no reward, so `S` is empty and `useStaged` is false — `single` if the user does not skip. PR 6 should drive the plan from the **enabled set**, not from the model-ready boolean alone (a disabled AI guard must not pull in staged clips).

---

## Output ids (already frozen — do not invent names)

**RewardOutputId:** `chime`, `musicFilter`, `rainStage`, `binauralSwell`, `none`.

**GuardOutputId:** `softBowl`, `chime`, `cough`, `alarm`, `none` — same strings as `GuardrailSound.name`. Do **not** rename stored id `chime` to `highChime`.

**BackgroundKind:** `drone`, `droneLoop`, `rain`, `userMusic`, `binaural`, `none`. Unmapped. Not an output method.

---

## ReveDto trap (still open — not this PR)

`FeatureDto.value` for `ai.drowsiness` is **`sleep_dir` only**. Computed-frame `guardrail.clarity` still comes from `ReveDto` via `GuardLane.onReveExtras`. Do **not** add fields to `FeatureDto`. Do **not** remove `MuseEventDto::Reve` in PR 6.

---

## Crown vs “working” (do not reopen)

This series does **not** unlock Crown sessions. Gate electrodes / quality length / computed frames / charts stay Muse-4-ch. Do not change `DeviceConfig` FFI fields.

---

## Do not reopen

See contract Key Decisions. Highlights for this PR:

- Inhibit ≠ guard. Guard never changes the reward scalar or `inTarget`.
- Background ≠ reward output ≠ guard output (already split in PR 5).
- `muffleReward` already landed; not a GuardOutputId.
- `epochWindowSeconds = 75`, `adaptIntervalSeconds = 30`.
- `percentileWarn` preserves absolute `_lastDelta` vs 0.25.
- `guardrailEngine` metadata stays `drowsinessMath` / `drowsinessLunaLarge` / … (not `bandMath` / `luna_base`).
- Calibration compose is **this PR**. Until now `useStaged` = “any `ai.*` enabled”.
- Charts may keep `electrodeAf7` (non-goal).
- Missing sample = no sample, not 0.
- Crown Start stays refused.

---

## Verify before calling PR 6 done

- `flutter analyze lib/src` (pre-existing infos/warnings in `session_recorder.dart`, `connect_window.dart`, `computed_sampler.dart` are OK; no new errors).
- Compose table matches the contract: `recordOnly` skippable / else single; AI in `S` → three staged clips; band-only → single baseline; `guardrailOnly` + AI → staged; `guardrailOnly` + band-math → single.
- Existing clip files still play; do not drop `reve-artifacts` / challenge / rest assets from the bundle (`test/calibration_assets_test.dart` bundling guard).
- Crown Start still refused.
- `test/calibration_assets_test.dart` and `test/feedback_pipeline_test.dart` still green; grow the recipe-selection test to the plan, not the boolean.
- Do not commit unless asked.

---

## First prompt for the new thread

> Continue from `.ai/feeback/handoff-pr6.md`. Frozen contract: `.ai/feeback/pipeline-contract.md`. Implement PR 6 only (`feat(feedback): compose calibration stages from subscribed features`). Replace `useStaged` with `CalibrationPlan` `{artifact, challenge, baseline}` from the enabled feature set `S`. Keep existing clips. Crown Start stays refused. Do not start PR 7. Do not reopen Key Decisions. Do not commit unless I ask.
