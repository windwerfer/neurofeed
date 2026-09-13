# Active Task

**Branch:** `refactor/monitor`

**Now:** graph draw-path perf, PRs **1–7** (PR **8** gated). Plan:
[archive/handoff-monitor-perf.md](archive/handoff-monitor-perf.md).
**Next thread:** short prompt pointing at
[archive/handoff-monitor-perf-4.md](archive/handoff-monitor-perf-4.md)
(Spectrogram heatmap bitmap). Sequential local
commits. Do not push, do not new branch.

Monitor product series **complete** (spec [monitor.md](monitor.md)). PRs
**0–7 landed**, product **PR 8 cancelled**. History:
[archive/handoff-monitor.md](archive/handoff-monitor.md).

Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).
Do not add averaging, a Bands strip on Spectrogram, Spectrogram FFT-window
chrome, or `SMOOTH` / `REAL TIME` Bands chrome.

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
