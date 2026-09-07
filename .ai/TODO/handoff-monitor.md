# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-07 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** |
| Suggested branch | `feat/monitor-graphs` from `main` (after SoLoud / current work merges). Do **not** pile onto `fix/soloud-engine-hardening` or Athena optics. |
| Cadence | **One PR per thread.** This file is the series map. Start at **PR 0**. |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, `File layout`, `PR Plan`, `Implementer protocol`). This file is implementer order, current-code pitfalls, and the **PR 0** start. Do not re-design graphs, naming, or the lease.

---

## Paste this to start a new thread

**PR 0 (first thread):**

```
Implement monitor PR 0 only: extract lib/src/session_v5/.
Spec: .ai/monitor.md (frozen). Handoff: .ai/TODO/handoff-monitor.md (this file, section “This thread — PR 0”).
Behavior-preserving. No UI. No FFI. No lib/src/monitor/ yet. Do not start PR 1a.
```

**Later graph threads (2 / 3 / 4)** must paste an ASCII wireframe and wait before painters. See spec **Implementer protocol**.

---

## What this series is doing

Sidebar live-signal views (Bands, Raw EEG, Spectrogram, PSD) were a first test: sweep EEG with add/remove graphs, a custom Bands dashboard, two placeholders. Recording is dual-owned:

- `AppStateNotifier.sessionRecorder` writes `session_$ts` temps from connect and **deletes** them on disconnect.
- `FeedbackRecorder` starts a **second** `SessionRecorder` on `startCalibration()`, also `session_$id`, same scratch dir.

This series: isolate graphs + connect/explicit recording under `lib/src/monitor/`, exclusive capture lease, rolling `tmp_` (30 min) for Inspect-beyond-RAM, explicit `recording_` with Save/Discard, unified **History** list. Feedback sessions stay `session_*`.

---

## Frozen (short — full list in the spec)

Do not re-litigate:

1. Feature root `lib/src/monitor/` + extract `lib/src/session_v5/` first.
2. Graph architecture **B** (`GraphShell` + per-kind panes). Cancel add/remove and `avgMode`.
3. **Follow / Inspect.** Not Live/History.
4. Sidebar: Feedback, **History**, Bands, Raw EEG, Histogram, PSD, **Spectrogram**. No Recordings item. Enum `feedbackHistory` stays; label becomes `History`.
5. Raw EEG = **oscilloscope sweep** (green wipe L→R). N panes = `channelCount.toInt()`. Not stripchart. Keep `SweepBuffer`.
6. Exclusive lease: `tmp` \| `recording` \| `feedback` \| `idle`. Release feedback lease only when `!_recorder.isRecording`.
7. Prefixes `tmp_$ts` / `recording_$ts` / `session_$id`. Feedback crash recovery stays `session_*` only.
8. Published files in the **same history folder**. One sqlite `session_metadata.db` + `kind`. Settings **Save files to folder**.
9. Spectrogram keeps that name. Histogram is new. PSD sidebar shortens to `PSD`.
10. Non-EEG: top-right electrode **text** labels, tap toggles **average**, depressed = on, default all, last-one stays. EEG: no chips.
11. 5 min SweepBuffer RAM + 30 min tmp. No second `LiveCache` EEG ring. File-backed Inspect is **PR 1c, required**.
12. `MonitorController` constructed in `main()` (same `ProviderContainer` as `AppStateNotifier`) + hydrate if already connected.
13. No FFI. Dart FFT in `monitor/dsp.dart` when those views land.
14. Graph PRs 2/3/4: **ASCII first**, wait, then code.
15. Crown graphs + recording allowed; Crown **Start Session** still refused.
16. Start Session during Record: three-layer refuse (`_refuseRecordingStart`, `AgentCommands._start` 409 `recording_active` **before** notifier, lease). Distinct from `crown_refused`.

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

## Current code (why PR 0 exists)

| Piece | Where | Problem |
|---|---|---|
| Connect writer | `lib/src/connection_provider.dart` `sessionRecorder` + `_startContinuousRecorder` | `session_$ts`; `stop()` deletes; ignores `Settings.recordStreams` |
| Feedback writer | `lib/src/feedback/feedback_recorder.dart` → own `SessionRecorder` | second `session_$id` in the same scratch dir |
| Scratch temps | `lib/src/charts/session_recorder.dart` | hardcoded `session_$ts.{raw,computed,metadata}` |
| Assemble | `lib/src/feedback/session_assembler.dart` | `writeScratchV5` hardcodes `session_$id.muse.feedback` |
| Dart `ComputedFrame` | `lib/src/feedback/computed_frame.dart` + `.freezed.dart` | needed by both products; move with part file |
| V5 models | `lib/src/feedback/session_v5_models.dart` | `DeviceInfoV5`, `StreamsConfig` — recording metadata source of truth |
| Crash recovery | `lib/src/feedback/crash_recovery.dart` | `session_*` only — **must stay that way** |
| Sweep EEG | `lib/src/views/sweep_eeg_view.dart` + `charts/sweep_buffer.dart` | add/remove (cap 12); **keep the wipe**; move buffer in PR 2 |
| Placeholders | `views/psd_view.dart`, `views/terminal.dart` | delete in PR 4 |
| `eventStream` | `connection_provider.dart` | **broadcast** — no listener ⇒ dropped. `main()` constructs `AppStateNotifier` before `runApp`. PR 1a hydrates. |
| `DeviceConfig.channelCount` | FRB `BigInt` | always `.toInt()` |
| Pad quality | `connection_provider` `_maybeComputeSignalQuality` | 4-ch, skip `ch > 3` — **out of scope** |

---

## This thread — PR 0

**Title:** `Extract session_v5 writer, assembler, ComputedFrame, and v5 models`

**Do:** move shared v5 Dart next to the FFI wrappers so monitor can assemble without importing feedback lanes.

**Do not:** UI, `lib/src/monitor/`, lease, tmp/recording prefixes in live connect, GraphShell, FFI, `build_runner` unless you edit `computed_frame.dart` source (moving the existing `.freezed.dart` is enough).

### Target tree

```
lib/src/session_v5/
  assemble.dart              # assembleV5Container, writeScratchV5, parseComputedJsonl,
                             # toFfiFrame, encodeThumbnailWebP, placeholderWebP,
                             # extractComputedScalars, ComputedScalars
  placeholder_webp.dart      # optional split; may live at top of assemble.dart
  scratch_writer.dart        # SessionRecorder moved; prefix default 'session'
  computed_frame.dart        # + computed_frame.freezed.dart (move together)
  models.dart                # was session_v5_models.dart
```

### Moves (keep behavior)

| From | To |
|---|---|
| `lib/src/feedback/computed_frame.dart` **and** `computed_frame.freezed.dart` | `session_v5/` — `part 'computed_frame.freezed.dart'` stays valid |
| `lib/src/feedback/session_v5_models.dart` | `session_v5/models.dart` |
| `lib/src/charts/session_recorder.dart` | `session_v5/scratch_writer.dart` (keep class name `SessionRecorder` or rename to `ScratchWriter` **and** typedef/re-export the old name) |
| Assemble helpers in `session_assembler.dart` (not FeedbackRecorder) | `session_v5/assemble.dart` |

Leave **thin re-exports** at the old paths so a missed import still compiles:

- `lib/src/feedback/computed_frame.dart` → `export 'package:muse_ml/src/session_v5/computed_frame.dart';`
- `lib/src/feedback/session_v5_models.dart` → export `session_v5/models.dart`
- `lib/src/feedback/session_assembler.dart` → export assemble symbols
- `lib/src/charts/session_recorder.dart` → export the writer
- `lib/src/feedback/session_store.dart` already `export 'session_v5_models.dart';` — keep that file as a re-export so `session_store.dart` does not change its public API

**Also retarget call sites** (do not rely on re-exports forever):

| File | Today |
|---|---|
| `lib/src/feedback/computed_sampler.dart` | `computed_frame.dart` |
| `lib/src/feedback/feedback_recorder.dart` | `session_recorder` + `session_assembler` + `computed_frame` |
| `lib/src/feedback/crash_recovery.dart` | `session_assembler` |
| `lib/src/feedback/session_store_core.dart` | `session_assembler` (`assembleV5Container`, `placeholderWebP`, `extractComputedScalars`) |
| `lib/src/views/feedback_dashboard.dart` | `encodeThumbnailWebP` |
| `lib/src/connection_provider.dart` | `charts/session_recorder.dart` |
| `test/session_computed_charts_test.dart` | recorder + assembler + computed_frame |

`FeedbackRecorder.assembleScratchV5` **stays** that method name (wrapper around `writeScratchV5`). Do not rename it.

### Allowed API tweaks (must default to today’s behavior)

`writeScratchV5` — add optional `prefix` (default `'session'`):

```dart
final file = File('${dir.path}/${prefix}_$id.muse.feedback');
```

`SessionRecorder.start` — add optional `prefix` (default `'session'`) so the base path is `$dir/${prefix}_$ts`. Sidecar stays **`.metadata` JSONL**. Do **not** implement the monitor `.json` snapshot here.

Do not change `containerEncodeV5` / header / tags.

### PR 0 done when

- `lib/src/session_v5/` exists with the files above.
- Old paths are re-exports (or gone if every call site is updated **and** `flutter analyze` is clean).
- Feedback still writes `session_*.raw` / `.computed` / `.metadata` and assembles `session_*.muse.feedback`.
- Connect still uses the same writer (still dual-owned — that is PR 1b).
- No new sidebar, no Record button, no `CaptureKind`.

### Verify (PR 0)

```bash
flutter analyze lib/src
cargo build --manifest-path rust/Cargo.toml
flutter test test/session_computed_charts_test.dart \
  test/session_store_test.dart test/session_export_test.dart \
  test/session_metadata_roundtrip_test.dart
```

Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`. Host `.so` trap: build the lib before those FFI tests. See `.ai/testing-guide.md` / skill `muse-verify`.

---

## Next threads (do not start in PR 0)

Read the matching spec sections when that thread opens.

### PR 1a — controller + caches, no disk

Construct `monitorControllerProvider` in `main()` immediately after `appStateProvider.notifier`. Subscribe to broadcast `eventStream`, **hydrate if `status.connected`**. Split `bandNames`/`bandColors` → `lib/src/charts/band_style.dart` (feedback dashboard/export keep importing charts). Move band ring into monitor. **Do not** add a second 5 min EEG `LiveCache`. Do not rewire `SweepEegView`. Keep 4-ch pad-quality ring in `connection_provider`.

### PR 1b — tmp + lease

Kill `AppStateNotifier.sessionRecorder` / `_startContinuousRecorder`. Connect starts `tmp_$ts`. Feedback `startCalibration` `acquireFeedbackLease` (discards tmp). `end()` releases **only if `!_recorder.isRecording`**. Failed `assembleScratchV5` stays `CaptureKind.feedback`. `Settings.recordStreams` applies to tmp (behavior change vs today’s all-streams dump). 30 min silent rotate. Launch glob-deletes leftover `tmp_*`. Tests in `test/monitor/capture_lease_test.dart`.

### PR 1c — file-backed Inspect (**required**)

Index framed `.raw` at flush boundaries; `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`. Until this lands, Inspect is SweepBuffer 5 min only — say so, do not claim 30 min.

### PR 2 — sweep EEG (ASCII first)

Paste ASCII of GraphShell + N stacked sweep panes (Follow/Inspect, 10 s window, green wipe, **no** Record yet, **no** electrode chips, no add/remove). Wait. Then move `sweep_buffer.dart` into `monitor/cache/`. Delete `graph_config.dart`, `eeg_dashboard.dart`, `eeg_chart.dart`, `sweep_eeg_view.dart` add/remove / `eeg_layout_*`. Default 10 s (`2560` samples). Placeholders: Muse-4 vs Crown-8 from `lastConnectedKind`.

### PR 3 / 4 — other graphs (ASCII first, each view)

Top-right depressed electrode labels → mean. Histogram new `AppView`. Keep `AppView.spectrogram`. FFT: Hamming 256-pt `1/N²`, edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50.

### PR 5a / 5b / 6

Record/Stop, 409 `recording_active` on **`AgentCommands._start`** (there is no `_sessionStart`), Save/Discard, crash recovery for `recording_*` only, History filter All|Feedback|Recordings, sqlite `kind`, Settings **Save files to folder**.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`.

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `monitor/`** except the lease API (PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`.

History list stays `lib/src/views/feedback_history.dart` (PR 6). Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **Broadcast `eventStream`:** constructing the controller only in `AppShell` misses connect. PR 1a = `main()` + hydrate. Do not copy `StreamingController`.
- **`assembleScratchV5` failure** keeps `_rawFile` (`isRecording == true`). Starting `tmp_` then is two writers again.
- **SAF** list/read/delete have **no** `dir:`. Do not publish into a `recordings/` child.
- **`channelCount` is `BigInt`.**
- **SweepBuffer is the 5 min EEG ring.** Do not also `LiveCache.appendEeg`.
- **tmp rotate** resets inspectable range; Record does not include pre-click bytes (Follow rings still show them).
- Stale `rust/target/release/` breaks `flutter run` if you ever touch FFI (this series should not).
- `flutter analyze lib/src` after every Dart PR. No goldens / `integration_test`.
- Agent HTTP: `persist: false`. `GET /state` uses `captureKind` + `captureElapsedSeconds`, not feedback `elapsedSeconds`. Crown 409 stays `crown_refused`.

---

## Docs when a PR lands

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| `AppView.histogram` (PR 4) | `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Series complete | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
