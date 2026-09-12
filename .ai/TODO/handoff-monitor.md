# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-12 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** Rev **6**. Bands Y is **dB display**. **PR 4 ASCII is approved.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c `3fb276b`, PR 2 `a9717bb`, PR 3 ASCII `8e45d37`, PR 3 `878cc8a`, PR 4 ASCII **this commit**). |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 4 painters** (Histogram + PSD + Spectrogram). ASCII already approved — **do not wait**. |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, user decisions **13–20**, Histogram / PSD / Spectrogram tables, **Build PR 4 with PR 7/8 in mind**, landscape cinema). This file is implementer order, current-code pitfalls, and the **PR 4** start. Do not re-design graphs, naming, or the lease. Do not change Bands or Raw EEG **painters**. Do not implement PR 7 or PR 8.

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

**PR 4 (this thread). ASCII is approved. Implement painters. Do not paste-and-wait. Do not implement PR 7 or PR 8.**

```
Implement monitor PR 4 only: Histogram + PSD + Spectrogram painters. ASCII is already approved (2026-09-12) — do not paste wireframes or wait. Spec: .ai/monitor.md (frozen, rev 6, user decisions 13–20). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 4”).
Histogram is a new AppView. Keep AppView.spectrogram and sidebar Spectrogram. PSD sidebar label PSD. Same electrode toggles as Bands (average membership, default all on, last-one stays). Dart FFT in monitor/dsp.dart: Hamming, 1/N², default 256-pt, n parameterized (power-of-two) for later PR 8. Band edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50.
Histogram: own ±100 µV (overflow ±50/±200), 64 bins, 2/4/8 default 8 s, tap hairline readout, Inspect freeze + elapsed m:ss–m:ss, no time slider, no pinch-custom. PSD: 2/4/8 default 4 s, X 0–60 (overflow 0–100), Y log power, band shading, alpha peak, same tap/Inspect. Spectrogram: 10s/20s/30s/2min/5min default 20 s, pinch-X custom cap 5 min, mag ▾ dual-thumb color min/max (not Hz), Y 0–60 Hz, hop ~0.25 s. Landscape cinema on graph views (hide status bar, sidebar, GraphShell toolbar). Record hidden until 5a.
Build for upcoming PRs (do not implement them): HistogramView/PsdView body is Column + Expanded so PR 7 can insert a ~30% Bands TimeSeriesPane with a time highlight; do not add a time slider; epoch is ViewportController strip start/end; one shared electrode Set. dsp.dart n is a parameter so PR 8 is FFT 0.5/1/2 s (128/256/512) on Spectrogram only.
Do not change Bands or Raw EEG painters. Do not implement the Bands context strip or the FFT dropdown.
When done: commit; rewrite .ai/TODO/handoff-monitor.md and .ai/active-task.md for PR 5a (Landed + This thread + fenced next-thread prompt); reply with that fenced prompt so it can be pasted into the next thread. Do not skip the commit or the next-thread prompt.
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
| **4 ASCII** | **this commit** — Spec rev 6. Landscape cinema; spectrogram `mag ▾` color; Histogram/PSD one pane + tap readout; PR 7 Bands context strip; PR 8 Spectrogram FFT 0.5/1/2 s. |

### PR 4 ASCII shipped (docs only)

- `.ai/monitor.md` rev 6: user decisions 13–20, ASCII wireframes, landscape cinema, **Build PR 4 with PR 7/8 in mind**
- Series map: **7** (Bands strip under Histogram/PSD), **8** (Spectrogram FFT window) after 6
- Painters are the **next** thread

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
| **4** | Histogram + PSD + Spectrogram (`AppView.histogram` only) | **yes** (approved 2026-09-12) — **this thread implements** | 2; ∥ 3 |
| **5a** | Record / Stop / assemble / 409 `recording_active` | no | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no | 5a |
| **6** | Unified History list + filter + Save files to folder | no | 5b |
| **7** | Bands context strip (~30%) under Histogram and PSD | **yes** | 4, 6 |
| **8** | Spectrogram `FFT 1s ▾` 0.5 / 1 / 2 s (128 / 256 / 512) | no | 4, 7 |

Hide Record until 5a. Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 3 + PR 4 ASCII)

| Piece | Where | After 3 / 4 ASCII |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts.{raw,computed,json}`; flush every 30 s or 64 KiB |
| Index | `monitor/cache/recording_index.dart` | `(elapsedT, fileLength)` at `flushRaw` frame boundaries. First frame offset **12**. Rotate clears. |
| File-backed source | `monitor/cache/file_backed_source.dart` | Wired from Raw EEG Inspect when the window starts older than SweepBuffer RAM. |
| Sweep EEG | `monitor/cache/sweep_buffer.dart` on `MonitorController` | One 5 min ring. Follow wraps; Inspect freeze fills right without wrap. |
| Raw EEG route | `app.dart` `AppView.rawEeg` → `monitor/views/raw_eeg_view.dart` | N `SweepPane`s. GraphShell Follow/Inspect, 10 s default. No Record, no chips, no add/remove, no `custom`. |
| GraphShell | `monitor/graph_shell.dart` | Shared chrome. Record slot `showRecord: false`. When `windowSeconds` ∉ `windowOptions`, closed label is **`custom`**. PR 4 hides the toolbar in landscape (cinema). |
| Bands | `monitor/views/bands_view.dart` | One `TimeSeriesPane`, five series, dB Y, electrode toggles, 30 s default, pinch-X `custom`. **Do not change the painter.** Cinema is shell/app chrome only. |
| Electrode toggles | `monitor/electrode_toggles.dart` | Top-right text; average membership; last-one stays. Reuse in PR 4. |
| BandCache | `monitor/cache/band_cache.dart` on `MonitorController` | 1 Hz, 1800 samples. Timestamps are **unix seconds**. Convert to elapsed at the pane using `captureStartedAtMs`. Linear µV²/Hz. |
| Overshoot | `monitor/panes/overshoot_hold.dart` | Bands only. `kBandsOvershootHold`. Do not use for Histogram/PSD/Spectrogram. |
| Lease / tmp | `monitor/recording/` | exclusive; rotate resets `captureStartedAtMs` and the index |
| Pad quality | `connection_provider` `_PadQualityRing` | 4-ch, 1 s — **do not grow** |
| Histogram / PSD / Spectrogram | `views/psd_view.dart`, `views/terminal.dart` | **Placeholders.** PR 4 painters replace them. |
| `AppView` | `settings.dart` | No `histogram` yet. `spectrogram` and `psd` exist. |

---

## This thread — PR 4

**Title:** `Add Histogram; implement PSD and Spectrogram`

**ASCII approved 2026-09-12.** Implement. Do not paste wireframes. Do not wait. Spec tables + ASCII in `.ai/monitor.md` are the layout.

When painters are done, follow **Close the thread** (commit + rewrite this file for PR 5a + fenced next-thread prompt). Do not skip it.

### Do

- Reuse PR 2/3 `GraphShell`, `ViewportController`, `ElectrodeToggles`. Record stays hidden (`showRecord: false`).
- Same electrode toggles as Bands: top-right text, depressed = in the **average**, default all on, last-one stays. Muse-4 vs Crown-8 from `lastConnectedKind`. Not overlay, not extra graphs.
- **Histogram** — new `AppView.histogram`. Sidebar **Histogram** (after Raw EEG). One pane. X: µV, own domain **±100** (overflow ±50 / ±200), not Raw EEG `SharedYScale`. Y: **count**. Window **2 / 4 / 8 s**, default **8 s**. No `custom`. 64 linear bins. Mean of selected. Follow = last T seconds. Inspect = freeze + chrome **`m:ss–m:ss`**. Tap (not drag) hairline + label. **No time slider.** View `body` = `Column` with the pane `Expanded` (PR 7 will insert ~30% Bands below).
- **PSD** — keep `AppView.psd`. Sidebar **PSD**. GraphShell title `Power Spectral Density`. One pane, no overlay. Welch of last T seconds, mean of selected. X: Hz **0–60** (0–100 overflow). Y: log power (`dB`). Window **2 / 4 / 8 s**, default **4 s**. 1 s Hamming segments, 50% hop, 256-pt FFT. Band shading: delta **1–4**, theta **4–8**, alpha **8–13**, beta **13–30**, gamma **30–50**. Peak: argmax 8–13 Hz, one label. Same Follow/Inspect/tap/Column-as-Histogram.
- **Spectrogram** — keep `AppView.spectrogram` and sidebar **Spectrogram**. Widget `monitor/views/spectrogram_view.dart`. Heatmap: X = time, Y = **0–60 Hz**, color = log power. STFT of the **mean** of selected. Window **10s / 20s / 30s / 2min / 5min**, default **20 s**, pinch-X **`custom`**, cap **5 min**. Hop ~0.25 s. Chrome **`mag ▾`**: dual-thumb **color min/max**, live, not Hz, not auto-pumping. Slim colorbar on the right. No averaging. No hold-finger. No FFT dropdown (PR 8).
- **Landscape cinema** — graph views only (`bands`, `rawEeg`, `histogram`, `psd`, `spectrogram`). Landscape: hide StatusBar, sidebar, GraphShell toolbar; pane fills. Portrait restores. Not Settings/Feedback/Streaming/History. Bands/Raw EEG painters unchanged.
- FFT: **`monitor/dsp.dart` only.** No FFT package. Cooley–Tukey, Hamming, power `(re²+im²)/(n*n)`. Default **`n = 256`**. **`n` is a power-of-two parameter** so PR 8 can pass 128 / 512 without rewriting FFT. Tests lock 256-pt + edges.
- EEG RAM is `SweepBuffer` only. Histogram/PSD/Spectrogram `getRange` through a thin adapter over `SweepBuffer.sampleAt` (index / 256 Hz). Do **not** add a second LiveCache EEG ring. Epoch for Histogram/PSD = `ViewportController` strip start/end (PR 7 highlight will use the same numbers).
- `settings.dart`: add `AppView.histogram` only. `parseAppView` is `v.name` — no `waterfall` alias. Update `_viewFromName` / `_viewNames` / `app.dart` switch + sidebar (Histogram after Raw EEG; PSD label `PSD`; Spectrogram stays).
- `test/agent/agent_protocol_test.dart`: `parseAppView('histogram')`. `spectrogram` stays the real name.
- Delete placeholders `lib/src/views/psd_view.dart` and `lib/src/views/terminal.dart` when replacements land.
- Update `.ai/ui-map.md`, `.ai/test-matrix.md`, `.ai/testing-guide.md` (`POST /view` `histogram`; **keep** `spectrogram`).
- Export new files from `monitor/monitor.dart`.

### Do not

- Paste ASCII or wait for approval (already approved).
- Implement PR 7 (Bands strip under Histogram/PSD) or PR 8 (`FFT 1s ▾`).
- Add a time slider under Histogram/PSD (PR 7 replaces that idea).
- Record button (5a).
- Change Bands or Raw EEG **painters**. Do not put chips on Raw EEG. Do not add `custom` to EEG window options. Do not reuse Bands overshoot hold. Cinema may hide their GraphShell toolbar in landscape — that is the allowed chrome change.
- Rename Spectrogram → Waterfall. No `AppView.waterfall`. No `AppView.recordings`.
- FFT package. New FFI. Linear-Y default on PSD. Log bins / KDE / per-channel overlay on Histogram. Stacked per-channel spectrograms. Spectrogram averaging. Hold-finger spectrogram readout. Hz-range dual-thumb (magnitude is the dual-thumb).
- Import `device_montage.dart` from feedback.
- FFI / v5 header / lease / prefixes. Growing pad-quality to 8.
- Crown Start, OSC-connect.

### Target files

```
lib/src/monitor/
  dsp.dart                         # NEW — Cooley–Tukey Hamming 1/N²; n parameterized; default 256
  panes/histogram_pane.dart        # NEW
  panes/psd_pane.dart              # NEW
  panes/spectrogram_pane.dart      # NEW
  views/histogram_view.dart        # NEW — Column + Expanded (PR 7 hook)
  views/psd_view.dart              # NEW — Column + Expanded (PR 7 hook)
  views/spectrogram_view.dart      # NEW
  monitor.dart                     # export
  viewport_controller.dart         # histogram/psd/spectrogram window options
  graph_shell.dart                 # landscape: hide toolbar

lib/src/settings.dart              # AppView.histogram; _viewFromName / _viewNames
lib/src/app.dart                   # sidebar + body + landscape cinema (status/sidebar)
lib/src/agent/agent_protocol.dart  # parseAppView already uses v.name — add enum value
test/agent/agent_protocol_test.dart
test/monitor/dsp_test.dart
.ai/ui-map.md
.ai/test-matrix.md
.ai/testing-guide.md

DELETE:
  lib/src/views/psd_view.dart
  lib/src/views/terminal.dart      # placeholder SpectrogramView
```

### Tests

Pure Dart preferred. No goldens / `integration_test`.

- `parseAppView('histogram')`; `parseAppView('spectrogram')` still works; no `waterfall`
- DSP: Hamming 256-pt, power `1/N²`, band edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50; `n` accepts other powers of two (even if PR 4 only calls 256)
- Histogram 64 bins, own ±100 µV domain
- Electrode toggles reused (default all on, last-one stays) — already covered; do not fork
- `flutter analyze lib/src` clean

### Verify (PR 4)

```bash
flutter analyze lib/src
flutter test test/monitor/ test/agent/agent_protocol_test.dart
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`. Visual graphs cannot be verified in CI — human `flutter run`.

### PR 4 done when

- Painters for Histogram, PSD, Spectrogram match the approved ASCII
- `AppView.histogram` exists; Spectrogram name unchanged; PSD sidebar `PSD`
- Same electrode toggles; Record hidden
- Landscape cinema on graph views
- Histogram/PSD are `Column` + `Expanded` (PR 7 hook); no time slider; `dsp` `n` parameterized
- Placeholders deleted
- ui-map + test-matrix + testing-guide updated
- `flutter analyze lib/src` clean
- **Close the thread:** rewrite this handoff + `active-task.md` for PR 5a, **commit**, reply with the fenced PR 5a paste prompt

---

## Next threads (do not start in PR 4)

### PR 5a — Record / Stop / assemble / 409 `recording_active`

Record/Stop on GraphShell, 409 `recording_active` on **`AgentCommands._start`** (there is no `_sessionStart`), Save/Discard. Recording `flushRaw` must keep indexing (same `RecordingIndex`).

### PR 5b / 6

Crash recovery for `recording_*` only, History filter All|Feedback|Recordings, sqlite `kind`, Settings **Save files to folder**.

### PR 7 — Bands context strip under Histogram and PSD (ASCII first)

After 6. Spec: [../monitor.md](../monitor.md) section **Histogram + PSD — Bands as a time map (PR 7)**. ~70% histogram/PSD + ~30% `TimeSeriesPane`. Highlight = T-second averaging window; Bands strip wider (30 s default, pinch-X). One electrode set. Time only — Histogram still raw µV, PSD still Welch. Spectrogram does **not** get this. Reuse `TimeSeriesPane`; do not fork Bands view. PR 4 already left `Column` + `Expanded` + shared epoch.

### PR 8 — Spectrogram FFT window

After 7. Chrome `FFT 1s ▾`: **0.5 / 1 / 2 s** → **128 / 256 / 512**. Not a free slider. Spectrogram only. PSD Welch stays 1 s / 256-pt. `dsp.dart` `n` was parameterized in PR 4. Then archive this handoff.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`.

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`.

History list stays `lib/src/views/feedback_history.dart` (PR 6). Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **PR 4 ASCII is approved.** Do not paste wireframes. Do not implement PR 7/8.
- **PR 7 hook:** Histogram/PSD `Column` + `Expanded`. No time slider. Epoch = strip start/end. One `Set<int>` for electrodes. Do not fork `TimeSeriesPane`.
- **PR 8 hook:** `dsp` `n` is a parameter. Default 256. Do not add the FFT dropdown yet.
- **`mag ▾` is color**, not Hz. Y is 0–60 Hz.
- **Broadcast `eventStream`:** controller stays in `main()` (1a). Do not move it to AppShell. SweepBuffer is on the controller — do not also subscribe in a view. BandCache is on the controller — do not add a second ring. Histogram/PSD/Spectrogram read SweepBuffer via an adapter.
- **Electrode toggles are average membership**, not extra graphs, not overlay. Last-one stays on. Reuse `electrode_toggles.dart`.
- **Do not copy Raw EEG sweep** into these views. Histogram is bins; PSD is a spectrum; Spectrogram is a heatmap.
- **FFT matches Rust:** Hamming, `1/N²`, edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50. Do not invent edges.
- **Histogram domain is own ±100 µV**, not Raw EEG `SharedYScale`.
- **`channelCount` is `BigInt` on FFI.** `MonitorState.channelCount` is already `int`.
- `flutter analyze lib/src` after every Dart PR. No goldens / `integration_test`.
- Agent HTTP: `persist: false`. No `/record/*` (5a). Crown 409 stays `crown_refused`. `POST /view` `histogram` is new; `spectrogram` already listed.

---

## Docs when a PR lands

Every PR: this handoff + `.ai/active-task.md` + **commit** + fenced next-thread prompt (see **Close the thread**). Plus:

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| Follow / Inspect (PR 2) | `.ai/ui-map.md` |
| Bands toggles / custom / dB (PR 3) | `.ai/ui-map.md` |
| `AppView.histogram` / cinema / mag (PR 4) | `.ai/ui-map.md`, `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Bands strip under Histogram/PSD (PR 7) | ui-map |
| Spectrogram `FFT 1s ▾` (PR 8) | ui-map |
| Series complete (after **8**) | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
