# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-12 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** Rev **6**. Bands Y is **dB display**. **PR 6 unified History landed.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `a9717bb`, PR 3 ASCII `8e45d37`, PR 3 `878cc8a`, PR 4 ASCII `4c968fa`, PR 4 `c3a40f5`, PR 5a `4fc83ec`, PR 5b `d4afac0`, PR 6 **this commit**). |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 7** (Bands context strip under Histogram/PSD — **ASCII first**). |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, **Histogram + PSD — Bands as a time map (PR 7)**). This file is implementer order, current-code pitfalls, and the **PR 7** start. Do not re-design graphs, naming, or the lease. Do not implement 8. **Paste ASCII and wait** before painters.

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

**PR 7 (this thread). Bands context strip under Histogram and PSD. ASCII first. Do not start 8.**

```
Implement monitor PR 7: Bands context strip (~30%) under Histogram and PSD. Spec: .ai/monitor.md (frozen, rev 6) section “Histogram + PSD — Bands as a time map (PR 7)”. Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 7”).
ASCII first: paste a two-pane wireframe (Histogram and the same for PSD) and wait for approval. Do not implement painters until the ASCII is approved in-thread. Do not start PR 8.
PR 4 already left Column + Expanded + shared ViewportController epoch. Reuse TimeSeriesPane; do not fork the Bands sidebar view. Highlight is time only (width = Histogram/PSD 2/4/8 s window). Bands strip is wider than T (default 30 s, pinch-X custom like Bands). One electrode-toggle set drives both panes. Spectrogram does not get this strip. Landscape cinema: both panes, no chrome.
When ASCII is approved: implement the strip; update .ai/ui-map.md; flutter analyze lib/src. Then Close the thread: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 8 (Landed + This thread + fenced next-thread prompt); reply with that fenced prompt. If ASCII is not yet approved, stop after the wireframe — do not implement. Do not skip the commit or the next-thread prompt once implementation lands.
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
| **5b** | `d4afac0` — Crash recovery for `recording_*` + sqlite `kind`. |
| **6** | **this commit** — Unified History + All/Feedback/Recordings filter + Save files to folder. |

### PR 6 shipped

- Sidebar **History** (`AppView.feedbackHistory` unchanged). Filter All \| Feedback \| Recordings on `FeedbackHistoryView`. `SessionSummary.kind` / `path` from sqlite. Default All.
- `kind = feedback` → `FeedbackDashboardView`. `kind = recording` → `monitor/views/recording_dashboard.dart` (Follow disabled; Inspect via in-memory `v5ExtractRaw`; reuse panes). v1 recording thumbs are not sparklines.
- v1 list is sqlite-only: no directory backfill of `recording_*` without a row. No `AppView.recordings`. No `recording_metadata.db`.
- `SessionStore` read/delete/`updateNotes` use sqlite `path` (recordings are `recording_$id.muse.feedback`, not `session_$id`). `moveAllTo` copies both `session_` and `recording_` `.muse.feedback`.
- Settings card **Save files to folder**. Folder-change dialog: `Move {s} session(s) and {r} recording(s) into the new folder? Choosing No leaves them in the current folder.` `_applyFolder` and `_resetFolder` both invalidate `sessionListProvider`.

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
| **6** | Unified History list + filter + Save files to folder | no — landed | 5b |
| **7** | Bands context strip (~30%) under Histogram and PSD | **yes** — **this thread** | 4, 6 |
| **8** | Spectrogram `FFT 1s ▾` 0.5 / 1 / 2 s (128 / 256 / 512) | no | 4, 7 |

Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 6)

| Piece | Where | After 6 |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts` on connect; **Record** starts `recording_$ts.{raw,computed,json}`. |
| Index | `monitor/cache/recording_index.dart` | Same `RecordingIndex` on tmp and recording `flushRaw`. Rotate (tmp only) clears. |
| Assemble | `MonitorRecorder.assemble` → `writeScratchV5(prefix: recording)` | Placeholder WebP. Never assemble tmp. |
| Save/Discard | `monitor/views/recording_save_discard.dart` | Title param. Live Save → `RecordingStore.publish`. Crash recovery title `Incomplete recording detected`. `RecordingSaveHost` on `AppShell`. |
| GraphShell | `monitor/graph_shell.dart` | `showRecord: true` on five live views. `followEnabled: false` on recording dashboard. Landscape hides toolbar. |
| CaptureLease | `monitor/recording/capture_lease.dart` | idle/tmp/recording/feedback. tmp→recording, recording→idle. Feedback refuses recording. |
| Agent | `agent_commands.dart` | `/record/start\|stop`; `_start` 412 `not_connected` → 409 `crown_refused` → 409 `recording_active`. |
| Feedback Start | `feedback_session.dart` | `_refuseCrownStart` then `_refuseRecordingStart`. |
| Crash recovery | `monitor/recording/crash_recovery.dart` | `recording_*` scan + assemble temps. Launch after feedback dialog + tmp glob. |
| RecordingStore | `monitor/recording/recording_store.dart` | publish = history-root file + sqlite `kind=recording`. Discard deletes scratch. |
| Sqlite | `feedback/session_sqlite.dart` | `kind TEXT NOT NULL DEFAULT 'feedback'`. |
| History list | `views/feedback_history.dart` | On-screen **History**. Filter All \| Feedback \| Recordings. Open by `kind`. |
| Recording dashboard | `monitor/views/recording_dashboard.dart` | Follow disabled. Inspect `v5ExtractRaw`. Reuses panes. |
| SessionStore | `feedback/session_store_core.dart` | List carries `kind`/`path`. Read/delete by sqlite `path`. `moveAllTo` both prefixes. sqlite-only list. |
| Folder change | `views/settings_view.dart` | Card **Save files to folder**. Dialog counts both prefixes. `sessionListProvider` invalidated from `_applyFolder` and `_resetFolder`. |

---

## This thread — PR 7

**Title:** `Add Bands context strip under Histogram and PSD`

**ASCII first.** Spec: **Histogram + PSD — Bands as a time map (PR 7)**. PR 4 left `Column` + `Expanded` + shared epoch. **Paste ASCII and wait** before painters.

When ASCII is approved and the strip is implemented, follow **Close the thread** (commit + rewrite this file for PR 8 + fenced next-thread prompt). If ASCII is not approved yet, stop after the wireframe.

### Do

- Paste a two-pane ASCII wireframe for Histogram (same chrome for PSD): ~70% histogram/PSD + ~30% Bands context strip. Highlight width = T (2 / 4 / 8 s). Bands strip **wider** than T (default **30 s**, pinch-X `custom` like Bands).
- After approval: insert `TimeSeriesPane` under the existing `Expanded` pane. Highlight overlay is **time only**. Histogram stays raw µV in `[start, start+T]`; PSD stays Welch of that window. Bands is the map, not the data source.
- One electrode-toggle set drives both panes.
- Landscape cinema: both panes, no chrome (PR 4 already cinemas GraphShell).
- Reuse `TimeSeriesPane`. Do not fork the Bands sidebar view. Do not change standalone Bands behavior except by sharing the pane widget.
- Update `.ai/ui-map.md` when chrome copy lands.

### Do not

- Implement before the ASCII is approved.
- PR 8 Spectrogram `FFT 1s ▾`.
- Give Spectrogram this strip (X is already time).
- Fork Bands view / `TimeSeriesPane`. Change Histogram / PSD / Spectrogram **painters** (the histogram/PSD painters stay; add a strip below).
- Time slider (none in PR 4; this strip replaces Inspect-elapsed as the primary time map).
- Crown Start, OSC-connect, v5 header, growing pads to 8.
- Widget goldens / `integration_test`.

### Target files (after ASCII approval)

```
lib/src/monitor/views/histogram_view.dart
lib/src/monitor/views/psd_view.dart
lib/src/monitor/panes/time_series_pane.dart   # highlight overlay only if needed; do not fork
.ai/ui-map.md
.ai/test-matrix.md
```

### Tests (after implement)

- Histogram / PSD still `Column` + `Expanded` + strip; epoch matches the highlight
- One electrode set drives both panes
- Spectrogram view unchanged (no strip)
- `flutter analyze lib/src` clean

### Verify (PR 7)

```bash
flutter analyze lib/src
flutter test test/monitor/histogram_pane_test.dart test/monitor/time_series_pane_test.dart test/monitor/graph_shell_test.dart
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`.

### PR 7 done when

- ASCII approved in-thread
- Histogram and PSD show a ~30% Bands context strip; highlight = T-second window
- Spectrogram unchanged; standalone Bands unchanged
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 8, **commit**, reply with the fenced PR 8 paste prompt

---

## Next threads (do not start in PR 7)

### PR 8 — Spectrogram FFT window

After 7. Chrome `FFT 1s ▾` 0.5 / 1 / 2 s → 128 / 256 / 512. `dsp.dart` `n` already parameterized. PSD Welch stays 1 s / 256-pt. Then archive this handoff.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`, `feedback/session_sqlite.dart` (`RecordingStore.publish` upserts `kind`).

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`. `_refuseRecordingStart` in `views/feedback_session.dart` is the other allowed edge (PR 5a). History list may import `monitor/views/recording_dashboard.dart` (PR 6).

History list stays `lib/src/views/feedback_history.dart`. Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **PR 7 is ASCII first.** Paste the two-pane wireframe and wait. Do not paint the strip until approved.
- **Do not fork Bands view.** Reuse `TimeSeriesPane`. Highlight is time only.
- **Spectrogram does not get this strip.**
- **v1 History list is sqlite-only** (landed PR 6). Do not add a directory backfill of `recording_*` without a row.
- **`SessionStore` read/delete use sqlite `path`.** Recordings are `recording_$id.muse.feedback`.
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
