# Feedback pipeline PR plan (archived)

Implemented. Live contract: [../feedback/pipeline-contract.md](../feedback/pipeline-contract.md).

## PR Plan

Each step is independently mergeable **as scoped below**. Step 2 does **not** kill `ProtocolType` and does **not** change `DeviceConfig` FFI. Old sessions must keep listing after every step. PR 3 is **not** parallel-safe without the `scalarForFeature` map (it depends on PR 2 for `FeatureInfo` names / `available_features`, and it must keep extracting from `BandsDto`).

### PR 1 — This contract

- **Title:** `docs: freeze feedback pipeline contract`
- **Files:** `.ai/feedback/pipeline-contract.md` (this document)
- **Deps:** none
- **Description:** Architecture freeze only. No code.

### PR 2 — Feature registry in Rust + `FeatureDto`

- **Title:** `feat(rust): feature registry, FeatureDto, Crown focus/calm pass-through`
- **Files:**
  - `rust/src/api/features.rs` (new: `FeatureDto`, `FeatureInfo`, `available_features`, `set_enabled_features`, `set_feature_electrodes`, per-feature name tables)
  - `rust/src/api/mod.rs`
  - `rust/src/api/muse.rs` (`MuseEventDto::Feature` importing `FeatureDto`; 1 Hz band-feature tick; **port `_maybeComputeSignalQuality` with a 1.0 s EEG ring (256 samples @ 256 Hz), not 1.0 ms**; autodrop when aggregating; `set_enabled_features` hook; default enabled = empty)
  - `rust/src/api/neurosity_osc.rs` (emit `device.focus`/`device.calm`; `/signalQuality` 0–1 → 0–100 for aggregator; **comment + index test** vs `DeviceConfig.electrode_names`)
  - `rust/src/api/session_format.rs` (no-op encode for `Feature`; `use crate::api::features::FeatureDto`)
  - generated `frb_generated.rs` + `lib/src/rust/**`
  - **Not** `device_config.rs` FFI fields
- **Deps:** PR 1
- **Description:** Registry + `FeatureDto` on the existing stream. Band `FeatureDto` only while enabled (default **empty**). Dual-emit `ai.drowsiness` **only when `ReveDto` is already emitted**. Pass through Crown focus/calm. Dart `default:` branches ignore `Feature`. **No UI change, no `ProtocolType` kill, no DeviceConfig Dart shape change.** Tests: electrode name resolution; unavailable reject; quality skip on null/short; Crown comment/index fixture; `cargo test --lib session_format` (Feature encodes empty).

### PR 3 — Protocol documents + kill `ProtocolType`

Keep **one PR** with an internal 3a/3b checklist (too coupled for two merges: Settings + catalog + gear share the document type).

- **Title:** `feat(feedback): protocol documents, string ids, features.json`
- **Deps:** PR 2 (not parallel-safe: needs `FeatureInfo` names and `available_features`; extraction stays on `BandsDto` via `scalarForFeature`)
- **3a checklist:** string ids; `assets/protocols.json` v4 (`defaultEnabled: true` on every row that has `guard`, including `alertnessClosed` / `mindfulness` / `concentration`); `assets/features.json` (all eight rows); `pubspec.yaml`; no drowsiness coalesce (`session_metadata.dart`, `session_store_core.dart`, **`crash_recovery.dart`**); `scalarForFeature` map; kill `RewardMetric`; `muffleReward` bool on the document **and** notifier (`_evaluateGuardrailWarning`); dummy `ProtocolInfo` constructors in `feedback_session.dart` / `feedback_dashboard.dart` / `feedback_history.dart`; **list rows** = catalog copy else raw id; **Recent** = catalog hit only (skip unknown); `protocolJson` snapshot; `protocolVersion` `"1"`
- **3b checklist:** replace `GuardrailMode` with `{feature}` + global `guard_model`; eager Settings migrate (first freeze-order `.isAi` wins `guard_model`); `_guardrailAllowedCache` → `guard != null`; no-pref documents **with** `guard` start ON; gear UI; `model_engine.dart` / `reve_import.dart` write global model, not `ProtocolType.drowsiness`; list filter by connected/last `DeviceKind` else all; Crown **list** band rows, **refuse Start**
- **Files:** 3a+3b above plus `protocol.dart`, `protocol_catalog.dart`, `settings.dart`, `settings_view.dart`, `session_export.dart`, `session_pdf_export.dart`, `test/calibration_assets_test.dart` (`expect(version, 4)`, every feature id ∈ `features.json` with matching `usableFor`, audio bundling), Settings fixture (unknown key + mixed old/new values + empty-pref `alertnessClosed` ON + mixed-AI `drowsiness` Luna / `twilight` REVE → `guard_model = luna_large`)
- **Still `Settings.feedbackMode`.** Do not split `FeedbackMode` here.
- **Do not edit** `session_chart_data.dart` `electrodeAf7` (charts non-goal).

### PR 4 — Split the notifier

- **Title:** `refactor(feedback): orchestrator, reward lane, guard lane, calibration runner`
- **Files:** `lib/src/feedback/feedback_state.dart` (shrink to orchestrator), new `feature_bus.dart`, `reward_lane.dart`, `guard_lane.dart`, `calibration_runner.dart`, `target_state.dart` (drop `electrodeAf7` from the **reward** path; `RatioEngine` stays; `epochWindowSeconds = 75`; aggregator takes names for inhibit), `feedback_engine.dart` (unchanged interface), `feedback_session.dart` if it imported `neededElectrodes` (gate electrodes, not AI window)
- **Deps:** PR 2 + PR 3
- **Description:** RewardLane consumes `FeatureDto` + inhibit from relative bands (same quality skip policy). GuardLane consumes `FeatureDto`; stop using `ReveDto` and then remove the variant. Orchestrator: timer, pause, record, **`_allGreen` still all montage pads**, playing pause from **gate** electrodes, `set_enabled_features` on start/end (lanes **on** this session, deduped). Computed-frame mapping as frozen. Behavior-preserving on Muse (75 s window, absolute-δ rail). **Crown Start still refused.**

### PR 5 — Output methods + audio role split

- **Title:** `refactor(audio): reward/guard/background outputs`
- **Files:** `lib/src/settings.dart` (`FeedbackMode` mapped), `lib/src/audio/audio_service.dart`, `feedback_audio_controller.dart`, `music_controller.dart`, `rain_feedback_controller.dart`, `binaural_beat_controller.dart`, `guardrail_sound.dart`, session picker UI (`_FeedbackModePicker`), `session_metadata.dart` `feedbackSound` reader
- **Deps:** PR 4
- **Description:** `RewardOutput.onSample` / `GuardOutput.onGuard`. Background unmapped. Preserve suppress policy for `musicFilter`/`rainStage`. **`muffleReward` already landed in PR 3** — do not migrate `GuardrailFeedback` here. Behavior-preserving picker. No SoLoud engine changes.

### PR 6 — Calibration composition

- **Title:** `feat(feedback): compose calibration stages from subscribed features`
- **Files:** `lib/src/audio/calibration_clips.dart` (`CalibrationManifest.recipeFor`), `calibration_runner.dart` / `feedback_state.dart`, `test/calibration_assets_test.dart`, optionally `assets/calibrations.json` seconds retune
- **Deps:** PR 4
- **Description:** Implement the compose table (AI → artifact+challenge+baseline; else baseline; record-only skippable). Optional adaptive 45/60 s baseline. Keep existing clips.

### PR 7 — Custom builder UI (last)

- **Title:** `feat(feedback): custom protocol builder`
- **Files:** new view under `lib/src/views/`, user protocol I/O under app-support `protocols/`, `feedback_list.dart` (user section), tests for load/validate/reject catalog-id collision
- **Deps:** PR 3–6 (a catalog protocol **and** a hand-built JSON protocol must already run the same path **on Muse**)
- **Description:** Form over the document (feature dropdowns from `available_features` ∩ `usableFor`, output dropdowns, inhibit rows, optional electrode names). Not a patcher. Not before the shared path exists. Gear must not offer `band.atr` as a guard.

---

## References

- `lib/src/feedback/protocol.dart` — `ProtocolType`, `RewardMetric`, `TargetCondition`, `GuardrailFeedback`, `ProtocolInfo.fromJson`, unused `isCompatibleWith`
- `lib/src/feedback/protocol_catalog.dart` — `ProtocolCatalog`, `useProtocolCopy`
- `lib/src/feedback/feedback_state.dart` — notifier, `_stagedCalibrationIntent`, `_onBands` (~4 Hz), `_inTargetVerdict`, `_evaluateGuardrailWarning`, `_allGreen`, `neededElectrodes`, `guardrailDeltaCeiling`
- `lib/src/feedback/feedback_engine.dart` — reward engine interface
- `lib/src/feedback/target_state.dart` — `RatioEngine.epochWindow = 300`, `TargetStateAggregator`, `_padUsable`
- `lib/src/feedback/guardrail_mode.dart` — `.name` vs `.ffId`
- `lib/src/feedback/session_metadata.dart` — `protocol` enum + drowsiness fallback; `calibrationJson`
- `lib/src/feedback/session_store_core.dart` — SQLite list coalesce
- `lib/src/feedback/crash_recovery.dart` — default `'drowsiness'`
- `lib/src/feedback/computed_sampler.dart` / `computed_frame.dart` — 4×5 bands; `FeedbackInfo.ratio`; `GuardrailInfo.sleepDir`
- `lib/src/feedback/session_chart_data.dart` — `electrodeAf7` (leave)
- `lib/src/connection_provider.dart` — `_maybeComputeSignalQuality` 4-slot
- `lib/src/settings.dart` — `FeedbackMode`, `guardrailModeForProtocol`
- `lib/src/reve/model_engine.dart` — writes `ProtocolType.drowsiness`
- `assets/protocols.json` v3, `assets/calibrations.json` v2
- `rust/src/api/muse.rs` — `MuseEventDto`, `ReveDto`, `BandsDto`, FFT, model window
- `rust/src/api/device_config.rs` — montage, `target_electrodes`, Crown names
- `rust/src/api/neurosity_osc.rs` — dropped `/focus` `/calm`; wrong electrode comment
- `rust/src/api/reve.rs` / `rust/src/analysis/guardrail.rs` — model + anchors
- `rust/src/api/session_format.rs` — `encode_session_event` no-ops Reve/Gestures; computed 4-ch
- `lib/src/audio/audio_service.dart` — three-layer comment vs `FeedbackMode`
- `lib/src/audio/guardrail_sound.dart` — `softBowl` / `chime` / `cough` / `alarm` / `none`
- `lib/src/views/feedback_list.dart`, `feedback_session.dart` — UI coupling
- `.ai/feedback/architecture.md`, `AGENTS.md` feedback hot spots
