# Active Task

**Branch:** `feat/session-computed-charts`

Pipeline PRs 1–7 are committed. Frozen spec:
[feedback/pipeline-contract.md](feedback/pipeline-contract.md). Do not reopen
those Key Decisions. **Crown Start stays refused.**

## In progress — session charts from v5 computed 1 Hz

**Frozen.** Steps 1–7 implemented on this branch. Spec:
[feedback/session-computed-charts.md](feedback/session-computed-charts.md).
Resume notes: [feedback/handoff-session-computed-charts-resume.md](feedback/handoff-session-computed-charts-resume.md).

Computed 1 Hz is the only summary waveform. Scratch v5 is assembled at
`end()`. No `SessionOverview` / 400-bucket metadata. Crash recovery scans
`scratchDirectory` and reuses `assembleV5Container` / `writeScratchV5`.

Still not verified on device/desktop: `flutter run -d linux` session-end
graphs + Save to history (not `.cache`).

## Not this thread

- On-device QA (calibration, audio, streaming, export) — leftover boxes in
  [feedback/todos.md](feedback/todos.md).
- Crown *run* (quality vectors, computed frames, charts device-aware).
- Android foreground service so recording survives app background.
- Publish `third_party/edf_export` to git+tag once export proves out on device.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
