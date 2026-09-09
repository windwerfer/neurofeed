# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md) **rev 5**, implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).

## Last thread — PR 3 ASCII (approved, specs locked)

Wireframe approved. Frozen spec updated (rev 5). Painters **not** in this
thread — next thread implements PR 3.

- Y: **dB** = `10·log10` of linear µV²/Hz (Muse app / SDK / Mind Monitor).
  BandCache stays linear.
- Mean of selected electrodes **in dB**.
- Pinch-X → dropdown **`custom`**; 15/30/60/120 restore. Default 30 s.
- Overshoot: dashed hold at last in-range Y, isolated in
  `overshoot_hold.dart` (<100 lines, easy to strip).
- One pane, five series, electrode text toggles, Record hidden.

## Landed

- PR 0 — `lib/src/session_v5/`
- PR 1a — `MonitorController` in `main()` + band cache
- PR 1b — tmp writer + exclusive lease
- PR 1c — file-backed Inspect of tmp `.raw` (`3fb276b`)
- PR 2 — GraphShell + N stacked sweep EEG panes (`a9717bb`)
- PR 3 ASCII — spec rev 5 (this commit)

## Next

**PR 3 implementation** — Bands on GraphShell + electrode toggles.
ASCII already approved; **do not wait**. Handoff section
“This thread — PR 3”. Hide Record until 5a.

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
