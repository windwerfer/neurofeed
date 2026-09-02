# Handoff — start PR 5 (audio outputs)

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Branch | `refactor/eeg_feature_implementation` (do not push unless asked) |
| Thought level | Contract frozen on xhigh. Implementation was high. Do not reopen Key Decisions. |
| Status | **PR 1 + PR 2 + PR 3 + PR 4 committed. Start PR 5. Do not start PR 6.** |

Read this file, then [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md). Key Decisions 1–19 and the 7-PR plan are the law. Do not re-design the pipeline.

---

## What this project is doing

Muse ML: Flutter UI + Rust BLE (`muse-rs` / btleplug) + on-device LUNA/REVE. The **feedback** stack is being restructured so catalog programs and later custom “bookmarks” share one pipeline:

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane / Background / Orchestrator
```

**Inhibit ≠ guard.** Background ≠ reward output ≠ guard output. JSON names IDs; Rust owns `(device, feature)` electrodes.

**Crown this series:** registry **produces** `device.focus` / `device.calm` and **can compute** `band.*`. Catalog **lists** band protocols when the selected kind is Crown. **Running** a catalog session on Crown is **out of scope**. **Crown Start stays refused in PR 5.**

Frozen spec: [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md).

PR order: **1 contract (done) → 2 feature bus (done) → 3 protocol documents (done) → 4 notifier split (done) → 5 audio outputs (this) → 6 calibration compose → 7 custom builder last.**

---

## PR 5 scope (from the contract)

`refactor(audio): reward/guard/background outputs`

**Deps:** PR 4.

**Split `FeedbackMode` now.** Catalog `reward.output` / `guard.output` become live (with Settings prefs). Do not implement the PR 6 compose table (keep `useStaged` as “any `ai.*` enabled”). Do not change v5 layout, SQLite schema, BLE, `DeviceConfig` FFI fields, or SoLoud engine internals. Do not unlock Crown sessions. Do not edit `session_chart_data.dart` `electrodeAf7` chart logic.

### Do

- Introduce the output-method interfaces (contract, frozen):

```dart
abstract class RewardOutput {
  Future<void> start();
  Future<void> stop();
  void onSample({required double percentile, required bool inTarget});
  void setMuffle(bool on); // no-op for chime
}

abstract class GuardOutput {
  Future<void> start();
  Future<void> stop();
  void onGuard({required bool active, required double intensity});
}
```

- `intensity` is reserved (alarm already ramps internally). v1 one-shots ignore it; `alarm` uses `active` to start/stop the ramp.
- **Background is not an output method.** Orchestrator starts/stops it from `background.kind` + user override (`Settings.soundName` today).
- Map today’s `FeedbackMode` 1:1:

| Old `FeedbackMode` | Reward output id | Background |
|---|---|---|
| `bowlChimes` | `chime` | keep `soundName` |
| `rain` | `rainStage` | suppressed at runtime |
| `music` | `musicFilter` | suppressed at runtime |
| `binaural` | `binauralSwell` | keep background |
| `none` | `none` | keep `soundName` |

- Guard outputs freeze to **existing** `GuardrailSound` names so `Settings.warningSoundName` does not migrate: `softBowl` / `chime` / `cough` / `alarm` / `none`. Do **not** rename the stored id `chime` to `highChime`.
- **Muffle is not a GuardOutputId.** It is `guard.muffleReward: bool` (already PR 3). `AudioService.setMusicMuffle` ducks music / rain / binaural. Chime reward is not muffled.
- Preserve suppress policy (engine, not JSON): `rainStage` and `musicFilter` suppress background; `binauralSwell` layers under background; `chime` / `none` keep background.
- `SessionMetadata.sound` / `feedbackSound` stay strings. After this PR, `feedbackSound` writes the **new** output id; readers accept both `bowlChimes` and `chime`.
- Behavior-preserving picker: session “Feedback Sound” tile still chooses the reward output. Wire it to output ids instead of `FeedbackMode`.
- RewardLane should call `RewardOutput.onSample`; GuardLane should call `GuardOutput.onGuard`. Today both still go through `AudioService` (`_applyReward` / `GuardLane.evaluateWarning`).
- Catalog `reward.output` default is `chime`; `guard.output` default is `softBowl`. Runtime: user pref wins; catalog default when unset.

### Do not

- Migrate `GuardrailFeedback` (the enum is already gone in PR 3).
- Change SoLoud engine / `SoLoudEngine.reinit` / Android latency profile.
- Implement PR 6 `CalibrationPlan` / compose table.
- Custom builder UI (PR 7).
- Unlock Crown Start.
- Change v5 body / computed columnar layout / SQLite schema / BLE / `DeviceConfig` FFI fields.
- Add fields to `FeatureDto`.
- Leave AI scoring running in the live view (`set_enabled_features([])` at session end already landed).

---

## Already landed (do not redo)

| Piece | Where | Notes |
|---|---|---|
| Contract | `.ai/feeback/pipeline-contract.md` | PR 1. Frozen. |
| Registry + FFI | `rust/src/api/features.rs` | 8 v1 IDs. `#[frb(ignore)]` on private `Registry` / `EegRing` / `ChannelBands`. Default enable set empty. |
| Dart FFI | `lib/src/rust/api/features.dart` | `availableFeatures` / `setEnabledFeatures` / `setFeatureElectrodes`. |
| Protocol documents | `assets/protocols.json` v4, `assets/features.json` | String ids. `muffleReward` on `ProtocolGuard`. `reward.output` catalog default `chime` — **runtime ignored until this PR**. |
| Settings guard | `lib/src/settings.dart` | `guardFeatureFor` / `guardModel`. **`feedbackMode` / `FeedbackMode` still live — this PR splits them.** |
| List + Crown refuse | `feedback_list.dart`, `feedback_session.dart` `_refuseCrownStart`, `feedback_state.dart` `startCalibration` | Keep the refuse. |
| FeatureBus | `lib/src/feedback/feature_bus.dart` | `FeatureSample` + `of(id)` / `publish` / `latest`. Orchestrator publishes every event; lanes consume `latest` (not a Stream subscription). |
| RewardLane | `lib/src/feedback/reward_lane.dart` | `FeatureDto.value` is the scalar. `scalarForFeature` **deleted**. Inhibit from `RelativeBandAggregator(names)`. Missing FeatureDto = hold last, no `recordEpoch`. Missing relative bands = fail closed (`inTarget = false`, no epoch). `onReward` still a callback into the orchestrator. |
| GuardLane | `lib/src/feedback/guard_lane.dart` | Warn from `FeatureDto`. `percentileWarnOver` is the split. `ReveDto` extras only (`onReveExtras`). Still calls `AudioService` for chime/muffle/alarm. |
| CalibrationRunner | `lib/src/feedback/calibration_runner.dart` | Same clips. `useStaged` = “any `ai.*` enabled”. Compose table is **PR 6**. |
| Orchestrator | `lib/src/feedback/feedback_state.dart` (~1565 lines) | Timer, pause, record, signal gate, `setEnabledFeatures` on start / `[]` on end+reset+dispose+ctor. `_applyReward` still switches on `FeedbackMode`. |
| Gate electrodes | `lib/src/feedback/gate_electrodes.dart` | Names; AI does not add TP9/TP10. `_allGreen` still all montage pads. |
| Phase/constants | `lib/src/feedback/feedback_phase.dart` | Extracted to break import cycles. Re-exported from `feedback_state.dart`. |
| RatioEngine | `lib/src/feedback/target_state.dart` | `epochWindowSeconds = 75` wall-clock. `FeedbackEngine` interface **unchanged**. No `electrodeAf7` in the reward path. |
| Charts | `lib/src/feedback/session_chart_data.dart` | Local `electrodeAf7` / `electrodeAf8` copies (non-goal). |
| Tests | `test/feedback_pipeline_test.dart` | FeatureBus, gate electrodes, 75 s window, RewardLane, `percentileWarn` split. |
| Reve dual-emit | `rust/src/api/muse.rs` | `ReveDto` then `FeatureDto { id: "ai.drowsiness", value: sleep_dir }` while Reve is on. **Do not delete `MuseEventDto::Reve`** — extras still feed computed-frame `guardrail.clarity`. |

`features.rs` tests share process-global registry state; they take `TEST_LOCK` in `reset()`. Do not drop that.

Last commits: `f0f917c` PR 1, `43b42e5` PR 2, `00850db` PR 3, `83df86d` PR 4.

---

## Resume here (current pointers)

| What | Where |
|---|---|
| `FeedbackMode` enum (bowlChimes/rain/music/binaural/none) | `lib/src/settings.dart` ~32 |
| Pref key `feedback_mode` | `settings.dart` `_feedbackModeKey` ~120, getter/setter ~320 |
| Orchestrator still holds `FeedbackState.feedbackMode` | `feedback_state.dart` ~46 |
| `selectFeedbackMode` | `feedback_state.dart` ~295 |
| `_applyReward` switch on `FeedbackMode` | `feedback_state.dart` ~1190 |
| `_musicActive` (muffle target) | `feedback_state.dart` ~1179 |
| RewardLane `onReward` callback | `reward_lane.dart` ~39; wired to `_applyReward` at notifier ctor ~148 |
| GuardLane still owns AudioService | `guard_lane.dart` ctor ~80; `evaluateWarning` ~260 (`setMusicMuffle` / `playWarningChime` / `startWarningAlarm`) |
| Session picker | `feedback_session.dart` `_FeedbackTile` ~800; `_FeedbackModePicker` ~1917 |
| `AudioService.playChannels` / `suppressesBackground` | `lib/src/audio/audio_service.dart` ~83 / ~158 |
| `AudioService.onStateUpdate` / `setMusicCutoffHz` / `setRainPercentile` / `setBinauralPercentile` | same file |
| Guardrail sound ids | `lib/src/audio/guardrail_sound.dart` (`softBowl`/`chime`/`cough`/`alarm`/`none`) |
| `SessionMetadata.feedbackSound` reader (string, no migrate yet) | `session_metadata.dart` ~843 / ~989 |
| Catalog `reward.output` / `guard.output` | `protocol.dart` `ProtocolReward.output` default `'chime'`; `ProtocolGuard.output` default `'softBowl'` |
| Crown refuse (keep) | `startCalibration` ~405; `_refuseCrownStart` ~2163 |

---

## Output id freeze (do not invent names)

**RewardOutputId:** `chime`, `musicFilter`, `rainStage`, `binauralSwell`, `none`.

**GuardOutputId:** `softBowl`, `chime`, `cough`, `alarm`, `none` — same strings as `GuardrailSound.name`.

**BackgroundKind:** `drone`, `droneLoop`, `rain`, `userMusic`, `binaural`, `none` (maps from today’s `soundName`). Unmapped to a feature. Not an output method.

Inputs: `chime` uses boolean `inTarget`; `musicFilter` / `rainStage` / `binauralSwell` use percentile rank from `FeedbackEngine.percentileOf`.

---

## ReveDto trap (still open — not this PR)

`FeatureDto.value` for `ai.drowsiness` is **`sleep_dir` only**. Computed-frame `guardrail.clarity` still comes from `ReveDto` via `GuardLane.onReveExtras`. Do **not** add fields to `FeatureDto`. Do **not** remove `MuseEventDto::Reve` in PR 5 (that would need FRB 2.11.1 codegen on both sides, and extras still have no other home).

---

## Crown vs “working” (do not reopen)

This series does **not** unlock Crown sessions. Gate electrodes / quality length / computed frames / charts stay Muse-4-ch. Do not change `DeviceConfig` FFI fields.

---

## Do not reopen

See contract Key Decisions. Highlights for this PR:

- Inhibit ≠ guard. Guard never changes the reward scalar or `inTarget`.
- Background ≠ reward output ≠ guard output — **this is the PR that splits them.**
- `muffleReward` already landed; not a GuardOutputId.
- `epochWindowSeconds = 75`, `adaptIntervalSeconds = 30`.
- `percentileWarn` preserves absolute `_lastDelta` vs 0.25.
- `guardrailEngine` metadata stays `drowsinessMath` / `drowsinessLunaLarge` / … (not `bandMath` / `luna_base`).
- Calibration `useStaged` stays “any `ai.*` enabled” until PR 6.
- Charts may keep `electrodeAf7` (non-goal).
- Missing sample = no sample, not 0.
- Crown Start stays refused.

---

## Verify before calling PR 5 done

- `flutter analyze lib/src` (pre-existing infos/warnings in `session_recorder.dart`, `connect_window.dart`, `computed_sampler.dart` are OK; no new errors).
- Behavior-preserving on Muse: same sounds, same suppress (rain/music kill background; binaural layers; chime keeps drone), same muffle of modulated reward while warning, chime reward not muffled.
- Settings migrate: stored `feedback_mode=bowlChimes` → reward `chime`, etc. Old sessions: `feedbackSound` reader accepts both `bowlChimes` and `chime`.
- Picker still one reward-output choice; background stays the existing sound tile.
- Crown Start still refused.
- `test/feedback_pipeline_test.dart` still green; add output-id migrate tests.
- Do not commit unless asked.

---

## First prompt for the new thread

> Continue from `.ai/feeback/handoff-pr5.md`. Frozen contract: `.ai/feeback/pipeline-contract.md`. Implement PR 5 only (`refactor(audio): reward/guard/background outputs`). Split `FeedbackMode` into `RewardOutput` / `GuardOutput` / unmapped background. Migrate `Settings.feedbackMode`. Preserve rain/music suppress and `muffleReward`. Catalog `reward.output` becomes live. Crown Start stays refused. Do not start PR 6. Do not reopen Key Decisions. Do not commit unless I ask.
