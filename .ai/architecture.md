# Architecture

## Stack

```
Flutter UI (lib/src)  — Riverpod
        │
flutter_rust_bridge 2.11.1
        ▼
rust_lib_muse_ml
  muse.rs            BLE scan/connect/subscribe, 1 Hz derived metrics, forwarder
  features.rs        feature registry → MuseEventDto::Feature
  device_config.rs   DeviceKind + electrode montage
  neurosity_osc.rs   Crown/Notion OSC
  simulator.rs       spawn_simulator: Eeg/Ppg/IMU/Telemetry (`sim:*`)
  reve.rs            model + guardrail FFI
  session_format.rs  .muse v4 body + .muse.feedback v5 container
  analysis/{gesture,reve,luna,guardrail}.rs
        │
        ├─ muse-rs 0.1.1 (patched fork of eugenehp 0.1.0)
        │     transport: btleplug 0.12.0-muse-5
        │     protocol:  parse.rs / protocol.rs / types.rs
        └─ reve-rs / luna-rs (git deps, RLX CPU)
```

`scan()` / `connect()` / `subscribe_events()` are the BLE FFI entry points.
`subscribe_events()` returns `Stream<MuseEventDto>` that drives UI, recording,
streaming, and the feedback orchestrator.

Permissions: `requestBlePermissions()` in `app.dart`. BLE init:
`main()` → `RustLib.init()` → MethodChannel `muse_ml/init` `ensureInitialized`
→ `museAndroidInit()` JNI → `btleplug::platform::init(&env)`. Details:
[btleplug.md](btleplug.md), [muse-rs.md](muse-rs.md).

## Devices

`DeviceKind` is `Muse` | `Neurosity` (headset family: montage / features /
Crown-start-refused). Simulation is not a kind — it is `connect_with_options`
`simulate: true` plus synthetic `sim:*` ids. Connect dropdown is Dart
`ConnectSource` { muse, neurosity, simulator } in
`lib/src/connect_source.dart` (catalog + Muse BLE filter). Simulator is
Debug mode only (`enable_simulated_devices`). Spec:
[connect-simulator-ux.md](connect-simulator-ux.md).

`DeviceConfig` owns channel count, electrode **names**, gate electrodes,
sampling rate, PPG/IMU flags.

| Source | Kind | Transport | Notes |
|------|-----------|--------|--------|
| Muse | muse | btleplug via muse-rs | BLE scan, Muse only. 4 pads TP9/AF7/AF8/TP10 @ 256 Hz |
| Neurosity | neurosity | OSC (`neurosity_osc.rs`) | Never BLE. Empty list OK (no OSC discovery yet). 8 ch |
| Simulator | muse or neurosity from the row | `simulator.rs` locally | Static catalog; Crown (OSC) / Notion (OSC) are 8-ch sim, no UDP. Emits headset events only (`Eeg` / `Ppg` / IMU / `Telemetry`); the forwarder derives bands, features, pulse, SpO2, quality. |

**Crown Start is refused** (`crownSessionUnsupportedMessage` in
`lib/src/feedback/protocol.dart`) whenever `kind == DeviceKind.neurosity`
(real or simulated). Muse simulator rows stay startable.

## Feature pipeline

JSON names IDs; Rust owns `(device, feature)` electrodes and autodrop.
Dart owns the session. Frozen decisions:
[feedback/pipeline-contract.md](feedback/pipeline-contract.md).
Implemented map: [feedback/architecture.md](feedback/architecture.md).

```
Headset / simulator
  → always-on Bands / Movement / Gestures
  → feature registry (subscribed ids only)
  → MuseEventDto stream
       ├─ FeatureDto → FeatureBus → RewardLane / GuardLane
       ├─ always-on bands → inhibit (beta/delta ceiling) + pad quality UI
       └─ SessionRecorder (v5 temps)
```

Copy for features: `assets/features.json` (`usableFor`: `reward` / `guard`).
`band.atr` is never a guard. Inhibit ≠ guard. Background ≠ reward output.

Debug + simulated device: `FeatureOverride` can latch `FeatureDto.value` by
id in `FeedbackStateNotifier._onEvent` (playing/paused only). Session
**Feature probe** card: master switch + one slider per present feature.
Skip-cal on a sim seeds a synthetic baseline so percentile/`inTarget` work.

## Session files

`.muse.feedback` v5, Rust-owned (`rust/src/api/session_format.rs`):

```
[68-byte header][WebP thumb][metadata zstd][computed 1 Hz zstd][raw zstd]
```

Raw body is format v4 (f32 payloads, f64 timestamps), framed zstd. Dart
delegates: `encodeSessionEvent` / `sessionFrameBytes` / `sessionParseBody` /
`containerEncodeV5` / `v5ParseHead` / `v5ExtractComputed`.

History list: SQLite `session_metadata.db` (typed columns + thumbnail BLOB).
At session `end()`, assemble a real v5 into scratch (placeholder WebP);
dashboard/history `v5ExtractComputed` → `prepareChartDataFromComputed`.
Save publishes to the history folder. Crash recovery scans
`scratchDirectory`. No `SessionOverview` / 400-bucket `metadata.summary`.
The list sparkline is the WebP thumbnail. Assembler:
`lib/src/feedback/session_assembler.dart`.

## Audio

`AudioService` over flutter_soloud. Five volume channels: master ×
background / feedback / intro / end bell / guardrail warning.

`SoLoudEngine` is the process singleton: init/deinit, AAudio profile, epoch,
and bundled-asset cache. Controllers do not deinit it. The Android AAudio
profile (`Settings.audioStableMode`) reopens only at session start
(`AudioService.ensureReady(reopenIfProfileDiffers: true)`). Bundled files
go through `SoLoudEngine.loadAsset`; user music uses `loadFile` and is not
cached.

Reward outputs (`RewardOutputId`): `chime`, `musicFilter`, `rainStage`,
`binauralSwell`, `none`. Background (`BackgroundKind`) is unmapped to a
feature. Guard outputs warn only — they never change `inTarget`.
Muffle is `RewardOutput.setMuffle` (GuardLane); it ducks modulated reward
plus both binaural controllers, not the unmodulated background loop.

## Network streaming

`StreamingController` mixes per-group channels (`StreamingMixer`) on connect.

- **OSC** — unicast UDP, batched `oscEncodeMessage`
- **LSL** — `liblsl`, auto-discovered
- **BrainFlow** — multicast "Streaming Board": raw LE f64, no header, 3
  samples/datagram. IMU/PPG on port+1/+2 only when `separateGroups` is on.

Wire-format reference: `third_party/brainflow/` (tag 5.9.0), not a build dep.

## Export

`SessionExporter`: PDF, PNG (thumb + charts), Mind Monitor CSV, EDF+
(`encodeEdfExport` → `third_party/edf_export`). PDF/PNG charts share
`prepareChartDataFromComputed` with the dashboard. CSV/EDF use the framed
raw body. Destination `<root>/export/`.

## Signal quality + gate

Pad quality 0–100: EEG std + `BandsDto.line_noise_ratio` (Dart UI dots) and
the same formula in Rust for autodrop (`pad_quality_from_std_and_noise`).
Before calibration: gate electrodes green for 3 s. After baseline: no re-lock.
Playing pauses only when **all** gate pads are critical for 10 s; never
auto-ends. Band features skip pads below 80; no usable pad → no `FeatureDto`
that tick (never emit `0.0`).
