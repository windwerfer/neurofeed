Archived 2026-09-24 — superseded by `.ai/contracts/fileformat_v6.md` (NFED6 / formatVersion 6). Historical v5 (NFED5) contract retained for reference only; do not treat as current law.

# Session format contract (`.neurofeed` v5)

| Field | Value |
|---|---|
| Status | **Implemented.** Header, tags 1–10, computed field set frozen. |
| Scope | On-disk `.neurofeed` bytes: magics, 68-byte header, sections, raw tags, computed JSONL, what metadata JSON *is today*. |
| Not this | Capture writer / assemble RAM / FGS ([data-plane-contract.md](data-plane-contract.md)); lane meanings that *fill* computed fields ([pipeline-contract.md](pipeline-contract.md)); SQLite history list ([../../README_history_cache.md](../../README_history_cache.md)); Athena tag 11 ([../TODO/athena-optics-contract.md](../TODO/athena-optics-contract.md)); Crown *session run*. |
| Authority | `rust/src/api/session_format.rs`. Dart is FFI only. |
| Human spec | [../../README_feedback_format.md](../../README_feedback_format.md) — byte tables and JSON examples. |

**If this contract changes, update `README_feedback_format.md` in the same change.** That file is the human-readable layout. This file is the freeze.

There is **no** other container version in this app. Do not add a compatibility reader, a dual-read path, or comments that teach an older `.neurofeed` layout.

---

## Ownership split

| Layer | Owns |
|---|---|
| Byte layout + FFI | Rust `session_format.rs` |
| Who writes / assemble / prefixes | Data-plane |
| What `feedback.*` / `guardrail.*` mean | Pipeline |
| History list (sqlite `kind`) | `README_history_cache.md` |

---

## Container (frozen)

```
[68-byte NFED5 header][WebP][zstd metadata JSON][zstd computed JSONL][raw body]
```

| Fact | Law |
|---|---|
| Magic | `NFED5\0` (6 bytes). Version byte **5**. |
| Header size | **68 bytes.** Do not grow it. |
| Flags | Byte `[7]` stays **0**. Do not use it for dual-read, unwrap, or a new section. |
| Offsets | u64 LE pairs: thumbnail, metadata, computed, raw. `raw_length` is **not** stored (`file_size - raw_offset`). |
| CRC | crc32 of header `[0..63]` in `[64..67]`. |
| Thumbnail | WebP. Placeholder at assemble (640×360) is fine. Real encode later must not pull raw EEG into RAM. |
| Metadata / computed | One zstd each at assemble (they are uncompressed JSON/JSONL on live scratch). |
| Raw section | **Copy** of live `.raw`. No outer zstd. No dual-read of files that had a second wrap. |

`v5ParseHead` returns opaque `metadataJson` bytes. It does **not** parse `kind`.

Charts, PDF, PNG plot **computed 1 Hz** (`v5ExtractComputed` → `prepareChartDataFromComputed`). Do not resurrect `metadata.summary` / `SessionOverview` / a 400-bucket series. The history-list preview is the WebP.

Save / notes / thumbnail patch copy raw (and computed, thumbnail) **sections as opaque bytes**. Only metadata JSON is decompressed. CSV/EDF may stream-parse raw on a worker, never `v5ExtractRaw` of a keepable file on the UI isolate.

---

## Two files, one container

| Kind | Published name | Scratch temps |
|---|---|---|
| Feedback | `session_$id.neurofeed` | `session_$id.{raw,computed,metadata}` |
| Recording | `recording_$ts.neurofeed` | `recording_$ts.{raw,computed,json}` |

`tmp_$ts.*` is connect-time only. **Never** assembled or published.

Sqlite `kind` (`feedback` \| `recording`) discriminates the History list. Live capture always goes to `scratchDirectory()` (SAF is history-only).

---

## Raw body (frozen)

Live `.raw` **is** the container raw section:

```
[8-byte NFEDBIN sentinel, u64 LE][u32 LE version=5][ [u32 length][zstd frame] … ]
```

Inner frames: zstd level **3**, ~64 KiB / 30 s. Codec is zstd, not zlib.

Each record is `[u8 tag][fields…]` with **no length prefix**. Size is implied by the tag. Payloads are f32; timestamps are f64; electrode is i16; little-endian.

| Tag | Stream | Payload |
|---|---|---|
| 1 | EEG | `[ts f64][electrode i16][n u16][n × f32]` |
| 2 | Telemetry | `[ts f64][battery f32][fuel f32][temp u16]` |
| 3 | Accelerometer | `[ts f64][seq u16][n u16][n × (x,y,z f32)]` |
| 4 | Gyroscope | same as 3 |
| 5 | PPG | `[ts f64][channel i16][n u16][n × f32]` |
| 6 | Bands | `[ts f64][electrode i16][δ θ α β γ f32]` |
| 7 | Pulse | `[ts f64][bpm f32][conf f32]` |
| 8 | Movement | `[ts f64][score f32]` |
| 9 | PeakAlpha | `[ts f64][freq f32][power f32]` |
| 10 | SpO₂ | `[ts f64][spo2 f32][conf f32]` |

Tags **1–10** are frozen. A new stream (Athena optics) is a **format PR** (next tag **11**), not a spine type system.

**Unknown tag: abort.** `parse_records` hits `_` and **stops** the body. That is the only safe parse: without a length prefix, skip desyncs the rest of the frame.

Product wish (leftover): old apps should still read EEG from files that contain a newer tag. That needs a **per-record** length prefix (a few bytes **per record**, not per file — Classic Muse EEG is ~85 records/s). Until that format PR, abort stays. Do not fake skip.

`encode_session_event` **no-ops** `Feature`, `Reve`, and Gestures. Gestures are metadata-only (JSON `at` seconds from start). They are not a `RecordingStream`.

**Timestamps:** raw `ts` is a **ms epoch**. CSV divides by 1000 before flooring. Computed `t` and gesture `at` are **seconds from this capture’s start**.

---

## Computed 1 Hz (field set frozen)

JSONL, one `ComputedFrame` per line. New columns need an explicit format PR **and** FRB. Do not add feature-id fields or music cutoff on the frame. Which reward/guard feature ran lives in metadata (`protocol` / `protocolJson` / `sessionSettings.guardFeature`).

| Field | Law |
|---|---|
| `t` | Seconds from capture start |
| `bands` | `N × 5` **absolute** powers `[δ, θ, α, β, γ]`. `N` = recorded channel count. Muse feedback sampler is **4**. Monitor sampler is `channelCount`. Crown-run changing `N` is that later series. |
| `lineNoise` / `signalQuality` | Same `N` |
| `pulse` / `movement` / `peakAlpha` / `spo2` | Optional. Charts may fall back to the raw body when omitted. |
| `guardrail` | `{ sleepDir, clarity, warning, delta }`. `sleepDir` = AI `sleep_dir` or **0** for band-math. `delta` = frontal **absolute** µV²/Hz. Do not stuff delta into `sleepDir`. |
| `feedback` | `{ ratio, threshold, inTarget, pct }`. `ratio` = reward **native** value. |
| `gestures` | String ids for that second |

Recordings write **zeroed** `guardrail` / `feedback` structs (keys present).

Meanings of the lane fields: [pipeline-contract.md](pipeline-contract.md) KD 18.

---

## Metadata JSON — two dialects (mistake)

Feedback and recording files share the container and **do not** share a metadata schema. That split was not designed; recording landed without a format contract.

**Do not silently unify.** Documented current shapes stay what readers must accept. Revisit: [../TODO/session_vs_recording_metadata.md](../TODO/session_vs_recording_metadata.md).

### Feedback (`SessionMetadata`) — flat

Written by `lib/src/feedback/session_metadata.dart`. Device fields are `deviceName` / `deviceModel` / `deviceId`. Does **not** write `formatVersion`, `appVersion`, `kind`, or `streams`. Sqlite stores `kind = 'feedback'` on publish.

Gesture key is **`at`** (seconds from start, int), not `offsetSeconds`. `sessionSettings` holds `guardFeature` and optional `modelSnapshot` **inside** settings. Snapshot `protocolJson` for detail/export/replay. `guardrailEngine` keeps writing `GuardrailMode.name`.

### Recording (`RecordingMetadata`) — nested

Written by `lib/src/monitor/recording/recording_metadata.dart`. Nested `device`, `formatVersion: 5`, `kind: "recording"`, and a complete ten-key `streams` object. Disabled streams stay `{ "enabled": false, "rateHz": 0 }` — never omitted.

Omit on recordings: `protocol`, `calibration`, `music`, `feedbackSound`, `drowsiness`, `modelSnapshot`, `sessionSettings`.

Examples: [../../README_feedback_format.md](../../README_feedback_format.md).

---

## Key Decisions

1. **Rust owns the layout.** Dart does not invent bytes. Format edits land in `session_format.rs`; `cargo test --lib session_format` stays green. Commit both FRB sides if the FFI surface changes.
2. **68-byte header, flags 0, tags 1–10 frozen.** New tags are a format PR. Do not grow the header.
3. **One container type, two published names.** `tmp_` never assembled.
4. **Live inner zstd; raw section is a copy of `.raw`.** No outer zstd, no dual-read, no flags bit. (Data-plane D1.)
5. **Unknown raw tag aborts.** Skip needs a per-record length prefix (later PR). Flags stay 0.
6. **Computed 1 Hz field set frozen.** Charts use that section only. No `SessionOverview`.
7. **`FeatureDto` is not a raw tag.** Gestures are metadata-only.
8. **Two metadata dialects are current fact, not the goal.** Do not unify in passing. See the TODO.
9. **No other container version.** Do not restore an older reader.
10. **Agents follow this file.** Same-change update of `README_feedback_format.md`. Deviations: written why first.

---

## Leftovers (not a reopen)

- Unify or formally dual-read session vs recording metadata JSON — [../TODO/session_vs_recording_metadata.md](../TODO/session_vs_recording_metadata.md).
- Per-record length prefix so unknown tags can be skipped.
- Real thumbnail encode (placeholder WebP is OK).
- History recording Inspect still `v5ExtractRaw`s a published file (data-plane 10 leftover).
- Athena tag 11 (queued). Old parsers will **stop** at that tag until skip exists.
- Crown-run `ComputedFrame.bands` length / name-based chart electrodes.

---

## Agent rules

- Read **this** file before changing `.neurofeed` layout, tags, computed JSON, or metadata writers.
- Update [../../README_feedback_format.md](../../README_feedback_format.md) in the same change.
- Do not reopen pipeline Key Decisions to “fix” computed columns.
- Do not reopen data-plane D1 to restore outer zstd.
- Do not add `rust/src/spine/normalize/`.
