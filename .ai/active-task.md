# Active Task

**Branch:** `feat/connect-simulator-ux`

Pipeline PRs 1–7 and session charts from v5 computed 1 Hz are on `main`.
Frozen pipeline: [feedback/pipeline-contract.md](feedback/pipeline-contract.md).
Do not reopen those Key Decisions. **Crown Start stays refused.**

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

Still not verified on device/desktop: Simulator tap-to-connect and Settings
scroll feel (`flutter run` / `flutter run -d linux`).

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
