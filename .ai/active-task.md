# Active Task

**Branch:** `fix/soloud-engine-hardening`

Pipeline PRs 1–7 and session charts from v5 computed 1 Hz are on `main`.
Frozen pipeline: [feedback/pipeline-contract.md](feedback/pipeline-contract.md).
Do not reopen those Key Decisions. **Crown Start stays refused.**

## This thread — SoLoud engine hardening (implemented)

Spec: [audio-engine.md](audio-engine.md). Handoff archived:
[archive/handoff-soloud-engine.md](archive/handoff-soloud-engine.md).

Engine owns init/deinit, epoch, and bundled-asset cache. Rain uses
`loadAsset` + looping. Chime preloads on `start()`. Calibration await uses
`getLength + 2s`. Alarm first tick is immediate; pause stops it.
`AudioService.setMusicMuffle` is gone; `RewardOutput.setMuffle` ducks
modulated reward plus both binaural controllers. Unmodulated background
is not ducked. `guard_lane.dart` was not edited.

## Landed — connect simulator UX + settings cleanup

Implemented on this branch. Frozen spec:
[connect-simulator-ux.md](connect-simulator-ux.md). Do not reopen those
Key Decisions. Do not mix OSC-connect or unlocking Crown Start.

Connect dropdown is Muse | Neurosity | Simulator (Simulator only in Debug
mode). `DeviceKind` is Muse | Neurosity; simulation is `simulate` + `sim:*`
ids. Neurosity listing is OSC-only (empty OK). Simulator catalog includes
Crown (OSC) / Notion (OSC) as local 8-ch simulator, no UDP.

Settings: no “AI sleep guardrail” card; music cutoff persists on
`onChangeEnd`; Debug mode switch last after About.

Simulator connect now actually starts `DeviceSimulator` on the tokio
runtime (`spawn_simulator` → EEG / PPG / IMU / telemetry). Derived
bands, pulse, SpO2, gestures, and pad quality come from the same
forwarder as a live Muse. Athena extra optical channels (8/16ch fNIRS)
are not simulated — Classic 3-ch PPG only.

Still not verified on device/desktop: Simulator tap-to-connect and Settings
scroll feel (`flutter run` / `flutter run -d linux`).

## Landed — debug agent HTTP

Loopback HTTP in `lib/src/agent/`. Drive: [testing-guide.md](testing-guide.md)
Linux agent, [test-matrix.md](test-matrix.md), skill `muse-run-linux`.
`--dart-define=MUSE_AGENT=true` (`1`/`yes` also via `parseDartDefineFlag`).

Live smoke 2026-09-05: Muse S connect (`scanMessage` null), view switch,
recordOnly skip-cal `phase=playing`, Crown 409. Widget /
`integration_test` stay deferred. Crown Start stays refused.

Handoff archived:
[archive/handoff-agent-http.md](archive/handoff-agent-http.md).

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
