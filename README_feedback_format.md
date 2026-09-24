# NeuroFeed — `.neurofeed` v6

**Format version:** 6  
**Container:** `[68-byte header][WebP thumbnail][metadata (zstd)][computed 1 Hz (zstd)][raw body]`

Rust owns the byte layout (`rust/src/api/session_format.rs`). Dart only calls FFI.

Schema authority: [`.ai/contracts/fileformat_v6.md`](.ai/contracts/fileformat_v6.md) (**Implemented / LOCKED**).  
Historical v5 freeze (archived): [`.ai/archive/session-format-contract-v5.md`](.ai/archive/session-format-contract-v5.md).

Two filenames, **one metadata dialect**:

| Kind | Published name | Scratch temps | Metadata JSON |
|------|----------------|---------------|---------------|
| Feedback session | `session_$id.neurofeed` | `session_$id.{raw,computed,metadata}` | Base + top-level `feedback{}` |
| Recording | `recording_$ts.neurofeed` | `recording_$ts.{raw,computed,json}` | Base only (no `feedback`) |

`tmp_$ts.*` is a rolling connect-time capture. It is **never** assembled or published.

History list is sqlite `kind` (`feedback` \| `recording`), not a directory scan. See [README_history_cache.md](README_history_cache.md).

**Timestamps:** computed `t`, annotation `onset`/`duration`, and gesture offsets are seconds from **this capture’s start** (content clock; does not advance during pause). Raw EEG/band timestamps in the raw body are **ms epochs**. Wall-clock `startedAt` / `savedAt` are ISO-8601 **with explicit offset or `Z`**; root `timeZone` is IANA (e.g. `Asia/Bangkok`).

---

## v6 container layout

```
Offset 0:        68-byte fixed header
  [0..5]     = b"NFED6\0"
  [6]        = 6 (version)
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
Offset raw_offset:       copy of live `.raw` (NFEDBIN + inner zstd frames)
```

`parseHead` / head parse (container is **NFED6**) returns opaque
`metadataJson` bytes. It does **not** parse `kind`.

There is no `metadata.summary` / `SessionOverview` and no 400-bucket series.
Dashboard, history, PDF, and PNG charts plot computed 1 Hz:
`extractComputed` (parses the **v6** container) →
`prepareChartDataFromComputed`. The history-list preview is the WebP thumbnail.

---

## Base metadata (both kinds)

Writers: `lib/src/session_format/metadata.dart` (`buildRecordingMetadataV6` /
`buildFeedbackMetadataV6`). Single nested dialect — **no** flat
`deviceName` / dual-shape accept path for new files.

```json
{
  "formatVersion": 6,
  "appVersion": "…",
  "kind": "recording",
  "savedAt": "2026-09-24T17:30:00.000+07:00",
  "startedAt": "2026-09-24T17:20:00.000+07:00",
  "timeZone": "Asia/Bangkok",
  "elapsedSeconds": 600,
  "durationS": 600,
  "notes": "",
  "sessionId": "…",
  "subject": { "id": "…", "nickname": "River" },
  "device": {
    "name": "Muse 2",
    "id": "…",
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
  },
  "stats": { "hr": { "mean": 68.2, "min": 54.0, "max": 91.0 } },
  "annotations": [
    { "onset": 45.0, "duration": 0, "type": "double_blink" },
    { "onset": 200.0, "duration": 10.0, "type": "pause" }
  ]
}
```

- `subject.id` = stable anonymous UUID v4 from Settings; optional `nickname`.
- Root `sessionId` = **file** identity (new per capture), not the person.
- `annotations[]` is the single timeline (pause / bad_quality / disconnect + gesture instants). No parallel `feedback.gestures[]`.

---

## Feedback extension

When `kind == "feedback"`, also write top-level `feedback: { … }` (protocol,
durationMinutes, calibration, sessionSettings, outcomeScalars, music, …).
Shared physio stays under base `stats` only. See contract **Feedback extension**.

---

## Raw stream — NFEDBIN body (inner zstd frames)

Unchanged framing vs prior releases: live `.raw` is `NFEDBIN` + versioned
inner frames. Outer container magic is **NFED6**.

---

## Code map

| Concern | Path |
|---------|------|
| Assemble / scratch | `lib/src/spine/assemble.dart` |
| v6 metadata writers | `lib/src/session_format/metadata.dart` |
| Annotations / base stats | `lib/src/session_format/stats_assemble.dart` |
| ComputedFrame (Dart) | `lib/src/session_format/computed_frame.dart` |
| Container encode/parse | `rust/src/api/session_format.rs` |
| Settings subject id | `lib/src/settings.dart` |
