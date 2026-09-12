# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md) **rev 6**, implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).

## Last thread — PR 5a

Record / Stop recording on GraphShell. `recording_$ts` temps, assemble on
Stop, Save/Discard (file copy, no sqlite `kind`). 409 `recording_active`.
`POST /record/start|stop`. `_refuseRecordingStart`. Same `RecordingIndex`
on recording `flushRaw`.

## Landed

- PR 0 — `lib/src/session_v5/`
- PR 1a — `MonitorController` in `main()` + band cache
- PR 1b — tmp writer + exclusive lease
- PR 1c — file-backed Inspect of tmp `.raw` (`3fb276b`)
- PR 2 — GraphShell + N stacked sweep EEG panes (`a9717bb`)
- PR 3 ASCII — spec rev 5 (`8e45d37`)
- PR 3 — Bands on GraphShell (`878cc8a`)
- PR 4 ASCII — spec rev 6 (`4c968fa`)
- PR 4 — Histogram + PSD + Spectrogram painters (`c3a40f5`)
- PR 5a — Record / Stop / assemble / 409 `recording_active` (this commit)

## Next

**PR 5b** — Crash recovery + sqlite `kind`. Handoff section “This thread —
PR 5b”. Then 6 (History filter), **7** Bands strip, **8** Spectrogram
`FFT 1s ▾`.

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- PR 6 History filter / Save files to folder.
- PR 7 Bands context strip. PR 8 Spectrogram FFT window.
- Changing graph painters.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
