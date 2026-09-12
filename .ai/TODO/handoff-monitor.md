# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-12 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** Rev **6**. Bands Y is **dB display**. **PR 5a Record/Stop landed.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `a9717bb`, PR 3 ASCII `8e45d37`, PR 3 `878cc8a`, PR 4 ASCII `4c968fa`, PR 4 `c3a40f5`, PR 5a **this commit**). |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 5b** (crash recovery + sqlite `kind`). |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, recording lifecycle, Capture lease, crash recovery, sqlite `kind`). This file is implementer order, current-code pitfalls, and the **PR 5b** start. Do not re-design graphs, naming, or the lease. Do not implement 6 (History filter / Save files to folder), 7, or 8.

---

## Close the thread (every PR)

A thread is **not done** until all four are true. Do not ask permission.

1. Code + tests + `flutter analyze lib/src` green.
2. **Rewrite this handoff** for the next PR in the same change:
   - Landed table: this PR's **commit hash** (or `this commit` if hashing after) + one-line note
   - Current-code table
   - Compact “what shipped” for this PR; full **This thread — PR N+1** brief (target files, do/don't, tests, pitfalls)
   - **Paste this to start a new thread** is a fenced prompt for PR N+1 only
   - `.ai/active-task.md` matches (last thread landed, next is N+1)
3. **Commit** code + this file + `active-task.md` (and ui-map / test-matrix when the spec says). Do not leave the handoff uncommitted. Do not end with “I can commit if you want.”
4. Reply with the **next-thread prompt in a fenced block** the user can copy into a new chat. Nothing else required from them.

After **PR 8**: archive this file to `.ai/archive/`, update `.ai/architecture.md` / `.ai/README.md`, commit, and reply that the series is complete (no next-thread prompt).

---

## Paste this to start a new thread

**PR 5b (this thread). Crash recovery + sqlite `kind`. Do not start 6/7/8.**

```
Implement monitor PR 5b only: crash recovery for recording_* + sqlite kind. Spec: .ai/monitor.md (frozen, rev 6). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 5b”).
Launch: after feedback’s session_* crash dialog, scan scratch for recording_* only (not tmp_, not session_*). Assembled leftover v5 → RecordingSaveDiscardDialog. Temps only → writeScratchV5(prefix: recording, placeholder WebP) then the same dialog. Copy: Incomplete recording detected. Reuse monitor/views/recording_save_discard.dart from 5a (do not fork). tmp_* still glob-deleted (already 1b).
RecordingStore.publish copies the scratch v5 into the history root as recording_$ts.muse.feedback and upserts session_metadata.db with kind = 'recording' (add the column here; DEFAULT 'feedback' migrates existing rows). Discard deletes scratch. v1 list is sqlite-only. No recording_metadata.db. No AppView.recordings.
Do not implement 6 (History filter / Save files to folder), 7, or 8. Do not change graph painters. Do not touch feedback crash_recovery.dart scanners.
When done: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 6 (Landed + This thread + fenced next-thread prompt); reply with that fenced prompt so it can be pasted into the next thread. Do not skip the commit or the next-thread prompt.
```

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Thin re-exports at old paths. |
| **1a** | `2a66eae` — `MonitorController` in `main()` after `appStateProvider.notifier`. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring. |
| **1b** | `8a0b9f0` — Exclusive `tmp_` writer + exclusive lease. Connect starts `tmp_$ts.{raw,computed,json}` with `Settings.recordStreams`. Feedback `acquireFeedbackLease` discards tmp; `end()` releases only if `!isRecording`. Launch glob-deletes leftover `tmp_*`. `GET /state` has `captureKind` / `captureElapsedSeconds`. |
| **1c** | `3fb276b` — `RecordingIndex` + `FileBackedSource` under `monitor/cache/`. `flushRaw` callback indexes `(elapsedT, fileLength)` at frame boundaries. `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`; timestamps are elapsed from `captureStartedAtMs`. tmp rotate clears the index. |
| **2** | `a9717bb` — GraphShell + N stacked sweep EEG panes. `SweepBuffer` on `MonitorController` (`monitor/cache/`). Default 10 s / 2560. Muse-4 vs Crown-8. Follow wipe; Inspect HOLD + fill-right; beyond 5 min calls `FileBackedSource`. Record hidden. Deleted add/remove, `graph_config`, `eeg_chart`, `eeg_dashboard`, `live_cache`, old Raw EEG views. |
| **3 ASCII** | `8e45d37` — Spec rev 5. Bands Y **dB** display; pinch-X **`custom`**; overshoot dashed hold (strippable). |
| **3** | `878cc8a` — Bands on GraphShell. One `TimeSeriesPane`, five series, mean of selected in dB. Electrode toggles (all on, last-one stays). Default 30 s; pinch-X → `custom`. Overshoot hold isolated in `overshoot_hold.dart`. Old `views/bands.dart` + `chart_controller.dart` deleted. Record hidden. |
| **4 ASCII** | `4c968fa` — Spec rev 6. Landscape cinema; spectrogram `mag ▾` color; Histogram/PSD one pane + tap readout; PR 7 Bands context strip; PR 8 Spectrogram FFT 0.5/1/2 s. |
| **4** | `c3a40f5` — Histogram + PSD + Spectrogram painters. `AppView.histogram`. Landscape cinema. `dsp.dart` Hamming `1/N²`, `n` parameterized. Record still hidden. |
| **5a** | **this commit** — Record / Stop / assemble / 409 `recording_active`. |

### PR 5a shipped

- GraphShell `showRecord: true` on all five graph views. On-screen **Record** / **Stop recording**. Disabled when `CaptureKind.feedback` or disconnected; tooltip `Stop the feedback session to record`. Elapsed only while `CaptureKind.recording`. Landscape still hides the toolbar.
- Record discards tmp (no prompt), starts `recording_$ts.{raw,computed,json}` with `Settings.recordStreams`. No pre-click bytes on disk. Same `RecordingIndex` on `flushRaw`.
- Stop flushes, `writeScratchV5(prefix: recording)` + placeholder WebP, then Save/Discard (`barrierDismissible: false`). Save copies scratch v5 into the history root; Discard deletes it; then tmp if still connected.
- In-app disconnect while recording: assemble + same dialog. Process exit: `assembleRecordingOnExit` then `disconnectOnClose`; no dialog.
- `CaptureLease` tmp→recording→idle. Feedback still refuses recording.
- Agent `POST /record/start` (412 `disconnected`, 409 `feedback_active`) and `POST /record/stop` (assemble, no publish). `persist: false`.
- `AgentCommands._start` 409 `recording_active` before `startCalibration`. Order: 412 `not_connected` → 409 `crown_refused` → 409 `recording_active`.
- UI `_refuseRecordingStart` after `_refuseCrownStart`. Title `Recording in progress`; Start is not auto-continued.
- **Sqlite `kind` is 5b.** History filter is 6. Painters unchanged.

---

## Series map (do not collapse)

| PR | Thread title | ASCII? | Depends |
|---|---|---|---|
| **0** | Extract `lib/src/session_v5/` | no | — |
| **1a** | `MonitorController` in `main()` + band cache; no disk | no | 0 |
| **1b** | `tmp_` writer + exclusive lease (kills dual `session_` writers) | no | 1a |
| **1c** | File-backed Inspect of tmp/recording `.raw` | no | 1b |
| **2** | GraphShell + N stacked **sweep** EEG panes; cancel add/remove | **yes** (landed) | 1b; prefer 1c first |
| **3** | Bands on GraphShell + electrode toggles | **yes** (landed) | 2 |
| **4** | Histogram + PSD + Spectrogram (`AppView.histogram` only) | **yes** (landed) | 2; ∥ 3 |
| **5a** | Record / Stop / assemble / 409 `recording_active` | no — landed | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no — **this thread** | 5a |
| **6** | Unified History list + filter + Save files to folder | no | 5b |
| **7** | Bands context strip (~30%) under Histogram and PSD | **yes** | 4, 6 |
| **8** | Spectrogram `FFT 1s ▾` 0.5 / 1 / 2 s (128 / 256 / 512) | no | 4, 7 |

Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 5a)

| Piece | Where | After 5a |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts` on connect; **Record** starts `recording_$ts.{raw,computed,json}`. |
| Index | `monitor/cache/recording_index.dart` | Same `RecordingIndex` on tmp and recording `flushRaw`. Rotate (tmp only) clears. |
| Assemble | `MonitorRecorder.assemble` → `writeScratchV5(prefix: recording)` | Placeholder WebP. Never assemble tmp. |
| Save/Discard | `monitor/views/recording_save_discard.dart` | File copy to history root / delete scratch. **No sqlite `kind` yet.** `RecordingSaveHost` on `AppShell`. |
| GraphShell | `monitor/graph_shell.dart` | `showRecord: true` on five views. Record / Stop recording. Landscape hides toolbar. |
| CaptureLease | `monitor/recording/capture_lease.dart` | idle/tmp/recording/feedback. tmp→recording, recording→idle. Feedback refuses recording. |
| Agent | `agent_commands.dart` | `/record/start\|stop`; `_start` 412 `not_connected` → 409 `crown_refused` → 409 `recording_active`. |
| Feedback Start | `feedback_session.dart` | `_refuseCrownStart` then `_refuseRecordingStart`. |
| Crash recovery | `monitor/recording/crash_recovery.dart` | **tmp glob only.** No `recording_*` scan. No `RecordingStore`. |
| Sqlite | `feedback/session_sqlite.dart` | **No `kind` column.** |

---

## This thread — PR 5b

**Title:** `Recover leftover recording_ temps on launch; sqlite kind`

No ASCII. Spec: crash / next launch sequence, `RecordingStore.publish`, sqlite `kind`, Save/Discard reuse.

When done, follow **Close the thread** (commit + rewrite this file for PR 6 + fenced next-thread prompt). Do not skip it.

### Do

- **Scan** scratch for `recording_*` only (temps `.raw` / `.computed` / `.json` and assembled `.muse.feedback`). Not `tmp_`, not `session_*`. Feedback `_idFrom` stays `session_` only — do not teach `lib/src/feedback/crash_recovery.dart` about recordings.
- **Launch order** (first frame, after feedback’s `showCrashRecoveryDialog`): delete leftover `tmp_*` (already `deleteLeftoverTmpCaptures`); then recording leftovers. Assembled v5 → `RecordingSaveDiscardDialog`. Temps only → `writeScratchV5(prefix: recording)` then the same dialog. Copy: **`Incomplete recording detected`**. Reuse `monitor/views/recording_save_discard.dart` (parameterize title if needed; do not fork a second dialog).
- **`RecordingStore.publish`** — copy scratch v5 into the history root as `recording_$ts.muse.feedback` and **upsert `session_metadata.db` with `kind = 'recording'`**. Add the column here (`ALTER TABLE … DEFAULT 'feedback'`). Protocol empty string. v1 list is sqlite-only (no stub `backfillPending` scan). No `recording_metadata.db`.
- **Discard** — delete scratch v5 (and leftover temps). Do not upsert.
- **Host** the monitor recovery dialog in `app.dart` after feedback’s `_CrashRecoveryWrapper`. Process-exit leftovers from 5a (`assembleRecordingOnExit`) land here.
- **5a Save** currently file-copies only. Wire Save (dialog + `savePendingRecording`) through `RecordingStore.publish` so a user Save in this PR also upserts `kind`. Keep monitor isolation: prefer `SessionSqlite.upsertSession` from `RecordingStore`; do not import `feedback_state.dart`.
- Update `.ai/ui-map.md` (Incomplete recording detected) if the dialog title/copy changes. `.ai/monitor/recording.md` if you add that file (spec lists it; optional if the handoff + spec already cover it).

### Do not

- PR 6 History filter All|Feedback|Recordings, sidebar label **History**, Settings **Save files to folder**, `moveAllTo` both prefixes, `recording_dashboard.dart`.
- PR 7 Bands strip. PR 8 FFT dropdown.
- Change Histogram / PSD / Spectrogram / Bands / Raw EEG **painters**.
- Assemble `tmp_`. Touch `session_*` scanners.
- Crown Start, OSC-connect, v5 header, growing pads to 8.
- Widget goldens / `integration_test`.
- `AppView.recordings`. A second sqlite.

### Target files

```
lib/src/monitor/recording/crash_recovery.dart   # scan recording_*; assemble temps
lib/src/monitor/recording/recording_store.dart  # NEW — publish / discard + sqlite kind
lib/src/monitor/views/recording_save_discard.dart  # reuse; maybe title param
lib/src/monitor/monitor_controller.dart         # Save → RecordingStore.publish
lib/src/feedback/session_sqlite.dart            # kind TEXT DEFAULT 'feedback'
lib/src/app.dart                                # after feedback crash dialog

test/monitor/crash_recovery_test.dart
test/monitor/recording_store_test.dart          # Dart+FFI (host .so)

.ai/ui-map.md
.ai/test-matrix.md
```

### Tests

Pure Dart preferred for the scanner. FFI for `publish` upsert + `kind`.

- Leftover `recording_*.raw/.computed/.json` → assemble → dialog path (scratch v5 exists)
- Leftover assembled `recording_*.muse.feedback` → dialog, no second assemble
- `tmp_*` still glob-deleted; `session_*` untouched
- `publish` upserts `session_metadata.db` with `kind = 'recording'`; existing rows `kind = 'feedback'`
- Discard deletes scratch, no sqlite row
- `flutter analyze lib/src` clean

### Verify (PR 5b)

```bash
flutter analyze lib/src
cargo build --manifest-path rust/Cargo.toml
flutter test test/monitor/
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`.

### PR 5b done when

- Launch recovers `recording_*` (temps or v5) with Incomplete recording detected + Save/Discard
- `RecordingStore.publish` writes history-root file and sqlite `kind = 'recording'`
- Existing sqlite rows default `feedback`
- tmp glob unchanged; feedback scanner unchanged
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 6, **commit**, reply with the fenced PR 6 paste prompt

---

## Next threads (do not start in PR 5b)

### PR 6 — Unified History

On-screen **History**; filter All | Feedback | Recordings. Settings **Save files to folder**; `moveAllTo` both prefixes. Recording row → `recording_dashboard.dart`.

### PR 7 — Bands context strip under Histogram and PSD (ASCII first)

After 6. Spec section **Histogram + PSD — Bands as a time map (PR 7)**. PR 4 left `Column` + `Expanded` + shared epoch.

### PR 8 — Spectrogram FFT window

After 7. `FFT 1s ▾` 0.5 / 1 / 2 s → 128 / 256 / 512. `dsp.dart` `n` already parameterized. Then archive this handoff.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`, `feedback/session_sqlite.dart` (`RecordingStore.publish` upserts `kind`).

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`. `_refuseRecordingStart` in `views/feedback_session.dart` is the other allowed edge (PR 5a).

History list stays `lib/src/views/feedback_history.dart` (PR 6). Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **Do not teach feedback `crash_recovery.dart` `recording_`.** Prefix-strict scanners.
- **Reuse 5a’s Save/Discard dialog.** Incomplete-recording copy is this PR; same widget.
- **Sqlite `kind` lands here**, not in 6. 6 is the History UI filter.
- **`publish` is file + sqlite.** 5a Save was file-copy only; wire it through `RecordingStore` so a live Save also upserts.
- **v1 list is sqlite-only.** Do not add a directory backfill of `recording_*.muse.feedback` without a row.
- **Do not assemble tmp.** Launch still glob-deletes leftover `tmp_*`.
- Agent HTTP: `persist: false`. Crown 409 stays `crown_refused`.
- `flutter analyze lib/src` after every Dart PR.

---

## Docs when a PR lands

Every PR: this handoff + `.ai/active-task.md` + **commit** + fenced next-thread prompt (see **Close the thread**). Plus:

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| `/record/*` and 409 (PR 5a) | testing-guide + ui-map |
| History label / Save files to folder (PR 6) | ui-map |
| Bands strip under Histogram/PSD (PR 7) | ui-map |
| Spectrogram `FFT 1s ▾` (PR 8) | ui-map |
| Series complete (after **8**) | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
