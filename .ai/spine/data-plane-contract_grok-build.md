# Data-Plane Spine Contract (Grok Build)

| Field | Value |
|---|---|
| Status | **Frozen** — D1 + D2 + D3 accepted. Implement from [handoff-spine.md](handoff-spine.md). |
| Date | 2026-09-20 |
| Author | Grok Build (this file). Sibling draft: [../archive/data-plane-contract.md](../archive/data-plane-contract.md) (Grokbot; historical, not implementable) |
| Branch | `refactor/spine` |
| Scope | Freeze acquisition → capture → Flutter subscribe so 12 h keepable recording is a designed load, not a hope. Ownership, compression, RAM, soak, folders, Android process survival. |
| Not this doc | Rewrite of [../feedback/pipeline-contract.md](../feedback/pipeline-contract.md); Crown *session run*; Connect UX; Athena optics; v5 68-byte header **size** / tag set 1–10; SoLoud; BLE/JNI/btleplug internals. **Does** change the container raw *section*: no outer zstd (see D1). |
| Packages | App `neurofeed`; Rust crate `rust_lib_neurofeed`. **No `muse_ml`.** |
| Codec | On-disk compression is **zstd**, not zlib. Level **3**, same as today. Do not switch codecs in this series. |

**Order of work:** this file is frozen. Implement from [handoff-spine.md](handoff-spine.md) (coordinator thread, PRs 1–7). Do not ship the Rust writer before PR 3 (outer zstd gone + streaming assemble).

**Sibling, not reopen:** align with the frozen feedback pipeline (always-on DSP vs subscribed `FeatureDto`, `FeatureBus`, Crown Start refused). If a spine change would force a feedback Key Decision reopen, **stop** and ping windwerfer.

---

## Decisions needed from windwerfer

Defaults below are what this contract implements if you say “go.” Override before PR 2.

| # | Question | Default in this file | Why it is a ping |
|---|---|---|---|
| D1 | Live inner zstd + outer container zstd on raw? | **Accepted.** Keep inner frames. **Kill the outer zstd.** **No backwards compatibility** for files that had the second wrap. See [Two layers](#two-layers-one-writer). |
| D2 | Android overnight in this series? | **Accepted.** Specify now, implement last (PR 7). Linux soak does not wait on it. |
| D3 | Replace `MuseEventDto` this series? | **Accepted: no.** Capture forks in Rust. Dart keeps `MuseEventDto` for graphs / FeatureBus / streaming. |

---

## What D3 is (the view pipe)

D1/D2 are about **disk** (how we record 12 h) and **the Android process** (how the app stays alive). D3 is about a **different pipe**: how live samples reach Flutter so graphs, feedback, and OSC/LSL can draw and react.

Today there is **one** FRB stream, `MuseEventDto`, for everything:

```
Rust forwarder
  → sink.add(MuseEventDto)     // EEG, bands, pulse, features, …
  → Dart connection_provider broadcast
       ├─ graphs
       ├─ FeatureBus → reward/guard
       ├─ OSC / LSL / BrainFlow
       └─ SessionRecorder.encode   ← this last use is the bug
```

The Grokbot draft called that whole stream a “short bridge” and said the end state was a **new** Rust→Dart API (maybe downsampled view samples, maybe several streams) that would **retire** `MuseEventDto`. That is a UI/FFI redesign. It is not what makes overnight recording work.

This series only needs the **fork**:

```
Rust forwarder
  ├─ capture writer (disk)     ← new, never goes through Dart
  └─ MuseEventDto → Dart       ← keep, for views only
```

So D3 is the question: **while we are in the spine, do we also invent a replacement for `MuseEventDto`?**

| | If we **skip** D3 (recommended) | If we **do** D3 now |
|---|---|---|
| 12 h file | Works (writer + no second zstd + FGS) | Same, plus a second project |
| Graphs / FeatureBus / streaming | Unchanged | Must be rewired onto whatever new API we invent |
| Risk | Low | High — new FFI, codegen, every `_onEvent`, easy to stall the writer PRs |
| 9/10 on this contract | Yes | Not required; would be a 10-adjacent series |

**Accepted: skip.** Capture must not use `MuseEventDto`. Dart may keep using it. A later series can replace the view pipe if graphs still jank after the encode roundtrip is gone.

---

## High-level

### What’s wrong

The pieces (BLE, simulator, always-on DSP, feature registry, v5 byte layout, monitor graphs, feedback lanes) are individually fine. The **spine** that ties acquisition to durable capture is not:

```
Headset / OSC / sim
  → Rust forwarder (derive bands / pulse / features)
  → FRB MuseEventDto                          ← every EEG packet crosses the bridge
  → Dart broadcast (connection_provider)
       ├─ graphs (bounded rings — this part is OK)
       ├─ FeatureBus / session / streaming
       └─ SessionRecorder.writeEvent          ← UI isolate
            encodeSessionEvent (sync FFI back to Rust)
            buffer 64 KiB
            sessionFrameBytes (sync FFI, zstd level 3)
            writeAsBytesSync
  → end/Save: readTemps() whole .raw into RAM
       → containerEncodeV5 zstd::encode_all of that body
       → dashboard / updateNotes often v5ExtractRaw + encode again
```

Three separate failures, often conflated:

1. **Roundtrip.** Samples that Rust already has are serialized to Dart, then sent back to Rust to become on-disk records. Classic Muse EEG is 12 samples/packet × 4 ch @ 256 Hz → **~85 EEG events/s** of sync FFI on the isolate that paints graphs.
2. **Whole-file RAM.** `readTemps` + `container_encode_v5` + `v5ExtractRaw` on Save/notes scale with session length. 12 h keepable capture is hundreds of MB uncompressed; peak RSS of **1 GB+** is a live hypothesis. `tmp_` 30 min rotate hides this; `recording_` / `session_` do not.
3. **Process death (Android).** No `FOREGROUND_SERVICE`, no wake lock, no recording notification. A 12 h file that never OOMs still dies when the OEM kills the activity. Linux soak cannot prove this.

Live zstd is **already happening** (`session_frame_bytes` on every 64 KiB / 30 s flush). Dart comments calling temps “uncompressed” are wrong. Assemble then zstds that framed `.raw` **again** (`encode_all` of the whole body into the container raw section). That second wrap is useless (zstd-of-zstd ~1.0) and is the OOM. **Kill it** (D1). Inner frames stay.

Honest score today: **4 / 10** (see [Score](#score-today--910)). DSP/registry are closer to 7; capture RAM and the encode roundtrip pull the blend down. Goal: **9**, then 10.

### Destination (one paragraph)

Rust owns device I/O, always-on DSP, subscribed feature production, and **capture encode + scratch append + streaming assemble**. Dart owns UI, session/monitor orchestration (lease, start/stop, Record vs Start), `FeatureBus`, reward/guard lanes, network streaming, and bounded graph rings. After derivation, the forwarder **forks**: one path appends to disk in Rust; the other sends `MuseEventDto` to Dart for views. EEG never comes back from Dart to be encoded. A 12 h `.neurofeed` is written as a file stream. Opening it later to change notes or plot computed 1 Hz does not decompress the raw body. Agents follow this file; deviations need a written why.

### How close (1–10)

| Layer | Today | Notes |
|---|---|---|
| Ingest (BLE / OSC / sim → forwarder) | 7 | Works. Simulator already shares the forwarder. Crown OSC is a second ingest that already maps to `MuseEventDto`. |
| Always-on DSP + feature registry | 7 | Aligns with the feedback contract. Do not rebuild. |
| Capture encode/write | 3 | Dart `SessionRecorder`; sync FFI + `writeAsBytesSync` on the UI isolate; live zstd in `session_frame_bytes`. |
| Assemble / Save / notes | 2 | Whole `.raw` in RAM; `updateNotes` and dashboards call `v5ExtractRaw` then re-encode. |
| Dart view path | 6 | Graphs are budgeted (`SweepBuffer` 5 min, `BandCache` 1800). Fan-out is a broadcast of every event. Fine for views; fatal if it stays the capture path. |
| Proof | 2 | No max-rate 12 h-equivalent harness. |
| Android process survival | 1 | Not started. |
| Folder locality (AI) | 3 | Capture lives in `session_v5/` + `feedback/` + `monitor/recording/`. |

**Blend ~4.** A 9 is the destination in this file, soak-proven on Linux plus Android FGS specified and landed. A 10 is device-proven overnight + leftover folder moves. We do not need a new view API to call it 9.

### Three ways to get there

#### Way A — Rust capture fork (chosen)

Forwarder derives, then forks to (1) Rust writer (2) Dart `MuseEventDto` sink.

- **For:** Kills the encode roundtrip; 12 h RAM becomes a file problem; one writer for `tmp_` / `recording_` / `session_`; matches “Rust vs Dart by function.”
- **Against:** FFI surface for start/stop/assemble; Inspect flush index must be fed from Rust; computed 1 Hz and sidecar JSON still originate in Dart and must be **posted in** (not re-derived in Rust).
- **Use when:** the goal is overnight + maintainable spine. This series.

#### Way B — Dart isolate recorder (bridge only)

Keep `MuseEventDto` as the capture path; move `SessionRecorder` off the UI isolate.

- **For:** Smaller first diff; still helps jank.
- **Against:** Every EEG packet still crosses FRB into Dart, then into another isolate, then often back into Rust for encode/zstd. Does not fix 12 h assemble RAM unless you also rewrite assemble. Becomes the permanent architecture by inertia (Grokbot H5).
- **Use when:** never as the end state. Not even as a named milestone in this series — it costs a throwaway isolate and leaves the roundtrip.

#### Way C — Streaming assemble only, leave live encode in Dart

Fix `container_encode_v5` / Save / notes so they never hold whole-raw. Leave `writeEvent` as-is.

- **For:** Smallest patch for the OOM at stop; falsifies H2 quickly.
- **Against:** 12 h still hammers the UI isolate at ~85+ sync FFI/s; overnight Android still dies; ownership stays a kitchen sink.
- **Use when:** as **PR 3 only** (prove RAM), not as the architecture.

**Chosen:** Way A. PR 3 may land the assemble RAM fix *on the current writer* so soak can fail or pass before the writer moves.

---

## Two layers, one writer

There are **not** three capture formats. There is **one** `SessionRecorder` (today) / one Rust writer (target). The prefix is only the filename and the sidecar flavor.

| Prefix | Live temps (same writer) | Becomes `.neurofeed` v5? |
|---|---|---|
| `tmp_$ts` | `.raw` + `.computed` + `.json` snapshot | **Never.** 30 min rotate; launch glob-deletes. Inspect reads `.raw`. |
| `recording_$ts` | same temps | **Yes**, on Stop / crash recovery Save. |
| `session_$id` | `.raw` + `.computed` + `.metadata` JSONL | **Yes**, on End (scratch v5) then History Save. |

Live `.raw` **is** the v5 **raw body** (the `NFEDBIN` stream with inner zstd frames). It is **not** the 68-byte container. The container is a wrapper put on at assemble:

```
Today (double-compress raw):

  live .raw     = NFEDBIN header + [u32][zstd frame]…     ← first zstd
  live .computed = uncompressed JSONL
  live sidecar   = uncompressed JSON / JSONL

  assemble → [68-byte NFED5 header][WebP]
             [zstd(metadata JSON)]      ← first zstd of JSON, keep
             [zstd(computed JSONL)]     ← first zstd of JSONL, keep
             [zstd(entire .raw file)]   ← SECOND zstd of already-framed raw; KILL
```

So: same implementation for all three prefixes; `tmp_` simply never takes the assemble step. Sidecar mode (JSONL vs snapshot) is the only product difference, not a second raw codec.

**Target assemble:** copy the live `.raw` **byte-for-byte** into the container raw section. Do not `zstd::encode_all` it. Metadata and computed still get one zstd at assemble (they were uncompressed on disk). Flags byte stays `0`. Header size unchanged.

**No backwards compatibility.** Files written with an outer zstd on the raw section are unsupported. Do **not** leave a `zstd::decode_all` fallback, a flags bit, or a magic sniff “just in case.” That leftover is how the second wrap comes back. `v5ExtractRaw` returns the raw section as the raw body (or, on the 12 h path, is not used — copy the section as opaque bytes). Old History files may fail raw extract/export; computed 1 Hz charts can still work if that section stays independently zstd’d. Product call: accept that.

**Purge on the PR that lands this** (same PR as the encode change, so docs never describe the dead wrap):

| Place | What to delete / rewrite |
|---|---|
| `rust/src/api/session_format.rs` | `zstd::encode_all` of `raw_body` in `container_encode_v5`; `zstd::decode_all` in `v5_extract_raw`; comments `[raw (zstd)]` and “Compress metadata, computed, raw separately” |
| `README_feedback_format.md`, `README.md`, `.ai/architecture.md` | container diagram `raw (zstd)` → raw section = NFEDBIN body (inner frames only) |
| `lib/src/session_v5/scratch_writer.dart` | “uncompressed temp files” — `.raw` **is** inner-zstd framed; only computed/sidecar are uncompressed while live |
| Tests that round-trip through outer raw zstd | encode/extract the raw section as opaque framed body |
| Grokbot draft | archived at `.ai/archive/data-plane-contract.md`; not implementable |

Do not add a comment “legacy files were double-zstd’d.” Agents copy comments.

---

## Live compression (zstd, not zlib)

The v5 raw body is already:

```
[12-byte NFEDBIN header][ u32 LE length ][ zstd frame ]…
```

`SessionRecorder.flushRaw` calls `sessionFrameBytes`, which is `zstd::encode_all` of up to 64 KiB of records, level 3. Inspect (`FileBackedSource`), crash recovery, and `sessionParseBody` all read that shape. The v5 **container** then wraps that entire `.raw` in a **second** zstd stream (`container_encode_v5`). That is the second compression you asked to kill.

You thought (during v5) that compressing as you write keeps tmp-read and final-read the same. **That instinct is right for the inner frames.** The outer wrap of raw fights it: History then has to undo a second codec before it sees the same bytes Inspect already knew.

### If we keep live inner frames (recommended)

| | |
|---|---|
| **Pro** | One parse path for live Inspect, crash leftover `.raw`, and the published raw body. `RecordingIndex` already keys off flush boundaries. zstd-3 on 10–15 KB/s ingest is cheap on a Rust thread (the pain today is FFI + UI isolate, not the codec). Overnight scratch is smaller. A crash leaves compacted frames, not a giant raw dump. Matches the v5 design you already shipped. |
| **Con** | Capture thread must not stall BLE notify (buffer, flush on a dedicated writer task). A torn last frame on crash is already the unit of loss — keep it small (64 KiB). |

### If we append uncompressed records while live

| | |
|---|---|
| **Pro** | Matches the first “don’t compress while recording” wording. Naive append. Zero codec CPU on the hot path. |
| **Con** | Live scratch ≠ published raw body, **or** you re-frame the whole night at stop (CPU + a second streaming pass). Inspect and `sessionParseBody` today `zstd::decode_all` each frame and **skip** on failure — uncompressed fallback in `session_frame_bytes` is already a likely silent drop. Two formats is the complexity you were trying to avoid. Disk during 12 h is ~0.5 GB vs ~0.35–0.45 GB — not the constraint. |

### If we drop inner frames and only outer-zstd at stop

Live file is a bag of records; published file is one zstd blob. Inspect during Record needs a different reader than History. Rejected: two readers, same data.

### Decision (D1 — accepted)

1. **Keep live inner zstd frames** (today’s raw-body format, ~64 KiB flush, level 3).
2. **Produce them in Rust** on a capture/writer task, never via Dart `sessionFrameBytes`.
3. **Kill the outer zstd on the container raw section.** Assemble **copies** the framed `.raw`. No flags bit, no dual-read, no leftover `decode_all` on the section.
4. **Keep** one zstd of metadata JSON and computed JSONL at assemble (those were uncompressed on disk).
5. **Do not** `readAsBytes()` a keepable `.raw` into Dart. Assemble is file-to-file.
6. **Purge** every comment/doc/code path that taught the second wrap (list above). Same PR as the encode change.

Uncompressed-live is rejected. Streaming-outer-zstd-of-raw is rejected. Dual-read of old outer-zstd files is rejected.

---

## Relationship to other freezes

| Topic | Frozen elsewhere | This contract |
|---|---|---|
| Always-on vs subscribed `FeatureDto` | Feedback pipeline | Same split. Capture records always-on streams per `Settings.recordStreams`. `FeatureDto` stays off the raw body (encode already no-ops it). |
| `FeatureBus`, Reward/Guard, protocol JSON | Feedback pipeline | Unchanged. Spine does not own lane semantics. |
| Crown Start | Refused | Still refused. One capture writer ≠ Crown session unlock. |
| v5 68-byte header / tags 1–10 | `session_format.rs`, `README_feedback_format.md` | Header **size** and tags unchanged. Raw **section** is a copy of `.raw` (no outer zstd, no dual-read). New tags (Athena optics) stay a separate format PR. |
| Connect UX, `DeviceKind` Muse \| Neurosity | connect-simulator-ux | Unchanged. |
| Monitor graph chrome / Follow lead / no Spectrogram FFT dropdown | `monitor.md` | Unchanged. Graphs stay bounded consumers. |
| Exclusive prefixes `tmp_` / `recording_` / `session_` | product + crash recovery | Unchanged names. Writer owner moves to Rust. |

---

## Current path (code, not vibes)

| Piece | Where | What it actually does |
|---|---|---|
| Event sink | `rust/src/api/muse.rs` `subscribe_events` | One `StreamSink<MuseEventDto>`. Forwarder `sink.add`. Failure **clears the sink** (disconnect). |
| Dart fan-out | `connection_provider` broadcast | Monitor, feedback, streaming all listen. |
| Live encode | `scratch_writer.dart` `writeEvent` | `encodeSessionEvent` + 64 KiB / 30 s `sessionFrameBytes` (zstd) + `writeAsBytesSync`. |
| Computed 1 Hz | `ComputedSampler` (4-ch), `MonitorSampler` (N-ch) | Dart timers. Feedback frames include lane scalars. |
| Sidecar | JSONL `.metadata` (session) or atomic `.json` (monitor) | Dart. |
| Assemble | `assemble.dart` → `containerEncodeV5` | Whole temps in RAM. Returns `Uint8List`. |
| Save / notes | dashboards, `session_store_core.updateNotes` | `v5ExtractRaw` + `containerEncodeV5` again. |
| Inspect | `FileBackedSource` + `RecordingIndex` | Range-reads complete inner frames from live `.raw`. |
| Lease | `CaptureLease` | idle \| tmp \| recording \| feedback. At most one writer. |
| Android | `AndroidManifest.xml` | BLE + internet. **No** FGS, **no** `WAKE_LOCK`, **no** `POST_NOTIFICATIONS`. |
| Design load (order-of-magnitude) | Classic Muse, all streams | ~10–15 KB/s uncompressed records → **~0.4–0.6 GB / 12 h**. Inner zstd helps a bit; EEG f32 is not text. |

`tmp_` rotate (30 min) is a bounded connect-time buffer and is **never** assembled. Do not treat a 30 min tmp as proof of 12 h.

---

## Target data flow

```
Sources (peers at the DTO boundary, not a new type algebra)
  Muse BLE | Crown/Neurosity OSC | Simulator | future ingest
        │
        ▼
Rust forwarder (existing: muse.rs / neurosity_osc.rs / simulator.rs)
  derive always-on bands / movement / gestures / pulse / SpO2 / quality
  subscribed FeatureDto (set_enabled_features)
        │
        ├──────────────────────────────────────────────┐
        ▼                                              ▼
Rust capture (new)                               FRB MuseEventDto
  encode records (cheap, on forwarder)           (view pipe only)
  try_send bytes → dedicated writer thread       Dart:
  writer: 64 KiB zstd frame + append               FeatureBus, lanes
  (never write() on the forwarder task)            bounded graph rings
        │                                          OSC/LSL/BrainFlow
        │                                          orchestration
        ▼
scratch: prefix_id.{raw,computed,metadata|json}
        │
        │ stop / end
        ▼
Rust streaming assemble → prefix_id.neurofeed on disk
  zstd(metadata), zstd(computed), raw section = copy of .raw (no outer zstd)
  FFI returns a path, never the bytes
```

**Forbidden:** Dart calling `encodeSessionEvent` / `sessionFrameBytes` on the live path. Dart `readAsBytes` of a keepable `.raw`. `containerEncodeV5` / `v5ExtractRaw` of a whole keepable capture on the UI isolate.

**Allowed one-way posts (not EEG roundtrips):** Dart → Rust computed JSONL line; Dart → Rust sidecar JSON; Dart → Rust start/stop/assemble commands.

---

## Key Decisions

1. **Fork after derivation, before Dart.** Capture taps the same outgoing DTOs the sink would send. It does **not** wait for Dart. It does **not** re-ingest `MuseEventDto` from Flutter. Native `MuseEvent` still maps to DTO once; disk records are encoded in that same Rust step (or from the DTO **before** `sink.add`), never after a Dart hop.

2. **One Rust writer, three prefixes.** `tmp_` / `recording_` / `session_` share one writer type. Dart keeps `CaptureLease` and product rules (Record vs Start, tmp rotate 30 min, tmp never assembled, prefix-strict crash recovery). Rust also refuses a second `start` (mutex). `recordStreams` is an argument to start, applied in Rust. **I/O runs on a dedicated writer thread** — see [Threading](#threading).

3. **Live inner zstd frames; no outer zstd on raw.** See [Two layers](#two-layers-one-writer). Metadata + computed still zstd at assemble. Header stays 68 bytes, flags `0`. No dual-read. Purge the second wrap from code and docs in the same PR.

4. **Assemble writes a path.** New FFI does not return the container `Vec<u8>` for keepable captures. Tests may still use in-memory helpers on **small** fixtures.

5. **Computed + sidecar go through the same writer.** Dart produces 1 Hz frames (lanes + N-ch monitor) and metadata JSON. Rust appends them. Two Dart facades (`FeedbackRecorder` / `MonitorRecorder`) are fine; two disk owners are not.

6. **Save / notes / thumbnail patch never decode raw.** Copy thumbnail, computed, and raw **sections as opaque bytes** (or stream-copy). Only metadata JSON is decompressed, edited, recompressed. Charts stay on computed 1 Hz. Export CSV/EDF may stream-parse raw on a worker, never `v5ExtractRaw` of 12 h on the UI isolate.

7. **`MuseEventDto` remains the Dart view pipe** (D3). Streaming, graphs, FeatureBus, connection status stay on it. This series does not design a replacement. Capture must not depend on it.

8. **Dart rings stay bounded.** `SweepBuffer` 5 min, `BandCache` 1800 s, optical rings as today. No “keep every event in Dart for 12 h.” Inspect beyond RAM uses the live `.raw` (file-backed), which requires the writer to keep inner-frame layout and a flush index.

9. **Drop policy.** Disk full or write error: **stop capture, keep temps, surface an error** — do not clear the BLE sink (today `sink.add` err → disconnect, which would also kill the session). View-pipe overflow may drop **view** samples; capture must not share that fate. Count drops; soak fails on capture drops > 0.

10. **Soak harness is required** before claiming 12 h. See [Design load and soak](#design-load-and-soak). Agents must not wait wall-clock 12 h.

11. **Multi-source “equals” means one writer + one DSP + one view DTO**, not a new `normalize/` type. Simulator already shares the forwarder. Crown OSC already maps in. Future sources (Athena optics) enter via a **format PR** (new tag), not a spine type system. Do not add `rust/src/spine/normalize/` in this series.

12. **Android overnight is specified here and implemented as PR 7.** Linux volume proof does not wait on it. See [Android addendum](#android-overnight-addendum).

13. **Folder locality for AI token locality**, without scattering a dozen empty crates. See [Target tree](#target-tree). Moves that are behavior-preserving are last.

14. **Agents follow this file.** Intentional deviations: written why in the PR or `.ai` note **before** merge. Silence is not assent.

15. **Do not reopen** feedback Key Decisions, Crown Start, Connect UX, monitor graph freezes, or the v5 header **size** / tag set. The raw-section unwrap (D1) is in scope for PR 3.

---

## Capture API sketch (names frozen enough to implement)

FRB 2.11.1, same style as `session_format.rs`. Prefer **path-returning** async-looking Dart `Future`s (Rust `pub fn`, not `pub async fn` with no await — house style). Do not `#[frb(sync)]` anything that can block on 12 h I/O.

```rust
// rust/src/spine/capture.rs — sketch, names frozen, not compiled here

/// prefix: "tmp" | "recording" | "session"
pub fn capture_start(
    dir: String,
    prefix: String,
    id: String,
    record_streams: Vec<String>, // RecordingStream names; empty = all
) -> anyhow::Result<()>;

pub fn capture_stop() -> anyhow::Result<()>; // flush; temps stay

/// Dart posts one JSONL line (no trailing interpretation in Rust).
pub fn capture_append_computed_line(line: Vec<u8>) -> anyhow::Result<()>;

/// JSONL append (session) or atomic snapshot (monitor); mode from start/prefix.
pub fn capture_write_sidecar(json: Vec<u8>) -> anyhow::Result<()>;

/// Stream-assemble into `{dir}/{prefix}_{id}.neurofeed`. Deletes temps on success.
/// Returns the destination path. Never returns file bytes.
pub fn capture_assemble_v5(
    metadata_json: Vec<u8>,
    thumbnail: Vec<u8>, // empty → placeholder WebP on the Rust side
) -> anyhow::Result<String>;

pub fn capture_discard() -> anyhow::Result<()>; // delete temps

/// Flush-boundary index for Inspect: (elapsed_s, exclusive_end_offset)
pub fn capture_flush_index() -> Vec<(f64, u64)>;
```

Live EEG/PPG/IMU/bands are **not** on this FFI. The forwarder calls into the writer in-process.

`encode_session_event` / `session_frame_bytes` remain for tests and for **small** fixtures. Production live path must not go Dart → those two.

Inspect: Dart `FileBackedSource` keeps reading the `.raw` path. Index comes from `capture_flush_index` (poll on Inspect) or a tiny debug stream — implementer’s choice, same entries as today’s `RecordingIndex`.

Crash recovery stays Dart and prefix-strict. It may call `capture_assemble_v5` on leftover temps (Rust must accept “no live session, temps on disk”).

---

## Threading

Rust is **already** several threads. Do not treat “move capture to Rust” as “do the write on whatever task happens to have the sample.”

| Who | Today | Capture |
|---|---|---|
| BLE / JNI notify | btleplug threads (Android: JNI attach) | **Never** write here |
| Converter task | `tokio::spawn` maps `MuseEvent` → DTO, `mpsc` cap **256** | unchanged |
| Forwarder task | **one** long-lived `tokio::spawn`: recv, FFT (`spawn_blocking` then **await**), gestures, `sink.add` to Dart | encode record bytes (tiny) + **`try_send`** to the writer. **No `write` / zstd / fsync** |
| Tokio blocking pool | FFT, AI inference | may run assemble at stop; not the live append loop |
| Dart UI isolate | `writeEvent` + sync FFI today | **Never** live encode |
| **Capture writer** | does not exist | **new dedicated `std::thread`** (or one long-lived `spawn_blocking` worker). Loop: recv bytes → 64 KiB buffer → inner zstd frame → `write`. Periodic `flush` (~30 s). Join on stop/assemble |

**Why a separate writer thread (this is the good choice):**

- Phone flash / desktop AV can stall a `write` for tens to hundreds of ms. The forwarder already waits on FFT `spawn_blocking` and on `sink.add`. Putting disk on that task fills the 256-event BLE channel and looks like packet loss.
- zstd-3 of 64 KiB is modest CPU; the syscall and dirty-page writeback are the jitter. Those belong on a thread whose only job is the file.
- A tokio worker that calls blocking `std::fs` for 12 h would pin a runtime thread. Tokio `fs` is `spawn_blocking` underneath anyway. A dedicated OS thread is the honest model.
- Unbounded channels would hide a wedged disk by growing RAM (defeats the 12 h RSS rule).

**Channel (bounded):** already-encoded record bytes, **not** DTOs (DTOs keep `Vec<f64>` samples). Capacity **~1–4 MiB** pending (covers a ~1 s flash stall at ~15 KB/s with headroom). `try_send` from the forwarder: if full, **do not block BLE/DSP**. Apply KD drop policy (stop capture, keep temps, error, increment counter). Soak fails if that counter is > 0 under the design load.

**Encode vs compress:** `encode_session_event` on the forwarder (microseconds). Inner zstd + `write` on the writer thread. Computed JSONL / sidecar posts from Dart enqueue on the same channel (or a second small queue on that thread) so there is still one file owner.

**Do not:** a second tokio runtime; write from the JNI thread; `spawn` a new thread per flush; `fsync` every frame (30 s / stop is enough).

---

## Subscribe / Dart views

Flexible on purpose:

| Consumer | Shape | Budget |
|---|---|---|
| Monitor graphs | listen + bounded rings | 5 min EEG RAM, 30 min bands, vsync-coalesced notify (already) |
| FeatureBus | broadcast per id, `sync: true` | latest-sample map; no 12 h log |
| Feedback orchestrator | `_onEvent` | lanes + 1 Hz sampler; no raw ring |
| Streaming | mixer | current behavior; not a capture owner |

Do not add an unbounded `List<MuseEventDto>` “for debugging” on the live path.

Smooth animation stays a **graph** problem (already mostly done: coalesced notify, PCHIP, Follow lead). Spine must not re-open monitor draw-path freezes. If soak + UI jank remains after the encode roundtrip is gone, that is a monitor PR, not a reason to put capture back in Dart.

---

## Assemble, Save, notes (RAM rules)

Invariant: **extra RSS for assemble / Save / notes / thumbnail patch does not grow with session length.** Budget: a few streaming buffers, cap **64 MB** extra vs idle for those operations on a 12 h file. (Idle app + graphs have their own baseline.)

| Operation | Today | Target |
|---|---|---|
| Stop Record / End session | `readTemps` + `containerEncodeV5` → `Uint8List` | `capture_assemble_v5` file-to-file |
| History Save of scratch v5 | often re-extract raw | `rename` / copy file + sqlite; or metadata patch |
| `updateNotes` | `v5ExtractRaw` + `containerEncodeV5` | rewrite metadata section only |
| Dashboard charts | computed 1 Hz | unchanged |
| CSV / EDF export | may parse raw | stream-parse on a worker; not UI isolate |

`container_encode_v5` as a “return whole file” helper may remain `#[cfg(test)]` or for fixtures **under a documented max size** (e.g. 2 min). Production keepable captures must not call it.

Placeholder WebP at assemble stays. Real thumbnail encode is still a later product beat; when it lands it must not pull raw EEG into RAM.

---

## Design load and soak

**Design load (keepable `recording_` / `session_`):**

- Device: Classic Muse rates, all `RecordingStream`s enabled (worst case).
- Duration-equivalent: **12 h** of those rates.
- Volume: ~0.4–0.6 GB uncompressed records (order-of-magnitude; harness prints the actual).
- Crown 8-ch is **not** the design load (Start refused; OSC not overnight). Do not block spine on it.
- `tmp_` is 30 min and out of scope for the 12 h RAM proof.

**Harness** (`rust/src/spine/soak/` or `cargo test --lib` + a `ignore`d/slow binary):

- Fill or replay at **max rate** (>> real time). No wall-clock 12 h in CI.
- Assert: capture drops = 0; write errors = 0; assemble succeeds; extra RSS during assemble **does not scale** with filled volume (spot-check 1 min vs 12 h-equivalent if the platform exposes RSS; otherwise assert no whole-file `Vec` in the assemble path via code review + a test that a fake 12 h-sized file assembles without `read_to_end` of the raw).
- A Dart/Linux agent path may also smash `simulate` + Record, but the **canonical** proof is the Rust filler so agents do not need a running UI.
- Document the command in [../test-matrix.md](../test-matrix.md) when the harness lands.

**Two acceptance bars** (do not mix):

| Bar | Proves | Does not prove |
|---|---|---|
| **Volume (Linux soak)** | append, inner frames, streaming assemble, notes patch, no O(n) RAM | phone process survival, BLE, OEM killers |
| **Process (Android FGS)** | recording/session survives screen-off + app background for hours | 12 h-equivalent RAM (use soak) |

9/10 requires both bars **specified** and volume **proven**; Android FGS **landed** (PR 7) even if a literal 12 h phone night is a manual QA box.

---

## Target tree

Doc-only until an explicit move PR. Do not create empty stub crates in the contract PR.

```
.ai/spine/
  data-plane-contract_grok-build.md   ← this file (governing)
  handoff-spine.md                    ← coordinator PRs 1–7

.ai/archive/
  data-plane-contract.md              ← Grokbot draft; not implementable

rust/src/spine/                       ← NEW: capture + soak only
  mod.rs
  capture.rs                          ← writer, assemble, sidecar, index
  soak.rs                             ← max-rate filler (test/bin)

rust/src/api/                         ← FRB re-exports; muse.rs forwarder calls spine
  session_format.rs                   ← still the byte-layout authority

lib/src/spine/                        ← NEW: thin Dart adapters
  capture_client.dart                 ← start/stop/assemble/sidecar FFI
  # FeedbackRecorder / MonitorRecorder become facades over this

lib/src/session_v5/                   ← interim FFI helpers / ComputedFrame
lib/src/monitor/recording/            ← lease, metadata, crash recovery, Inspect
lib/src/feedback/*recorder*           ← facade + session crash recovery
```

**Do not move in this series:** `muse.rs` DSP, `features.rs`, graph panes, audio, protocol builder.

AI locality rule: new capture/assemble/soak code lands under `spine/`. Do not add a third writer under `monitor/` or `feedback/`.

---

## Android overnight addendum

Today the app is an Activity with BLE permissions. Screen-off + background **will** kill recording on modern Android. A Dart isolate does not fix that. A Rust writer does not fix that.

### Required for phone overnight (PR 7)

1. **Foreground service** in the same process as Flutter/Rust (BLE + writer must keep the existing `GLOBAL_JVM` / adapter). Type: `connectedDevice` (BLE headset). Manifest: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS` (API 33+).
2. **Persistent notification** while `CaptureKind` is `recording` or `feedback` (not for `tmp_` connect-time). Copy: recording vs session; elapsed; tap opens the app. A Stop action may request the app to stop; it must not tear down BLE from a dead isolate.
3. **Start FGS when** keepable capture starts; **stop FGS when** that capture ends (including crash-recovery UI still holding an unsaved session — keep FGS until Save/Discard if the process is alive).
4. **Do not keep the screen on** as the overnight mechanism. Overnight sleep recording wants the panel off. Optional “keep screen awake” is a later session-UI toggle, not a capture requirement.
5. **No `RECEIVE_BOOT_COMPLETED`.** We do not auto-resume a session after reboot; crash recovery on next launch is enough.
6. **Battery exemption** is OEM-optional, not required in PR 7. May be a Settings deep-link later.
7. **Audio:** existing SoLoud session audio already argues for a service if we want background music; PR 7 may share one FGS for “session or recording active.” Do not start a second competing service. Do not deinit SoLoud from a controller (audio-engine freeze).

### Not in PR 7

- iOS background modes.
- Writing scratch to SAF while live (live capture stays `scratchDirectory()`).
- Changing BLE reconnect policy.

### Linux / Windows

No FGS. Overnight = the process left running. Soak covers volume. Desktop `AppLifecycleListener` already assembles recording on exit — keep that.

---

## PR plan

Each step is independently mergeable. Behavior-preserving on Muse for connect, Record, Start Session, History Save/Discard, Inspect, crash recovery. Crown Start stays refused. State `bridge` vs `end-state` in the PR title: PRs 2–6 are end-state capture; view pipe stays `MuseEventDto`.

### PR 1 — This contract

- **Files:** this file; optional pointer from [../active-task.md](../active-task.md) / [../README.md](../README.md) once accepted.
- **Deps:** none.
- **Not:** code.

### PR 2 — Soak harness on **current** code

- **Goal:** measure, do not “fix” yet. Filler at max rate; print GB, RSS if available, drop counters.
- **Files:** `rust/src/spine/soak.rs` (or tests next to `session_format.rs` if `spine/` is too early — move in PR 4).
- **Deps:** PR 1.
- **Pass:** harness runs; documents today’s O(n) assemble (expected fail on RAM invariant). This is the baseline.

### PR 3 — Streaming assemble + kill outer raw zstd + purge + notes/Save without whole-raw RAM

- **Still Dart writer OK.** Copy `.raw` into the container raw section. `v5_extract_raw` does **not** zstd-decode the section. `updateNotes` / dashboard Save copy the raw section as opaque bytes. File-to-file assemble (no `Vec` of 12 h).
- **Purge** the table in [Two layers](#two-layers-one-writer) in the **same** PR (encode, comments, README, architecture diagram, tests). Do not leave a commented-out `encode_all(raw)` or a “legacy” branch.
- **Deps:** PR 2 (so we can re-run soak).
- **Pass:** soak 12 h-equivalent assemble extra RSS O(1); `cargo test --lib session_format`; grep of `session_format.rs` / format README has no “raw (zstd)” container line; existing assemble tests on **small** fixtures green.
- **Not:** moving encode off Dart yet; not supporting old double-wrapped files.

### PR 4 — Rust writer behind the three prefixes

- Forwarder fork; `capture_start` / stop / sidecar / computed line; Dart facades.
- Inspect index; crash recovery calls assemble-on-temps.
- **Deps:** PR 3.
- **Pass:** `flutter test` recording/session assemble + file-backed source; Linux agent Record/Stop still works; soak drops = 0.
- **Not:** folder moves of graphs; not Android FGS.

### PR 5 — Delete live Dart encode path

- Remove `writeEvent` → `encodeSessionEvent` from production. Keep FFI helpers for tests/export as needed.
- **Deps:** PR 4.
- **Pass:** no production caller of live `sessionFrameBytes` from Dart; analyze clean.

### PR 6 — Folder locality (behavior-preserving)

- Land remaining adapters under `lib/src/spine/` and `rust/src/spine/`. Re-exports so old import paths don’t break, or update imports in one PR.
- **Deps:** PR 5.

### PR 7 — Android FGS addendum

- Manifest + service + notification + start/stop with keepable capture.
- **Deps:** PR 4 (writer in-process).
- **Pass:** documented manual: start recording, background, screen off, 10+ min still appending (full 12 h is QA, not CI).
- **Not:** keep-screen-on; battery exemption UI unless trivial.

Rollback: revert the PR. Inner frame layout does not change. **No** promise that History files from before this PR still extract raw.

Later series (not this contract’s 9/10): optional view-API (D3 if declined); Athena optics tag; Crown run; battery exemption Settings.

Subagent workflow (when implementing): one subagent per PR, this file + `AGENTS.md` as required reading. Do not spawn a swarm to rewrite the contract.

---

## Agent rules

- Read **this** file before data-plane / recording / scratch / assemble / overnight work. Do not implement from archived Grokbot `../archive/data-plane-contract.md`.
- Follow Key Decisions. Deviate only with a written why first.
- Do not reopen the feedback pipeline, Crown Start, Connect UX, monitor graph freezes, or v5 header size / tags 1–10. Raw-section unwrap is KD 3 / PR 3, not a sneak format series.
- Do not add live Dart encode or whole-raw `readAsBytes` / `encode_all` / `v5ExtractRaw` on keepable captures.
- Do not add `rust/src/spine/normalize/`.
- Prove volume with the soak harness; do not claim 12 h from a 30 s Record.
- Do not claim Android overnight from Linux soak.
- Packages: `neurofeed`, `rust_lib_neurofeed` only.

---

## Score (today → 9/10)

**Today ~4/10.**

**9 requires:**

1. Key Decisions accepted (D1–D3 resolved).
2. Capture encode/append in Rust for all three prefixes; Dart does not encode EEG.
3. Streaming assemble + notes/Save RAM invariant proven on 12 h-equivalent soak (drops = 0).
4. Inner zstd frames unchanged; container raw section is a copy of `.raw`; second wrap **deleted** from code and docs (no dual-read).
5. Soak harness in-tree and listed in the test matrix.
6. `lib/src/spine/` + `rust/src/spine/` started (PR 4–6).
7. Android FGS landed (PR 7) — process bar specified **and** implemented.

**10 (later):** real overnight on a phone; leftover import paths gone; optional view-API series.

---

## Risks

| ID | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Assemble/Save/notes still decode whole raw | **High** | PR 3 first; soak; ban `v5ExtractRaw` on keepable files in production |
| R2 | Writer on the BLE/forwarder task stalls notifies | **High** | Dedicated writer thread + bounded `try_send`; soak drop counters |
| R3 | Inspect breaks when index/flush moves to Rust | **High** | Same inner-frame layout; `capture_flush_index`; keep `file_backed_source_test` |
| R4 | Crash recovery / prefix lease regress | **High** | Existing recovery tests; Rust mutex + Dart lease |
| R5 | Android FGS typed wrong (`dataSync` vs `connectedDevice`) or killed anyway | **Med** | `connectedDevice`; manual matrix; OEM exemption later |
| R6 | Computed 1 Hz / sidecar “temporarily” stay Dart files | **Med** | KD 5; PR 4 must take both |
| R7 | Scope creep: normalize layer, new view API, Crown run | **Med** | KD 11, D3, non-goals |
| R8 | Inner vs outer zstd confusion in a PR | **Med** | This section; tests that live `.raw` still `session_parse_body`s |

---

## Observability

Keep `[muse]`, `[crown_osc]`, `[session]`, `[monitor]`.

Add `[spine]`:

- start/stop + prefix + id
- append bytes, flush count, capture drop/error counters
- assemble: duration, output size, **not** whole-file in RAM
- soak: rate, duration-equivalent, GB, pass/fail

Debug-only. No crashlytics.

---

## Alternatives considered (summary)

| Alt | Verdict |
|---|---|
| Dart `SessionRecorder` as permanent owner | Rejected (Way B/C as end state) |
| Uncompressed live scratch | Rejected unless D1 overridden; splits read paths |
| Compress every N minutes as a third mode | Rejected; inner 64 KiB frames already batch |
| Side-stream raw bytes to Dart, bypass derivation | Rejected; duplicates DSP; breaks multi-source |
| New normalize type + retire `MuseEventDto` this series | Rejected; not needed for 12 h; different contract |
| Keep-screen-on as overnight | Rejected; FGS + screen off |
| Outer zstd of already-framed `.raw` (today, streamed, or “legacy dual-read”) | **Rejected.** Second compression. Copy `.raw`. Delete the wrap. No compatibility decoder. |
| Uncompressed live scratch | Rejected; splits Inspect vs History |

Chosen: **Way A** + live inner zstd in Rust + **no outer raw zstd** (no dual-read) + FGS addendum. D3 default skip.

---

PR / implementer notes live on `refactor/spine`. **Contract first, then PRs 2–7.** D1–D3 accepted. No remaining pings unless you reopen something.
