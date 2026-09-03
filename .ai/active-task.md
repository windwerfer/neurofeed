# Active Task

**Branch:** `feat/connect-simulator-ux`

Pipeline PRs 1–7 and session charts from v5 computed 1 Hz are on `main`.
Frozen pipeline: [feedback/pipeline-contract.md](feedback/pipeline-contract.md).
Do not reopen those Key Decisions. **Crown Start stays refused.**

## In progress — connect simulator UX + settings cleanup

**Frozen spec:** [connect-simulator-ux.md](connect-simulator-ux.md).  
**Start here:** [handoff-connect-simulator-ux.md](handoff-connect-simulator-ux.md).

Connect dropdown becomes Muse | Neurosity | Simulator (Simulator only in
Debug mode). `DeviceKind` collapses to Muse | Neurosity; simulation is
`simulate` + `sim:*` ids. Neurosity listing is OSC-only (empty OK — do not
fix OSC connect). Simulator catalog includes Crown (OSC) / Notion (OSC) as
local 8-ch simulator, no UDP.

Collaterals: remove Settings “AI sleep guardrail” card; fix settings scroll
hitch; Debug mode switch.

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
