# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md) **rev 6**, implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).
**PR 4 ASCII is approved** (landscape cinema, spectrogram `mag ▾`,
Histogram/PSD one pane; PR 7 context strip and PR 8 FFT window are later).

## Last thread — PR 4 ASCII (docs)

Spec rev 6. Painters are the next thread. Do not paste-and-wait again.
Do not implement PR 7 or PR 8 in PR 4; leave the hooks (Column + Expanded,
parameterized FFT `n`).

## Landed

- PR 0 — `lib/src/session_v5/`
- PR 1a — `MonitorController` in `main()` + band cache
- PR 1b — tmp writer + exclusive lease
- PR 1c — file-backed Inspect of tmp `.raw` (`3fb276b`)
- PR 2 — GraphShell + N stacked sweep EEG panes (`a9717bb`)
- PR 3 ASCII — spec rev 5 (`8e45d37`)
- PR 3 — Bands on GraphShell (`878cc8a`)
- PR 4 ASCII — spec rev 6 (this commit)

## Next

**PR 4 painters** — Histogram + PSD + Spectrogram. ASCII already
approved. Handoff section “This thread — PR 4”. Hide Record until 5a.
After 6: **PR 7** Bands strip under Histogram/PSD, then **PR 8**
Spectrogram `FFT 1s ▾`.

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- Record button (PR 5a).
- PR 7 Bands context strip. PR 8 Spectrogram FFT window.
- Changing Bands or Raw EEG painters.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
