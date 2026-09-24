# File format v6 — unified metadata (draft)

| Field | Value |
|---|---|
| Status | **Draft.** Contract only. Not implemented. |
| Scope | Unify recording + feedback **metadata JSON**; prepare a **v6 clean cut** (container magic/version + writers/readers). |
| Not this | Implement Rust/Dart writers yet; Athena tag 11; History UI chrome; pipeline Key Decisions. |
| Supersedes (when landed) | Dual dialects in [session-format-contract.md](session-format-contract.md) § Metadata; [../TODO/session_vs_recording_metadata.md](../TODO/session_vs_recording_metadata.md). |
| Human layout (today) | [../../README_feedback_format.md](../../README_feedback_format.md) — update **in the same PR** that implements v6. |
| History cache | [../../README_history_cache.md](../../README_history_cache.md) — promote a small scalar set into sqlite later. |

Agents: adhere to **Design rules** below. Inventory is from code (cited), not guesswork.

---

## Design rules (must adhere)

1. **One base schema for both kinds.** Identity + `device` + `streams` + `stats` (+ quality/gaps) always present. Optional top-level `feedback` object **only** when `kind == "feedback"`; omit (or null) for recordings.
2. **Two layers of stats.** (a) **Computed 1 Hz** — charts / AI time series (`ComputedFrame`). (b) **Session summary** — scalars/short structs on metadata, computed at assemble/save (later: a small set as sqlite columns).
3. **Do not duplicate time series into metadata.** Metadata = scalars + short structs + compact interval lists. Computed = second-by-second.
4. **Band aggregates are named metrics** (e.g. mean α, α/θ, frontal–temporal α asymmetry, cross-channel α variance). Never vague "spread".
5. **Recordings keep zeroed `guardrail` / `feedback` on computed frames** if charts expect keys. Session-level top-level `feedback` object is **absent** on recordings.
6. **No backward compatibility with v5.** Clean cut: new magic/version (`NFED6` / `formatVersion: 6`), delete dual-dialect readers, dead comments, and leftover "accept both shapes" code **in the same effort**.
7. **Collect all useful + cheap session stats at save.** Promote a small set into sqlite later. Mark uncertain metrics `experimental: true` or nest under `stats.experimental` (may be removed if unused).

Also:

- Every file carries explicit `kind`, `formatVersion`, `appVersion`.
- Shared nested `stats` for both kinds (feedback-only reward/guard scalars live under `feedback` or under `stats` only when meaningful for both — prefer `feedback.*` for training-only).
- Fit / usable-signal summary and battery start/end when cheap.
- **Gestures:** metadata/session event markers today (`GestureMarker.at`); `streams.gestures` is a stub (`enabled: false`). Do not invent a raw tag without a format PR. Clarify stream enablement vs event list.

---

## Inventory (from code)

### Sources

| Area | Path |
|---|---|
| Recording metadata | `lib/src/monitor/recording/recording_metadata.dart` |
| Feedback metadata | `lib/src/feedback/session_metadata.dart` |
| Device / streams models | `lib/src/session_v5/models.dart` (`DeviceInfoV5`, `StreamsConfig`) |
| Computed frame | `lib/src/session_v5/computed_frame.dart` |
| Monitor 1 Hz writer | `lib/src/monitor/recording/monitor_sampler.dart` (N-ch; zeroed guard/feedback) |
| Feedback 1 Hz writer | `lib/src/feedback/computed_sampler.dart` (4-ch; live guard/feedback) |
| Scalar extract at publish | `lib/src/spine/assemble.dart` → `extractComputedScalars` |
| Recording publish → sqlite | `lib/src/monitor/recording/recording_store.dart` |
| Feedback publish → sqlite | `lib/src/feedback/session_store_core.dart` |
| Usable pad gate | `lib/src/monitor/signal_usable.dart` (`kUsableSignalThreshold = 80`) |
| Sticky BandCache | `lib/src/monitor/cache/band_cache.dart` (`appendHeldUnusableGap` = **live-only**) |
| Disconnect-during-recording | `lib/src/monitor/monitor_controller.dart` (`_onDisconnectedUnlocked` / gap filler) |
| Feedback interrupt | `lib/src/feedback/feedback_state.dart` (`FeedbackInterruptKind.disconnect` \| `badSignal`) |
| Format freeze (v5) | `.ai/contracts/session-format-contract.md`, `README_feedback_format.md` |
| Dialect TODO | `.ai/TODO/session_vs_recording_metadata.md` |
| Sqlite columns | `README_history_cache.md`, `lib/src/feedback/session_sqlite.dart` |

### A) Already recorded

#### Recording metadata JSON (`RecordingMetadata`)

Always nested:

- Identity: `formatVersion` (5), `appVersion`, `kind: "recording"`, `savedAt`, `startedAt`, `elapsedSeconds`, `durationS`, `notes`
- `device`: `name`, `id`, `firmware`, `model`, `sensors`, `channelCount`, `channelLabels`
- `streams`: complete ten keys (`eeg`…`gestures`); disabled = `{enabled:false, rateHz:0}` (never omitted)

**Not in recording metadata today:** any `stats`, quality/gaps, battery, gestures list, protocol/calibration/music.

#### Feedback metadata JSON (`SessionMetadata`) — flat dialect

Written by `buildSessionMetadata()`:

- Timing / notes: `protocol`, `durationMinutes`, `elapsedSeconds`, `durationS`, `sound`, `savedAt`, `startedAt`, `notes`, `sessionId`
- Flat device: `deviceName`, `deviceModel`, `deviceId` (not nested `device`)
- `recordedChannels`, `recordedData` (stream name list)
- `gestures[]` (`type`, `at` seconds) when markers enabled
- Nested: `calibration`, `drowsiness`, `music`, `sessionSettings` (incl. `guardFeature` / `guardModel`), optional `protocolJson`
- Optional save-time `stats` blob: `peakAlphaFreq/Power`, `targetPct`, `stillnessPct`, `avgBpm`, `avgAlphaRel`
- Flat mirrors (when stats present): `avgSpo2`, `peakAlphaHz`, `peakAlphaPower`, `pctInTarget`, `avgSleepDir`

**Absent on feedback files today:** `formatVersion`, `appVersion`, `kind`, nested `device`, ten-key `streams`. Sqlite sets `kind=feedback` on publish.

**Schema fields rarely/never filled by `buildSessionMetadata`:** `signalQualityMean`, `pctQcOk`, `avgMovement`, `guardrailWarnCount`, `modelKind` / `modelSha256` / `feedbackEngine` / `userId` — present on the Dart model + sqlite, often null in file JSON.

#### Computed 1 Hz (both kinds) — not metadata

`ComputedFrame`: `t`, `bands` (N×5 abs), `lineNoise`, `signalQuality`, optional `pulse` / `movement` / `peakAlpha` / `spo2`, `guardrail{sleepDir,clarity,warning,delta}`, `feedback{ratio,threshold,inTarget,pct}`, `gestures[]` (string ids that second).

Recordings: zeroed `guardrail`/`feedback` keys still present.

#### Sqlite (publish-time; not always in metadata JSON)

From `extractComputedScalars` + row upsert: `avg_hr`, `avg_spo2`, `peak_alpha_hz/power`, `pct_in_target`, `avg_movement`, `guardrail_warn_count`, `avg_sleep_dir`, plus identity/device columns. `signal_quality_mean` / `pct_qc_ok` columns exist but are usually unset from metadata.

### B) Candidates to add (valuable + cheap at save)

Compute from computed JSONL (and raw telemetry if needed) at assemble/save. Prefer nesting under `stats`.

| Candidate | Notes | experimental? |
|---|---|---|
| HR mean / min / max | From computed `pulse` | no |
| SpO₂ mean / min / max | From computed `spo2` | no |
| Peak-alpha summary | mean freq; max-power freq/power (today extract keeps max-power pair only) | no |
| Movement mean (+ optional stillness %) | From computed `movement` | no |
| `% usable` / `% good quality` | Seconds where mean (or gate) `signalQuality ≥ 80` | no |
| Channel usable fractions | Per-label fraction of seconds pad ≥ 80 | no |
| Battery start / end | First/last telemetry samples in raw (tag 2) when stream enabled | no |
| Fit / contact summary | Derive from quality fractions + channel labels | no |
| Session duration | Already have `durationS` / `elapsedSeconds` | — |
| Named band stats | mean α (abs), mean α/θ, frontal–temporal α asymmetry, cross-ch α variance — over **usable** seconds only | **yes** (tune formulas) |
| `% overshoot` / held | Needs a defined yMax policy; overshoot today is **paint-time** on Monitor Bands | **yes** |
| Compact `gaps` intervals | Single `{from,to,event}` list for pause / unusable / disconnect (see Gaps model) | no; list is canonical, `stats.gapSeconds` optional |
| Feedback-only: `% in target`, guard warn count, mean sleepDir | Already extracted for sqlite; put in `feedback` / shared `stats` cleanly | no |

Do **not** dump full 1 Hz series into metadata.

### Gap / quality handling today (confirm)

| Mechanism | Behavior |
|---|---|
| Pad quality threshold | 80 (`kUsableSignalThreshold` / `signalGoodThreshold`). Critical interrupt at 40 for 10 s (`badSignalPauseSeconds`). |
| BandCache sticky unusable | Stamped at append when pad bad; **live chart only** — comment: does **not** feed Rust capture writer. |
| Overshoot hold | Paint-time (`overshoot_hold.dart`); not a persisted sample bit. |
| Disconnect during recording | Sampler stopped; `appendHeldUnusableGap` 1 Hz into BandCache for UI; raw gets no new BLE events. Capture lease held open. |
| Feedback disconnect / badSignal | Phase → `interrupted`; audio/ticker pause. Computed sampler is **not** stopped until `end()`. |
| Raw during bad quality | **Still records** whatever Muse events arrive. Unusable ≠ dropped. Disconnect is the exception (no packets). |

---

## Proposal: recording BASE metadata JSON

Shared root for `kind: "recording"` and (with `feedback` attached) for feedback.

### Shape

```
identity: formatVersion, appVersion, kind, savedAt, startedAt, elapsedSeconds, durationS, notes
device:   { name, id, firmware, model, sensors, channelCount, channelLabels }
streams:  { ten keys… }   // gestures enablement stub; see Gestures
stats:    { … aggregates; gapSeconds?: { pause, unusable, disconnect }; experimental?: { … } }
gaps:     [ { from, to, event }, … ]   // canonical timeline; see Gaps model
feedback: { … }   // ONLY when kind == "feedback"
```

### Example — `kind: "recording"`

```json
{
  "formatVersion": 6,
  "appVersion": "dev",
  "kind": "recording",
  "savedAt": "2026-09-24T10:30:00.000Z",
  "startedAt": "2026-09-24T10:20:00.000Z",
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
  },
  "stats": {
    "hr": { "mean": 68.2, "min": 54.0, "max": 91.0 },
    "spo2": { "mean": 98.1, "min": 96.0, "max": 99.0 },
    "peakAlpha": { "meanHz": 10.1, "maxPowerHz": 10.4, "maxPower": 5.2 },
    "movement": { "mean": 0.018 },
    "quality": {
      "mean": 86.4,
      "pctGood": 92.0,
      "channelUsable": { "TP9": 0.94, "AF7": 0.88, "AF8": 0.91, "TP10": 0.95 }
    },
    "gapSeconds": { "pause": 10.0, "unusable": 15.0, "disconnect": 8.0 },
    "battery": { "startPct": 81.0, "endPct": 76.0 },
    "experimental": {
      "bands": {
        "meanAlphaAbs": 4.6,
        "meanAlphaTheta": 1.7,
        "frontalTemporalAlphaAsym": 0.12,
        "crossChannelAlphaVar": 0.08
      }
    }
  },
  "gaps": [
    { "from": 120.0, "to": 135.0, "event": "unusable" },
    { "from": 200.0, "to": 210.0, "event": "pause" },
    { "from": 400.0, "to": 408.0, "event": "disconnect" }
  ]
}
```

Notes:

- Omit top-level `feedback` on recordings.
- Root `gaps` is the **canonical** timeline. Optional `stats.gapSeconds` is derived from that list (sum of `to - from` per `event`); never a second source of truth.
- `gaps` must stay compact (merge adjacent same-`event` runs). Not a 1 Hz dump.
- `streams.gestures.enabled` remains false until a real stream exists; gesture **markers** (feedback) live under `feedback.gestures` or base `events` if shared later.

---

## Gaps model (locked)

**Decision:** one extensible root array `gaps[]` of interval objects. **Not** three parallel top-level bags `paused{}` / `unusable{}` / `disconnected{}` (anti-pattern — rejected as the primary model).

### Canonical shape

```json
"gaps": [
  { "from": 120.0, "to": 135.0, "event": "unusable" },
  { "from": 200.0, "to": 210.0, "event": "pause" },
  { "from": 400.0, "to": 408.0, "event": "disconnect" }
]
```

Field names: camelCase to match the rest of the format (`from`, `to`, `event`).

### Rules

1. **Single array** of `{ from, to, event }`. Extend later by adding new `event` strings — no new root keys.
2. **`event` enum (initial):** `pause` | `unusable` | `disconnect`.
   - Do **not** invent `overshoot` gaps in metadata until overshoot is product-defined as a persisted interval. Overshoot today is paint-only / experimental on Monitor Bands; sticky bad pads are already covered by quality-driven `unusable`.
3. **Times** are seconds from capture start (same clock as computed `t`).
4. **Merge** adjacent same-`event` runs; keep the list compact. Not a 1 Hz dump.
5. **Reject** parallel top-level `paused` / `unusable` / `disconnected` objects as the primary model. Readers and writers use `gaps` only.
6. **Product → event mapping:**
   - Feedback `badSignal` interrupt → `event: "unusable"`
   - User pause → `event: "pause"`
   - BLE loss / disconnect → `event: "disconnect"`

### Optional summary nesting

Canonical source: `gaps`. Optional derived counts live under **`stats.gapSeconds`** (seconds-by-event), e.g. `{ "pause": 10.0, "unusable": 15.0, "disconnect": 8.0 }`. Do not use a separate root `gapsSummary` object; keep aggregates under `stats`.

### Layers (unchanged intent)

1. **Metadata** — `gaps` (+ optional `stats.gapSeconds`) for AI / History.
2. **Computed** — keep per-second `signalQuality` (+ sticky semantics in live BandCache). Do not copy every second into metadata.
3. **Raw** — continues to store samples while the device streams, including low-quality epochs. Disconnect simply yields silence (no packets). Optional later: raw index hints via the same interval list (byte offsets are a separate PR; metadata times are enough for v6 draft).

**Confirm from code:** raw does **not** drop unusable-quality samples; BandCache sticky is live-only. Computed is where holds/gaps matter most for charts; metadata gets the compact timeline for agents.

---

## Feedback extension (brief)

Same base. When `kind == "feedback"`, attach:

```json
"feedback": {
  "protocol": "drowsiness",
  "protocolVersion": "1",
  "protocolJson": { },
  "sound": "Ambient Drone",
  "feedbackSound": "bowlChimes",
  "calibration": { },
  "sessionSettings": { },
  "drowsiness": { },
  "music": { },
  "gestures": [{ "type": "doubleBlink", "at": 45 }],
  "training": {
    "pctInTarget": 62.0,
    "stillnessPct": 71.0,
    "avgAlphaRel": 0.42,
    "guardrailWarnCount": 3,
    "avgSleepDir": 0.34
  }
}
```

Migrate flat `SessionMetadata` fields into nested `device` / `streams` / `stats` / `feedback` — do not keep a second root schema. Full feedback redesign is out of scope for this file; enough that agents do not invent a parallel tree.

Shared physiological aggregates stay in base `stats` (HR, SpO₂, movement, quality, battery, experimental bands). Training-only scalars stay under `feedback.training` (or equivalent).

---

## Container clean cut (when implementing)

Not coded in this draft; checklist for the implementation PR:

- New magic `NFED6\0`, version byte **6** (header size policy: follow a deliberate format PR — do not silently grow past 68 without decision).
- **Delete** v5 dual-dialect metadata readers, "accept both shapes", and obsolete comments in the same PR.
- One writer path for base metadata; feedback adds `feedback` object.
- Update `README_feedback_format.md` + this contract status → Implemented in the same change.
- Sqlite: keep reading `kind`; bump `format_version` to 6; promote only the small agreed scalar set.
- Computed field set: keep frozen unless a separate format PR adds columns; recordings still write zeroed guard/feedback keys.

---

## Agent rules / musts

1. Read **this file** before changing metadata writers, v6 container bytes, or session/recording unify work.
2. **No v5 compat shims.** Clean cut only.
3. Implementing agents update `README_feedback_format.md` (and mark this contract Implemented) in the **same** PR.
4. Do not stuff 1 Hz series into metadata; do not invent vague band "spread" names.
5. Do not unify History UI chrome as a side effect of this format work.
6. Deviations need a written why before merge.

---

## Leftovers / open (not blocking this draft)

- Exact named-band formulas (experimental until product locks them).
- Whether `% overshoot` / overshoot intervals are worth persisting later (paint-time today; **not** a `gaps.event` until defined — see Gaps model).
- Per-record length prefix / Athena tag 11 (separate format PRs).
- Whether feedback pause should stop the computed sampler (today it does not until `end()`). Pause **does** get a `gaps` entry with `event: "pause"` when support lands.
