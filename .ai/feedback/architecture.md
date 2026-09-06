# Feedback system (as implemented)

Pipeline PRs 1–7 implemented. Frozen decisions:
[pipeline-contract.md](pipeline-contract.md) — do not reopen them.

Session summary charts plot v5 computed 1 Hz
(`v5ExtractComputed` → `prepareChartDataFromComputed`). Spec archive:
[../archive/session-computed-charts.md](../archive/session-computed-charts.md).

## Pipeline

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane
Orchestrator (FeedbackStateNotifier): calibration, timer, pause, record, quality gate
Background audio: unmapped to a feature
```

**Inhibit ≠ guard.** Inhibit AND-gates the reward verdict (`betaCeiling` /
`deltaCeiling`). Guard is an independent warning lane and never modulates
the reward scalar or `inTarget`. Background ≠ reward output ≠ guard output.

JSON names IDs. Rust owns `(device, feature)` electrodes and autodrop.
`assets/features.json` is copy + `usableFor` only.

## Lanes

| Piece | Where | Role |
|-------|--------|------|
| Feature registry | `rust/src/api/features.rs` | `available_features` / `set_enabled_features` / `set_feature_electrodes`; 8 v1 ids |
| FeatureBus | `lib/src/feedback/feature_bus.dart` | Fan-out `FeatureDto` by id; missing ticks are not published as 0 |
| RewardLane | `lib/src/feedback/reward_lane.dart` | Native value → `RatioEngine` threshold + inhibit → reward output |
| GuardLane | `lib/src/feedback/guard_lane.dart` | Native value → percentile warn + delta rail → guard output |
| FeedbackEngine | `lib/src/feedback/feedback_engine.dart` | Interface; `RatioEngine` implements it (`target_state.dart`) |
| CalibrationRunner | `lib/src/feedback/calibration_runner.dart` | Compose stages from subscribed features |
| Gate names | `lib/src/feedback/gate_electrodes.dart` | Names, never indices, resolved against the device montage |
| Feature probe | `lib/src/feedback/feature_override.dart` | Debug + sim: latch native `FeatureDto.value` before the bus/lanes |

v1 feature ids (`assets/features.json` + `SPECS` in `features.rs`):

- Reward: `band.atr`, `band.tar`, `band.btr`, `band.alpha` (+ Crown `device.focus` / `device.calm`)
- Guard: `band.delta`, `ai.drowsiness` (+ Crown `device.*`). **`band.atr` is never a guard.**

`RatioEngine` success window is **wall-clock 75 s** (`epochWindowSeconds`),
not an event count. EMA adaptation per clean sample. Ceiling =
`baselineMean + 1.5·stddev`; floor = baseline percentile.

## Protocol documents

Catalog and user docs are the same type (`origin: catalog | user`).
`ProtocolType` is gone. On-disk id is a string (`drowsiness`, `user.…`).

- Catalog copy + wiring: `assets/protocols.json` via `protocol_catalog.dart`
- User docs: `user_protocol_store.dart`; builder UI `lib/src/views/protocol_builder.dart`
- Frozen catalog ids in `lib/src/feedback/protocol.dart` (`catalogProtocolIds`)

A protocol wires: reward feature + output + optional inhibit, optional guard
feature + output, background kind, calibration id, electrode **names**
(empty = Rust default).

**Crown Start is refused** whenever `listingDeviceKind` /
`lastConnectedKind` is `DeviceKind.neurosity` (real Crown/Notion or the
Crown (OSC) / Notion (OSC) simulator rows). Catalog may list band protocols
on that kind; `startCalibration` must not silently train C3/F5.

`DeviceKind` is Muse | Neurosity. Simulation is `ConnectSource.simulator` +
`sim:*` ids, not extra enum variants. List filter is last connected this
process; no device this process → show all catalog rows.

Non-reward catalog rows: `recordOnly` (calibration skippable) and
`guardrailOnly` (warnings only).

## Calibration

`assets/calibrations.json` v2. Each id (`eyes-closed-01` / `eyes-open-01`)
has `single` (one random intro + **50 s** silent baseline) and `staged`
(artifacts 15 s / eyes-open 30 s / eyes-closed 45 s).

Variant: AI model ready → staged; band math / no guardrail → single.
`CalibrationRunner` composes stages from the subscribed features.

## Audio outputs

`lib/src/audio/output_ids.dart`:

- `RewardOutputId`: `chime` / `musicFilter` / `rainStage` / `binauralSwell` / `none`
- `BackgroundKind`: `drone` / `droneLoop` / `rain` / `userMusic` / `binaural` / `none`
- Guard sounds: soft bowl / bell / cough / volume-ramped alarm / none

Five volume channels (master × background / feedback / intro / end bell /
guardrail). Music + AI at once is allowed; a one-time stutter warning fires
at **choice** time (`_maybeWarnMusicAiCpu`).

`SoLoudEngine` owns init/deinit, epoch, and the bundled-asset cache.
Session start: `AudioService.ensureReady(reopenIfProfileDiffers: true)`.
Muffle is `RewardOutput.setMuffle` (GuardLane); it ducks modulated reward
plus both binaural controllers, not the unmapped background loop. Spec:
[../audio-engine.md](../audio-engine.md).

## State machine

```
Idle → Calibrating → Playing ⇄ Paused → Ended → Dashboard
                   └ interrupted (disconnect / bad signal, auto-resume)
```

Orchestrator: `lib/src/feedback/feedback_state.dart`. No ready phase — a
finished baseline always calls `startPlaying()`.

## Recording

Three temps under scratch while playing (`.raw` / `.computed` / `.metadata`).
At `end()`, assemble a v5 container into scratch (placeholder WebP), then
set `phase = ended`. Dashboard and history both
`v5ExtractComputed` → `prepareChartDataFromComputed`. Save publishes to the
history folder; Discard deletes the scratch v5.

Crash recovery (`crash_recovery.dart`) scans `scratchDirectory` for leftover
scratch v5 and orphan three-temps, assembles via `writeScratchV5`, then
Save → `publishSession` or Discard → delete.

One assembler: `session_assembler.dart`. Spec archive:
[../archive/session-computed-charts.md](../archive/session-computed-charts.md).
