# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-07 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a `2a66eae`, PR 1b this commit). Suggested name was `feat/monitor-graphs`. |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 1c**. |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, `File layout`, `PR Plan`, `Implementer protocol`). This file is implementer order, current-code pitfalls, and the **PR 1c** start. Do not re-design graphs, naming, or the lease.

---

## Paste this to start a new thread

**PR 1c (this thread):**

```
Implement monitor PR 1c only: file-backed Inspect of tmp/recording .raw.
Spec: .ai/monitor.md (frozen). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 1c”).
Index framed .raw at flush boundaries; getRange prepends sessionHeaderBytes() then sessionParseBody. Convert ms-epoch timestamps to elapsed via captureStartedAtMs. No GraphShell. No Record button. Do not start PR 2.
```

**Later graph threads (2 / 3 / 4)** must paste an ASCII wireframe and wait before painters. See spec **Implementer protocol**.

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Thin re-exports at old paths. |
| **1a** | `2a66eae` — `MonitorController` in `main()` after `appStateProvider.notifier`. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring. `live_cache.dart` unused (delete in PR 2). `SweepEegView` untouched. |
| **1b** | Exclusive `tmp_` writer + lease. `AppStateNotifier.sessionRecorder` gone. Connect starts `tmp_$ts.{raw,computed,json}` with `Settings.recordStreams`. Feedback `acquireFeedbackLease` discards tmp; `end()` releases only if `!isRecording`. Launch glob-deletes leftover `tmp_*`. `GET /state` has `captureKind` / `captureElapsedSeconds`. Snapshot sidecar `prefix_$id.json.tmp` → `prefix_$id.json`. No Record chrome, no GraphShell, no file-backed Inspect. |

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

## Current code (why PR 1c exists)

| Piece | Where | After 1b |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts.{raw,computed,json}`; flush every 30 s or 64 KiB via `SessionRecorder.flushRaw` (`sessionFrameBytes`) |
| Index | **missing** | Inspect beyond SweepBuffer 5 min has no file reader |
| `.raw` layout | `session_format.rs` | 12-byte `MUSEBIN` header, then frames `[u32 LE zstd-len][payload]`. `sessionParseBody` **rejects** a mid-file slice (`Truncated .muse header` / `Not a .muse file`) |
| `flushRaw` | `session_v5/scratch_writer.dart` | appends one frame; **no callback**, no index |
| Sweep EEG | `views/sweep_eeg_view.dart` + `charts/sweep_buffer.dart` | own 5 min `SweepBuffer` + `eventStream`. **Do not rewire** (PR 2) |
| `disk_session.dart` | `lib/src/charts/disk_session.dart` | unused stub (`getRange` returns `[]`). Replaced by `file_backed_source.dart` — **delete** if still unreferenced |
| `live_cache.dart` | `lib/src/charts/live_cache.dart` | unused. Delete in PR 2, not 1c |
| Lease / tmp | `monitor/recording/` | exclusive; rotate resets `captureStartedAtMs` (and must reset the index) |
| Pad quality | `connection_provider` `_PadQualityRing` | 4-ch, 1 s — **do not grow** |
| Crash recovery | `feedback/crash_recovery.dart` | `session_*` only. Monitor glob-deletes `tmp_*` only |

tmp exists so Inspect of the **current connection** can go past 5 min RAM, up to the 30 min cap. Until 1c that is a documented gap — do not claim 30 min Inspect.

---

## This thread — PR 1c

**Title:** `Index tmp_/recording_ raw frames for Inspect beyond SweepBuffer`

**Do:** frame-boundary index of the open `tmp_` (and later `recording_`) `.raw`. `FileBackedSource.getRange` reads complete frames, **prepends `sessionHeaderBytes()`**, calls `sessionParseBody`, converts ms-epoch record timestamps to elapsed via `captureStartedAtMs`.

**Do not:** GraphShell, SweepEegView rewire, Record button, `recording_` live UI, assembling tmp, moving `sweep_buffer.dart`, deleting `live_cache.dart`, growing pad-quality to 8, changing the v5/`.muse` byte layout, FFI surface, claiming saved-recording dashboard Inspect (PR 6).

### Target files (new)

```
lib/src/monitor/cache/
  recording_index.dart       # (elapsedT, fileLength) at flushRaw frame boundaries
  file_backed_source.dart    # getRange: seek complete frames, prepend header, parse

test/monitor/
  recording_index_test.dart  # and/or file_backed_source_test.dart — Dart+FFI
```

`disk_session.dart` is an unused stub. Delete it in this PR if nothing imports it (today nothing does). Do not keep a second disk source.

### Index

`RecordingIndex` entries are `(elapsedT, fileLength)` produced **only** at `flushRaw` (`sessionFrameBytes`) boundaries. Do **not** index mid-frame or unflushed pending bytes.

- `elapsedT` = last EEG timestamp in that flush, converted: `(tsMs - captureStartedAtMs) / 1000.0`. If the flush has no EEG (bands-only, etc.), use the last EEG ts already seen, or skip the entry if none yet.
- `fileLength` = `_rawFile.lengthSync()` **after** the frame is appended. That is the exclusive end offset of this frame (start of the next).
- First frame starts at offset **12** (header). Do not treat offset 0 as a frame.
- Binary search / scan the index to find entries covering `[startElapsed, endElapsed]`.

Hook `flushRaw` — add a callback on `SessionRecorder` or wrap it in `MonitorRecorder`. Do not fork a second writer. Periodic 30 s flush + 64 KiB auto-flush already exist; index those.

**tmp rotate** (already in 1b): discard file, new `tmp_$ts`, reset `captureStartedAtMs`. **Clear the index.** Inspect of “current connection” is the new tmp plus whatever is still in the 5 min RAM ring — not the previous tmp.

### `FileBackedSource.getRange(startElapsed, endElapsed)`

Frozen steps:

1. Find index entries covering the window.
2. `RandomAccessFile.setPosition` at the first needed frame start; read **complete** frames through the last needed frame (do not slice mid-frame).
3. **Prepend `sessionHeaderBytes()`** (12-byte `MUSEBIN` header). A mid-file slice without it fails `sessionParseBody`.
4. `sessionParseBody` on that buffer. Convert record timestamps (ms epoch) to elapsed via `captureStartedAtMs`.

`EegSampleRecord.timestamp` is the ms epoch of the **first** sample in the packet; later samples in the packet are 1/256 s apart. Viewport domain is **elapsed seconds from this capture**, same as computed JSONL `t`.

```
elapsed = (tsMs - captureStartedAtMs) / 1000.0
```

**Never treat `captureStartedAtMs == null` as unix epoch.** If missing, skip file-backed range (RAM ring only).

`SessionData.eegSamples` is `BigInt` — `.toInt()` if you need an `int`.

Saved recordings (`v5ExtractRaw` → in-memory body that **already has** the 12-byte header) can wait for the recording dashboard (PR 6). **tmp** index is this PR. Do not treat the zstd v5 container as seekable.

### Who consumes it (not this PR)

PR 2 Inspect of the current connection: SweepBuffer if the window fits in 5 min; otherwise `FileBackedSource`. 1c lands the source and keeps it wired from the tmp writer so PR 2 can call `getRange`. Do **not** change SweepEegView in 1c.

Follow still paints from RAM rings only.

### Tests (FFI)

Host lib first: `cargo build --manifest-path rust/Cargo.toml`.

Required cases:

1. After `writeEvent` + `flushRaw`, index has one entry; `fileLength` equals the `.raw` size
2. `getRange` over that window returns EEG (or bands) with **elapsed** `t`, not unix seconds
3. Slice **without** prepending `sessionHeaderBytes()` → `sessionParseBody` errors (`Truncated .muse header` / `Not a .muse file`) — assert the prepend path does not
4. `getRange` does not start mid-frame (read from a frame boundary; incomplete last frame is omitted)
5. Rotate / new tmp → index empty (or only the new file)
6. `captureStartedAtMs == null` → no unix-epoch range

### PR 1c done when

- `RecordingIndex` + `FileBackedSource` exist under `monitor/cache/`
- tmp `flushRaw` appends index entries
- `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`
- timestamps are elapsed from `captureStartedAtMs`
- tmp rotate clears the index
- No GraphShell, no Record chrome, SweepEegView untouched
- `flutter analyze lib/src` clean
- FFI tests green

Until PR 2 uses this, **say in the PR** that live Inspect is still SweepBuffer 5 min RAM only. Do not claim 30 min Inspect is done.

### Verify (PR 1c)

```bash
cargo build --manifest-path rust/Cargo.toml
flutter analyze lib/src
flutter test test/monitor/recording_index_test.dart \
  test/monitor/file_backed_source_test.dart \
  test/monitor/capture_lease_test.dart \
  test/monitor/monitor_sampler_test.dart \
  test/monitor/band_cache_test.dart
```

(Adjust test filenames if you combine them.) Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`.

---

## Next threads (do not start in PR 1c)

### PR 2 — sweep EEG (ASCII first)

Paste ASCII of GraphShell + N stacked sweep panes (Follow/Inspect, 10 s window, green wipe, **no** Record yet, **no** electrode chips, no add/remove). Wait. Then move `sweep_buffer.dart` into `monitor/cache/`. Delete `graph_config.dart`, `eeg_dashboard.dart`, `eeg_chart.dart`, `sweep_eeg_view.dart` add/remove / `eeg_layout_*`. Default 10 s (`2560` samples). Placeholders: Muse-4 vs Crown-8 from `lastConnectedKind`. Inspect beyond 5 min uses 1c `FileBackedSource`.

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

- **`sessionParseBody` needs the 12-byte header.** A seek into framed `.raw` is not a `.muse` body. Always prepend `sessionHeaderBytes()`.
- **Do not slice mid-frame.** Frames are `[u32 LE length][zstd bytes]`. Incomplete trailing frame: omit it.
- **Index only at `flushRaw`.** Unflushed pending bytes stay RAM-only until the 30 s / 64 KiB flush.
- **Broadcast `eventStream`:** controller stays in `main()` (1a). Do not move it to AppShell.
- **`assembleScratchV5` failure** keeps `_rawFile`. Do not release the lease (1b invariant).
- **tmp rotate** resets inspectable file-backed range. Clear the index.
- **Record (5a)** does not include pre-click bytes in the recording file. Out of scope for 1c.
- **`channelCount` is `BigInt`.** Always `.toInt()`. Same for `SessionData.eegSamples`.
- **SweepBuffer is the 5 min EEG ring** (still in `charts/`). Do not add a LiveCache EEG ring. Leave `live_cache.dart` for PR 2.
- Stale `rust/target/release/` breaks `flutter run` if you ever touch FFI (this series should not). 1c **calls** existing FFI (`sessionHeaderBytes` / `sessionParseBody` / `sessionFrameBytes`); it must not change them.
- `flutter analyze lib/src` after every Dart PR. No goldens / `integration_test`.
- Agent HTTP: `persist: false`. No `/record/*` (5a). Crown 409 stays `crown_refused`.
- Sidecar rename stays `prefix_$id.json.tmp` → `prefix_$id.json`. Feedback `.metadata` JSONL stays append-only.

---

## Docs when a PR lands

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| `AppView.histogram` (PR 4) | `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Series complete | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux. PR 1c has no on-screen copy.
