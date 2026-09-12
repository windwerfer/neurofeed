# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md) **rev 6**, implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).

## Last thread — PR 5b

Crash recovery for leftover `recording_*` (temps assemble, assembled v5
dialog). Title `Incomplete recording detected`. `RecordingStore.publish`
upserts `session_metadata.db` `kind = 'recording'`. Existing rows default
`feedback`. Live Save wired through publish. tmp glob and feedback
`session_*` scanner unchanged.

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
- PR 5a — Record / Stop / assemble / 409 `recording_active` (`4fc83ec`)
- PR 5b — Crash recovery + sqlite `kind` (this commit)

## Next

**PR 6** — Unified History + filter + Save files to folder. Handoff
section “This thread — PR 6”. Then **7** Bands strip (ASCII first),
**8** Spectrogram `FFT 1s ▾`.

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- PR 7 Bands context strip. PR 8 Spectrogram FFT window.
- Changing graph painters.

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
