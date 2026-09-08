# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-08 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b `8a0b9f0`, PR 1c this commit). Suggested name was `feat/monitor-graphs`. |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 2**. |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, `File layout`, `PR Plan`, `Implementer protocol`). This file is implementer order, current-code pitfalls, and the **PR 2** start. Do not re-design graphs, naming, or the lease.

---

## Paste this to start a new thread

**PR 2 (this thread):**

```
Implement monitor PR 2 only: GraphShell + N stacked sweep EEG panes.
Spec: .ai/monitor.md (frozen). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 2”).
Paste ASCII of GraphShell + N stacked sweep panes (Follow/Inspect, 10 s window, green wipe, no Record, no electrode chips, no add/remove) and WAIT before painters.
Then move sweep_buffer.dart into monitor/cache/. Delete graph_config / eeg_dashboard / eeg_chart and SweepEegView add/remove / eeg_layout_*. Default 10 s (2560 samples). Muse-4 vs Crown-8 from lastConnectedKind. Inspect beyond 5 min uses FileBackedSource (PR 1c). Hide Record until 5a.
```

**Graph threads (2 / 3 / 4)** must paste an ASCII wireframe and wait before painters. See spec **Implementer protocol**.

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Thin re-exports at old paths. |
| **1a** | `2a66eae` — `MonitorController` in `main()` after `appStateProvider.notifier`. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring. `live_cache.dart` unused (delete in PR 2). `SweepEegView` still owns its own SweepBuffer. |
| **1b** | `8a0b9f0` — Exclusive `tmp_` writer + lease. Connect starts `tmp_$ts.{raw,computed,json}` with `Settings.recordStreams`. Feedback `acquireFeedbackLease` discards tmp; `end()` releases only if `!isRecording`. Launch glob-deletes leftover `tmp_*`. `GET /state` has `captureKind` / `captureElapsedSeconds`. |
| **1c** | `RecordingIndex` + `FileBackedSource` under `monitor/cache/`. `flushRaw` callback indexes `(elapsedT, fileLength)` at frame boundaries. `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`; timestamps are elapsed from `captureStartedAtMs`. tmp rotate clears the index. Deleted unused `charts/disk_session.dart`. **Live Inspect is still SweepBuffer 5 min RAM only** until PR 2 wires this source. |

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

## Current code (after PR 1c)

| Piece | Where | After 1c |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts.{raw,computed,json}`; flush every 30 s or 64 KiB |
| Index | `monitor/cache/recording_index.dart` | `(elapsedT, fileLength)` at `flushRaw` frame boundaries. First frame offset **12**. Rotate clears. |
| File-backed source | `monitor/cache/file_backed_source.dart` | `MonitorController.fileBackedSource` → `getRange(startElapsed, endElapsed)`. Prepends header. Elapsed via `captureStartedAtMs`. Null start → empty. |
| Sweep EEG | `views/sweep_eeg_view.dart` + `charts/sweep_buffer.dart` | **own** 5 min `SweepBuffer` + `eventStream`. Add/remove, `GraphConfig.avgMode`, `eeg_layout_*`. **Rewire in PR 2.** |
| Raw EEG route | `app.dart` `AppView.rawEeg` → `RawEegView` → `SweepEegView` | Replace with `monitor/views/raw_eeg_view.dart` |
| `live_cache.dart` | `lib/src/charts/live_cache.dart` | unused. **Delete in PR 2.** |
| `graph_config.dart` / `eeg_chart.dart` / `eeg_dashboard.dart` | `lib/src/charts/` | add/remove + dead dashboard. **Delete in PR 2.** |
| Lease / tmp | `monitor/recording/` | exclusive; rotate resets `captureStartedAtMs` and the index |
| Pad quality | `connection_provider` `_PadQualityRing` | 4-ch, 1 s — **do not grow** |

Live Inspect is still SweepBuffer **5 min RAM only** until PR 2 calls `FileBackedSource.getRange`. Do not claim 30 min Inspect is done until that wire exists.

---

## PR 1c (landed) — what shipped

`RecordingIndex` + `FileBackedSource` under `monitor/cache/`. `SessionRecorder.onRawFlushed(fileLength)` after each `sessionFrameBytes` append. `MonitorRecorder` tracks last EEG ts, converts `(tsMs - captureStartedAtMs) / 1000.0`, skips the entry if no EEG yet. Bands-only flush reuses last EEG ts. Rotate / discard / new tmp **clears** the index.

`FileBackedSource.getRange`: covering frames → `RandomAccessFile.setPosition` at a **frame boundary** (offset 12 for the first) → complete frames only → prepend `sessionHeaderBytes()` → `sessionParseBody` → elapsed timestamps. Incomplete trailing frame omitted. `captureStartedAtMs == null` → empty `SessionData` (never unix epoch).

PR 2 Inspect of the current connection: SweepBuffer if the window fits in 5 min; otherwise `ref.read(monitorControllerProvider.notifier).fileBackedSource?.getRange(...)`. Follow still paints from RAM only.

Tests: `test/monitor/recording_index_test.dart`, `file_backed_source_test.dart` (FFI). Host lib: `cargo build --manifest-path rust/Cargo.toml`.

---

## This thread — PR 2

**Title:** `N stacked sweep EEG panes; cancel add/remove`

**ASCII first (required).** Paste a wireframe of `GraphShell` + N stacked sweep panes and **wait**. Do not write painters, move `sweep_buffer.dart`, or delete views until the ASCII is approved.

Wireframe must show:

- Header: **Follow | Inspect**, window length (2/4/8/10 s, default **10 s**), **no Record**, **no electrode chips**
- N stacked sweep panes (placeholder N = 4 Muse / 8 Crown from `lastConnectedKind`)
- Left electrode labels, plot, shared y-scale
- Follow = green wipe left→right; Inspect = grey freeze cursor
- Empty / waiting-for-signal state
- **No** add/remove, **no** drawer, **no** SMOOTH/REALTIME

### Do

- `GraphShell` as `ConsumerWidget` chrome (architecture B). Record slot exists but **hidden** until 5a.
- N stacked `SweepPane`s, `N = config.channelCount.toInt()` (`DeviceKind.muse` → 4 TP9/AF7/AF8/TP10; `neurosity` → 8 Crown names). Simulator Crown (`sim:crown-osc`) is 8-ch and startable for graphs.
- Keep oscilloscope sweep. Move `charts/sweep_buffer.dart` → `monitor/cache/sweep_buffer.dart`. Keep 300 s history + display ring + `dispPos`. `freeze()` / `resume()` / `sampleAt` / `displaySample`.
- Default window **10 s** (`2560` samples). Discrete 2 / 4 / 8 / 10 s.
- Follow = live green wipe. Inspect = `freeze()` + pan. Pinch-pan or drag **enters Inspect**. Follow snaps back (`resume()`).
- Inspect of the current connection: SweepBuffer if the window fits in 5 min; otherwise `FileBackedSource.getRange` (PR 1c). Convert nothing — 1c already returns elapsed `t`.
- `MonitorController` owns the SweepBuffer (one ring, not a second LiveCache). Hydrate/subscribe already in `main()`.
- Delete add/remove, `GraphConfig`, `avgMode`, `eeg_layout_*` persistence.
- Delete `live_cache.dart` once unused.
- Update `.ai/ui-map.md` for Follow / Inspect / Raw EEG chrome (same PR). Spoken names: Follow, Inspect — not Live / History / Freeze.

### Do not

- Implement painters before ASCII approval.
- Stripchart replacement. Do not delete `SweepBuffer`.
- Record button / Stop / `recording_` live UI (5a). Hide the chrome slot.
- Electrode chips on Raw EEG (each electrode is a pane).
- Bands / Histogram / PSD / Spectrogram (PR 3 / 4).
- Growing pad-quality to 8. Status-bar dots stay 4-ch.
- FFI / v5 header / lease / prefixes.
- Claiming 30 min Inspect unless `FileBackedSource` is actually called from Inspect.
- `device_montage.dart` imported from feedback. Feedback stays on `DeviceConfig.forKind`.

### Target files

```
lib/src/monitor/
  graph_shell.dart                 # NEW — chrome only
  viewport_controller.dart         # NEW — Follow / Inspect; elapsed domain
  empty_state.dart                 # NEW — "Waiting for signal"
  device_montage.dart              # NEW — monitor-only; N = channelCount.toInt()
  panes/sweep_pane.dart            # NEW — one electrode, green wipe / grey freeze
  views/raw_eeg_view.dart          # NEW — Column of N SweepPanes
  cache/sweep_buffer.dart          # MOVED from charts/
  cache/eeg_data_source.dart       # MOVE from charts/ if Raw EEG needs ChartSample
                                   # (or keep using SweepBuffer APIs directly)

lib/src/app.dart                   # AppView.rawEeg body → monitor RawEegView
.ai/ui-map.md                      # Follow / Inspect / Raw EEG chrome

DELETE:
  lib/src/views/sweep_eeg_view.dart
  lib/src/views/raw_eeg.dart
  lib/src/charts/graph_config.dart
  lib/src/charts/eeg_chart.dart
  lib/src/charts/eeg_dashboard.dart
  lib/src/charts/live_cache.dart    # if no remaining consumers
```

Ignore `eeg_layout_*` prefs; do not migrate `GraphConfig` JSON.

### SweepBuffer ownership

Today `SweepEegView` constructs its own `SweepBuffer` and listens to `eventStream`. After PR 2, **one** SweepBuffer lives on `MonitorController` (constructed in `main()`, already subscribed). Do **not** also run `LiveCache.appendEeg`. Delete `live_cache.dart`.

Follow writes the display ring. Inspect `freeze()` then `sampleAt` + pan. Beyond 5 min: `fileBackedSource?.getRange(startElapsed, endElapsed)` — EEG packet `timestamp` is already elapsed seconds; samples are 1/256 s apart.

`captureStartedAtMs == null`: RAM ring only (index 0 ⇒ t = 0 for the visible window). Never treat null as unix epoch (1c already skips file-backed).

### Montage

```dart
final kind = app.lastConnectedKind ?? DeviceKind.muse;
final names = electrodeNamesForKind(kind); // already on MonitorState
final n = names.length; // 4 or 8
```

`channelCount` on FFI `DeviceConfig` is `BigInt` — `.toInt()` if you call `forKind`. `MonitorState.channelCount` is already an `int`.

### Tests

Pure Dart preferred. No goldens / `integration_test`.

- Default window is 2560 samples / 10 s
- Muse-4 vs Crown-8 pane count from `lastConnectedKind`
- Follow wipe advances `dispPos`; Inspect `freeze()` stops it
- No `eeg_layout_*` writes
- Inspect window older than SweepBuffer 5 min calls `FileBackedSource` (can stub)
- `flutter analyze lib/src` clean

### Verify (PR 2)

```bash
flutter analyze lib/src
flutter test test/monitor/
```

FFI tests in `test/monitor/file_backed_source_test.dart` still need
`cargo build --manifest-path rust/Cargo.toml` first. Do **not** run FRB.
Do **not** `cargo check --target aarch64-linux-android`. Visual sweep
cannot be verified in CI — human `flutter run` after ASCII approval.

### PR 2 done when

- ASCII approved, then painters
- GraphShell + N SweepPanes; add/remove gone
- SweepBuffer moved; `live_cache.dart` / `graph_config.dart` / old Raw EEG views gone
- Record hidden; no chips
- Inspect beyond 5 min uses 1c `FileBackedSource`
- `.ai/ui-map.md` updated
- `flutter analyze lib/src` clean

---

## Next threads (do not start in PR 2)

### PR 3 / 4 — other graphs (ASCII first, each view)

Top-right depressed electrode labels → mean. Histogram new `AppView`. Keep `AppView.spectrogram`. FFT: Hamming 256-pt `1/N²`, edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50.

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
- **`sessionParseBody` needs the 12-byte header.** File-backed Inspect already prepends in 1c. Do not parse a mid-file slice yourself.
- **Do not slice mid-frame.** 1c omits incomplete trailing frames.
- **Index only at `flushRaw`.** Unflushed pending bytes stay RAM-only until the 30 s / 64 KiB flush. Inspect of the last few seconds may still be SweepBuffer-only.
- **Broadcast `eventStream`:** controller stays in `main()` (1a). Do not move it to AppShell. After PR 2, SweepBuffer is on the controller — do not also subscribe in the view.
- **tmp rotate** resets inspectable file-backed range. Clear was 1c; SweepBuffer RAM still has up to 5 min of the previous tmp.
- **Record (5a)** does not include pre-click bytes. Out of scope for PR 2.
- **`channelCount` is `BigInt` on FFI.** `MonitorState.channelCount` is already `int`.
- **SweepBuffer is the 5 min EEG ring.** Do not add a LiveCache EEG ring. Delete `live_cache.dart` in this PR.
- Stale `rust/target/release/` breaks `flutter run` if you ever touch FFI (this series should not).
- `flutter analyze lib/src` after every Dart PR. No goldens / `integration_test`.
- Agent HTTP: `persist: false`. No `/record/*` (5a). Crown 409 stays `crown_refused`.
- Sidecar rename stays `prefix_$id.json.tmp` → `prefix_$id.json`. Feedback `.metadata` JSONL stays append-only.

---

## Docs when a PR lands

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| Follow / Inspect (PR 2) | `.ai/ui-map.md` |
| `AppView.histogram` (PR 4) | `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Series complete | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
