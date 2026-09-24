# File format v6 — unified metadata (draft)

| Field | Value |
|---|---|
| Status | **Draft** (writers/readers not implemented). **Annotations model = LOCKED.** **Base metadata vocabulary = LOCKED** (see Locked vocabulary). |
| Scope | Unify recording + feedback **metadata JSON**; prepare a **v6 clean cut** (container magic/version + writers/readers). |
| Not this | Implement Rust/Dart writers yet; rename Dart/Rust identifiers yet; Athena tag 11; History UI chrome; pipeline Key Decisions. |
| Supersedes (when landed) | Dual dialects in [session-format-contract.md](session-format-contract.md) § Metadata; [../TODO/session_vs_recording_metadata.md](../TODO/session_vs_recording_metadata.md). |
| Human layout (today) | [../../README_feedback_format.md](../../README_feedback_format.md) — update **in the same PR** that implements v6. |
| History cache | [../../README_history_cache.md](../../README_history_cache.md) — promote a small scalar set into sqlite later. |

Agents: adhere to **Design rules** and **Locked vocabulary** below. Inventory is from code (cited), not guesswork. JSON keys in this contract are the **source of truth** — prefer them when implementing writers/readers and when renaming Dart/Rust identifiers in a later PR; do not invent synonyms.

---

## Design rules (must adhere)

1. **Base names and objects on EDF / standard EEG recording formats** (EDF+, BIDS-EEG, common annotation practice). Do not reinvent what those already have, except when they don’t fit our product (document why).
2. **One base schema for both kinds.** Identity + `device` + `streams` + `stats` (+ quality/`annotations`) always present. Optional top-level `feedback` object **only** when `kind == "feedback"`; omit (or null) for recordings.
3. **Two layers of stats.** (a) **Computed 1 Hz** — charts / AI time series (`ComputedFrame`). (b) **Session summary** — scalars/short structs on metadata, computed at assemble/save (later: a small set as sqlite columns).
4. **Do not duplicate time series into metadata.** Metadata = scalars + short structs + compact interval lists. Computed = second-by-second.
5. **Band aggregates are named metrics** (e.g. mean α, α/θ, frontal–temporal α asymmetry, cross-channel α variance). Never vague "spread".
6. **Recordings keep zeroed `guardrail` / `feedback` on computed frames** if charts expect keys. Session-level top-level `feedback` object is **absent** on recordings.
7. **No backward compatibility with v5.** Clean cut: new magic/version (`NFED6` / `formatVersion: 6`), delete dual-dialect readers, dead comments, and leftover "accept both shapes" code **in the same effort**.
8. **Collect all useful + cheap session stats at save.** Promote a small set into sqlite later. Mark uncertain metrics `experimental: true` or nest under `stats.experimental` (may be removed if unused).

Also:

- Every file carries explicit `kind`, `formatVersion`, `appVersion`.
- Shared nested `stats` for both kinds (feedback-only reward/guard scalars live under `feedback` or under `stats` only when meaningful for both — prefer `feedback.*` for training-only).
- Fit / usable-signal summary and battery start/end when cheap.
- **Gestures:** instant user-interaction events live in root `annotations[]` (same timeline as pause / bad_quality / disconnect). `streams.gestures` remains an enablement stub (`enabled: false`) until a raw gesture stream exists — not a duplicate event list. Do not invent a raw tag without a format PR.

---

## Alignment scorecard vs EDF+/BIDS

Honest 1–10 match of v6 names/shapes to EDF+, BIDS-EEG, and common annotation practice. **better / equal / worse** is relative to those standards for *that* metadata area — inventing where they have no analogue counts as equal/better for the app, not as pretending EDF has it.

| Area | Score | Overall | Why (one line) |
|---|---:|---|---|
| Identity / timing (`startedAt`, `durationS`, …) | 7 | **equal** | `startedAt` / `durationS` map cleanly to EDF start + BIDS `RecordingDuration`; we invent `kind` / `formatVersion` / `appVersion` / `savedAt` / `elapsedSeconds` (no EDF analogue — better for app); **weaker** — no Patient ID / sex / birthdate fields EDF carries. |
| Device / channels | 7 | **equal** | Nested `device` + `channelLabels` ≈ EDF labels / BIDS `channels.tsv` / `ManufacturersModelName`; **weaker** — no separate Manufacturer, `channelCount` is generic not `EEGChannelCount`; stream key `spo2` (SpO₂) maps to EDF label `SaO2` on export. |
| Streams / sampling rates | 6 | **better for app** | `rateHz` ≈ BIDS `SamplingFrequency`; the ten-key `streams` enablement map has **no EDF analogue** (equal/better for app product config). |
| Annotations (onset/duration/type + gesture + gap) | 9 | **better** | Locks to EDF+ TAL / BIDS `events.tsv` nominators; unified quality + gesture timeline matches real EDF+ practice; `bad_quality` MNE-friendly. |
| Session stats aggregates | 6 | **better for app** | Nested `stats` (HR/SpO₂/quality/battery/experimental) — **no EDF metadata analogue** (closest: analysis-result files / BIDS derivatives); correct invent for History/AI. |
| Feedback extension (protocol, calibration, music) | 8 | **better for app** | Neurofeedback-specific; **no EDF/BIDS analogue** (protocol loosely ↔ `TaskName`); invent is documented and scoped under `feedback` only. |
| **Overall composite** | **7** | **equal → better** | Strong on annotations + timing; honest invent for `stats` / `streams` / `kind` / `feedback`; remaining gaps: Patient demographics; PascalCase sidecar keys and EDF `SaO2` label map on **export** (JSON keeps `spo2`). |

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

**Not in recording metadata today:** any `stats`, quality/`annotations`, battery, gestures list, protocol/calibration/music.

#### Feedback metadata JSON (`SessionMetadata`) — flat dialect

Written by `buildSessionMetadata()`:

- Timing / notes: `protocol`, `durationMinutes`, `elapsedSeconds`, `durationS`, `sound`, `savedAt`, `startedAt`, `notes`, `sessionId`
- Flat device: `deviceName`, `deviceModel`, `deviceId` (not nested `device`)
- `recordedChannels`, `recordedData` (stream name list)
- `gestures[]` (`type`, `at` seconds) when markers enabled — **v6:** fold into root `annotations[]` (see Annotations model); do not keep a parallel `feedback.gestures` list
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
| Compact `annotations` timeline | Single `{onset,duration,type}` list for pause / bad_quality / disconnect **and** gesture instants (`duration: 0`) (see Annotations model) | no; list is canonical, `stats.annotationSeconds` optional |
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
streams:  { ten keys… }   // gestures enablement stub only; markers → annotations
stats:    { … aggregates; annotationSeconds?: { pause, bad_quality, disconnect }; experimental?: { … } }
annotations: [ { onset, duration, type }, … ]   // unified timeline: quality intervals + gesture instants
feedback: { … }   // ONLY when kind == "feedback"; NO gestures[] list
```

### Example — `kind: "recording"`

Uses **Locked vocabulary** keys (no synonyms).

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
    "annotationSeconds": { "pause": 10.0, "bad_quality": 15.0, "disconnect": 8.0 },
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
  "annotations": [
    { "onset": 45.0, "duration": 0, "type": "double_blink" },
    { "onset": 120.0, "duration": 15.0, "type": "bad_quality" },
    { "onset": 200.0, "duration": 10.0, "type": "pause" },
    { "onset": 312.0, "duration": 0, "type": "double_jaw_clench" },
    { "onset": 400.0, "duration": 8.0, "type": "disconnect" }
  ]
}
```

Notes:

- Omit top-level `feedback` on recordings.
- Root `annotations` is the **canonical** timeline (quality/pause/disconnect **and** gesture / interaction events). Optional `stats.annotationSeconds` is derived from interval types only (sum of `duration` per `type` for types with `duration > 0`); never a second source of truth. Instant gestures (`duration: 0`) do not contribute seconds.
- `annotations` must stay compact (merge adjacent same-`type` interval runs). Instant events are not merged across time. Not a 1 Hz dump.
- `streams.gestures.enabled` remains false until a real raw gesture stream exists. Gesture **markers** are rows in `annotations[]` — **not** a parallel `feedback.gestures` array (single source of truth).

---

## Annotations model — **LOCKED**

> **LOCKED.** Not draft-open. Shape `{ onset, duration, type }`, interval types `pause` | `bad_quality` | `disconnect`, gesture types snake_case with `duration: 0` for instants, **single source of truth** at root `annotations[]`. Do not reopen without a format PR.

**Decision:** one extensible root array `annotations[]` of `{ onset, duration, type }` objects. **Not** three parallel top-level bags `paused{}` / `unusable{}` / `disconnected{}` (anti-pattern — rejected as the primary model). **Not** `gaps` as the root key (jargon; does not map to EDF+/BIDS). **Not** a separate `feedback.gestures[]` list (duplicate timeline — rejected; see Gestures / interactions).

### Canonical shape

```json
"annotations": [
  { "onset": 45.0, "duration": 0, "type": "double_blink" },
  { "onset": 120.0, "duration": 15.0, "type": "bad_quality" },
  { "onset": 200.0, "duration": 10.0, "type": "pause" },
  { "onset": 312.0, "duration": 0, "type": "double_jaw_clench" },
  { "onset": 400.0, "duration": 8.0, "type": "disconnect" }
]
```

Field names: camelCase JSON style of neurofeed. Interval keys intentionally match EDF+/BIDS nominators (`onset`, `duration`) so they are single-token camelCase already. `type` values are **snake_case** strings (quality + gesture alike).

### Locked names

| Role | Locked name | Rejected / why |
|---|---|---|
| Root array | `annotations` | `gaps` (app jargon); `events` (BIDS file name — keep for export, not JSON root; overlaps task/gesture language); `segments` / `bad_segments` (BrainVision-ish but implies only rejectable spans; pause is intentional) |
| Interval start | `onset` | `from` / `start` / `at` — not EDF+/BIDS; v5 gesture JSON used `at` — migrate to `onset` |
| Interval length | `duration` | `to` / `end` — EDF+ TAL and BIDS `events.tsv` both use duration, not exclusive end |
| Discriminator | `type` | `event` (vague; clashes with “events file”); `label` (EDF free text is the *value*); `trial_type` (BIDS task-condition column — wrong semantic for quality/pause; OK as **export** column) |
| User pause | `pause` | Keep; no universal EDF string. EEGLAB `boundary` / BrainVision `New Segment` mean *discontinuity after cut or resume* — different product meaning |
| Low pad quality | `bad_quality` | `unusable` (neurofeed-only); `artifact` (usually blink/muscle); bare `BAD` (MNE convention is a *prefix*). Value **starts with `bad`** so MNE `reject_by_annotation` works if exported as description |
| BLE / link loss | `disconnect` | `disconnected` (adjective; Muse sample string “Disconnected”); `signal_lost` (clearer clinically but farther from product `FeedbackInterruptKind.disconnect`) |
| Double blink | `double_blink` | v5 `doubleBlink` camelCase — snake_case to match other `type` tokens; not EDF standard text (EDF has no blink token; free UTF-8 OK) |
| Double jaw clench | `double_jaw_clench` | v5 `doubleClench` — spell out *jaw* (product/trust UI already says Jaw); `jaw_clench` reserved if single-clench detection is added later |
| Eye up / down | `eye_up` / `eye_down` | v5 `eyeUp` / `eyeDown` — snake_case |

### Gestures / interactions in `annotations` (locked)

**A) Unified timeline — YES.** Root `annotations[]` holds:

- Interval quality / session control: `pause` | `bad_quality` | `disconnect`
- Instant user-interaction / gesture events: `double_blink` | `double_jaw_clench` | `eye_up` | `eye_down` (extensible)

This matches EDF+ practice: one Annotations signal holds lights on/off, sleep stages, stimuli, responses, technician notes, button presses, and free-text events in the same TAL stream ([EDF+ §2.2](https://www.edfplus.info/specs/edfplus.html), [standard texts](https://www.edfplus.info/specs/edftexts.html); PhysioNet ERP-BCI / Sleep-EDF examples).

**Instant events — `duration: 0` (locked).** Always include `duration` (never omit, never `null`):

- BIDS `events.tsv` requires `duration`; **zero** means an impulse / instantaneous event.
- EDF+ TAL allows *omitting* Duration when irrelevant; exporters may drop the `\x15Duration` segment when `duration == 0`.
- One JSON shape for all rows keeps parsers simple.

**B) Single source of truth — annotations only.** Do **not** also store a full `feedback.gestures[]` array of `{type, at}`. Optional feedback-only extras (protocol, training scalars, music, calibration) stay under `feedback.*`. If a UI needs a gesture count, derive it by filtering `annotations` where `type` ∈ gesture set, or add a cheap scalar later under `feedback.training` — never a second event list.

`streams.gestures` remains `{ enabled, rateHz }` enablement for a future raw stream; it is **not** the marker list.

### What EDF+ annotations typically hold (research summary)

EDF+ stores arbitrary UTF-8 annotation texts in TALs (`Onset` [`\x15` `Duration`] `\x14` text… `\x00`). Common contents:

| Category | Examples (EDF standard texts or practice) | neurofeed analogue |
|---|---|---|
| Time-keeping | Empty first TAL per data record (`+onset\x14\x14\x00`) | Container only — **not** rows in `annotations[]` |
| Recording bounds | `Recording starts`, `Recording ends` | Implied by file; optional later |
| Lights / environment | `Lights off`, `Lights on` | Free-text / future `type` if product needs |
| Sleep staging | `Sleep stage W/N1/N2/N3/R/…` (duration required) | Out of scope for monitor/feedback v6 |
| Respiratory / cardiac / movement scoring | `Apnea`, `Hypopnea`, `Limb movement`, `EEG arousal`, `Desaturation`, … | Out of scope |
| Stimuli / responses / EP | Unique repeated texts e.g. `Stimulus click…`, `Response…`, pre-stimulus beeps (auditory EP example) | Gesture / interaction `type`s |
| Technician / free notes | Turning in bed, door close, arbitrary UTF-8 | `notes` is **file-level**; per-time notes could be future `type: "note"` + text field (not v6) |
| Routine EEG events | `Eyes Closed`, `Hyperventilation` | Closest to our blink/eye gestures |
| Button / marker | EDF Event signal / marker channel; PhysioNet button presses | Gestures as instant annotations |
| Bad / rejectable spans | (free text; MNE uses `bad*` descriptions) | `bad_quality` |
| Acquisition gaps | Discontinuous EDF+D + timekeeping TALs | `disconnect` / `pause` as product intervals on a continuous timeline |

**Yes — blink / jaw-clench belong in the same `annotations` array.** Shape: `{ "onset": <seconds>, "duration": 0, "type": "double_blink" }` (etc.). Export to EDF+ as TAL text = `type`; to BIDS as `onset`/`duration`/`trial_type`.

### Rules

1. **Single array** of `{ onset, duration, type }`. Extend later by adding new `type` strings — no new root keys.
2. **`type` enum (initial):**
   - Intervals: `pause` | `bad_quality` | `disconnect`
   - Instants (`duration: 0`): `double_blink` | `double_jaw_clench` | `eye_up` | `eye_down`
   - Do **not** invent `overshoot` annotations in metadata until overshoot is product-defined as a persisted interval. Overshoot today is paint-only / experimental on Monitor Bands; sticky bad pads are already covered by quality-driven `bad_quality`.
3. **Times:** `onset` and `duration` are seconds from capture start (same clock as computed `t`). Matches EDF+ TAL onset (seconds from file startdate/time) and BIDS `events.tsv` onset/duration. `duration` is always present; use `0` for instants.
4. **Merge** adjacent same-`type` **interval** runs (`duration > 0`); keep the list compact. Do not merge distinct instant events. Not a 1 Hz dump.
5. **Reject** parallel top-level `paused` / `unusable` / `disconnected` objects and parallel `feedback.gestures[]` as primary models. Readers and writers use `annotations` only.
6. **Product → type mapping:**
   - Feedback `badSignal` interrupt → `type: "bad_quality"`
   - User pause → `type: "pause"`
   - BLE loss / disconnect → `type: "disconnect"`
   - v5 `GestureType.doubleBlink` → `double_blink`
   - v5 `GestureType.doubleClench` → `double_jaw_clench`
   - v5 `GestureType.eyeUp` / `eyeDown` → `eye_up` / `eye_down`

### Optional summary nesting

Canonical source: `annotations`. Optional derived counts live under **`stats.annotationSeconds`** (seconds-by-type for interval types only), e.g. `{ "pause": 10.0, "bad_quality": 15.0, "disconnect": 8.0 }`. Instant types are omitted from that map (or counted under a future `stats.annotationCounts` if needed). Do not use a separate root summary object; keep aggregates under `stats`.

### EDF+ / BIDS / MNE export mapping

When exporting (see `.ai/export.md` EDF+ path), map as follows:

| neurofeed JSON | EDF+ TAL | BIDS `*_events.tsv` | MNE `Annotations` |
|---|---|---|---|
| `onset` | TAL Onset (`+{onset}` seconds from file start) | `onset` | `onset` |
| `duration` (> 0) | TAL Duration (unsigned seconds; byte `0x15` prefix) | `duration` | `duration` |
| `duration` (== 0) | Omit Duration segment (EDF+ allows skip) **or** encode `0` | `duration` = `0` | `duration` = `0` |
| `type` | annotation text (UTF-8 between `0x14` separators) | `trial_type` (or a sidecared custom column if preferred) | `description` |
| `pause` | text `pause` | `trial_type=pause` | `description="pause"` |
| `bad_quality` | text `bad_quality` | `trial_type=bad_quality` | `description="bad_quality"` (rejected when `reject_by_annotation=True`) |
| `disconnect` | text `disconnect` | `trial_type=disconnect` | `description="disconnect"`; treat like acquisition skip / discontinuity |
| `double_blink` etc. | text = `type` string | `trial_type` = `type` | `description` = `type` (not `bad*` — do not auto-reject) |

EDF+ timekeeping TALs (empty text, per-data-record start) are **container** mechanics — not rows in `annotations[]`.

## Locked vocabulary (base metadata JSON keys)

> **LOCKED.** camelCase JSON keys below are the contract source of truth. Prefer them in writers/readers and when renaming Dart/Rust identifiers in a later PR. Do **not** invent synonyms (`sfreq`, `ch_names`, `SaO2` as a JSON key, PascalCase BIDS sidecar spellings, parallel gesture lists, …). Map to EDF+/BIDS/MNE names on **export**, not inside neurofeed JSON. snake_case is reserved for `annotations[].type` values (and similar enums).

Discipline: rename only when EDF / BIDS / common EEG has a **clearly better** term that does not break product meaning. Otherwise keep.

### Locked vocabulary table — old → new → standard basis

| Old (v5 / draft candidate) | New (locked JSON) | Standard basis / rationale |
|---|---|---|
| `spo2` / `SpO2` / `sao2` / `SaO2` | **`spo2`** | EDF+ standard signal text is **`SaO2`**; Muse measures **SpO₂** (pulse oximetry via PPG), not arterial SaO₂. Keep product-accurate `spo2` (consistent all-lowercase acronym camelCase). Export may label EDF `SaO2`. Reject `spO2` (ugly) and `sao2` (wrong physiology as JSON id). |
| `startedAt` | **`startedAt`** | EDF `startdate`+`starttime`; BIDS often `AcquisitionTime`. One ISO-8601 field beats EDF’s split. Keep. |
| `savedAt` | **`savedAt`** | No EDF/BIDS file-write timestamp analogue. Keep — assemble/save time. |
| `durationS` | **`durationS`** | BIDS `RecordingDuration` (seconds). Keep unit suffix; do **not** adopt PascalCase `recordingDuration`. |
| `elapsedSeconds` | **`elapsedSeconds`** | No direct EDF analogue (wall/session elapsed may differ from stored samples). Keep — product timing. |
| `channelLabels` / `ch_names` / electrode names | **`channelLabels`** | EDF signal **label**; BIDS `channels.tsv` `name`; MNE `ch_names`. Keep `channelLabels` (EDF “label” sense) as array on `device`. |
| `rateHz` / `sfreq` / `SamplingFrequency` | **`rateHz`** | BIDS `SamplingFrequency`; EDF samples/record ÷ duration. Keep unit-in-name; map on export. Reject `sfreq` (MNE-only jargon in product JSON). |
| `pulse` / HR / bpm / `heartRate` | **`pulse`** (stream) | Computed 1 Hz stream id; PPG-derived pulse rate. Keep to match `ComputedFrame`. Session aggregates use **`stats.hr`** `{mean,min,max}` (clinical HR summary — no EDF metadata field). |
| `peakAlpha` | **`peakAlpha`** | No EDF/BIDS analogue. Keep — matches computed frame / stream enablement. |
| `device` (+ `name`,`id`,`firmware`,`model`,`sensors`,`channelCount`,`channelLabels`) | **`device`** nest | EDF equipment subfield; BIDS `Manufacturer*` / `ManufacturersModelName`. Keep nest; map manufacturer fields on export. No Patient ID/sex/birthdate in v6 (documented gap). |
| `notes` / Comments | **`notes`** | EDF free-text / technician notes live in Annotations; BIDS `Comments` is dataset-level. Keep file-level `notes` (product copy). |
| `annotations` | **`annotations`** | EDF+ Annotations / TAL; BIDS `events.tsv`. **Already LOCKED** — see Annotations model. |
| `annotations[]` shape | **`{onset,duration,type}`** | EDF+ Onset/Duration; BIDS required `onset`/`duration` (0 = instant). Locked. |
| Gesture `type` strings (`doubleBlink`, …) | **`double_blink`**, **`double_jaw_clench`**, **`eye_up`**, **`eye_down`** | snake_case locked; free UTF-8 TAL text / BIDS `trial_type` on export. |
| Interval `type` strings | **`pause`**, **`bad_quality`**, **`disconnect`** | Locked; `bad_*` prefix is MNE-friendly. |
| `stats` (+ nested) | **`stats`** | No EDF metadata analogue (analysis / BIDS derivatives). Keep. Nested clarity locked below. |
| `feedback.gestures[]` / v5 `at` | **fold into `annotations[]`**; time key **`onset`** | Single SoT; v5 `at` → `onset`. |

### Nested `stats` field names (locked; no EDF analogue)

| Locked key | Meaning |
|---|---|
| `stats.hr` `{mean,min,max}` | Heart-rate summary from computed `pulse` |
| `stats.spo2` `{mean,min,max}` | SpO₂ summary from computed `spo2` |
| `stats.peakAlpha` `{meanHz,maxPowerHz,maxPower}` | Peak-alpha summary |
| `stats.movement` `{mean}` (+ optional stillness later) | Movement summary |
| `stats.quality` `{mean,pctGood,channelUsable}` | Pad / usable-signal summary |
| `stats.annotationSeconds` `{pause,bad_quality,disconnect}` | Derived seconds-by-type from interval annotations only |
| `stats.battery` `{startPct,endPct}` | Telemetry bookends when available |
| `stats.experimental` | Tunable / removable band aggregates |

### Also locked (identity / streams / feedback shells)

| Locked key | Notes |
|---|---|
| `formatVersion`, `appVersion`, `kind` | Container / app identity; `kind` = `recording` \| `feedback` |
| `streams` ten keys | `eeg`, `bands`, `pulse`, `spo2`, `movement`, `peakAlpha`, `imu`, `ppg`, `telemetry`, `gestures` — enablement `{enabled,rateHz}`; `gestures` stub only |
| `feedback` | Only when `kind=="feedback"`; no `gestures[]` list |

### Naming rationale (expanded)

Cited conventions that locked annotations **and** the vocabulary table above:

1. **EDF+ TALs** ([edfplus.info/specs/edfplus.html](https://www.edfplus.info/specs/edfplus.html)): annotations use **Onset** + optional **Duration** in seconds from recording startdate/time; free-text UTF-8 strings. Root concept = *annotations*, not “gaps”. Duration may be omitted in the wire TAL when irrelevant — our JSON still stores `duration: 0` for instants.
2. **EDF+ standard texts** ([edftexts.html](https://www.edfplus.info/specs/edftexts.html)): includes signal label **`SaO2`**; obligatory PSG strings; no standard blink/clench tokens — custom snake_case types export as TAL text. JSON stream id stays `spo2` (SpO₂).
3. **BIDS events** ([bids-specification — Events](https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html)): required **`onset`**, **`duration`** (zero = instantaneous); optional **`trial_type`**. EEG sidecars use PascalCase (`SamplingFrequency`, `RecordingDuration`, `ManufacturersModelName`) — map on **export**.
4. **BIDS EEG sidecar** ([electroencephalography](https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html)): equipment and sampling beside the recording; our nested `device` + `streams.*.rateHz` + `durationS` carry the same ideas under product camelCase.
5. **MNE-Python**: `mne.Annotations(onset, duration, description)`; rejection descriptions start with **`bad`** / `BAD`. Gesture descriptions must **not** start with `bad`.
6. **BrainVision Analyzer**: **Bad Interval** vs **New Segment** — informed `bad_quality` vs product `pause` / `disconnect` (do not overload EEGLAB `boundary`).
7. **EEGLAB**: `type: "boundary"` = discontinuity/cut — not user pause on a continuous timeline.
8. **Muse / LibMuse**: `addAnnotationString` free text — stable short tokens export cleanly.
9. **PhysioNet**: ERP-BCI / Sleep-EDF mix stimuli, responses, and stages in one annotation channel — gestures are peer rows beside quality intervals.
10. **JSON style:** metadata keys camelCase; annotation **values** snake_case.

Future agents: change locked names only with a format PR and an updated table. Prefer adding a new `annotations[].type` over renaming existing ones.

### Layers (unchanged intent)

1. **Metadata** — `annotations` (+ optional `stats.annotationSeconds`) for AI / History.
2. **Computed** — keep per-second `signalQuality` (+ sticky semantics in live BandCache) and per-second `gestures[]` string ids on the frame for charts. Do not copy every second into metadata; session marker list is `annotations` only.
3. **Raw** — continues to store samples while the device streams, including low-quality epochs. Disconnect simply yields silence (no packets). Optional later: raw index hints via the same interval list (byte offsets are a separate PR; metadata times are enough for v6 draft).

**Confirm from code:** raw does **not** drop unusable-quality samples; BandCache sticky is live-only. Computed is where holds / quality gaps matter most for charts; metadata gets the compact `annotations` timeline for agents. v5 `GestureMarker` / `feedback.gestures` → v6 `annotations` rows with `duration: 0`.

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

**Gestures:** do **not** put `feedback.gestures[]` here. Double blink / jaw clench / eye markers are rows in root `annotations[]` with `duration: 0` (see Annotations model). v5 `gestures: [{ "type": "doubleBlink", "at": 45 }]` migrates to `{ "onset": 45.0, "duration": 0, "type": "double_blink" }` on the base object.

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
7. **Locked JSON keys are the source of truth.** When implementing writers/readers, and when renaming Dart/Rust identifiers in a later PR, prefer the keys in **Locked vocabulary** and the **Annotations model — LOCKED** section. Do not invent synonyms (`sfreq`, `ch_names`, `sao2` as a JSON key, `SamplingFrequency` in neurofeed JSON, parallel `feedback.gestures[]`, …). Map EDF+/BIDS/MNE spellings on export only. Do **not** rename app source in the same change as a contract-only edit unless the task says so.
8. **Annotations model is LOCKED** — do not reopen shape, nominators, or initial `type` strings without a format PR.

---

## Leftovers / open (not blocking; vocabulary + annotations locked)

- Exact named-band formulas (experimental until product locks them).
- Whether `% overshoot` / overshoot intervals are worth persisting later (paint-time today; **not** an `annotations.type` until defined — see Annotations model).
- Per-record length prefix / Athena tag 11 (separate format PRs).
- Whether feedback pause should stop the computed sampler (today it does not until `end()`). Pause **does** get an `annotations` entry with `type: "pause"` when support lands.
