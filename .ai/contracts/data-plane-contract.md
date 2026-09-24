# Data-plane spine contract

| Field | Value |
|---|---|
| Status | **Implemented.** D1–D3 frozen. |
| Scope | Acquisition → capture → Flutter subscribe. Ownership, compression, RAM, soak, folders, Android process survival. |
| Not this | Feedback pipeline; Crown *session run*; Connect UX; Athena optics; 68-byte `.neurofeed` header **size** / tags 1–10 ([fileformat_v6.md](fileformat_v6.md)); SoLoud; BLE/JNI internals. **Did** unwrap the container raw *section* (no outer zstd). |
| Packages | App `neurofeed`; Rust crate `rust_lib_neurofeed`. |
| Codec | On-disk compression is **zstd**, level **3**. Do not switch codecs. |

Sibling: [pipeline-contract.md](pipeline-contract.md). If a spine change would
force a feedback Key Decision reopen, **stop**.

Coordinator history (done): [../archive/handoff-spine.md](../archive/handoff-spine.md).
Do not implement from any archived Grokbot draft.

---

## Decisions (accepted)

| # | Decision |
|---|---|
| **D1** | Keep live inner zstd frames. **No outer zstd** on the container raw section. **No dual-read** of files that had the second wrap. |
| **D2** | Android overnight is specified here. FGS landed (`connectedDevice`, same process). Linux soak does not prove phone overnight. |
| **D3** | Do **not** replace `MuseEventDto`. Capture forks in Rust. Dart keeps `MuseEventDto` for graphs / FeatureBus / streaming. |

---

## Ownership

```
Headset / OSC / sim
  → Rust forwarder (derive bands / pulse / features / quality)
       ├─ capture writer (disk)     ← never through Dart
       └─ MuseEventDto → Dart       ← views only
```

- **Rust** owns device I/O, always-on DSP, subscribed feature production, capture encode, scratch append, streaming assemble.
- **Dart** owns UI, session/monitor orchestration (lease, start/stop, Record vs Start), `FeatureBus`, reward/guard lanes, network streaming, bounded graph rings.
- EEG never comes back from Dart to be encoded.
- Computed 1 Hz JSONL and sidecar JSON still originate in Dart and **post in**.

### Prefixes (one writer)

| Prefix | Live temps | Becomes `.neurofeed` (NFED6)? |
|---|---|---|
| `tmp_$ts` | `.raw` + `.computed` + `.json` | **Never.** 30 min rotate; launch glob-deletes. |
| `recording_$ts` | same | **Yes**, on Stop / crash recovery Save. |
| `session_$id` | `.raw` + `.computed` + `.metadata` JSONL | **Yes**, on End then History Save. |

Dart `SessionRecorder` is a facade. `writeEvent` is a **test injector**; production does not call it.

### Two layers

Live `.raw` **is** the container raw body (`NFEDBIN` + inner zstd frames). It is **not** the 68-byte NFED6 header.

```
live .raw      = NFEDBIN header + [u32][zstd frame]…   ← first zstd
live .computed = uncompressed JSONL
live sidecar   = uncompressed JSON / JSONL

assemble → [68-byte NFED6 header][WebP]
           [zstd(metadata JSON)]
           [zstd(computed JSONL)]
           copy of entire .raw file                    ← no second zstd
```

Assemble **copies** `.raw` byte-for-byte. Flags byte stays `0`. Header size unchanged. Files that had an outer zstd on raw are unsupported — no `decode_all` fallback, no flags bit, no magic sniff.

---

## Key Decisions

1. **Fork after derivation, before Dart.** Capture taps outgoing DTOs in Rust. It does not wait for Dart and does not re-ingest `MuseEventDto` on the live path.
2. **One Rust writer, three prefixes.** Dart keeps `CaptureLease` and product rules (Record vs Start, tmp rotate 30 min, tmp never assembled, prefix-strict crash recovery). Rust also refuses a second `start`. `recordStreams` is an argument to start. I/O runs on a dedicated writer thread.
3. **Live inner zstd frames; no outer zstd on raw.** Metadata + computed still zstd at assemble. No dual-read. Do not restore the second wrap in code or docs.
4. **Assemble writes a path.** FFI does not return the container `Vec<u8>` for keepable captures. In-memory helpers are for **small** fixtures only.
5. **Computed + sidecar go through the same writer.** Two Dart facades (`FeedbackRecorder` / `MonitorRecorder`) are fine; two disk owners are not.
6. **Save / notes / thumbnail patch never decode raw.** Copy thumbnail, computed, and raw **sections as opaque bytes**. Only metadata JSON is decompressed. Charts stay on computed 1 Hz. CSV/EDF may stream-parse raw on a worker, never `v5ExtractRaw` of 12 h on the UI isolate.
7. **`MuseEventDto` remains the Dart view pipe** (D3). Capture must not depend on it.
8. **Dart rings stay bounded.** `SweepBuffer` 5 min, `BandCache` 1800 s. No “keep every event in Dart for 12 h.” Inspect beyond RAM uses live `.raw` + flush index.
9. **Drop policy.** Disk full or write error: **stop capture, keep temps, surface an error** — do not clear the BLE sink. View-pipe overflow may drop **view** samples only. Soak fails on capture drops > 0.
10. **Soak harness is required** before claiming 12 h. Agents must not wait wall-clock 12 h. Command: [../test-matrix.md](../test-matrix.md).
11. **Multi-source “equals” means one writer + one DSP + one view DTO.** Do not add `rust/src/spine/normalize/`. New streams (Athena optics) enter via a **format PR**, not a spine type system.
12. **Android overnight is specified here; FGS landed.** Linux volume proof does not wait on a phone night.
13. **New capture/assemble/soak code stays under `spine/`.** Do not add a third writer under `monitor/` or `feedback/`.
14. **Agents follow this file.** Deviations: written why before merge.
15. **Do not reopen** feedback Key Decisions, Crown Start, Connect UX, monitor graph freezes, or the container header **size** / tag set (NFED6). Do not restore outer zstd.

---

## Capture API (names frozen)

FRB re-exports in `rust/src/api/capture.rs`. Prefer path-returning Dart `Future`s. Do not `#[frb(sync)]` anything that can block on 12 h I/O. Computed/sidecar posts are `#[frb(sync)]` (`try_send`); assemble is not.

| Fn | Role |
|---|---|
| `capture_start(dir, prefix, id, record_streams, started_at_ms)` | prefix `"tmp"` \| `"recording"` \| `"session"` |
| `capture_stop()` | flush; temps stay |
| `capture_append_computed_line(line)` | Dart posts one JSONL line |
| `capture_write_sidecar(json)` | JSONL append (session) or atomic snapshot (monitor) |
| `capture_assemble_v5(metadata_json, thumbnail)` | file-to-file; returns path; deletes temps on success |
| `capture_assemble_v5_at(...)` | leftover temps, no live session |
| `capture_discard()` | delete temps |
| `capture_flush_index()` | Inspect: `(elapsed_s, exclusive_end_offset)` |

Also: `capture_flush`, `capture_recorded_channels`, `capture_drop_count`, `capture_write_errors`, `capture_is_active`. `capture_append_event` is a **test / Inspect injector**. Live EEG/PPG/IMU/bands are **not** on this FFI; the forwarder calls `on_dto` in-process.

`encode_session_event` / `session_frame_bytes` remain for tests and small fixtures. Production live path must not go Dart → those two.

---

## Threading

| Who | Capture |
|---|---|
| BLE / JNI notify | **Never** write here |
| Forwarder task | encode record bytes + **`try_send`**. No `write` / zstd / fsync |
| **Capture writer** (`std::thread`) | recv → 64 KiB buffer → inner zstd frame → `write`. Flush ~30 s. Join on stop/assemble |
| Dart UI isolate | views, orchestration, computed/sidecar posts. **Never** live encode |

Channel: already-encoded record bytes, **not** DTOs. Cap **`MAX_PENDING_BYTES=4MiB`**. `try_send` from the forwarder: if full, do not block BLE/DSP; apply KD drop policy. Do not: a second tokio runtime; write from the JNI thread; `spawn` a thread per flush; `fsync` every frame.

---

## RAM

Extra RSS for assemble / Save / notes / thumbnail patch **does not grow with session length.** Budget: a few streaming buffers, cap **64 MB** extra vs idle on a 12 h file.

**Forbidden on the live / keepable path:** Dart `encodeSessionEvent` / `sessionFrameBytes`; Dart `readAsBytes` of a keepable `.raw`; `containerEncodeV5` / `v5ExtractRaw` of a whole keepable capture on the UI isolate.

**Allowed one-way posts:** computed JSONL line; sidecar JSON; start/stop/assemble commands.

---

## Soak (two bars)

Design load: Classic Muse rates, all `RecordingStream`s, **12 h equivalent** (~0.4–0.6 GB uncompressed records). Crown is not the design load. `tmp_` is 30 min and out of scope.

Harness: `rust/src/spine/soak.rs`. Default 60 s equivalent; 12 h-equivalent is `#[ignore]` / `NEUROFEED_SOAK_EQUIV_SECS=43200`. Pass = drops 0, write_errors 0, assemble succeeds, extra assemble RSS does not scale with volume.

| Bar | Proves | Does not prove |
|---|---|---|
| **Volume (Linux soak)** | append, inner frames, streaming assemble, notes patch, no O(n) RAM | phone process survival, BLE, OEM killers |
| **Process (Android FGS)** | recording/session survives screen-off + background | 12 h-equivalent RAM (use soak) |

A literal 12 h phone night is manual QA.

---

## Android FGS

Same process as Flutter/Rust. Type **`connectedDevice`**. Manifest: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS` (API 33+).

Start FGS when keepable capture starts (`recording` / `feedback`); stop when that capture ends (keep until Save/Discard if unsaved). **Not** for `tmp_`. Persistent notification: recording vs session; elapsed; tap opens the app.

Do **not** keep the screen on as the overnight mechanism. No `RECEIVE_BOOT_COMPLETED`. Share one FGS with session audio; do not start a second competing service. Do not deinit SoLoud from a controller.

Linux / Windows: no FGS. Overnight = process left running. Desktop `AppLifecycleListener` already assembles recording on exit.

Spoken names: [../ui-map.md](../ui-map.md) Android capture notification.

---

## Tree

```
.ai/contracts/data-plane-contract.md   ← this file
rust/src/spine/{mod,capture,soak}.rs
rust/src/api/{capture.rs, session_format.rs, muse.rs}
lib/src/spine/{capture_client,capture_foreground,scratch_writer,assemble}.dart
```

`session_format.rs` is still the byte-layout authority. Do not move DSP, features, graph panes, audio, or the protocol builder under `spine/`.

---

## 10 leftovers (not a reopen)

- Literal 12 h phone night (FGS itself landed).
- Leftover import re-exports under `session_v5/` / `feedback/` / `charts/`.
- History recording Inspect still `v5ExtractRaw`s a published file.
- Optional view-API series (D3 declined).

---

## Agent rules

- Read **this** file before data-plane / recording / scratch / assemble / overnight work.
- Do not restore Dart live encode, outer zstd on the container raw section, or whole-raw `readAsBytes` / `v5ExtractRaw` on keepable captures.
- Do not add `rust/src/spine/normalize/`.
- Do not claim 12 h from a 30 s Record, or Android overnight from Linux soak.
