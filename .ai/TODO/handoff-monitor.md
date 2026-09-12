# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-12 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** Rev **6**. Bands Y is **dB display**. **PR 5b crash recovery + sqlite `kind` landed.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `a9717bb`, PR 3 ASCII `8e45d37`, PR 3 `878cc8a`, PR 4 ASCII `4c968fa`, PR 4 `c3a40f5`, PR 5a `4fc83ec`, PR 5b **this commit**). |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 6** (unified History + filter + Save files to folder). |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, Unified History, folder-change UI, sqlite `kind`). This file is implementer order, current-code pitfalls, and the **PR 6** start. Do not re-design graphs, naming, or the lease. Do not implement 7 or 8.

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

**PR 6 (this thread). Unified History + filter + Save files to folder. Do not start 7/8.**

```
Implement monitor PR 6 only: unified History list + filter + Save files to folder. Spec: .ai/monitor.md (frozen, rev 6). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 6”).
Sidebar label History (enum stays feedbackHistory). Filter All | Feedback | Recordings. kind=feedback row → FeedbackDashboardView; kind=recording row → monitor/views/recording_dashboard.dart (Follow disabled). Sqlite kind already landed in 5b; v1 list is sqlite-only (no directory backfill of recording_* without a row). No AppView.recordings. No recording_metadata.db.
Settings card Save files to folder. Folder-change dialog counts both prefixes: “Move {s} session(s) and {r} recording(s) into the new folder? Choosing No leaves them in the current folder.” moveAllTo copies session_ and recording_ .muse.feedback. Invalidate sessionListProvider from _applyFolder and _resetFolder. Delete/read recording files via the sqlite path column (not session_$id).
Do not implement 7 or 8. Do not change graph painters. Do not touch feedback crash_recovery.dart scanners.
When done: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 7 (Landed + This thread + fenced next-thread prompt); reply with that fenced prompt so it can be pasted into the next thread. Do not skip the commit or the next-thread prompt.
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
| **5a** | `4fc83ec` — Record / Stop / assemble / 409 `recording_active`. |
| **5b** | **this commit** — Crash recovery for `recording_*` + sqlite `kind`. |

### PR 5b shipped

- Launch: after feedback `showCrashRecoveryDialog`, glob-delete `tmp_*`, then scan `recording_*` only. Assembled leftover v5 → `RecordingSaveDiscardDialog`. Temps only → `writeScratchV5(prefix: recording)` then the same dialog. Title **`Incomplete recording detected`**. Same widget as 5a Stop (title param). `tmp_*` glob unchanged. Feedback `crash_recovery.dart` scanners untouched.
- `RecordingStore.publish` copies scratch v5 into the history root as `recording_$ts.muse.feedback` and upserts `session_metadata.db` with `kind = 'recording'`, protocol empty. Discard deletes scratch + leftover temps, no sqlite row.
- `ALTER TABLE sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'feedback'` (existing rows migrate). `SessionStore.publishSession` sets `kind = 'feedback'`. v1 list is sqlite-only. No `recording_metadata.db`. No `AppView.recordings`.
- 5a live Save now goes through `RecordingStore.publish` (file + sqlite). `RecordingSaveHost` unchanged.

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
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no — landed | 5a |
| **6** | Unified History list + filter + Save files to folder | no — **this thread** | 5b |
| **7** | Bands context strip (~30%) under Histogram and PSD | **yes** | 4, 6 |
| **8** | Spectrogram `FFT 1s ▾` 0.5 / 1 / 2 s (128 / 256 / 512) | no | 4, 7 |

Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 5b)

| Piece | Where | After 5b |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts` on connect; **Record** starts `recording_$ts.{raw,computed,json}`. |
| Index | `monitor/cache/recording_index.dart` | Same `RecordingIndex` on tmp and recording `flushRaw`. Rotate (tmp only) clears. |
| Assemble | `MonitorRecorder.assemble` → `writeScratchV5(prefix: recording)` | Placeholder WebP. Never assemble tmp. |
| Save/Discard | `monitor/views/recording_save_discard.dart` | Title param. Live Save → `RecordingStore.publish`. Crash recovery title `Incomplete recording detected`. `RecordingSaveHost` on `AppShell`. |
| GraphShell | `monitor/graph_shell.dart` | `showRecord: true` on five views. Record / Stop recording. Landscape hides toolbar. |
| CaptureLease | `monitor/recording/capture_lease.dart` | idle/tmp/recording/feedback. tmp→recording, recording→idle. Feedback refuses recording. |
| Agent | `agent_commands.dart` | `/record/start\|stop`; `_start` 412 `not_connected` → 409 `crown_refused` → 409 `recording_active`. |
| Feedback Start | `feedback_session.dart` | `_refuseCrownStart` then `_refuseRecordingStart`. |
| Crash recovery | `monitor/recording/crash_recovery.dart` | `recording_*` scan + assemble temps. Launch after feedback dialog + tmp glob. |
| RecordingStore | `monitor/recording/recording_store.dart` | publish = history-root file + sqlite `kind=recording`. Discard deletes scratch. |
| Sqlite | `feedback/session_sqlite.dart` | `kind TEXT NOT NULL DEFAULT 'feedback'`. |
| History list | `views/feedback_history.dart` | Still **Feedback History**. No filter. `SessionStore.delete` / read still `session_$id` only. |
| Folder change | `views/settings_view.dart` | Card **Save feedback to folder**. `_onPickFolder` counts `session_` only. `moveAllTo` copies `session_` only. |

---

## This thread — PR 6

**Title:** `Unify History list with All/Feedback/Recordings filter`

No ASCII. Spec: Unified History, folder-change UI, `moveAllTo` both prefixes, recording dashboard.

When done, follow **Close the thread** (commit + rewrite this file for PR 7 + fenced next-thread prompt). Do not skip it. PR 7 is ASCII first (Bands context strip).

### Do

- **Sidebar label** `Feedback History` → **`History`**. Enum stays `AppView.feedbackHistory`. ui-map.
- **Filter** All | Feedback | Recordings on `FeedbackHistoryView`. `kind` is already a sqlite column (5b). Carry it on the list row (`SessionSummary` or a thin wrapper) so the view can filter. Default All.
- **Open row:** `kind = feedback` → `FeedbackDashboardView` (unchanged). `kind = recording` → **`monitor/views/recording_dashboard.dart`**. Follow is **disabled** (no live stream). Inspect saved recording via `v5ExtractRaw` (in-memory body; prepend is already in the extracted body). Reuse monitor panes; do not fork painters. v1 thumbnails are placeholder WebP — no sparkline for recordings.
- **Read / delete by sqlite `path`.** `SessionStore._museName` is `session_$id`. Recordings are `recording_$id.muse.feedback`. Delete, `readContainer`, `readPng` must use the row's `path` (or `RecordingStore`) so History delete of a recording actually removes the file.
- **Settings card** `Save feedback to folder` → **`Save files to folder`**. Dialog body: `Move {s} session(s) and {r} recording(s) into the new folder? Choosing No leaves them in the current folder.` Count **both** prefixes from `listFiles()`. `_applyFolder(migrate: true)` copies both (extend `SessionStore.moveAllTo` or a helper). Invalidate `sessionListProvider` from `_applyFolder` **and** `_resetFolder` (reset already does).
- **v1 list is sqlite-only.** Do not add a directory backfill of `recording_*.muse.feedback` without a row. Files published in 5b already have rows.
- Update `.ai/ui-map.md` (History, filter, Save files to folder, folder-change dialog).

### Do not

- PR 7 Bands strip. PR 8 FFT dropdown.
- Change Histogram / PSD / Spectrogram / Bands / Raw EEG **painters**.
- `AppView.recordings`. A second sqlite. `recording_metadata.db`.
- Directory backfill / restore stub `backfillPending` for recordings.
- Assemble `tmp_`. Touch `session_*` scanners.
- Crown Start, OSC-connect, v5 header, growing pads to 8.
- Widget goldens / `integration_test`.
- EDF/CSV/PDF export of recordings.

### Target files

```
lib/src/views/feedback_history.dart          # History label in the view; filter; open by kind
lib/src/app.dart                             # sidebar label History
lib/src/views/settings_view.dart             # Save files to folder; count both prefixes
lib/src/feedback/session_store_core.dart     # list kind; moveAllTo both prefixes; delete/read by path
lib/src/monitor/views/recording_dashboard.dart  # NEW
lib/src/feedback/session_metadata.dart       # SessionSummary.kind if needed

test/monitor/recording_store_test.dart       # moveAllTo recording_ (or new history test)
test/session_store_test.dart                 # if moveAllTo / delete path changes

.ai/ui-map.md
.ai/test-matrix.md
```

### Tests

- List includes `kind = recording` rows from sqlite; no scan of history-root files without a row
- Filter All / Feedback / Recordings (pure Dart on summaries)
- `moveAllTo` copies `recording_*.muse.feedback` as well as `session_*`
- Delete of a recording removes `recording_$id.muse.feedback` (not a missing `session_$id`)
- `flutter analyze lib/src` clean

### Verify (PR 6)

```bash
flutter analyze lib/src
cargo build --manifest-path rust/Cargo.toml
flutter test test/monitor/ test/session_store_test.dart
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`.

### PR 6 done when

- Sidebar says **History**; filter All | Feedback | Recordings
- Recording row opens `recording_dashboard.dart`; feedback row still opens the session dashboard
- Folder-change copies both prefixes; card **Save files to folder**
- sqlite-only list; no `AppView.recordings`
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 7, **commit**, reply with the fenced PR 7 paste prompt

---

## Next threads (do not start in PR 6)

### PR 7 — Bands context strip under Histogram and PSD (ASCII first)

After 6. Spec section **Histogram + PSD — Bands as a time map (PR 7)**. PR 4 left `Column` + `Expanded` + shared epoch. **Paste ASCII and wait** before painters.

### PR 8 — Spectrogram FFT window

After 7. `FFT 1s ▾` 0.5 / 1 / 2 s → 128 / 256 / 512. `dsp.dart` `n` already parameterized. Then archive this handoff.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`, `feedback/session_sqlite.dart` (`RecordingStore.publish` upserts `kind`).

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`. `_refuseRecordingStart` in `views/feedback_session.dart` is the other allowed edge (PR 5a). History list may import `monitor/views/recording_dashboard.dart` (PR 6).

History list stays `lib/src/views/feedback_history.dart`. Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **Sqlite `kind` already landed in 5b.** 6 is the History UI filter, not another column.
- **v1 list is sqlite-only.** Do not add a directory backfill of `recording_*.muse.feedback` without a row.
- **`SessionStore._museName` is `session_$id`.** Recordings live at `recording_$id.muse.feedback`. Delete / read / export must use the sqlite `path` (or you will no-op delete and leave orphans).
- **`moveAllTo` today copies `session_` only.** Folder-change would orphan recordings. Copy both prefixes; SAF `listFiles` is tree-root only (no `recordings/` subfolder).
- **No `AppView.recordings`.** Enum stays `feedbackHistory`; on-screen **History**.
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
