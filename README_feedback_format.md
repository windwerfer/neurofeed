# Muse ML — `.muse.feedback` v5

**Format version:** 5
**Container:** `[68-byte header][WebP thumbnail][metadata (zstd)][computed 1 Hz (zstd)][raw (zstd)]`

Rust owns the byte layout (`rust/src/api/session_format.rs`). Dart only calls FFI.

Two filenames, same container type, same history folder:

| Kind | Published name | Scratch temps | Metadata JSON |
|------|----------------|---------------|---------------|
| Feedback session | `session_$id.muse.feedback` | `session_$id.{raw,computed,metadata}` | Flat `SessionMetadata` (`lib/src/feedback/session_metadata.dart`) |
| Recording | `recording_$ts.muse.feedback` | `recording_$ts.{raw,computed,json}` | Nested `RecordingMetadata` (`lib/src/monitor/recording/recording_metadata.dart`) |

`tmp_$ts.*` is a rolling connect-time capture. It is **never** assembled or published.

History list is sqlite `kind` (`feedback` \| `recording`), not a directory scan. See [README_history_cache.md](README_history_cache.md).

**Timestamps:** computed `t` and gesture offsets are seconds from **this capture’s start**. Raw EEG/band timestamps in the `.muse` body are **ms epochs**.

---

## v5 container layout

```
Offset 0:        68-byte fixed header
  [0..5]     = b"MUSE5\0"
  [6]        = 5 (version)
  [7]        = flags (reserved)
  [8..15]    = thumbnail_offset (u64 LE)
  [16..23]   = thumbnail_length (u64 LE)
  [24..31]   = metadata_offset (u64 LE)
  [32..39]   = metadata_length (u64 LE)
  [40..47]   = computed_offset (u64 LE)
  [48..55]   = computed_length (u64 LE)
  [56..63]   = raw_offset (u64 LE)
  [64..67]   = crc32(header[0..63])

Offset thumbnail_offset: WebP thumbnail (placeholder at assemble; 640×360)
Offset metadata_offset:  zstd-compressed metadata JSON
Offset computed_offset:  zstd JSON Lines (one ComputedFrame per line)
Offset raw_offset:       zstd-compressed raw .muse v4 body
```

`v5ParseHead` returns opaque `metadataJson` bytes. It does **not** parse `kind`.

There is no `metadata.summary` / `SessionOverview` and no 400-bucket series.
Dashboard, history, PDF, and PNG charts plot computed 1 Hz:
`v5ExtractComputed` → `prepareChartDataFromComputed`. The history-list
preview is the WebP thumbnail.

---

## Feedback metadata (`SessionMetadata`)

This is what `SessionMetadata.toJson()` actually writes. It is **flat**
(device fields are `deviceName` / `deviceModel` / `deviceId`, not a nested
`device` object). It does **not** write `formatVersion`, `appVersion`,
`kind`, or `streams`. Sqlite stores `kind = 'feedback'` on publish.

```json
{
  "protocol": "drowsiness",
  "durationMinutes": 15,
  "elapsedSeconds": 900,
  "durationS": 900,
  "sound": "Ambient Drone",
  "savedAt": "2026-08-22T14:30:00.000Z",
  "startedAt": "2026-08-22T14:15:00.000Z",
  "notes": "",
  "deviceName": "Muse 0ABC",
  "deviceModel": "Classic",
  "deviceId": "AA:BB:CC:DD:EE:FF",
  "recordedChannels": ["TP9", "AF7", "AF8", "TP10"],
  "feedbackSound": "bowlChimes",
  "metadataDescription": "…",
  "protocolVersion": "1",
  "calibrationProfile": "eyes-closed-01",
  "calibration": { "version": 2, "kind": "staged", "calibrationId": "eyes-closed-01" },
  "sessionSettings": { "dynamicAdapt": true, "guardFeature": "ai.drowsiness" },
  "gestures": [{ "type": "doubleBlink", "at": 45 }],
  "drowsiness": { "scoreTotalPct": 12.5, "meanSleepDir": 0.34 },
  "music": { "tracks": [{ "at": 150.0, "name": "track01.opus" }] }
}
```

Gesture JSON key is **`at`** (seconds from recording start, stored as int),
not `offsetSeconds`. Music track/cutoff samples also use `at`.

`sessionSettings` includes `guardFeature` (`band.delta` / `ai.drowsiness` /
`none`) and optional `modelSnapshot` **inside** settings, not at the top
level.

Calibration `kind` is `"single"` or `"staged"`. Phases and recalibrations
are present when that calibration ran.

---

## Recording metadata (`RecordingMetadata`)

Written for `recording_*` (and the tmp sidecar snapshot). Nested `device`
and a complete ten-key `streams` object. Disabled streams stay in the map
as `{ "enabled": false, "rateHz": 0 }` — never omitted (`StreamsConfig.fromJson`
requires all ten keys).

```json
{
  "formatVersion": 5,
  "appVersion": "dev",
  "kind": "recording",
  "savedAt": "2026-09-07T12:00:00.000Z",
  "startedAt": "2026-09-07T11:50:00.000Z",
  "elapsedSeconds": 600,
  "durationS": 600,
  "notes": "",
  "device": {
    "name": "Muse 2 (Simulated)",
    "id": "sim:muse-2",
    "firmware": "Classic",
    "model": "Classic",
    "sensors": ["EEG", "PPG", "IMU"],
    "channelCount": 4,
    "channelLabels": ["TP9", "AF7", "AF8", "TP10"]
  },
  "streams": {
    "eeg": { "enabled": true, "rateHz": 256 },
    "bands": { "enabled": true, "rateHz": 1 },
    "pulse": { "enabled": true, "rateHz": 1 },
    "spo2": { "enabled": true, "rateHz": 1 },
    "movement": { "enabled": true, "rateHz": 1 },
    "peakAlpha": { "enabled": true, "rateHz": 1 },
    "imu": { "enabled": true, "rateHz": 52 },
    "ppg": { "enabled": true, "rateHz": 64 },
    "telemetry": { "enabled": true, "rateHz": 1 },
    "gestures": { "enabled": false, "rateHz": 0 }
  }
}
```

Omit on recordings: `protocol`, `calibration`, `music`, `feedbackSound`,
`drowsiness`, `modelSnapshot`, `sessionSettings`. Gestures are not a
`RecordingStream`. Enablement follows Settings → **Session recording**
(also applies to tmp and feedback).

---

## Computed stream (1 Hz) — own zstd section

JSON Lines, one `ComputedFrame` per line. `t` is seconds from **this**
capture start.

```json
{
  "t": 123.0,
  "bands": [[1.2, 2.5, 4.8, 3.1, 1.9], [1.1, 2.4, 5.0, 3.0, 1.8], [1.3, 2.6, 4.7, 3.2, 2.0], [1.0, 2.3, 4.9, 3.1, 1.7]],
  "pulse": 72.3,
  "movement": 0.012,
  "peakAlpha": { "freq": 10.2, "power": 4.5 },
  "spo2": 98.5,
  "lineNoise": [0.01, 0.02, 0.01, 0.03],
  "signalQuality": [85, 90, 60, 70],
  "guardrail": { "sleepDir": 0.34, "clarity": 0.78, "warning": false, "delta": 0.12 },
  "feedback": { "ratio": 1.85, "threshold": 1.2, "inTarget": true, "pct": 0.62 },
  "gestures": ["blink"]
}
```

| Field | Notes |
|-------|--------|
| `bands` | `N × 5` absolute powers `[δ, θ, α, β, γ]`. Feedback sampler is **4-ch**. Monitor sampler is `channelCount`. |
| `lineNoise` / `signalQuality` | Same `N`. |
| `guardrail` / `feedback` | Recordings write zeroed structs. |

---

## Raw stream — own zstd section

Original `.muse` v4 body (header + zstd frames, tags 1–10):

| Tag | Stream | Typical rate | Payload |
|-----|--------|--------------|---------|
| 1 | EEG | 256 Hz | [ts, electrode, n, n×f32] |
| 2 | Telemetry | 1 Hz | [ts, battery, fuel, temp] |
| 3 | Accelerometer | 52 Hz | [ts, seq, n, n×(x,y,z)] |
| 4 | Gyroscope | 52 Hz | [ts, seq, n, n×(x,y,z)] |
| 5 | PPG | 64 Hz | [ts, channel, n, n×f32] |
| 6 | Bands | ~10 Hz on the wire | [ts, electrode, δ,θ,α,β,γ] |
| 7 | Pulse | 1 Hz | [ts, bpm, conf] |
| 8 | Movement | 1 Hz | [ts, score] |
| 9 | PeakAlpha | ~10 Hz on the wire | [ts, freq, power] |
| 10 | SpO₂ | 1 Hz | [ts, spo2, conf] |

`ts` in this body is a **ms epoch**. CSV export divides by 1000 before flooring.

---

## Scratch and crash recovery

Live writes always go to `scratchDirectory()`, not the history folder (SAF
is history-only).

| Prefix | Temps | On crash / leftover |
|--------|-------|---------------------|
| `session_$id` | `.raw` `.computed` `.metadata` (JSONL) | Feedback dialog **Incomplete Session Detected** → Save Session / Discard. Assembles via `writeScratchV5`. |
| `recording_$ts` | `.raw` `.computed` `.json` (atomic snapshot) | **Incomplete recording detected** → Save / Discard. Same History folder, sqlite `kind=recording`. |
| `tmp_$ts` | `.raw` `.computed` `.json` | Launch **glob-deletes**. Never assembled. |

Feedback recovery must not learn `tmp_` / `recording_`. Monitor recovery
must not learn `session_`.

---

## Implementation

| Piece | Where |
|-------|--------|
| Byte layout / FFI | `rust/src/api/session_format.rs` |
| Assemble / scratch v5 | `lib/src/session_v5/assemble.dart` |
| Scratch writer | `lib/src/session_v5/scratch_writer.dart` (`SessionRecorder`, `prefix`) |
| Feedback metadata | `lib/src/feedback/session_metadata.dart` |
| Recording metadata | `lib/src/monitor/recording/recording_metadata.dart` |
| ComputedFrame | `lib/src/session_v5/computed_frame.dart` |

No v4 `.muse.feedback` compatibility. Old v4 files are ignored by History.
