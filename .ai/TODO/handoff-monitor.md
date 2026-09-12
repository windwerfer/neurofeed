# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-12 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** Rev **6**. Bands Y is **dB display**. **PR 4 painters landed.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `a9717bb`, PR 3 ASCII `8e45d37`, PR 3 `878cc8a`, PR 4 ASCII `4c968fa`, PR 4 **this commit**). |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 5a** (Record / Stop / assemble / 409 `recording_active`). |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, recording lifecycle, Capture lease, Agent HTTP `/record/*`, Start Session vs Record). This file is implementer order, current-code pitfalls, and the **PR 5a** start. Do not re-design graphs, naming, or the lease. Do not implement 5b (crash recovery + sqlite `kind`), 6, 7, or 8.

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

**PR 5a (this thread). Record / Stop / assemble / 409 `recording_active`. Do not start 5b/6/7/8.**

```
Implement monitor PR 5a only: Record / Stop / assemble / 409 recording_active. Spec: .ai/monitor.md (frozen, rev 6). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 5a”).
Unhide Record on GraphShell (showRecord: true). Record starts recording_$ts (discard tmp, no pre-click bytes on disk). Stop recording flushes, writeScratchV5(prefix: recording, placeholder WebP), then Save/Discard. Save copies the scratch v5 into the history root; Discard deletes it. Then restart tmp if still connected. Recording elapsed only while CaptureKind.recording. Disabled when feedback or disconnected (tooltip Stop the feedback session to record).
Agent: POST /record/start (412 disconnected, 409 feedback_active) and POST /record/stop. AgentCommands._start 409 recording_active before startCalibration (order: 412 not_connected → 409 crown_refused → 409 recording_active). UI _refuseRecordingStart in feedback_session.dart after _refuseCrownStart. Lease already refuses recording. flushRaw must keep indexing (same RecordingIndex). persist: false.
Do not implement 5b (crash recovery + sqlite kind), 6 (History filter / Save files to folder), 7, or 8. Do not change graph painters.
When done: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 5b (Landed + This thread + fenced next-thread prompt); reply with that fenced prompt so it can be pasted into the next thread. Do not skip the commit or the next-thread prompt.
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
| **4** | **this commit** — Histogram + PSD + Spectrogram painters. `AppView.histogram`. Landscape cinema. `dsp.dart` Hamming `1/N²`, `n` parameterized. Record still hidden. |

### PR 4 shipped

- `AppView.histogram`; sidebar Histogram after Raw EEG; PSD label `PSD`; Spectrogram unchanged
- Histogram / PSD / Spectrogram on GraphShell; electrode toggles reused; Record hidden
- Histogram: ±100 µV (overflow ±50/±200), 64 bins, 2/4/8 default 8 s, tap hairline, Inspect `m:ss–m:ss`, Column + Expanded
- PSD: Welch 1 s Hamming 50% hop 256-pt, 2/4/8 default 4 s, X 0–60 (0–100 overflow), log Y, band shading, alpha peak, Column + Expanded
- Spectrogram: 10s/20s/30s/2min/5min default 20 s, pinch-X `custom` cap 5 min, `mag ▾` color min/max, Y 0–60 Hz, hop ~0.25 s
- Landscape cinema on graph views (status bar, sidebar, GraphShell toolbar)
- Placeholders `views/psd_view.dart` / `views/terminal.dart` deleted
- PR 7/8 hooks only: no Bands strip, no FFT dropdown, no time slider

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
| **5a** | Record / Stop / assemble / 409 `recording_active` | no — **this thread** | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no | 5a |
| **6** | Unified History list + filter + Save files to folder | no | 5b |
| **7** | Bands context strip (~30%) under Histogram and PSD | **yes** | 4, 6 |
| **8** | Spectrogram `FFT 1s ▾` 0.5 / 1 / 2 s (128 / 256 / 512) | no | 4, 7 |

Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 4)

| Piece | Where | After 4 |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts.{raw,computed,json}`; flush every 30 s or 64 KiB. **No `recording_` yet.** |
| Index | `monitor/cache/recording_index.dart` | `(elapsedT, fileLength)` at `flushRaw` frame boundaries. First frame offset **12**. Rotate clears. Keep this on Record. |
| File-backed source | `monitor/cache/file_backed_source.dart` | Wired from Raw EEG Inspect when the window starts older than SweepBuffer RAM. |
| Sweep EEG | `monitor/cache/sweep_buffer.dart` on `MonitorController` | One 5 min ring. Histogram/PSD/Spectrogram read via `cache/sweep_mean.dart`. |
| GraphShell | `monitor/graph_shell.dart` | Shared chrome. Record slot `showRecord: false`. Landscape hides toolbar. `formatWindow` / `inspectRangeLabel` / `toolbarMiddle`. |
| Histogram | `monitor/views/histogram_view.dart` | Column + Expanded. ±100 µV, 64 bins, 8 s default. |
| PSD | `monitor/views/psd_view.dart` | Column + Expanded. Welch 256-pt, 4 s default. Title `Power Spectral Density`. |
| Spectrogram | `monitor/views/spectrogram_view.dart` | Heatmap, `mag ▾`, 20 s default, pinch-X `custom`. |
| FFT | `monitor/dsp.dart` | Hamming, `1/N²`, `n` power-of-two (default 256). |
| CaptureLease | `monitor/recording/capture_lease.dart` | tmp / feedback only. **No recording transitions yet.** |
| Lease / tmp | `monitor/recording/` | exclusive; rotate resets `captureStartedAtMs` and the index |
| Agent | `agent_commands.dart` `_start` | 412 `not_connected` → 409 `crown_refused` → start. **No `recording_active`. No `/record/*`.** |
| Feedback Start | `feedback_session.dart` | `_refuseCrownStart` only. No `_refuseRecordingStart`. |
| `AppView` | `settings.dart` | `histogram` exists. `parseAppView` is `v.name`. |

---

## This thread — PR 5a

**Title:** `Record / Stop recording; 409 recording_active`

No ASCII. Spec: recording lifecycle, Capture lease table, Agent HTTP, Start Session vs Record (three layers, like Crown).

When done, follow **Close the thread** (commit + rewrite this file for PR 5b + fenced next-thread prompt). Do not skip it.

### Do

- **GraphShell** — `showRecord: true` on all five graph views (or build Record inside the shell from `monitorControllerProvider`). On-screen **`Record`** / **`Stop recording`**. Disabled when `CaptureKind.feedback` or disconnected. Tooltip `Stop the feedback session to record`. Show recording elapsed only while `CaptureKind.recording`. Landscape cinema still hides the toolbar (user rotates to portrait to Record).
- **`MonitorController.startRecording` / `stopRecording`**
  - Record: discard tmp (no prompt), start `recording_$ts.{raw,computed,json}` with `Settings.recordStreams`. Reset `captureStartedAtMs`. **Do not include pre-click bytes** (rings still show them in Follow).
  - Stop: flush, `writeScratchV5(prefix: 'recording')` with `placeholderWebP`, then Save/Discard. After Save or Discard, if still connected start tmp.
- **`CaptureLease`** — add tmp→recording and recording→idle. Feedback still **refuses** recording (`tryAcquireFeedback` already does). Record button hidden/disabled during feedback.
- **`MonitorRecorder`** — start with prefix `recording`. **`flushRaw` must keep indexing** the same `RecordingIndex` (PR 1c). Do not fork a second index.
- **Save/Discard** — `monitor/views/recording_save_discard.dart`. Same dialog on Stop and (later) in-app disconnect-while-recording. `barrierDismissible: false`. Save: copy assembled scratch v5 into the **history root** as `recording_$ts.muse.feedback`. Discard: delete scratch v5. **Sqlite `kind` is 5b** — do not add the column here unless Save cannot work without it; prefer file copy only.
- **Agent**
  - `POST /record/start` — 412 disconnected; 409 `feedback_active`; else start recording. `persist: false`.
  - `POST /record/stop` — 200; assemble. Tests assert scratch v5 exists; do **not** publish as a History row test (that is 5b/6).
  - `AgentCommands._start`: after Crown check, if `captureKind == recording` return 409 `recording_active` **before** `startCalibration`. Order: 412 `not_connected` → 409 `crown_refused` → 409 `recording_active` → start. There is **no** `_sessionStart`.
- **UI refuse** — `_refuseRecordingStart` in `feedback_session.dart` after `_refuseCrownStart`. Dialog title `Recording in progress`, body `Stop the recording before starting a session.`, actions `Cancel` / `Stop recording`. Start is **not** auto-continued.
- **Notifier** — `acquireFeedbackLease()` already returns false while recording; keep `debugPrint('[feedback] refusing Start: recording_active'); return;`.
- In-app Disconnect while recording: flush+assemble, then the same Save/Discard dialog. Process exit: best-effort assemble inside `disconnectOnClose`; **no dialog** (5b recovers).
- Update `.ai/ui-map.md` (Record / Stop recording) and `.ai/testing-guide.md` (`/record/*`, 409 `recording_active`).

### Do not

- 5b crash recovery for `recording_*`, sqlite `kind`, `RecordingStore.publish` into `session_metadata.db` (unless Save is implemented as that helper — then 5b still owns crash recovery + History list).
- PR 6 History filter All|Feedback|Recordings, Settings **Save files to folder**.
- PR 7 Bands strip. PR 8 FFT dropdown.
- Change Histogram / PSD / Spectrogram / Bands / Raw EEG **painters**.
- Assemble `tmp_`. Rename tmp→recording in place. Two writers.
- Crown Start, OSC-connect, v5 header, growing pads to 8.
- Widget goldens / `integration_test`.

### Target files

```
lib/src/monitor/
  graph_shell.dart                     # showRecord; Record / Stop recording
  monitor_controller.dart              # startRecording / stopRecording
  recording/capture_lease.dart         # tmp → recording → idle
  recording/monitor_recorder.dart      # prefix recording_; keep flushRaw index
  views/recording_save_discard.dart    # NEW

lib/src/agent/agent_commands.dart      # /record/start|stop; _start 409 recording_active
lib/src/views/feedback_session.dart    # _refuseRecordingStart
lib/src/feedback/feedback_state.dart   # already refuses lease; log recording_active

.ai/ui-map.md
.ai/testing-guide.md
.ai/test-matrix.md
```

### Tests

Pure Dart preferred. No goldens / `integration_test`.

- Record while tmp → `captureKind == recording`; tmp files gone; `recording_*` temps exist
- Stop → scratch `recording_$ts.muse.feedback` exists (placeholder WebP)
- Discard deletes scratch; Save copies to history root
- `flushRaw` still indexes during recording (same `RecordingIndex`)
- `acquireFeedbackLease` false while recording
- Agent `_start` 409 `recording_active` (and still 409 `crown_refused` for Crown)
- `POST /record/start` 412 disconnected; 409 `feedback_active`
- `flutter analyze lib/src` clean

### Verify (PR 5a)

```bash
flutter analyze lib/src
flutter test test/monitor/ test/agent/
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`.

### PR 5a done when

- Record / Stop on GraphShell; elapsed while recording; disabled during feedback
- `recording_$ts` temps + assemble on Stop + Save/Discard
- 409 `recording_active` on `_start`; `/record/start|stop`; UI refuse dialog
- Indexing continues on recording `flushRaw`
- ui-map + testing-guide updated
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 5b, **commit**, reply with the fenced PR 5b paste prompt

---

## Next threads (do not start in PR 5a)

### PR 5b — Crash recovery + sqlite `kind`

`recording_*` only (not `tmp_`, not `session_*`). Incomplete recording dialog. `RecordingStore.publish` upserts `session_metadata.db` with `kind = 'recording'`. Default `kind = 'feedback'` migrates existing rows.

### PR 6 — Unified History

On-screen **History**; filter All | Feedback | Recordings. Settings **Save files to folder**; `moveAllTo` both prefixes.

### PR 7 — Bands context strip under Histogram and PSD (ASCII first)

After 6. Spec section **Histogram + PSD — Bands as a time map (PR 7)**. PR 4 left `Column` + `Expanded` + shared epoch.

### PR 8 — Spectrogram FFT window

After 7. `FFT 1s ▾` 0.5 / 1 / 2 s → 128 / 256 / 512. `dsp.dart` `n` already parameterized. Then archive this handoff.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`.

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`.

History list stays `lib/src/views/feedback_history.dart` (PR 6). Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **Record does not include pre-click bytes** on disk. Follow rings still show them. Intentional.
- **Do not rename tmp → recording.** Discard tmp, start a new capture.
- **`flushRaw` indexing** must work for `recording_` the same as tmp. Rotate does not apply to recording (uncapped except a 2 h warning).
- **409 `recording_active` is not `crown_refused`.** Distinct codes. Order: not_connected → crown_refused → recording_active.
- **There is no `_sessionStart`.** Patch `AgentCommands._start`.
- **Release lease after Stop** only when the recording writer is closed; then tmp if connected.
- **Do not assemble tmp.** Launch still glob-deletes leftover `tmp_*`.
- **Sqlite `kind` is 5b.** History filter is 6. Painters are done; do not restyle graphs.
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
