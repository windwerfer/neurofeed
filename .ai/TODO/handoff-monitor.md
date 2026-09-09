# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-09 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `28008c9`). Suggested name was `feat/monitor-graphs`. |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 3**. |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, `File layout`, `PR Plan`, `Implementer protocol`). This file is implementer order, current-code pitfalls, and the **PR 3** start. Do not re-design graphs, naming, or the lease.

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
4. Reply with the **next-thread prompt in a fenced block** the user can copy into a new chat. Nothing else required from them. Graph PRs (2 / 3 / 4) keep ASCII-first + wait in that prompt.

After PR 6: archive this file to `.ai/archive/`, update `.ai/architecture.md` / `.ai/README.md`, commit, and reply that the series is complete (no next-thread prompt).

---

## Paste this to start a new thread

**PR 3 (this thread):**

```
Implement monitor PR 3 only: Bands on GraphShell + electrode toggles.
Spec: .ai/monitor.md (frozen). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 3”).
Paste ASCII of GraphShell + one Bands pane (Follow/Inspect, 30 s window, top-right depressed electrode text labels as average membership, no Record, no Add graph, no SMOOTH/REALTIME) and WAIT before painters.
Then replace views/bands.dart with monitor/views/bands_view.dart. One TimeSeriesPane, five series (delta/theta/alpha/beta/gamma from band_style.dart), mean of selected electrodes. Default 30 s (15/30/60/120). Default all on; last-one stays. Hide Record until 5a.
When done: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 4 (Landed + This thread + fenced next-thread prompt); reply with that fenced prompt so it can be pasted into the next thread. Do not skip the commit or the next-thread prompt.
```

**Graph threads (2 / 3 / 4)** must paste an ASCII wireframe and wait before painters. See spec **Implementer protocol**.

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Thin re-exports at old paths. |
| **1a** | `2a66eae` — `MonitorController` in `main()` after `appStateProvider.notifier`. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring. |
| **1b** | `8a0b9f0` — Exclusive `tmp_` writer + lease. Connect starts `tmp_$ts.{raw,computed,json}` with `Settings.recordStreams`. Feedback `acquireFeedbackLease` discards tmp; `end()` releases only if `!isRecording`. Launch glob-deletes leftover `tmp_*`. `GET /state` has `captureKind` / `captureElapsedSeconds`. |
| **1c** | `3fb276b` — `RecordingIndex` + `FileBackedSource` under `monitor/cache/`. `flushRaw` callback indexes `(elapsedT, fileLength)` at frame boundaries. `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`; timestamps are elapsed from `captureStartedAtMs`. tmp rotate clears the index. |
| **2** | `28008c9` — GraphShell + N stacked sweep EEG panes. `SweepBuffer` on `MonitorController` (`monitor/cache/`). Default 10 s / 2560. Muse-4 vs Crown-8. Follow wipe; Inspect HOLD + fill-right; beyond 5 min calls `FileBackedSource`. Record hidden. Deleted add/remove, `graph_config`, `eeg_chart`, `eeg_dashboard`, `live_cache`, old Raw EEG views. |

---

## Series map (do not collapse)

| PR | Thread title | ASCII? | Depends |
|---|---|---|---|
| **0** | Extract `lib/src/session_v5/` | no | — |
| **1a** | `MonitorController` in `main()` + band cache; no disk | no | 0 |
| **1b** | `tmp_` writer + exclusive lease (kills dual `session_` writers) | no | 1a |
| **1c** | File-backed Inspect of tmp/recording `.raw` | no | 1b |
| **2** | GraphShell + N stacked **sweep** EEG panes; cancel add/remove | **yes** | 1b; prefer 1c first |
| **3** | Bands on GraphShell + electrode toggles | **yes** | 2 |
| **4** | Histogram + PSD + Spectrogram (`AppView.histogram` only) | **yes** (each view) | 2; ∥ 3 |
| **5a** | Record / Stop / assemble / 409 `recording_active` | no | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no | 5a |
| **6** | Unified History list + filter + Save files to folder | no | 5b |

Hide Record until 5a. Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 2)

| Piece | Where | After 2 |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts.{raw,computed,json}`; flush every 30 s or 64 KiB |
| Index | `monitor/cache/recording_index.dart` | `(elapsedT, fileLength)` at `flushRaw` frame boundaries. First frame offset **12**. Rotate clears. |
| File-backed source | `monitor/cache/file_backed_source.dart` | Wired from Raw EEG Inspect when the window starts older than SweepBuffer RAM. |
| Sweep EEG | `monitor/cache/sweep_buffer.dart` on `MonitorController` | One 5 min ring. Follow wraps; Inspect freeze fills right without wrap. |
| Raw EEG route | `app.dart` `AppView.rawEeg` → `monitor/views/raw_eeg_view.dart` | N `SweepPane`s. GraphShell Follow/Inspect, 10 s default. No Record, no chips, no add/remove. |
| GraphShell | `monitor/graph_shell.dart` | Shared chrome. Record slot `showRecord: false`. |
| Bands | `views/bands.dart` | **Still old dashboard** (SMOOTH/REALTIME/Add graph). **PR 3.** |
| Lease / tmp | `monitor/recording/` | exclusive; rotate resets `captureStartedAtMs` and the index |
| Pad quality | `connection_provider` `_PadQualityRing` | 4-ch, 1 s — **do not grow** |

---

## PR 2 (landed) — what shipped

GraphShell + N stacked sweep panes. `SweepBuffer` moved to `monitor/cache/` and owned by `MonitorController` (appended from the existing `eventStream` in `main()`). Default window **10 s / 2560**. Montage from `lastConnectedKind` (Muse 4 / Crown 8). Follow = thin theme wipe (`onSurface`), gray traces, electrode name in-pane top-right. Inspect = wipe and previous pass vanish; origin stays; new samples fill the blank to the right until the pane edge; pan uses history; older than 5 min RAM calls `FileBackedSource.getRange`. X-axis `m:ss` elapsed from capture start, bottom pane only. Record hidden. Deleted `sweep_eeg_view.dart`, `raw_eeg.dart`, `graph_config.dart`, `eeg_chart.dart`, `eeg_dashboard.dart`, `live_cache.dart`. No `eeg_layout_*`.

ASCII corrections that landed: in-pane names, gray thin traces, theme wipe (not green), Inspect fill-right (not grey freeze bar), x labels only on the bottom pane.

Tests: `test/monitor/viewport_controller_test.dart`, `graph_shell_test.dart`. `flutter analyze lib/src` clean. `flutter test test/monitor/` green.

---

## This thread — PR 3

**Title:** `Standardize Bands view on GraphShell`

When this PR is done, follow **Close the thread** (commit + rewrite this file for PR 4 + fenced next-thread prompt). Do not skip it.

**ASCII first (required).** Paste a wireframe of `GraphShell` + **one** Bands pane and **wait**. Do not write the TimeSeries painter or delete `views/bands.dart` until the ASCII is approved.

Wireframe must show:

- Header: **Follow | Inspect**, window length (15/30/60/120 s, default **30 s**), **no Record**
- Top-right electrode **text** labels (Muse TP9/AF7/AF8/TP10 or Crown 8). Tap toggles **average membership**. Depressed = selected. Default all on. Last one stays on.
- **One** pane, five series (delta / theta / alpha / beta / gamma), colors from `charts/band_style.dart`
- Y: absolute power µV²/Hz. X: elapsed from capture start
- **No** Add graph, **no** SMOOTH/REALTIME in the main bar, **no** side drawer, **no** overlay traces, **no** extra graphs from electrode taps

### Do

- Reuse PR 2 `GraphShell` + `ViewportController`. Record stays hidden.
- `monitor/views/bands_view.dart` + `monitor/panes/time_series_pane.dart` + `monitor/electrode_toggles.dart`.
- Mean of selected electrodes. Still **one** graph.
- Default window **30 s**. Discrete 15 / 30 / 60 / 120 s.
- Follow = strip advances with new BandCache samples. Inspect = freeze viewport; pan/zoom on user input. Pinch-pan or drag enters Inspect. Follow snaps back.
- Delete `lib/src/views/bands.dart`. `AppView.bands` body → monitor `BandsView`.
- Update `.ai/ui-map.md` for Bands chrome + electrode toggles.
- BandCache already lives on `MonitorController` (1a). Do not add a second ring.

### Do not

- Implement painters before ASCII approval.
- Record button (5a).
- Histogram / PSD / Spectrogram (PR 4).
- Raw EEG changes (PR 2 is done). Do not put chips on Raw EEG.
- SMOOTH in the main bar (optional Smooth on overflow only). Drop `_futureOffset` / REALTIME.
- Import `device_montage.dart` from feedback.
- FFI / v5 header / lease / prefixes.
- Growing pad-quality to 8.

### Target files

```
lib/src/monitor/
  electrode_toggles.dart           # NEW — top-right text; average membership
  panes/time_series_pane.dart      # NEW — 5 series, mean of selected
  views/bands_view.dart            # NEW — GraphShell + one pane

lib/src/app.dart                   # AppView.bands body → monitor BandsView
.ai/ui-map.md                      # Bands chrome + toggles

DELETE:
  lib/src/views/bands.dart
```

`chart_controller.dart` in `charts/` is the old autoScroll helper. Prefer `ViewportController` (elapsed domain). Delete `chart_controller.dart` if nothing else imports it after this PR.

### Tests

Pure Dart preferred. No goldens / `integration_test`.

- Default window 30 s
- Five series; mean of selected electrodes
- Toggles: default all on; last one stays
- Muse-4 vs Crown-8 labels from `lastConnectedKind`
- `flutter analyze lib/src` clean

### Verify (PR 3)

```bash
flutter analyze lib/src
flutter test test/monitor/
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`. Visual bands cannot be verified in CI — human `flutter run` after ASCII approval.

### PR 3 done when

- ASCII approved, then painters
- Bands on GraphShell; one pane; electrode toggles; old dashboard gone
- Record hidden
- `.ai/ui-map.md` updated
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 4, **commit**, reply with the fenced PR 4 paste prompt

---

## Next threads (do not start in PR 3)

### PR 4 — Histogram + PSD + Spectrogram (ASCII first, each view)

Histogram new `AppView`. Keep `AppView.spectrogram`. FFT: Hamming 256-pt `1/N²`, edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50. Same electrode toggles as Bands. Can land parallel to PR 3 if needed, but this series is one PR per thread — do PR 4 next.

### PR 5a / 5b / 6

Record/Stop, 409 `recording_active` on **`AgentCommands._start`** (there is no `_sessionStart`), Save/Discard, crash recovery for `recording_*` only, History filter All|Feedback|Recordings, sqlite `kind`, Settings **Save files to folder**. Recording `flushRaw` must keep indexing (same `RecordingIndex`).

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`.

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`.

History list stays `lib/src/views/feedback_history.dart` (PR 6). Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **ASCII first.** Paste the wireframe and wait. Painters after approval only.
- **Broadcast `eventStream`:** controller stays in `main()` (1a). Do not move it to AppShell. SweepBuffer is on the controller — do not also subscribe in a view.
- **BandCache timestamps** are still unix seconds (`dto.timestamp / 1000.0`). Convert to elapsed at the pane boundary using `captureStartedAtMs`. Never treat null start as unix epoch.
- **Electrode toggles are average membership**, not extra graphs, not overlay. Last-one stays on.
- **Do not copy Raw EEG sweep** into Bands. Bands is a strip / time series.
- **`channelCount` is `BigInt` on FFI.** `MonitorState.channelCount` is already `int`.
- `flutter analyze lib/src` after every Dart PR. No goldens / `integration_test`.
- Agent HTTP: `persist: false`. No `/record/*` (5a). Crown 409 stays `crown_refused`.

---

## Docs when a PR lands

Every PR: this handoff + `.ai/active-task.md` + **commit** + fenced next-thread prompt (see **Close the thread**). Plus:

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| Follow / Inspect (PR 2) | `.ai/ui-map.md` |
| Bands toggles (PR 3) | `.ai/ui-map.md` |
| `AppView.histogram` (PR 4) | `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Series complete | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
