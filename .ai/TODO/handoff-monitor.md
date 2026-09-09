# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-09 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** Bands Y is **dB display** (rev 5). |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `a9717bb`). Spec lock for PR 3 ASCII is **this commit**. |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 3 implementation** (ASCII already approved). |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, `File layout`, `PR Plan`, **Bands table**, user decisions **10–12**). This file is implementer order, current-code pitfalls, and the **PR 3 implementation** start. Do not re-design graphs, naming, or the lease. **Do not paste-and-wait ASCII** — that already happened.

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
4. Reply with the **next-thread prompt in a fenced block** the user can copy into a new chat. Nothing else required from them. Graph PRs (4) keep ASCII-first + wait in that prompt. PR 3 does **not**.

After PR 6: archive this file to `.ai/archive/`, update `.ai/architecture.md` / `.ai/README.md`, commit, and reply that the series is complete (no next-thread prompt).

---

## Paste this to start a new thread

**PR 3 implementation (this thread). ASCII is already approved — do not wait.**

```
Implement monitor PR 3 only: Bands on GraphShell + electrode toggles. ASCII is already approved — do not paste-and-wait.
Spec: .ai/monitor.md (frozen, rev 5). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 3”).
Replace views/bands.dart with monitor/views/bands_view.dart. One TimeSeriesPane, five series (delta/theta/alpha/beta/gamma from band_style.dart). Mean of selected electrodes in dB (10·log10 of linear µV²/Hz; BandCache stays linear). Default 30 s (15/30/60/120); pinch-X → dropdown shows “custom”; preset restores. Default all electrodes on; last-one stays. Hide Record until 5a. Overshoot: dashed hold at last in-range Y, isolated in monitor/panes/overshoot_hold.dart (<100 lines, easy to strip). No Add graph, no SMOOTH/REALTIME.
When done: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 4 (Landed + This thread + fenced next-thread prompt with ASCII-first + wait); reply with that fenced prompt so it can be pasted into the next thread. Do not skip the commit or the next-thread prompt.
```

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Thin re-exports at old paths. |
| **1a** | `2a66eae` — `MonitorController` in `main()` after `appStateProvider.notifier`. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring. |
| **1b** | `8a0b9f0` — Exclusive `tmp_` writer + lease. Connect starts `tmp_$ts.{raw,computed,json}` with `Settings.recordStreams`. Feedback `acquireFeedbackLease` discards tmp; `end()` releases only if `!isRecording`. Launch glob-deletes leftover `tmp_*`. `GET /state` has `captureKind` / `captureElapsedSeconds`. |
| **1c** | `3fb276b` — `RecordingIndex` + `FileBackedSource` under `monitor/cache/`. `flushRaw` callback indexes `(elapsedT, fileLength)` at frame boundaries. `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`; timestamps are elapsed from `captureStartedAtMs`. tmp rotate clears the index. |
| **2** | `a9717bb` — GraphShell + N stacked sweep EEG panes. `SweepBuffer` on `MonitorController` (`monitor/cache/`). Default 10 s / 2560. Muse-4 vs Crown-8. Follow wipe; Inspect HOLD + fill-right; beyond 5 min calls `FileBackedSource`. Record hidden. Deleted add/remove, `graph_config`, `eeg_chart`, `eeg_dashboard`, `live_cache`, old Raw EEG views. |
| **3 ASCII** | **this commit** — Spec rev 5. Bands Y **dB** display; pinch-X **`custom`**; overshoot dashed hold (strippable). Painters **not** in this commit. |

---

## Series map (do not collapse)

| PR | Thread title | ASCII? | Depends |
|---|---|---|---|
| **0** | Extract `lib/src/session_v5/` | no | — |
| **1a** | `MonitorController` in `main()` + band cache; no disk | no | 0 |
| **1b** | `tmp_` writer + exclusive lease (kills dual `session_` writers) | no | 1a |
| **1c** | File-backed Inspect of tmp/recording `.raw` | no | 1b |
| **2** | GraphShell + N stacked **sweep** EEG panes; cancel add/remove | **yes** (landed) | 1b; prefer 1c first |
| **3** | Bands on GraphShell + electrode toggles | **approved** — implement | 2 |
| **4** | Histogram + PSD + Spectrogram (`AppView.histogram` only) | **yes** (each view) | 2; ∥ 3 |
| **5a** | Record / Stop / assemble / 409 `recording_active` | no | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no | 5a |
| **6** | Unified History list + filter + Save files to folder | no | 5b |

Hide Record until 5a. Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 2 + spec lock)

| Piece | Where | After 2 / spec lock |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts.{raw,computed,json}`; flush every 30 s or 64 KiB |
| Index | `monitor/cache/recording_index.dart` | `(elapsedT, fileLength)` at `flushRaw` frame boundaries. First frame offset **12**. Rotate clears. |
| File-backed source | `monitor/cache/file_backed_source.dart` | Wired from Raw EEG Inspect when the window starts older than SweepBuffer RAM. |
| Sweep EEG | `monitor/cache/sweep_buffer.dart` on `MonitorController` | One 5 min ring. Follow wraps; Inspect freeze fills right without wrap. |
| Raw EEG route | `app.dart` `AppView.rawEeg` → `monitor/views/raw_eeg_view.dart` | N `SweepPane`s. GraphShell Follow/Inspect, 10 s default. No Record, no chips, no add/remove. |
| GraphShell | `monitor/graph_shell.dart` | Shared chrome. Record slot `showRecord: false`. Dropdown `value` must be in `items` today — PR 3 must show **`custom`** when `windowSeconds` is not in `windowOptions`. |
| Bands | `views/bands.dart` | **Still old dashboard** (SMOOTH/REALTIME/Add graph, linear min/max Y). **PR 3 painters.** |
| BandCache | `monitor/cache/band_cache.dart` on `MonitorController` | 1 Hz, 1800 samples. Timestamps are **unix seconds** (`dto.timestamp / 1000.0`). Convert to elapsed at the pane using `captureStartedAtMs`. |
| Lease / tmp | `monitor/recording/` | exclusive; rotate resets `captureStartedAtMs` and the index |
| Pad quality | `connection_provider` `_PadQualityRing` | 4-ch, 1 s — **do not grow** |

---

## Approved ASCII (do not re-litigate)

Muse-4, Follow, 30 s, all electrodes in the mean:

```
┌─ GraphShell 48px ─────────────────────────────────────────────────────────┐
│ [ Follow | Inspect ]  30s ▾                          [TP9] [AF7] [AF8] [TP10] │
│   ^^^^^^               ^ 15 / 30 / 60 / 120 / custom                          │
├───────────────────────────────────────────────────────────────────────────┤
│ dB                                                                        │
│  20 ┤                                              * gamma                │
│     │     /\                                          beta                │
│  10 ┤    /  \/\        /\/\                                               │
│     │   /      \  /\  /    \/\      /\/     /\  ← blink: +bump on dB      │
│   0 ┤  /        \/  \/        \____/       /  \                           │
│     │ /                                   /    \                          │
│ -10 ┼─────────────────────────────────────────────────────────────────── │
│     0:12              0:22              0:32              0:42            │
│     └────────── elapsed from capture start · newest at right ─────────────┘│
└───────────────────────────────────────────────────────────────────────────┘
```

After pinch-zoom X: closed dropdown label is **`custom`**. Pick 15/30/60/120 to restore a preset.

Crown: same chrome, eight depressed text labels `CP3 C3 F5 PO3 PO4 F6 C4 CP4` (scroll the cluster if they overflow; do not wrap onto a second bar).

Empty: disconnected → empty axes. Connected, no BandCache samples → muted `Waiting for signal`.

Not in this view: Record, Add graph, SMOOTH/REALTIME/LIVE, side drawer, overlay, extra graphs from electrode taps, sweep wipe, pinch-Y.

---

## This thread — PR 3

**Title:** `Standardize Bands view on GraphShell`

ASCII is **approved**. Implement painters. When done, follow **Close the thread** (commit + rewrite this file for PR 4 + fenced next-thread prompt). Do not skip it. Do not paste a new wireframe and wait.

### Do

- Reuse PR 2 `GraphShell` + `ViewportController`. Record stays hidden (`showRecord: false`).
- `monitor/views/bands_view.dart` + `monitor/panes/time_series_pane.dart` + `monitor/electrode_toggles.dart`.
- Electrode toggles in GraphShell `toolbarExtras` (top-right text, depressed = in the average). Default all on. Last one stays on. Muse-4 vs Crown-8 from `lastConnectedKind` via `device_montage.dart`.
- **One** pane, five series (delta / theta / alpha / beta / gamma), colors from `charts/band_style.dart`. Always all five.
- Mean of selected electrodes **in dB**: for each band, `10·log10(max(linear, ε))` per selected electrode, then mean those dB values (Mind Monitor averages SDK log values). Do **not** mean linear then log.
- BandCache stays linear µV²/Hz. Convert at the pane. `ε` small positive (e.g. `1e-12`) so log is defined.
- Default window **30 s**. Discrete 15 / 30 / 60 / 120. `ViewportController.bandsWindowOptions`.
- Pinch-zoom **X** (two-finger) and one-finger drag **enter Inspect**. Pinch changes `windowSeconds` around the focal point. If the length is not a preset, GraphShell closed label is **`custom`**. Picking a preset restores it. Follow snaps to live at the **current** length (custom or preset). Zoom-in floor ~5 s; zoom-out cap `min(elapsed, 1800)`.
- Y: auto on visible **dB** + ~15% pad. Y may be negative; **0 is not the floor**. Ease up ~1–2 s, down ~8–15 s.
- Overshoot hold: see below.
- Follow = strip advances, newest at right. Inspect = freeze viewport; pan/zoom. **Not** a sweep (no wipe, no fill-right).
- X labels: elapsed `m:ss` from `captureStartedAtMs`. BandCache unix seconds → elapsed at the pane. Never treat null start as unix epoch.
- Delete `lib/src/views/bands.dart`. `AppView.bands` body → monitor `BandsView`.
- Update `.ai/ui-map.md` for Bands chrome, `custom`, electrode toggles, dB.
- Delete `lib/src/charts/chart_controller.dart` if nothing else imports it after this PR.
- Export new files from `monitor/monitor.dart` as needed.

### Overshoot hold (keep, but easy to strip)

Isolate in **`lib/src/monitor/panes/overshoot_hold.dart`** (flag + helpers, **< 100 lines**). TimeSeriesPane calls it; nothing else.

- Sample above current Y-max → paint **dashed** at last in-range Y (not the real value, not a rail clip).
- Overshoot samples must **not** feed the auto scale.
- `const kBandsOvershootHold = true;` at the top of that file. Deleting the file + its import/call is the strip path.
- Do not use pad-quality or blink markers.

### Do not

- Paste ASCII and wait. Approved.
- Record button (5a).
- Histogram / PSD / Spectrogram (PR 4).
- Raw EEG changes (PR 2 is done). Do not put chips on Raw EEG. Do not add `custom` to EEG window options.
- SMOOTH in the main bar. Drop `_futureOffset` / REALTIME.
- Import `device_montage.dart` from feedback.
- FFI / v5 header / lease / prefixes. Do not change Rust FFT or BandCache units.
- Growing pad-quality to 8.
- Pinch-Y. Relative %. Log-storage.

### Target files

```
lib/src/monitor/
  electrode_toggles.dart           # NEW — top-right text; average membership
  panes/time_series_pane.dart      # NEW — 5 series, mean of selected in dB
  panes/overshoot_hold.dart        # NEW — dashed last-in-range; <100 lines; strip by deleting
  views/bands_view.dart            # NEW — GraphShell + one pane
  graph_shell.dart                 # custom dropdown when value ∉ windowOptions
  viewport_controller.dart         # bandsWindowOptions; strip follow/inspect/pan/pinch-X
  monitor.dart                     # export new files

lib/src/app.dart                   # AppView.bands body → monitor BandsView
.ai/ui-map.md                      # Bands chrome + toggles + custom + dB

DELETE:
  lib/src/views/bands.dart
  lib/src/charts/chart_controller.dart   # if unused after
```

`ViewportController` today is EEG-centric (`follow(SweepBuffer)`). Add elapsed-domain helpers for the strip (visible window in elapsed seconds, pan, pinch-X) without breaking Raw EEG.

GraphShell `DropdownButton.value` must exist in `items`. When `windowSeconds` is not in `windowOptions`, add a selected `custom` item (not a destination the user picks to “go custom” — pinch does that).

### Tests

Pure Dart preferred. No goldens / `integration_test`.

- Default window 30 s
- Five series; mean of selected electrodes **in dB**
- Toggles: default all on; last one stays
- Muse-4 vs Crown-8 labels from `lastConnectedKind`
- `custom` when window is not a preset; preset restores
- Overshoot hold: value above Y-max does not raise the scale; helper is unit-testable
- `10·log10` floor (`ε`) does not produce NaN
- `flutter analyze lib/src` clean

### Verify (PR 3)

```bash
flutter analyze lib/src
flutter test test/monitor/
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`. Visual bands cannot be verified in CI — human `flutter run` after this PR.

### PR 3 done when

- Bands on GraphShell; one pane; electrode toggles; dB Y; custom X; overshoot hold isolated; old dashboard gone
- Record hidden
- `.ai/ui-map.md` updated
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 4, **commit**, reply with the fenced PR 4 paste prompt (**ASCII first + wait** for each of Histogram / PSD / Spectrogram)

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

- **PR 3 ASCII is approved.** Do not wait. Painters now.
- **Broadcast `eventStream`:** controller stays in `main()` (1a). Do not move it to AppShell. SweepBuffer is on the controller — do not also subscribe in a view. BandCache is on the controller — do not add a second ring.
- **BandCache timestamps** are still unix seconds (`dto.timestamp / 1000.0`). Convert to elapsed at the pane boundary using `captureStartedAtMs`. Never treat null start as unix epoch.
- **Electrode toggles are average membership**, not extra graphs, not overlay. Last-one stays on.
- **Do not copy Raw EEG sweep** into Bands. Bands is a strip / time series.
- **Mean in dB**, then plot. Storage stays linear.
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
| Bands toggles / custom / dB (PR 3) | `.ai/ui-map.md` |
| `AppView.histogram` (PR 4) | `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Series complete | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
