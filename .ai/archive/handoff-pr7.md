# Handoff — start PR 7 (custom protocol builder)

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Branch | `refactor/eeg_feature_implementation` (do not push unless asked) |
| Thought level | Contract frozen on xhigh. Implementation was high. Do not reopen Key Decisions. |
| Status | **PR 1–6 committed. Start PR 7 (last).** |

Read this file, then [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md). Key Decisions 1–19 and the 7-PR plan are the law. Do not re-design the pipeline.

---

## What this project is doing

Muse ML: Flutter UI + Rust BLE (`muse-rs` / btleplug) + on-device LUNA/REVE. The **feedback** stack is being restructured so catalog programs and later custom “bookmarks” share one pipeline:

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane / Background / Orchestrator
```

**Inhibit ≠ guard.** Background ≠ reward output ≠ guard output. JSON names IDs; Rust owns `(device, feature)` electrodes.

**Crown this series:** registry **produces** `device.focus` / `device.calm` and **can compute** `band.*`. Catalog **lists** band protocols when the selected kind is Crown. **Running** a catalog session on Crown is **out of scope**. **Crown Start stays refused in PR 7.**

Frozen spec: [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md).

PR order: **1 contract (done) → 2 feature bus (done) → 3 protocol documents (done) → 4 notifier split (done) → 5 audio outputs (done) → 6 calibration compose (done) → 7 custom builder last (this).**

---

## PR 7 scope (from the contract)

`feat(feedback): custom protocol builder`

**Deps:** PR 3–6 (a catalog protocol **and** a hand-built JSON protocol must already run the same path **on Muse**).

A **form over the document**. Not a visual patcher (rejected alternative 2). Catalog and user documents are the same type (`origin: catalog | user`). UI may say "Programs"; the type is protocol.

Do not change v5 layout, SQLite schema, BLE, `DeviceConfig` FFI fields, or SoLoud engine internals. Do not unlock Crown sessions. Do not edit `session_chart_data.dart` `electrodeAf7` chart logic. Do not reopen Key Decisions.

### Do

- New view under `lib/src/views/` — a form that writes a `ProtocolDocument`:
  - Feature dropdowns from `available_features(kind)` ∩ `features.json` `usableFor` (reward picker only offers `usableAsReward()`, guard picker only `usableAsGuard()`). **Gear / builder must not offer `band.atr` as a guard.**
  - Output dropdowns: `RewardOutputId` / `GuardOutputId` / `BackgroundKind` (already frozen; do not invent names).
  - Inhibit rows (`betaCeiling` / `deltaCeiling` + `max`).
  - Optional electrode **names** (`reward.electrodes` / `guard.electrodes`), never indices. Empty = Rust default.
  - Copy fields, color, calibration id (`eyes-closed-01` / `eyes-open-01` from `calibrations.json`).
  - `locked: []` on new user documents. Runtime still ignores `locked` except this builder (honor catalog locks if editing is ever offered for catalog rows — v1 builder is user docs only).
- User protocol I/O under app-support `protocols/*.json` (one document per file, `origin: "user"`). **Not** the history SAF tree. No remote fetch. No code execution from JSON.
- User IDs: `user.<slug>` where `slug` is `[a-z0-9-]{3,64}`. Catalog IDs are reserved; **reject** a user document whose `id` collides with a catalog id (`catalogProtocolIds`) or an existing user file.
- `feedback_list.dart`: a user section (saved bookmarks) plus an entry point to the builder. Catalog rows stay as today. List filter is still last-connected / currently connected `DeviceKind`, else show all.
- After save, invalidate `protocolCatalogProvider` so the new row appears. `ProtocolCatalog.load()` already unions the asset with `mergeUserProtocols()`.
- Tests: load / validate / reject catalog-id collision; `usableFor` violations (e.g. `band.atr` as guard) rejected at parse (already true in `ProtocolReward.fromJson` / `ProtocolGuard.fromJson` — keep that and cover it from the builder save path).
- Crown Start stays refused (`startCalibration` early return + `_refuseCrownStart` dialog). A user `device.focus` doc may **list** on Crown; **Start is still refused**.

### Do not

- Visual patcher (FFT bins, biquads, arithmetic boxes). JSON names IDs; code owns behavior.
- Unlock Crown Start.
- Change v5 body / computed columnar layout / SQLite schema / BLE / `DeviceConfig` FFI fields.
- Add fields to `FeatureDto`.
- Re-split audio outputs / reopen `FeedbackMode`.
- Leave AI scoring running in the live view (`set_enabled_features([])` at session end already landed).
- “Fix” the `guardrailDeltaCeiling` comment/code unit mismatch.
- Edit `session_chart_data.dart` `electrodeAf7`.
- Reopen Key Decisions. This is the last PR of the series, not a license to revisit 1–6.

---

## Already landed (do not redo)

| Piece | Where | Notes |
|---|---|---|
| Contract | `.ai/feeback/pipeline-contract.md` | PR 1. Frozen. |
| Registry + FFI | `rust/src/api/features.rs` | 8 v1 IDs. Default enable set empty. |
| Protocol documents | `assets/protocols.json` v4, `assets/features.json` | String ids. Parse rejects `usableFor` violations. |
| Settings | `lib/src/settings.dart` | `guardFeatureFor` / `guardModel`. `feedback_mode` stores `RewardOutputId` names. |
| List + Crown refuse | `feedback_list.dart`, `feedback_session.dart` `_refuseCrownStart`, `feedback_state.dart` `startCalibration` | Keep the refuse. |
| FeatureBus / lanes | `feature_bus.dart`, `reward_lane.dart`, `guard_lane.dart` | RewardLane → `RewardOutput.onSample`; GuardLane → `GuardOutput.onGuard` + `setMuffle`. |
| Audio outputs | `lib/src/audio/{output_ids,reward_output,guard_output}.dart` | `RewardOutputId` / `GuardOutputId` / unmapped `BackgroundKind`. |
| Calibration compose (PR 6) | `calibration_clips.dart` `CalibrationPlan`, `calibration_runner.dart`, `feedback_state.dart` `_enabledFeatureIds` | Plan from `S`. `recipeFor(calibrationId, plan:)`. |
| User-file **read** path | `ProtocolCatalog.mergeUserProtocols` | App-support `protocols/*.json`. Catalog wins on id collision (file skipped). `userProtocolIdPattern`. **No write/delete yet.** |
| Tests | `test/feedback_pipeline_test.dart`, `test/calibration_assets_test.dart`, `test/output_ids_test.dart` | FeatureBus, gate electrodes, 75 s window, compose table, output-id migrate. |

`features.rs` tests share process-global registry state; they take `TEST_LOCK` in `reset()`. Do not drop that.

Last commits: `f0f917c` PR 1, `43b42e5` PR 2, `00850db` PR 3, `83df86d` PR 4, `98097d7` PR 5, `c4dfdae` PR 6.

---

## Resume here (current pointers)

| What | Where |
|---|---|
| User id pattern + reserved catalog ids | `protocol.dart` `userProtocolIdPattern`, `catalogProtocolIds` |
| Document parse (`usableFor` reject, `locked`) | `protocol.dart` `ProtocolReward.fromJson` ~195, `ProtocolGuard.fromJson` ~267 |
| `ProtocolDocument.toJson` (write this) | `protocol.dart` ~383 |
| Read-only merge of `protocols/*.json` | `protocol_catalog.dart` `mergeUserProtocols` ~80 (catalog wins; skip bad files) |
| List (no user section yet) | `feedback_list.dart` — `catalog.all` / `listedFor`; add a user section + builder entry |
| Session Start + Crown refuse | `feedback_session.dart` `_refuseCrownStart` ~2152; `feedback_state.dart` `startCalibration` ~433 |
| Feature copy + `usableFor` | `assets/features.json`, `feature_catalog.dart` `usableAsReward` / `usableAsGuard` |
| `available_features` | `availableFeatures(kind:)` FFI; `availableFeaturesProvider` in `protocol_catalog.dart` |
| Output ids | `lib/src/audio/output_ids.dart`, `guardrail_sound.dart` |
| Calibration ids the form may pick | `assets/calibrations.json` v2: `eyes-closed-01`, `eyes-open-01` |
| Compose from `S` (already works for user docs) | `CalibrationPlan.fromEnabledFeatures`; orchestrator `_enabledFeatureIds` |
| Gear (catalog session) | `feedback_session.dart` ~1981 — already `none` / `band.delta` / `ai.drowsiness` only. Builder must stay on `usableFor`. |

`ProtocolCatalog.load()` already calls `mergeUserProtocols()`. Saving a file is not enough until the provider is invalidated.

Loader today **skips** collisions and malformed files. The builder **save** path must **reject** (error to the user) a catalog-id collision, a non-matching `user.<slug>`, and a `usableFor` violation — do not silently write a file the loader will ignore.

---

## Output ids (already frozen — do not invent names)

**RewardOutputId:** `chime`, `musicFilter`, `rainStage`, `binauralSwell`, `none`.

**GuardOutputId:** `softBowl`, `chime`, `cough`, `alarm`, `none` — same strings as `GuardrailSound.name`. Do **not** rename stored id `chime` to `highChime`.

**BackgroundKind:** `drone`, `droneLoop`, `rain`, `userMusic`, `binaural`, `none`. Unmapped. Not an output method.

---

## Storage (frozen)

- Directory: app-support `protocols/*.json` (one document per file, `origin: "user"`).
- **Not** the history SAF tree. Do not scan the history folder for `.json`.
- Catalog asset ∪ support-dir glob; catalog wins on id collision.
- No remote fetch. No `eval`. IDs go to FFI only as `String` feature ids / electrode names (Rust rejects unknowns).

---

## ReveDto trap (still open — not this PR)

`FeatureDto.value` for `ai.drowsiness` is **`sleep_dir` only**. Computed-frame `guardrail.clarity` still comes from `ReveDto` via `GuardLane.onReveExtras`. Do **not** add fields to `FeatureDto`. Do **not** remove `MuseEventDto::Reve`.

---

## Crown vs “working” (do not reopen)

This series does **not** unlock Crown sessions. Gate electrodes / quality length / computed frames / charts stay Muse-4-ch. Do not change `DeviceConfig` FFI fields. A user document with `device.focus` may list on Crown; Start stays refused.

---

## Do not reopen

See contract Key Decisions. Highlights for this PR:

- Inhibit ≠ guard. Guard never changes the reward scalar or `inTarget`.
- Background ≠ reward output ≠ guard output (already split in PR 5).
- `muffleReward` already landed; not a GuardOutputId.
- `epochWindowSeconds = 75`, `adaptIntervalSeconds = 30`.
- `percentileWarn` preserves absolute `_lastDelta` vs 0.25.
- `guardrailEngine` metadata stays `drowsinessMath` / `drowsinessLunaLarge` / … (not `bandMath` / `luna_base`).
- Calibration compose is done (PR 6). `CalibrationPlan` from `S`.
- Charts may keep `electrodeAf7` (non-goal).
- Missing sample = no sample, not 0.
- Crown Start stays refused.
- Builder is a **form over the document**, not a patcher.

---

## Verify before calling PR 7 done

- `flutter analyze lib/src` (pre-existing infos/warnings in `session_recorder.dart`, `connect_window.dart`, `computed_sampler.dart` are OK; no new errors).
- Saving a user document writes `protocols/user.<slug>.json` with `origin: "user"` and `locked: []`.
- Catalog-id collision (`drowsiness`, …) is rejected. Invalid slug is rejected. `band.atr` as guard is rejected.
- A hand-built JSON in that directory (valid `user.*` id, legal lanes) lists and **runs the same Muse path** as a catalog row (features → `CalibrationPlan` → lanes → outputs).
- Gear / builder never offers a reward-only feature as a guard.
- Crown Start still refused.
- `test/calibration_assets_test.dart` and `test/feedback_pipeline_test.dart` still green; add builder I/O tests.

---

## First prompt for the new thread

> Continue from `.ai/feeback/handoff-pr7.md`. Frozen contract: `.ai/feeback/pipeline-contract.md`. Implement PR 7 only (`feat(feedback): custom protocol builder`). Form over the document. User I/O under app-support `protocols/*.json`. Reject catalog-id collisions. Do not offer `band.atr` as a guard. Crown Start stays refused. Do not reopen Key Decisions.
