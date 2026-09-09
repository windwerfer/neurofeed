# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md), implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header.

## Last thread — PR 2 (implemented)

GraphShell + N stacked sweep EEG panes.

- `SweepBuffer` moved to `monitor/cache/`; owned by `MonitorController`.
- Default 10 s (2560 samples). Muse-4 vs Crown-8 from `lastConnectedKind`.
- Follow: thin theme wipe, gray traces, names in-pane top-right.
- Inspect: wipe + previous pass vanish; fill-right with live data;
  pan uses RAM; older than 5 min calls `FileBackedSource`.
- Record hidden. No chips, no add/remove. Deleted `graph_config` /
  `eeg_dashboard` / `eeg_chart` / `live_cache` / old Raw EEG views.

## Landed

- PR 0 — `lib/src/session_v5/`
- PR 1a — `MonitorController` in `main()` + band cache
- PR 1b — tmp writer + exclusive lease
- PR 1c — file-backed Inspect of tmp `.raw` (`3fb276b`)
- PR 2 — GraphShell + N stacked sweep EEG panes (`28008c9`)

## Next

**PR 3** — Bands on GraphShell + electrode toggles. **ASCII first**, then
wait (handoff section “This thread — PR 3”). Hide Record until 5a.

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- Histogram / PSD / Spectrogram (PR 4), Record button (PR 5a).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
