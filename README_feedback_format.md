# Muse ML — `.muse.feedback` v5 Metadata Format

**Format version:** 5  
**Container:** `[68-byte header][WebP thumbnail][metadata (zstd)][computed 1 Hz (zstd)][raw (zstd)]`  
**All timestamps:** seconds from recording (calibration) start, unless noted as wall-clock epoch.

---

## Top-Level Metadata JSON Structure

```json
{
  "formatVersion": 5,
  "appVersion": "1.0.0+1",
  "savedAt": "2026-08-22T14:30:00.000Z",
  "notes": "User free-text notes",
  "protocol": "drowsiness",
  "durationMinutes": 15,
  "elapsedSeconds": 900,
  "feedbackSound": "bowlChimes",
  "metadataDescription": "Scientific description from protocols.json",
  "device": { ... },
  "calibration": { ... },
  "streams": { ... },
  "sessionSettings": { ... },
  "summary": { ... },
  "gestures": [ ... ],
  "drowsiness": { ... },
  "music": { ... },
  "modelSnapshot": { ... }
}
```

---

## 1. Device Information

```json
"device": {
  "name": "Muse 0ABC",
  "id": "AA:BB:CC:DD:EE:FF",
  "firmware": "3.0.12",
  "model": "Classic",
  "sensors": ["EEG", "PPG", "IMU"],
  "channelCount": 4,
  "channelLabels": ["TP9", "AF7", "AF8", "TP10"]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | BLE display name |
| `id` | string | MAC address (stable identifier) |
| `firmware` | string | Headset firmware version |
| `model` | string | "Classic", "Athena", "Crown", or "Unknown" |
| `sensors` | string[] | Subset of `["EEG", "PPG", "IMU"]` |
| `channelCount` | int | Number of EEG electrodes (4 for Muse, 8 for Crown) |
| `channelLabels` | string[] | Electrode labels in index order (0..N-1) |

---

## 2. Calibration Record

Complete snapshot of the calibration that ran (or was skipped).

```json
"calibration": {
  "version": 2,
  "kind": "staged",
  "calibrationId": "eyes-closed-01",
  "calibrationJson": { ... },
  "calibrationStartSecs": 1724327400.123,
  "calibrationEndSecs": 1724327550.456,
  "trainingStartSecs": 1724327550.456,
  "usedStartAnyway": false,
  "greenStableSeconds": 3,
  "faultyPadSeconds": 20,
  "baseline": {
    "percentile": 40,
    "count": 120,
    "mean": 1.85,
    "stddev": 0.42
  },
  "phases": [
    {
      "clipId": "artifacts",
      "clipFile": "calibration/artifacts.opus",
      "spokenText": "Blink, clench, look up, look down...",
      "eyes": null,
      "challengeText": null,
      "startSecs": 0.0,
      "endSecs": 30.0,
      "kind": "stage"
    },
    {
      "clipId": "eyes-open-challenge",
      "clipFile": "calibration/eyes_open.opus",
      "spokenText": "Keep eyes open, count backwards from 100...",
      "eyes": "open",
      "challengeText": "Count backwards from 100 by 7s",
      "startSecs": 30.0,
      "endSecs": 60.0,
      "kind": "stage"
    },
    {
      "clipId": "eyes-closed-rest",
      "clipFile": "calibration/eyes_closed.opus",
      "spokenText": "Close eyes, let mind rest...",
      "eyes": "closed",
      "challengeText": null,
      "startSecs": 60.0,
      "endSecs": 150.0,
      "kind": "stage"
    }
  ],
  "recalibrations": [
    {
      "atSecs": 420.5,
      "baseline": {
        "percentile": 40,
        "count": 85,
        "mean": 1.92,
        "stddev": 0.38
      }
    }
  ],
  "trainingStartOffsetSecs": 150.333
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | int | Calibration manifest version (2) |
| `kind` | string | `"single"` or `"staged"` |
| `calibrationId` | string | Key from `calibrations.json` (e.g., `eyes-closed-01`) |
| `calibrationJson` | object | **Full immutable snapshot** of the calibration definition from `calibrations.json` (both variants, all clips, texts, timings) |
| `calibrationStartSecs` | float? | Wall-clock epoch seconds when calibration began (recording start) |
| `calibrationEndSecs` | float? | Wall-clock epoch seconds when baseline finished |
| `trainingStartSecs` | float? | Wall-clock epoch seconds when feedback/training began |
| `usedStartAnyway` | bool | User bypassed green-stable gate via faulty-pad fallback |
| `greenStableSeconds` | int? | Required continuous green-signal seconds before calibration proceeds |
| `faultyPadSeconds` | int? | Non-green seconds on non-program pads before "Continue anyway" offered |
| `baseline` | object | ATR baseline statistics (percentile, count, mean, stddev) |
| `phases` | array | Clip phases with timings, spoken text, challenge text, eye state |
| `recalibrations` | array | In-flight recalibrations (timestamp + new baseline stats) |
| `trainingStartOffsetSecs` | float? | Derived: `trainingStartSecs - calibrationStartSecs` (seconds) |

### Phase Object

| Field | Type | Description |
|-------|------|-------------|
| `clipId` | string | Identifier from `calibrations.json` |
| `clipFile` | string | Audio asset path (e.g., `calibration/artifacts.opus`) |
| `spokenText` | string | Spoken transcript of the guidance clip |
| `eyes` | string? | `"open"`, `"closed"`, or `null` |
| `challengeText` | string? | On-screen cognitive challenge (e.g., "Count backwards by 7s") |
| `startSecs` | float? | Seconds from recording start to phase start |
| `endSecs` | float? | Seconds from recording start to phase end |
| `kind` | string | `"intro"` (single calibration) or `"stage"` (staged calibration) |

---

## 3. Streams Configuration

What data streams were recorded and at what rate.

```json
"streams": {
  "eeg": { "enabled": true, "rateHz": 256, "electrodes": [0,1,2,3] },
  "bands": { "enabled": true, "rateHz": 10, "electrodes": [0,1,2,3] },
  "pulse": { "enabled": true, "rateHz": 1 },
  "spo2": { "enabled": true, "rateHz": 1 },
  "movement": { "enabled": true, "rateHz": 1 },
  "peakAlpha": { "enabled": true, "rateHz": 10 },
  "imu": { "enabled": true, "rateHz": 52, "sensors": ["accel", "gyro"] },
  "ppg": { "enabled": true, "rateHz": 64, "channels": ["ir", "red"] },
  "telemetry": { "enabled": true, "rateHz": 1 },
  "gestures": { "enabled": true, "rateHz": 1 }
}
```

| Stream | Rate | Notes |
|--------|------|-------|
| `eeg` | 256 Hz | Raw EEG per electrode (µV) |
| `bands` | 10 Hz | Absolute band powers (δ, θ, α, β, γ) per electrode |
| `pulse` | 1 Hz | Heart rate BPM from PPG IR |
| `spo2` | 1 Hz | Blood oxygen % from PPG IR+Red |
| `movement` | 1 Hz | Accelerometer-derived movement score |
| `peakAlpha` | 10 Hz | Peak alpha frequency + power |
| `imu` | 52 Hz | Accelerometer + gyroscope (3-axis each) |
| `ppg` | 64 Hz | Raw IR + Red channels |
| `telemetry` | 1 Hz | Battery, fuel gauge, temperature |
| `gestures` | 1 Hz | Blink/clench/eye events |

---

## 4. Session Settings Snapshot

All session-affecting settings at save time.

```json
"sessionSettings": {
  "dynamicAdapt": true,
  "responsiveness": 0.5,
  "baselinePercentile": 40,
  "guardrailEnabled": true,
  "guardrailEngine": "lunaLarge",
  "warningThresholdPercentile": 90,
  "warningSound": "softChime",
  "musicFolder": "/Music/Meditation",
  "musicMinCutoffHz": 220.0,
  "musicMaxCutoffHz": 4000.0,
  "musicInvert": false,
  "musicShuffle": true,
  "binauralPresetId": "theta4",
  "binauralCarrierHz": 200.0,
  "binauralBeatHz": 4.0,
  "markersInFeedbackEnabled": true,
  "eyeMarkersEnabled": false
}
```

---
 
## 5. Decimated Summary (SessionOverview) — Metadata JSON

**Current files may still contain this.** A frozen spec will drop `metadata.summary` / `SessionOverview` and plot computed 1 Hz instead — see `.ai/feedback/session-computed-charts.md`. Do not add new fields here.

400-bucket decimated view used today for **fast history rendering** without reading the computed stream. Stored in the metadata JSON (`summary` key).
 
```json
"summary": {
  "bucketCount": 400,
  "bucketWidthSecs": 2.25,
  "startSecs": 1724327400.123,
  "endSecs": 1724328300.456,
  "trainingStartSecs": 150.333,
  "bands": {
    "0": { "delta": [...], "theta": [...], "alpha": [...], "beta": [...], "gamma": [...] },
    "1": { ... },
    "2": { ... },
    "3": { ... }
  },
  "pulse": [62.1, 61.8, 62.3, null, ...],
  "spo2": [98.0, 97.5, 98.2, ...],
  "movement": [0.02, 0.01, 0.03, ...],
  "peakAlphaFreq": [9.8, 10.1, 10.0, ...],
  "peakAlphaPower": [4.2, 4.5, 4.3, ...]
}
```
 
| Field | Type | Description |
|-------|------|-------------|
| `bucketCount` | int | Always 400 |
| `bucketWidthSecs` | float | Session duration / 400 |
| `startSecs` | float | Wall-clock epoch of first bucket |
| `endSecs` | float | Wall-clock epoch of last bucket |
| `trainingStartSecs` | float? | Seconds from recording start to training boundary |
| `bands` | object | Per-electrode band power arrays (absolute µV²) |
| `pulse` | float?[] | BPM per bucket |
| `spo2` | float?[] | SpO₂ % per bucket |
| `movement` | float?[] | Movement score per bucket |
| `peakAlphaFreq` | float?[] | Hz per bucket |
| `peakAlphaPower` | float?[] | Absolute power per bucket |
 
> **Note:** This decimated summary is for **instant history UI rendering** (charts, stats cards). The **full-resolution 1 Hz data** lives in the separate zstd-compressed *computed section* as JSON Lines (see Section 10). The summary is computed at save time from the full computed frames and decimated to exactly 400 buckets.
 
---
 
## 6. Gesture Markers

Timestamped gesture events during the session.

```json
"gestures": [
  { "type": "doubleBlink", "offsetSeconds": 45.2 },
  { "type": "doubleClench", "offsetSeconds": 123.7 },
  { "type": "eyeUp", "offsetSeconds": 201.4 }
]
```

| Type | Values |
|------|--------|
| `type` | `"doubleBlink"`, `"doubleClench"`, `"eyeUp"`, `"eyeDown"` |
| `offsetSeconds` | float — seconds from **recording (calibration) start** |

---

## 7. Guardrail (Drowsiness) Trace

Per-second guardrail scores (decimated to 400 buckets in metadata; full series in computed stream).

```json
"drowsiness": {
  "scoreTotalPct": 12.5,
  "meanSleepDir": 0.34,
  "threshold": 0.62,
  "bucketWidthSecs": 2.25,
  "buckets": [
    { "offsetSecs": 1.125, "sleepDir": 0.21, "delta": 0.15, "warning": false },
    { "offsetSecs": 3.375, "sleepDir": 0.68, "delta": 0.22, "warning": true },
    ...
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `scoreTotalPct` | float | % of scored seconds with warning active |
| `meanSleepDir` | float | Mean sleep-direction over scored seconds |
| `threshold` | float? | Baseline percentile threshold used for warnings |
| `bucketWidthSecs` | float | Seconds per bucket (matches `summary.bucketWidthSecs`) |
| `buckets` | array | Decimated buckets with mean sleepDir, delta, warning flag |

---

## 8. Music Feedback Record

```json
"music": {
  "trackCount": 8,
  "minCutoffHz": 220.0,
  "maxCutoffHz": 4000.0,
  "invert": false,
  "shuffle": true,
  "tracks": [
    { "offsetSecs": 150.0, "name": "track01.opus" },
    { "offsetSecs": 198.3, "name": "track02.opus" }
  ],
  "bucketWidthSecs": 2.25,
  "buckets": [
    { "offsetSecs": 1.125, "hz": 2450.0 },
    { "offsetSecs": 3.375, "hz": 2380.0 }
  ]
}
```

---

## 9. Model Snapshot (Guardrail AI Identity)

Critical for reproducibility when fine-tuning foundation models.

```json
"modelSnapshot": {
  "engine": "lunaLarge",
  "weightsSha256": "a1b2c3d4e5f6...",
  "configJson": { ... },
  "repoRevision": "v0.0.4-latent-embedding-fix",
  "loadedAt": "2026-08-22T14:25:10.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `engine` | string | `"bandMath"`, `"lunaBase"`, `"lunaLarge"`, `"reveBase"`, or `"none"` |
| `weightsSha256` | string | SHA-256 of the `model.safetensors` file |
| `configJson` | object | Full model config (from `model_config_json()` FFI) |
| `repoRevision` | string | Git tag/rev of the model repo (e.g., `v0.0.4-latent-embedding-fix`) |
| `loadedAt` | string | ISO8601 timestamp when model was loaded for this session |

---

## 10. Computed Stream (1 Hz) — Separate zstd Section

Not in metadata JSON — stored in its own zstd-compressed section as JSON Lines (one `ComputedFrame` per line). Each frame:

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

| Field | Type | Description |
|-------|------|-------------|
| `t` | float | Seconds from recording start |
| `bands` | float[4][5] | Absolute band powers per electrode [δ, θ, α, β, γ] |
| `pulse` | float? | BPM |
| `movement` | float? | 0.0–1.0 |
| `peakAlpha` | object? | `{ freq, power }` |
| `spo2` | float? | % |
| `lineNoise` | float[4] | Per-electrode 50/60 Hz mains fraction |
| `signalQuality` | int[4] | Per-pad 0–100 quality score |
| `guardrail` | object | Sleep-direction, clarity, warning, frontal delta |
| `feedback` | object | ATR ratio, threshold, in-target, success % |
| `gestures` | string[] | Event names in this second |

---

## 11. Raw Stream — Separate zstd Section

The original `.muse` v4 body (header + zstd frames with tags 1–10). Contains all high-rate events:

| Tag | Stream | Rate | Payload |
|-----|--------|------|---------|
| 1 | EEG | 256 Hz | [ts, electrode, n, n×f32] |
| 2 | Telemetry | 1 Hz | [ts, battery, fuel, temp] |
| 3 | Accelerometer | 52 Hz | [ts, seq, n, n×(x,y,z)] |
| 4 | Gyroscope | 52 Hz | [ts, seq, n, n×(x,y,z)] |
| 5 | PPG | 64 Hz | [ts, channel, n, n×f32] |
| 6 | Bands | 10 Hz | [ts, electrode, δ,θ,α,β,γ] |
| 7 | Pulse | 1 Hz | [ts, bpm, conf] |
| 8 | Movement | 1 Hz | [ts, score] |
| 9 | PeakAlpha | 10 Hz | [ts, freq, power] |
| 10 | SpO₂ | 1 Hz | [ts, spo2, conf] |

---

## v5 Container Layout

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

Offset thumbnail_offset: WebP thumbnail (640×360, lossy q=75)

Offset metadata_offset: zstd-compressed metadata JSON (level 3)

Offset computed_offset: zstd-computed 1 Hz frames as JSON Lines (level 3)

Offset raw_offset: zstd-compressed raw .muse body (level 3)
```

**Reading**: Read first 68 bytes → parse header → exact-offset reads for each section → zstd decompress.

---

## Crash Recovery

During recording, three uncompressed temp files are written to `<cache>/sessions/<session_id>/`:

```
session_<ts>.raw          # raw event bytes (uncompressed)
session_<ts>.computed     # JSON Lines (one ComputedFrame per line)
session_<ts>.metadata     # JSON Lines (metadata events)
```

On app start, any incomplete triplets are detected. A **blocking modal** shows:
- Session duration, protocol, calibration kind
- Artifacts detected, guardrail warnings
- Buttons: **Save Session** (assembles v5) / **Discard**

No navigation allowed until dismissed.

---

## Migration Notes

- **No v4 backward compatibility** — v5 is a clean break.
- Old v4 files are ignored by the new history UI.
- "Clear Cache" button in Settings → drops SQLite tables → re-imports all v5 files on next history load (reads metadata + computed from each file).
- Users should delete old `.muse.feedback` v4 files manually.

---

## Implementation Checklist

- [ ] Rust: `container_encode_v5` (✅ done)
- [ ] Rust: `v5_parse_header`, `v5_parse_head`, `v5_extract_computed`, `v5_extract_raw` (✅ done)
- [ ] Dart: `ComputedFrame` + `ComputedSampler` (✅ done)
- [ ] Dart: `SessionRecorder` rewrite with 3 temp files (in progress)
- [ ] Dart: `FeedbackRecorder.appendComputed` / `finalize` → calls `container_encode_v5`
- [ ] Dart: Crash recovery scan + blocking modal
- [ ] Dart: `SessionMetadata` v5 fields (`formatVersion`, `appVersion`, `modelSnapshot`, `streams`)
- [ ] Rust: `modelSnapshot` helper (weights SHA-256, config JSON, repo revision)
- [ ] SQLite: `computed` table (1 Hz rows), updated `metadata` blob
- [ ] History UI: reads from SQLite, not head reads
- [ ] Tests: v5 round-trip, crash recovery, SQLite import