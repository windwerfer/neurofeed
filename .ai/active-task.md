# Active Task

**Branch:** `refactor/monitor`

**Now:** none. Monitor product **and** draw-path perf are complete.
Spec: [monitor.md](monitor.md). History:
[archive/handoff-monitor.md](archive/handoff-monitor.md),
[archive/handoff-monitor-perf.md](archive/handoff-monitor-perf.md)
(PRs 1–7 landed; **PR 8 skipped**).

Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).
Do not add averaging, a Bands strip on Spectrogram, Spectrogram FFT-window
chrome, or `SMOOTH` / `REAL TIME` Bands chrome. Do not pause `SweepBuffer`
/ `BandCache` on view change.

## Queued elsewhere (not this branch)

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
