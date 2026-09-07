# Active Task

**Branch:** `refactor/monitor`

Monitor series (frozen spec [monitor.md](monitor.md), implementer
[TODO/handoff-monitor.md](TODO/handoff-monitor.md)). One PR per thread.
Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header.

## This thread — PR 1b (implemented)

Replace dual `session_` writers with an exclusive `tmp_` capture lease.

- `AppStateNotifier.sessionRecorder` is gone. Connect starts rolling
  `tmp_$ts.{raw,computed,json}` (Settings `recordStreams` applied).
- Feedback `startCalibration` `acquireFeedbackLease` (discards tmp).
  `end()` releases only when `!_recorder.isRecording`. Failed assemble
  stays `CaptureKind.feedback` and does not start tmp.
- Launch glob-deletes leftover `tmp_*` after feedback crash recovery.
  Feedback `crash_recovery.dart` still `session_*` only.
- `GET /state` exposes `captureKind` and `captureElapsedSeconds`.
- No GraphShell, no Record button, no `recording_` live UI, no file-backed
  Inspect (PR 1c).

## Landed

- PR 0 — `lib/src/session_v5/`
- PR 1a — `MonitorController` in `main()` + band cache
- PR 1b — tmp writer + exclusive lease (this commit)

## Next

**PR 1c** — file-backed Inspect of tmp `.raw` (required). Index flush
boundaries; `getRange` prepends `sessionHeaderBytes()` then
`sessionParseBody`. Then PR 2 GraphShell (ASCII first). Hide Record until 5a.

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
