# Handoff — start PR 3 (protocol documents)

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Branch | `main` (ahead of origin; do not push unless asked) |
| Thought level | Contract frozen on xhigh. Implementation was high. Do not reopen Key Decisions. |
| Status | **PR 1 + PR 2 committed. Start PR 3. Do not start PR 4.** |

Read this file, then [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md). Key Decisions 1–19 and the 7-PR plan are the law. Do not re-design the pipeline.

---

## What this project is doing

Muse ML: Flutter UI + Rust BLE (`muse-rs` / btleplug) + on-device LUNA/REVE. The **feedback** stack is being restructured so catalog programs and later custom “bookmarks” share one pipeline:

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane / Background / Orchestrator
```

**Inhibit ≠ guard.** Background ≠ reward output. JSON names IDs; Rust owns `(device, feature)` electrodes.

**Crown this series:** registry **produces** `device.focus` / `device.calm` and **can compute** `band.*`. PR 3 **may list** band protocols when the selected kind is Crown. **Running** a catalog session on Crown is **out of scope** (orchestrator refuses Start; quality / computed 1 Hz / charts stay 4-ch until a later series). `ai.drowsiness` is Muse-only.

Frozen spec: [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md).

PR order: **1 contract (done) → 2 feature bus (done) → 3 protocol documents (this) → 4 notifier split → 5 audio outputs → 6 calibration compose → 7 custom builder last.**

---

## PR 3 scope (from the contract)

`feat(feedback): protocol documents, string ids, features.json`

Keep **one PR** with an internal 3a/3b checklist (too coupled for two merges: Settings + catalog + gear share the document type).

**Deps:** PR 2 (not parallel-safe). Needs `FeatureInfo` names and `available_features`. Extraction stays on `BandsDto` via a temporary `scalarForFeature` map until PR 4.

**Still `Settings.feedbackMode`.** Do not split `FeedbackMode`. Do not edit `session_chart_data.dart` `electrodeAf7`. Do not change v5 layout, SQLite schema, BLE, or `DeviceConfig` FFI fields.

### 3a — documents + kill `ProtocolType` / `RewardMetric`

- String protocol ids everywhere (`ProtocolInfo` → `ProtocolDocument` parsed from JSON, no enum).
- `assets/protocols.json` **version 3 → 4**. Mapping table in the contract is the law (do not guess). Every row that **has** a `guard` object gets `defaultEnabled: true` (including `alertnessClosed` / `mindfulness` / `concentration`). `alertnessOpen` / `recordOnly` omit `guard`. Copy strings migrate **verbatim**.
- Delete dead fields `requiredElectrodes` / `allowedDevices`.
- `assets/features.json` — all **eight** v1 rows (copy + `usableFor`). Add a `pubspec.yaml` asset entry next to `protocols.json`.
- Tests: `test/calibration_assets_test.dart` `expect(json['version'], 4)`; every `reward.feature` / `guard.feature` exists in `features.json` with matching `usableFor`; audio bundling guard stays.
- No drowsiness coalesce: `session_metadata.dart`, `session_store_core.dart`, **`crash_recovery.dart`**. Unknown ids stay the raw id (list rows) or are skipped (Recent).
- Temporary `scalarForFeature(String id, RelativeTarget t)` — ATR/TAR/BTR/relative alpha from `BandsDto`. **No hardcoded 1/2.** Deleted in PR 4 when RewardLane reads `FeatureDto`.
- Kill `RewardMetric`. `TargetCondition` / `BetaCeiling` / `DeltaCeiling` stay, parsed from `reward.inhibit`.
- `muffleReward` bool on the document **and** in the notifier (`_evaluateGuardrailWarning` reads `spec.guard.muffleReward`). `GuardrailFeedback` dies here (not PR 5).
- Dummy `ProtocolInfo` constructors in `feedback_session.dart` / `feedback_dashboard.dart` / `feedback_history.dart` must stop using `ProtocolType.drowsiness`.
- List rows = catalog copy else raw id. Recent = catalog hit only (skip unknown). `protocolJson` snapshot of the **resolved** document. `protocolVersion` write `"1"` (string; readers accept int or string).
- User protocols: if `protocols/*.json` already exist under app-support, load them (`origin: "user"`). Builder I/O is PR 7.

### 3b — GuardrailMode split + list filter + Crown Start refuse

- Replace `GuardrailMode` with `{feature: band.delta|ai.drowsiness|none}` + global `guard_model`.
- Eager migrate in `Settings.load` **before any getter runs** (old `ProtocolType.name → GuardrailMode.name` → new object). First freeze-order `.isAi` wins `guard_model`. Mixed leftover values must not throw.
- `_guardrailAllowedCache` → `document.guard != null`.
- No-pref: document **with** `guard` starts ON (`band.delta`). Do **not** honor unused v3 `guardrailDefault: false`.
- Gear UI: still lists `ai.drowsiness` when a model is installed; `guard.locked` is empty so the gear may switch. Catalog does **not** lock `guard.feature`.
- `model_engine.dart` / `reve_import.dart` write global `guard_model`, **not** `ProtocolType.drowsiness`.
- List filter: last-connected / currently connected `DeviceKind` (incl. simulated). No device this process → show all (today’s `catalog.all`).
- Crown **list** band rows; **refuse Start** with a clear error (Crown session run is a later series). `ai.drowsiness` unavailable on Crown.
- `SessionSettings.guardrailEngine` keeps writing today’s `GuardrailMode.name` (`drowsinessMath`, …). Add `guardFeature` + `guardModel`. Do **not** start writing `bandMath` / `luna_base` into `guardrailEngine`.

**PR 3 test fixture (required):**

- Unknown protocol key + mixed old-string / new-object values; `Settings.load` must not throw.
- `alertnessOpen` / `recordOnly` must not gain `band.delta`.
- Empty prefs: `alertnessClosed` / `mindfulness` / `concentration` **ON** (`band.delta`), same as `drowsiness`.
- Mixed AI: `drowsiness = drowsinessLunaLarge`, `twilight = drowsinessReveBase` → `guard_model = luna_large`, both `{feature: ai.drowsiness}`.

---

## Already landed (do not redo)

| Piece | Where | Notes |
|---|---|---|
| Contract | `.ai/feeback/pipeline-contract.md` | PR 1. Frozen. |
| Registry + FFI | `rust/src/api/features.rs` | 8 v1 IDs; Muse AF7/AF8 vs Crown PO3/PO4; `ai.drowsiness` Muse-only; `device.*` Crown-only. `#[frb(ignore)]` on private `Registry` / `EegRing` / `ChannelBands`. |
| Dart FFI | `lib/src/rust/api/features.dart` | `availableFeatures` / `setEnabledFeatures` / `setFeatureElectrodes` + `FeatureDto` / `FeatureInfo` / `FeatureSource` / `FeatureLane`. Default enable set **empty**. |
| `MuseEventDto::Feature` | `muse.dart` / `muse.freezed.dart` | Ignored by existing `default:` / `_` until PR 4 (`feedback_state.dart` ~1320, `connection_provider.dart` ~290, `streaming_controller.dart` ~143, `session_recorder.dart` `_ => false`). |
| Crown `/focus` `/calm` | `rust/src/api/neurosity_osc.rs` | `FeatureDto` iff enabled. `/signalQuality` 0–1 → 0–100 for aggregator only. Electrode comment fixed (`0=CP3…`). |
| Encode no-op | `session_format.rs` | `Feature(_)` with Reve/Gestures. |
| FRB hygiene | `flutter_rust_bridge.yaml` `rust_preamble`; `#[frb(ignore)]` on `spawn_simulator` / `DeviceSimulator::with_config` | So codegen compiles. `neurosity_osc.dart` JoinHandle stub is unused — don’t wire it. |

`features.rs` tests share process-global registry state; they take `TEST_LOCK` in `reset()`. Do not drop that.

---

## Crown vs simulator vs “working” (do not reopen)

PR 2 **already** made Crown and simulated kinds **produce** features:

- `available_features(SimulatedMuse)` mirrors Muse; `SimulatedNeurosity` mirrors Neurosity.
- Crown `/focus` `/calm` pass through as `FeatureDto` when enabled.
- Band `FeatureDto` on Crown uses PO3/PO4 + `/signalQuality` autodrop.
- `DeviceSimulator.new` / `start` / `stop` stay on the Dart FFI. `spawn_simulator` / `with_config` were never Dart-exposed; they are `#[frb(ignore)]` so `tokio::JoinHandle` does not leak.

**This series does not unlock Crown sessions.** PR 3 lists band protocols on Crown and **refuses Start**. A later series (allowed to touch quality length, computed frames, charts) is when Crown actually runs. Do not “fix” Crown `BandsDto.line_noise_ratio` stuffing in PR 3. Do not change `DeviceConfig` FFI fields.

---

## Do not reopen

See contract Key Decisions. Highlights:

- Gate electrodes ≠ producer electrodes. AI window does **not** add TP9/TP10 to the playing pause.
- `epochWindowSeconds = 75` is PR 4, not PR 3. Do not change `RatioEngine`.
- `percentileWarn` preserves absolute `_lastDelta` vs 0.25 (unit-comment mismatch is a later science PR).
- `guardrailEngine` metadata stays `GuardrailMode.name` (`drowsinessMath`, …).
- No-pref guardrail: any document **with** a `guard` object defaults **ON** (today’s Settings, not unused JSON `guardrailDefault: false`).
- `reward.output` catalog default is `chime`; **ignore at runtime** — keep `Settings.feedbackMode` through PR 4.
- `_allGreen` stays all montage pads this refactor.

---

## Verify before calling PR 3 done

- `flutter analyze lib/src` (pre-existing infos/warnings in `session_recorder.dart`, `connect_window.dart`, `computed_sampler.dart` are OK; no new errors).
- `flutter test test/calibration_assets_test.dart` (and the Settings fixture above).
- `cargo test --manifest-path rust/Cargo.toml --lib features::` + `session_format` still green if you touch FFI (you should not need to).
- If you change the FFI surface, `flutter_rust_bridge_codegen generate` (CLI **2.11.1**) and commit both sides. Keep `#[frb(ignore)]` on `Registry`.
- Do not commit unless asked.

---

## First prompt for the new thread

> Continue from `.ai/feeback/handoff-pr3.md`. Frozen contract: `.ai/feeback/pipeline-contract.md`. Implement PR 3 only (`feat(feedback): protocol documents, string ids, features.json`): one PR, internal 3a then 3b. Kill `ProtocolType` / `RewardMetric` / `GuardrailMode`; ship `assets/features.json` (all eight rows) and `protocols.json` v4 from the contract mapping table; temporary `scalarForFeature`; eager Settings migrate; Crown may list band protocols but Start is refused. Do not start PR 4. Do not reopen Key Decisions. Do not commit unless I ask.
