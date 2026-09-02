# Handoff — start PR 4 (notifier split)

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Branch | `main` (ahead of origin; do not push unless asked) |
| Thought level | Contract frozen on xhigh. Implementation was high. Do not reopen Key Decisions. |
| Status | **PR 1 + PR 2 + PR 3 committed. Start PR 4. Do not start PR 5.** |

Read this file, then [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md). Key Decisions 1–19 and the 7-PR plan are the law. Do not re-design the pipeline.

---

## What this project is doing

Muse ML: Flutter UI + Rust BLE (`muse-rs` / btleplug) + on-device LUNA/REVE. The **feedback** stack is being restructured so catalog programs and later custom “bookmarks” share one pipeline:

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane / Background / Orchestrator
```

**Inhibit ≠ guard.** Background ≠ reward output. JSON names IDs; Rust owns `(device, feature)` electrodes.

**Crown this series:** registry **produces** `device.focus` / `device.calm` and **can compute** `band.*`. PR 3 **lists** band protocols when the selected kind is Crown and **refuses Start**. **Running** a catalog session on Crown is **out of scope** (quality / computed 1 Hz / charts stay 4-ch until a later series). `ai.drowsiness` is Muse-only. **Crown Start stays refused in PR 4.**

Frozen spec: [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md).

PR order: **1 contract (done) → 2 feature bus (done) → 3 protocol documents (done) → 4 notifier split (this) → 5 audio outputs → 6 calibration compose → 7 custom builder last.**

---

## PR 4 scope (from the contract)

`refactor(feedback): orchestrator, reward lane, guard lane, calibration runner`

**Deps:** PR 2 + PR 3.

**Still `Settings.feedbackMode`.** Do not split `FeedbackMode` (that is PR 5). Do not edit `session_chart_data.dart` `electrodeAf7`. Do not change v5 layout, SQLite schema, BLE, or `DeviceConfig` FFI fields. Do not implement the PR 6 compose table (keep `useStaged` as “any `ai.*` enabled”). Do not implement `RewardOutput` / `GuardOutput` (PR 5) — lanes still call today’s `AudioService` APIs.

### Do

- Shrink `FeedbackStateNotifier` (`lib/src/feedback/feedback_state.dart`, ~1850 lines) to an **orchestrator**: timer, pause, record, signal gate, session start/end.
- New files:
  - `lib/src/feedback/feature_bus.dart` — `FeatureSample` + `FeatureBus.of(id)` / `publish(MuseEventDto)`
  - `lib/src/feedback/reward_lane.dart` — consumes `FeatureDto` + inhibit from relative bands
  - `lib/src/feedback/guard_lane.dart` — consumes `FeatureDto`; warn decision no longer reads `ReveDto.sleepDir`
  - `lib/src/feedback/calibration_runner.dart` — extract today’s calibration playback from the notifier (same clips, same `useStaged` boolean). Compose-from-subscribed-features is **PR 6**.
- `FeedbackEngine` / `RatioEngine` stay. Change the **window** to **wall-clock** `epochWindowSeconds = 75` (equivalent of today’s 300 epochs at ~4 Hz `_onBands`). Do **not** switch to 30 one-Hz `FeatureDto` samples. `adaptIntervalSeconds = 30` stays wall-clock.
- Delete PR 3’s temporary `scalarForFeature` and the reward-path `TargetStateAggregator` AF7/AF8 constants (`electrodeAf7` / `electrodeAf8` in `target_state.dart`). Reward scalar comes from `FeatureDto.value`.
- `RelativeBandAggregator(List<String> electrodeNames)` is **only for inhibit + nerd-stats**, using gate/reward montage names and Dart’s 4-slot quality (Muse). No file-level `electrodeAf7` in the reward path.
- `neededElectrodes = [1, 2]` becomes **gate electrodes** resolved from names (Muse AF7/AF8). Playing-phase pause uses gate electrodes only. **`_allGreen` stays all montage pads.** AI window does **not** add TP9/TP10 to the gate.
- Orchestrator calls `set_enabled_features` on session **start** (lanes **on** this session, deduped) and `set_enabled_features([])` on **end**. Include `guard.feature` only when the guard is on for this session (Settings not `none`, and a model if `ai.*`). Optional `set_feature_electrodes` before enable if the document has name overrides. `available_features` + `DeviceConfig.forKind` as needed. Calls succeed with no headset (store the set).
- Dual-emit today: Rust already emits `FeatureDto { id: "ai.drowsiness", value: sleep_dir }` **only while `ReveDto` is already on**. GuardLane consumes that `FeatureDto`. Then **stop emitting `ReveDto`** for the warn path. `FeatureDto` stays `{id, timestamp, value}` — do not add fields. Extra Reve diagnostics (`clarity`, `dim`, `kind`) currently feed computed-frame `guardrail.clarity`; preserve those computed fields as today (see trap below).
- Computed-frame mapping stays frozen: `feedback.ratio` = reward **native**; `guardrail.sleepDir` = AI `sleep_dir` or **0** for band-math; `guardrail.delta` = frontal **absolute** delta (µV²/Hz). No feature-id fields on the frame.
- `percentileWarn` preserves today’s **code**, split: band-math = native `band.delta` vs rest percentile **and** vs 0.25; AI = `sleep_dir` vs rest percentile **and** absolute frontal delta vs 0.25 (always-on `BandsDto`, **not** `FeatureDto.value` of `ai.drowsiness`). Do not “fix” the `guardrailDeltaCeiling` comment/code unit mismatch.
- Missing `FeatureDto` this tick = no sample (hold last output, do not `recordEpoch`). Never coerce to `0.0`.
- **Crown Start still refused** (UI dialog + `startCalibration` early return). Do not unlock Crown sessions.
- `feedback_session.dart` only if it imported `neededElectrodes` (gate electrodes, not AI window).

### Do not

- Split `FeedbackMode` / introduce `RewardOutput.onSample` / `GuardOutput.onGuard` (PR 5). `muffleReward` already landed in PR 3.
- Change calibration recipe selection beyond extracting the current runner (PR 6).
- Custom builder UI (PR 7).
- Edit `session_chart_data.dart` `electrodeAf7` (charts non-goal).
- Change v5 body / computed columnar layout / SQLite schema / BLE / `DeviceConfig` FFI fields.
- “Fix” Crown `BandsDto.line_noise_ratio` stuffing.
- Leave AI scoring running in the live view (`set_enabled_features([])` at process init and session end).

---

## Already landed (do not redo)

| Piece | Where | Notes |
|---|---|---|
| Contract | `.ai/feeback/pipeline-contract.md` | PR 1. Frozen. |
| Registry + FFI | `rust/src/api/features.rs` | 8 v1 IDs; Muse AF7/AF8 vs Crown PO3/PO4; `ai.drowsiness` Muse-only; `device.*` Crown-only. `#[frb(ignore)]` on private `Registry` / `EegRing` / `ChannelBands`. |
| Dart FFI | `lib/src/rust/api/features.dart` | `availableFeatures` / `setEnabledFeatures` / `setFeatureElectrodes` + `FeatureDto` / `FeatureInfo`. Default enable set **empty**. **Nothing calls `setEnabledFeatures` yet.** |
| `MuseEventDto::Feature` | `muse.dart` / `muse.freezed.dart` | Ignored by existing `default:` / `_` until this PR (`feedback_state.dart` `_onEvent` ~1287, `connection_provider.dart` ~234, `streaming_controller.dart` ~117, `session_recorder.dart` `_ => false`). |
| Crown `/focus` `/calm` | `rust/src/api/neurosity_osc.rs` | `FeatureDto` iff enabled. |
| Encode no-op | `session_format.rs` | `Feature(_)` with Reve/Gestures. |
| Protocol documents | `assets/protocols.json` v4, `assets/features.json` (8 rows), `protocol.dart` `ProtocolDocument`, `feature_catalog.dart` | String ids. `TargetCondition` / `BetaCeiling` / `DeltaCeiling` parsed from `reward.inhibit`. `muffleReward` on `ProtocolGuard`. |
| Settings | `lib/src/settings.dart` | Eager migrate. `guardFeatureFor` / `setGuardFeature` / `guardModel` / `setGuardModel`. No `ProtocolType` / `GuardrailMode` enum. |
| List + Crown refuse | `feedback_list.dart`, `feedback_session.dart` `_refuseCrownStart`, `feedback_state.dart` `startCalibration` | List by `listingDeviceKind`; Start dialog + notifier early return. |
| Temporary extractor | `target_state.dart` `scalarForFeature` | **Delete in this PR.** |
| `RatioEngine.featureId` | `target_state.dart` | String, default `'band.atr'`. Engine is direction-agnostic. `epochWindow = 300` **events** — convert to 75 s wall-clock. |
| `neededElectrodes = [1, 2]` | `feedback_state.dart` ~46 | Become named gate electrodes. |
| `electrodeAf7 = 1` / `electrodeAf8 = 2` | `target_state.dart` ~7–8 | Delete from **reward** path. Charts file may keep its own copy. |
| Guardrail helpers | `guardrail_mode.dart` | No enum. `guardFeatureBandDelta` / `AiDrowsiness` / `None`, `guardrailEngineName` writes historical `drowsinessMath` / `drowsinessLunaLarge` / … into metadata. |
| Session metadata | `session_metadata.dart` | `protocol` is `String`; `protocolJson`; `protocolVersion` `"1"`; `SessionSettings.guardFeature` + `guardModel`; `guardrailEngine` still `GuardrailMode.name`. |

`features.rs` tests share process-global registry state; they take `TEST_LOCK` in `reset()`. Do not drop that.

Last commits: `f0f917c` PR 1, `43b42e5` PR 2, `00850db` PR 3.

---

## Resume here (current pointers)

| What | Where |
|---|---|
| Notifier kitchen sink | `lib/src/feedback/feedback_state.dart` (~1850 lines) |
| `_onEvent` ignores `Feature` via `default:` | same, ~1287 |
| `_onBands` ~4 Hz ATR extract + `_metricOf` → `scalarForFeature` | same, ~1320 / ~1457 |
| `_inTargetVerdict` inhibit AND-gate | same, ~1328 |
| `_evaluateGuardrailWarning` / `_onReve` | same, ~1651 / ~1697 |
| `_allGreen` / `neededElectrodes` | same, ~46 / ~1818 |
| Crown refuse (notifier) | `startCalibration` ~459 `debugPrint` + return |
| Crown refuse (UI) | `feedback_session.dart` `_refuseCrownStart` |
| `RatioEngine.epochWindow = 300` | `target_state.dart` ~95 |
| `TargetStateAggregator` AF7/AF8 | `target_state.dart` ~412 / ~434 |
| `scalarForFeature` | `target_state.dart` ~64–71 |
| `FeedbackEngine` interface | `lib/src/feedback/feedback_engine.dart` — **do not change the interface** |
| `setEnabledFeatures` unused | `lib/src/rust/api/features.dart` |
| Reve dual-emit | `rust/src/api/muse.rs` after `MuseEventDto::Reve` |
| Band `FeatureDto` 1 Hz tick | `muse.rs` `emit_enabled_band_features` |
| Always-on bands still flow | `_onBands` must keep running for inhibit, nerd-stats, recording, absolute-δ rail |

---

## Threshold / window freeze (do not reopen)

- **`epochWindowSeconds = 75`**, not 30 s of 1 Hz `FeatureDto`. Today `_onBands` fires per pad (~4 Hz when both frontals are usable), so 300 events ≈ 75 s. RewardLane must preserve that Muse adapt feel with a wall-clock window (or equivalent epoch count at the new sample rate — 75 s is the law, not “300 FeatureDto samples”).
- **`adaptIntervalSeconds = 30`** wall-clock stays.
- **`percentileWarn`:** band-math uses native `band.delta` (absolute AF7/AF8 µV²/Hz via `_frontalDeltaAverage`) vs rest percentile **and** vs `guardrailDeltaCeiling` (0.25). AI uses `sleep_dir` vs rest percentile **and** the same absolute `_lastDelta` vs 0.25. The comment on `guardrailDeltaCeiling` (`feedback_state.dart` ~55–58) claims normalized power; **the code does not normalize.** Do not silently switch to relative-δ.
- Inhibit AND-gates `inTarget` only. Guard never changes the reward scalar or `inTarget`. `muffleReward` muffles the reward **output** while a warning is active (already wired from `spec.guard.muffleReward`).

---

## ReveDto trap (do not expand `FeatureDto`)

`FeatureDto.value` for `ai.drowsiness` is **`sleep_dir` only**. `ReveDto` also carries `clarity` / `dim` / `kind` used by computed-frame `guardrail.clarity`.

PR 4 must:

1. Drive the **warn decision** from `FeatureDto` (plus always-on bands for the absolute-δ rail).
2. Keep computed-frame `guardrail.clarity` / `sleepDir` / `delta` **behavior-preserving**.
3. **Not** add fields to `FeatureDto`.

If stopping `ReveDto` emission would zero `clarity`, keep emitting `ReveDto` for extras only until those fields have a home that is not `FeatureDto`. Removing the `MuseEventDto::Reve` variant is in-scope **only** once no Dart reader remains; that needs `flutter_rust_bridge_codegen generate` (CLI **2.11.1**) and both sides committed. Prefer “stop using Reve for the warn path” over a drive-by FFI deletion if extras are still required.

`encode_session_event` already no-ops `Reve` and `Feature`. Do not add a v5 body tag.

---

## `set_enabled_features` rules (frozen FFI)

- Unknown id → `Err`. Unavailable on this kind → `Err`. Always-on-only names → `Err`.
- Duplicate ids: dedupe, `Ok`.
- Empty vec unsubscribes all subscribed features (always-on unaffected).
- `set_feature_electrodes` before enable: allowed. Empty names reset to registry default. `device.*`: `Err`. Unknown names: `Err`. `ai.drowsiness` on Crown: `Err`.
- Reconnect does not re-enable; orchestrator re-calls on session start.
- Default enabled set is empty. No band `FeatureDto` in the live view until a session enables ids.
- Orchestrator still calls `guardrail_enable` **and** puts `ai.drowsiness` in the enabled set when that lane is on. If the id is in the set without `guardrail_enable`, Rust emits nothing (already).

---

## Crown vs simulator vs “working” (do not reopen)

PR 2 already made Crown and simulated kinds **produce** features. PR 3 lists band protocols on Crown and refuses Start. **This series does not unlock Crown sessions.** Gate electrodes / quality length / computed frames / charts stay Muse-4-ch. Do not change `DeviceConfig` FFI fields (`target_electrodes` / `needed_electrodes` / `DeviceFeatures`).

---

## Do not reopen

See contract Key Decisions. Highlights for this PR:

- Inhibit ≠ guard. Background ≠ reward output (split is PR 5).
- Gate electrodes ≠ producer electrodes. AI window does **not** add TP9/TP10 to the playing pause.
- `_allGreen` stays all montage pads this refactor.
- `epochWindowSeconds = 75`, not 30 s of 1 Hz samples.
- `percentileWarn` preserves absolute `_lastDelta` vs 0.25.
- `guardrailEngine` metadata stays `drowsinessMath` / `drowsinessLunaLarge` / … (not `bandMath` / `luna_base`).
- `reward.output` catalog default is `chime`; **ignore at runtime** — keep `Settings.feedbackMode` through this PR.
- Charts may keep `electrodeAf7` (non-goal).
- Missing sample = no sample, not 0.

---

## Verify before calling PR 4 done

- `flutter analyze lib/src` (pre-existing infos/warnings in `session_recorder.dart`, `connect_window.dart`, `computed_sampler.dart` are OK; no new errors).
- Behavior-preserving on Muse: 75 s success window, absolute-δ rail, inhibit AND-gate, Crown Start still refused.
- If you touch FFI (`Reve` variant, enable-set): `flutter_rust_bridge_codegen generate` (CLI **2.11.1**) and commit **both** `rust/src/frb_generated.rs` and `lib/src/rust/`. Keep `#[frb(ignore)]` on `Registry`. `cargo test --manifest-path rust/Cargo.toml --lib features::` + `session_format` still green.
- Do not commit unless asked.

---

## First prompt for the new thread

> Continue from `.ai/feeback/handoff-pr4.md`. Frozen contract: `.ai/feeback/pipeline-contract.md`. Implement PR 4 only (`refactor(feedback): orchestrator, reward lane, guard lane, calibration runner`). Split `FeedbackStateNotifier` into FeatureBus + RewardLane + GuardLane + calibration runner + orchestrator. RewardLane consumes `FeatureDto` and deletes `scalarForFeature`; GuardLane consumes `FeatureDto` for the warn path; `epochWindowSeconds = 75`; `set_enabled_features` on session start/end. Crown Start stays refused. Still `Settings.feedbackMode`. Do not start PR 5. Do not reopen Key Decisions. Do not commit unless I ask.
