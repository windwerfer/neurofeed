# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md), implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header.

## Last thread — PR 1c (implemented)

File-backed Inspect of tmp/recording `.raw`.

- `RecordingIndex` entries `(elapsedT, fileLength)` only at `flushRaw`
  frame boundaries. First frame starts at offset 12.
- `FileBackedSource.getRange` seeks complete frames, prepends
  `sessionHeaderBytes()`, then `sessionParseBody`.
- Record timestamps (ms epoch) convert to elapsed via
  `captureStartedAtMs`. Null start → no unix-epoch range.
- tmp rotate clears the index.
- Deleted unused `charts/disk_session.dart`.
- No GraphShell, no Record button, SweepEegView untouched.

**Live Inspect is still SweepBuffer 5 min RAM only.** PR 2 must wire
`FileBackedSource` before claiming 30 min Inspect.

## Landed

- PR 0 — `lib/src/session_v5/`
- PR 1a — `MonitorController` in `main()` + band cache
- PR 1b — tmp writer + exclusive lease
- PR 1c — file-backed Inspect of tmp `.raw` (this commit)

## Next

**PR 2** — GraphShell + N stacked sweep EEG panes. **ASCII first**, then
wait (handoff section “This thread — PR 2”). Hide Record until 5a.
Inspect beyond 5 min uses 1c `FileBackedSource`.

## Not this thread

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- GraphShell (PR 2), Record button (PR 5a).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
