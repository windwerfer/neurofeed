# Active Task

**Branch:** `refactor/eeg_feature_implementation`

Pipeline PRs 1–7 (feature registry through the custom protocol builder) are
committed. Frozen spec: [feedback/pipeline-contract.md](feedback/pipeline-contract.md).
Do not reopen those Key Decisions. **Crown Start stays refused.**

## Next — session charts from v5 computed 1 Hz

**Frozen.** Implement from a new topic branch. Do not mix with the protocol
builder.

- Spec: [feedback/session-computed-charts.md](feedback/session-computed-charts.md)
- Handoff: [feedback/handoff-session-computed-charts.md](feedback/handoff-session-computed-charts.md)

Computed 1 Hz is the only summary waveform. Assemble a real v5 file in scratch
at session end. No 400-bucket `SessionOverview`.

## Not this thread

- On-device QA (calibration, audio, streaming, export) — leftover boxes in
  [feedback/todos.md](feedback/todos.md).
- Crown *run* (quality vectors, computed frames, charts device-aware).
- Android foreground service so recording survives app background.
- Publish `third_party/edf_export` to git+tag once export proves out on device.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
