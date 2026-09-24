# File format v6 — unified metadata (draft)

| Field | Value |
|---|---|
| Status | **Draft** (writers/readers not implemented). **Annotations model = LOCKED.** **Base metadata vocabulary = LOCKED** (see Locked vocabulary). **`subject` object = PREPARED** (anonymous-first; see Subject model). **Feedback extension = DRAFTED** (schema mostly locked; see Feedback extension + Open questions). |
| Scope | Unify recording + feedback **metadata JSON**; prepare a **v6 clean cut** (container magic/version + writers/readers). |
| Not this | Implement Rust/Dart writers yet; rename Dart/Rust identifiers yet; Athena tag 11; History UI chrome; pipeline Key Decisions. |
| Supersedes (when landed) | Dual dialects in [session-format-contract.md](session-format-contract.md) § Metadata; [../TODO/session_vs_recording_metadata.md](../TODO/session_vs_recording_metadata.md). |
| Human layout (today) | [../../README_feedback_format.md](../../README_feedback_format.md) — update **in the same PR** that implements v6. |
| History cache | [../../README_history_cache.md](../../README_history_cache.md) — promote a small scalar set into sqlite later. |

Agents: adhere to **Design rules** and **Locked vocabulary** below. Inventory is from code (cited), not guesswork. JSON keys in this contract are the **source of truth** — prefer them when implementing writers/readers and when renaming Dart/Rust identifiers in a later PR; do not invent synonyms.

---

## Design rules (must adhere)

1. **Base names and objects on EDF / standard EEG recording formats** (EDF+, BIDS-EEG, common annotation practice). Do not reinvent what those already have, except when they don’t fit our product (document why).
2. **One base schema for both kinds.** Identity + `subject` + `device` + `streams` + `stats` (+ quality/`annotations`) always present. Optional top-level `feedback` object **only** when `kind == "feedback"`; omit (or null) for recordings.
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
- **Subject (anonymous-first):** every file carries a nested root `subject` object (BIDS naming). Always include stable anonymous `subject.id`. Optional display `nickname` and voluntary demographics (`sex`, `ageAtRecording`, `meditationExperience`, …) are **omitted until the user provides them** — never invent placeholders that look like PII. File/session identity (`sessionId` when present) stays at **root**, not under `subject`. See **Subject model**.

---

## Alignment scorecard vs EDF+/BIDS

Honest 1–10 match of v6 names/shapes to EDF+, BIDS-EEG, and common annotation practice. **better / equal / worse** is relative to those standards for *that* metadata area — inventing where they have no analogue counts as equal/better for the app, not as pretending EDF has it.

| Area | Score | Overall | Why (one line) |
|---|---:|---|---|
| Identity / timing (`startedAt`, `durationS`, `subject`, …) | 8 | **equal → better** | `startedAt` / `durationS` map cleanly to EDF start + BIDS `RecordingDuration`; nested `subject.id` → EDF Local Patient Identification **code** / BIDS `participant_id` (anonymous-first); optional `sex` / `ageAtRecording` omit until collected (EDF sex/birthdate → `X` when unknown); `nickname` display-only (EDF **name** stays `X` unless user opts into export); invent `kind` / `formatVersion` / `appVersion` / `savedAt` / `elapsedSeconds` / root `sessionId` (file identity, not under `subject`). |
| Device / channels | 7 | **equal** | Nested `device` + `channelLabels` ≈ EDF labels / BIDS `channels.tsv` / `ManufacturersModelName`; **weaker** — no separate Manufacturer, `channelCount` is generic not `EEGChannelCount`; stream key `spo2` (SpO₂) maps to EDF label `SaO2` on export. |
| Streams / sampling rates | 6 | **better for app** | `rateHz` ≈ BIDS `SamplingFrequency`; the ten-key `streams` enablement map has **no EDF analogue** (equal/better for app product config). |
| Annotations (onset/duration/type + gesture + gap) | 9 | **better** | Locks to EDF+ TAL / BIDS `events.tsv` nominators; unified quality + gesture timeline matches real EDF+ practice; `bad_quality` MNE-friendly. |
| Session stats aggregates | 6 | **better for app** | Nested `stats` (HR/SpO₂/quality/battery/experimental) — **no EDF metadata analogue** (closest: analysis-result files / BIDS derivatives); correct invent for History/AI. |
| Feedback extension (protocol, calibration, music) | 8 | **better for app** | Neurofeedback-specific; **no EDF/BIDS analogue** (protocol loosely ↔ `TaskName`); invent is documented and scoped under `feedback` only. |
| **Overall composite** | **8** | **equal → better** | Strong on annotations + timing + anonymous `subject`; honest invent for `stats` / `streams` / `kind` / `feedback`; remaining gaps: PascalCase sidecar keys and EDF `SaO2` label map on **export** (JSON keeps `spo2`); voluntary demographics stay omit-until-collected (privacy). |

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
| Movement mean (+ optional `stillnessPct`) | From computed `movement`; **`stillnessPct` locked** under `stats.movement` | no |
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
identity: formatVersion, appVersion, kind, savedAt, startedAt, elapsedSeconds, durationS, notes, sessionId?
subject:  { id, nickname?, sex?, ageAtRecording?, meditationExperience?, … }  // anonymous-first; omit voluntary until collected
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
  "sessionId": "cap_20260924_102000_a1b2",
  "subject": {
    "id": "anon_a1b2c3d4e5f6",
    "nickname": "River"
  },
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
    "movement": { "mean": 0.018, "stillnessPct": 71.0 },
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
- Minimal anonymous `subject`: always `id`; optional `nickname` for UI. Do **not** invent `sex` / `ageAtRecording` / `meditationExperience` until the user volunteers them (omit keys). Root `sessionId` identifies **this capture/file**, not the person — do not nest it under `subject`.
- Root `annotations` is the **canonical** timeline (quality/pause/disconnect **and** gesture / interaction events). Optional `stats.annotationSeconds` is derived from interval types only (sum of `duration` per `type` for types with `duration > 0`); never a second source of truth. Instant gestures (`duration: 0`) do not contribute seconds.
- `annotations` must stay compact (merge adjacent same-`type` interval runs). Instant events are not merged across time. Not a 1 Hz dump.
- `streams.gestures.enabled` remains false until a real raw gesture stream exists. Gesture **markers** are rows in `annotations[]` — **not** a parallel `feedback.gestures` array (single source of truth).

---

## Subject model — **PREPARED** (anonymous-first)

> **PREPARED.** Root key `subject` and required anonymous `id` are locked naming. Voluntary demographic / experience fields are **schema-ready but omitted until collected**. Do not reopen the root key without a format PR; adding a new optional voluntary field is OK with a table update.

**Decision:** nested root object **`subject`** (BIDS `participants.tsv` / `participant_id` terminology). Prefer `subject` over EDF’s packed “Local Patient Identification” string as the JSON shape; map components to EDF on **export**. Do **not** use a parallel root `patient` key.

### Privacy rule (locked intent)

1. **Anonymous by default.** Never write real legal name, full birthdate, national ID, email, or other direct PII into metadata unless the product later adds an explicit user opt-in for that field.
2. **`subject.id` is a stable anonymous code** (app-generated), not a real-world name. Suitable as EDF patient **code** and as the bare token behind BIDS `participant_id` (`sub-{id}` on export).
3. **`nickname` is display-only.** Shown in History / UI. On EDF export, Local Patient Identification **name** subfield stays **`X`** unless the user has opted to export nickname as the name token. Never treat nickname as a verified identity.
4. **Omit unknown voluntary fields** — do not write `null`, empty string, or `"X"` placeholders into JSON for fields the user never provided. EDF export fills unknown subfields with `X` at export time.
5. **Prefer age-at-recording over birthdate** for any age-related voluntary data (BIDS `age`; privacy: cap at 89 per BIDS). Full `dd-MMM-yyyy` birthdate is EDF’s native form — we do **not** store it by default.
6. **`sessionId` is file identity**, not subject identity. When present (feedback today; recordings when capture ids exist), keep it at **root** beside timing fields. Same person (`subject.id`) may have many `sessionId`s.

### Canonical minimal shape (always)

```json
"subject": {
  "id": "anon_a1b2c3d4e5f6",
  "nickname": "River"
}
```

`nickname` itself is optional — if the user never set a display name, omit it:

```json
"subject": {
  "id": "anon_a1b2c3d4e5f6"
}
```

### Optional voluntary fields (omit until collected)

| Field | Type | When | Notes |
|---|---|---|---|
| `nickname` | string | User set a display name | UI only; EDF name → `X` unless export opt-in |
| `sex` | `"F"` \| `"M"` \| `"X"` \| `"other"` | User volunteered | EDF Local Patient ID uses `F`/`M`/`X` only — map `"other"` → `X` on EDF export; BIDS `sex` accepts male/female/other (map on export) |
| `ageAtRecording` | number (years) | User volunteered age (or derived with consent) | BIDS `age`; prefer over DOB. Cap at 89 for privacy (BIDS). EDF **birthdate** subfield stays `X` unless a future opt-in stores DOB |
| `yearOfBirth` | integer | Only if product later collects year (not full DOB) | Still weaker PII than full birthdate; prefer `ageAtRecording`. Omit by default |
| `meditationExperience` | string or short struct | User volunteered | Neurofeed-specific; no EDF/BIDS column — BIDS extra column / sidecar on export if needed. Nest under `subject` (not `stats.experimental`) so it stays person-level |

No other PII columns in v6. Future voluntary fields require a format PR + table row.

### EDF+ Local Patient Identification ↔ `subject`

EDF+ packs an 80-byte ASCII field as space-separated subfields ([EDF+ additional specs](https://www.edfplus.info/specs/edfplus.html)):

`code` `sex` `birthdate` `name` [optional additional…]

Unknown / anonymized subfields are a single **`X`**. Spaces inside a subfield become underscores.

| EDF+ subfield | neurofeed JSON | Default anonymous export | Notes |
|---|---|---|---|
| **code** (hospital / admin code) | `subject.id` | `subject.id` (spaces → `_`) | Stable anonymous subject code |
| **sex** (`F` / `M` / `X`) | `subject.sex` | `X` if omitted | `"other"` → `X` on EDF wire |
| **birthdate** (`dd-MMM-yyyy`) | *(none by default)*; optional future DOB / derive from `yearOfBirth` only with opt-in | `X` | Prefer `ageAtRecording` in JSON; do not invent a fake birthdate from age |
| **name** | `subject.nickname` (display) | `X` | Export nickname as name **only** with explicit user opt-in; otherwise always `X` |
| additional subfields | optional later | — | e.g. experience tokens — only if export needs them |

Example anonymous EDF patient field: `{id} X X X` (e.g. `anon_a1b2c3d4e5f6 X X X`).

EDF+ **Local Recording Identification** (Startdate / investigation code / technician / equipment) maps from **file** identity + `device` + `startedAt` — **not** from `subject`. Investigation / EEG number ≈ root `sessionId` when present.

### BIDS `participants.tsv` ↔ `subject`

| BIDS column | neurofeed JSON | Notes |
|---|---|---|
| `participant_id` (REQUIRED) | `subject.id` | Export as `sub-{id}` (BIDS entity); strip or normalize `anon_` prefix policy in the export PR |
| `age` (RECOMMENDED) | `subject.ageAtRecording` | Omit column/value if unknown; cap 89 |
| `sex` (RECOMMENDED) | `subject.sex` | Map `F`/`M`/`other` ↔ BIDS allowed spellings on export |
| `handedness` etc. | *(not in v6)* | Add only with a format PR |
| custom columns | `meditationExperience` etc. | Allowed as extra TSV columns + `participants.json` sidecar defs |

One row per `subject.id` across a BIDS dataset; many recordings/sessions share that participant.

### Locked names (subject)

| Role | Locked name | Rejected / why |
|---|---|---|
| Root object | `subject` | `patient` (EDF wording — keep for export docs only); `participant` (BIDS file jargon; `subject` matches BIDS `sub-` entity + common EEG code) |
| Anonymous code | `subject.id` | `patientId` / `patientCode` / `userId` — `userId` collides with accounts; EDF “code” becomes export mapping, not JSON key |
| Display name | `subject.nickname` | `name` / `patientName` — too easy to confuse with legal name / EDF name subfield |
| Sex | `subject.sex` | Keep EDF-friendly tokens in JSON (`F`/`M`/`X`) plus `"other"`; map to BIDS on export |
| Age | `subject.ageAtRecording` | `age` alone is ambiguous (now vs at recording); `birthdate` / `dateOfBirth` rejected as default (PII) |
| Experience | `subject.meditationExperience` | Product-specific voluntary; not under `stats` |
| Session / capture id | root `sessionId` | Not under `subject` — file identity (EDF recording / investigation code) |

### Rules

1. Always write `subject` with at least `id` for new v6 files.
2. Omit voluntary keys until collected (no null stubs).
3. Do not put `sessionId` inside `subject`.
4. Do not put device fields inside `subject` (device stays nested `device`).
5. Export mappers own EDF `X` padding and BIDS `sub-` prefix — JSON stays product camelCase.

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
| `device` (+ `name`,`id`,`firmware`,`model`,`sensors`,`channelCount`,`channelLabels`) | **`device`** nest | EDF equipment subfield; BIDS `Manufacturer*` / `ManufacturersModelName`. Keep nest; map manufacturer fields on export. Person demographics live under **`subject`**, not `device`. |
| `notes` / Comments | **`notes`** | EDF free-text / technician notes live in Annotations; BIDS `Comments` is dataset-level. Keep file-level `notes` (product copy). |
| *(none / flat userId)* | **`subject`** nest | BIDS participant / `participants.tsv`; EDF Local Patient Identification unpacked. **PREPARED** — see Subject model. |
| `userId` / patient code / hospital code | **`subject.id`** | EDF patient **code**; BIDS `participant_id` (`sub-{id}` on export). Anonymous stable id — not legal name. |
| display name / patient name | **`subject.nickname`** (optional) | UI only; EDF **name** subfield → `X` unless export opt-in. Reject JSON key `name` on subject. |
| sex / gender | **`subject.sex`** (optional, omit until collected) | EDF `F`/`M`/`X`; add `"other"` for product; map to BIDS on export. |
| age / DOB | **`subject.ageAtRecording`** (optional) | BIDS `age`; prefer over birthdate. EDF birthdate → `X` by default. Reject default `birthdate` / `dateOfBirth`. |
| meditation / practice history | **`subject.meditationExperience`** (optional) | Voluntary; no EDF field. BIDS extra column on export if needed. |
| `sessionId` (feedback dialect) | **`sessionId`** (root, optional) | File/capture identity — EDF Local **Recording** Identification investigation code, **not** patient code. Do not nest under `subject`. |
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
| `stats.movement` `{mean,stillnessPct?}` | Movement summary; optional `stillnessPct` (% seconds below stillness gate — shared physiology, not training-only) |
| `stats.quality` `{mean,pctGood,channelUsable}` | Pad / usable-signal summary |
| `stats.annotationSeconds` `{pause,bad_quality,disconnect}` | Derived seconds-by-type from interval annotations only |
| `stats.battery` `{startPct,endPct}` | Telemetry bookends when available |
| `stats.experimental` | Tunable / removable band aggregates |

### Also locked (identity / subject / streams / feedback shells)

| Locked key | Notes |
|---|---|
| `formatVersion`, `appVersion`, `kind` | Container / app identity; `kind` = `recording` \| `feedback` |
| `sessionId` | Optional root file/capture id (feedback today); **not** under `subject` |
| `subject` (+ `id` required; voluntary fields omit-until-collected) | Anonymous-first person object — see Subject model |
| `streams` ten keys | `eeg`, `bands`, `pulse`, `spo2`, `movement`, `peakAlpha`, `imu`, `ppg`, `telemetry`, `gestures` — enablement `{enabled,rateHz}`; `gestures` stub only |
| `feedback` | Only when `kind=="feedback"`; no `gestures[]` list |

### Naming rationale (expanded)

Cited conventions that locked annotations **and** the vocabulary table above:

1. **EDF+ TALs** ([edfplus.info/specs/edfplus.html](https://www.edfplus.info/specs/edfplus.html)): annotations use **Onset** + optional **Duration** in seconds from recording startdate/time; free-text UTF-8 strings. Root concept = *annotations*, not “gaps”. Duration may be omitted in the wire TAL when irrelevant — our JSON still stores `duration: 0` for instants.
2. **EDF+ standard texts** ([edftexts.html](https://www.edfplus.info/specs/edftexts.html)): includes signal label **`SaO2`**; obligatory PSG strings; no standard blink/clench tokens — custom snake_case types export as TAL text. JSON stream id stays `spo2` (SpO₂).
3. **BIDS events** ([bids-specification — Events](https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html)): required **`onset`**, **`duration`** (zero = instantaneous); optional **`trial_type`**. EEG sidecars use PascalCase (`SamplingFrequency`, `RecordingDuration`, `ManufacturersModelName`) — map on **export**.
4. **BIDS EEG sidecar** ([electroencephalography](https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html)): equipment and sampling beside the recording; our nested `device` + `streams.*.rateHz` + `durationS` carry the same ideas under product camelCase.
4b. **EDF+ Local Patient Identification** ([edfplus.info](https://www.edfplus.info/specs/edfplus.html)): packed `code sex birthdate name` (unknown → `X`). neurofeed keeps a nested `subject` object and packs this string on export — anonymous-first (`code` = `subject.id`, others `X` until volunteered).
4c. **BIDS `participants.tsv`** ([data summary files](https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html)): required `participant_id`; recommended `age`, `sex`. Maps from `subject.*`; age privacy cap 89.
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

## Feedback extension — **DRAFTED**

> **DRAFTED** (not fully LOCKED). Shape and field homes below are the working contract for implementers. Most nesting choices are decided; remaining product/schema choices are listed under **Open questions** at the end of this file. Do not invent a parallel root schema or a second gesture list.

**Rule:** when `kind == "feedback"`, attach a single top-level `feedback: { … }` object. Omit (or null) for `kind == "recording"`. Everything already covered by **base** (`subject`, `device`, `streams`, `stats`, `annotations`, identity/timing) stays **out** of `feedback` — no duplicates.

### Field classification (from `SessionMetadata` / `buildSessionMetadata`)

| Current field(s) | v6 home | Action |
|---|---|---|
| `savedAt`, `startedAt`, `elapsedSeconds`, `durationS`, `notes` | base identity | → base |
| `sessionId` | root `sessionId` | → base |
| `userId` | `subject.id` | → base (anonymous-first) |
| `deviceName` / `deviceModel` / `deviceId` | nested `device` | → base (`deviceModel` today often = firmware string; nested `device` carries both `model` + `firmware`) |
| `recordedChannels` | `device.channelLabels` | → base |
| `recordedData` | `streams` ten-key enablement | → base |
| `gestures[]` `{type,at}` | root `annotations[]` `{onset,duration:0,type}` | → annotations SoT; **drop** parallel list |
| `stats.peakAlphaFreq/Power`, flat `peakAlphaHz`/`peakAlphaPower`, `avgBpm`, `avgSpo2`, `avgMovement`, `stillnessPct` | `stats.peakAlpha` / `stats.hr` / `stats.spo2` / `stats.movement` | → base `stats` only |
| `signalQualityMean`, `pctQcOk` | `stats.quality.{mean,pctGood}` | → base |
| `protocol`, `protocolVersion`, `protocolJson` | `feedback.*` | → `feedback{}` |
| `durationMinutes` | `feedback.durationMinutes` | → `feedback{}` (planned length; **not** a duplicate of `durationS`) |
| `sound`, `feedbackSound` | `feedback.sound` / `feedback.feedbackSound` | → `feedback{}` |
| `metadataDescription` | `feedback.metadataDescription` | → `feedback{}` (protocol copy) |
| `calibration`, `calibrationProfile` | `feedback.calibration` (+ optional profile id/string) | → `feedback{}` |
| `drowsiness` | `feedback.drowsiness` (for now) | → `feedback{}` — see Open questions vs `protocolResults` |
| `music` | `feedback.music` | → `feedback{}` (shape keep as-is) |
| `sessionSettings` (+ optional `modelSnapshot`, `guardFeature`, `guardModel`) | `feedback.sessionSettings` | → `feedback{}` |
| Top-level `guardrailEngine` / `modelKind` / `modelSha256` / `feedbackEngine` | fold into `feedback.sessionSettings` / `modelSnapshot` | → `feedback{}`; **drop** flat root mirrors |
| `targetPct` / `pctInTarget`, `avgAlphaRel`, `guardrailWarnCount`, `avgSleepDir` | `feedback.training.*` | → `feedback{}` (training-only) |
| Parallel `feedback.gestures[]` | — | **Rejected** (annotations SoT) |
| `stillnessPct` under training | — | **Drop** — base `stats.movement.stillnessPct` only |

### Example — `kind: "feedback"` (base + `feedback` block)

Uses locked base vocabulary. `feedback` holds only what base does not.

```json
{
  "formatVersion": 6,
  "appVersion": "dev",
  "kind": "feedback",
  "savedAt": "2026-09-24T10:30:00.000Z",
  "startedAt": "2026-09-24T10:15:00.000Z",
  "elapsedSeconds": 900,
  "durationS": 900,
  "notes": "",
  "sessionId": "sess_20260924_101500_c3d4",
  "subject": {
    "id": "anon_a1b2c3d4e5f6",
    "nickname": "River"
  },
  "device": {
    "name": "Muse 2",
    "id": "AA:BB:CC:DD:EE:FF",
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
    "movement": { "mean": 0.018, "stillnessPct": 71.0 },
    "quality": {
      "mean": 86.4,
      "pctGood": 92.0,
      "channelUsable": { "TP9": 0.94, "AF7": 0.88, "AF8": 0.91, "TP10": 0.95 }
    },
    "annotationSeconds": { "pause": 10.0, "bad_quality": 15.0, "disconnect": 0.0 },
    "battery": { "startPct": 81.0, "endPct": 76.0 }
  },
  "annotations": [
    { "onset": 45.0, "duration": 0, "type": "double_blink" },
    { "onset": 120.0, "duration": 15.0, "type": "bad_quality" },
    { "onset": 200.0, "duration": 10.0, "type": "pause" },
    { "onset": 312.0, "duration": 0, "type": "double_jaw_clench" }
  ],
  "feedback": {
    "protocol": "drowsiness",
    "protocolVersion": "1",
    "protocolJson": {
      "id": "drowsiness",
      "version": 1,
      "reward": { "feature": "alpha_rel" },
      "guard": { "feature": "ai.drowsiness" }
    },
    "durationMinutes": 15,
    "sound": "Ambient Drone",
    "feedbackSound": "bowlChimes",
    "metadataDescription": "Eyes-closed alpha uptrain with drowsiness guard.",
    "calibrationProfile": "eyes-closed-01",
    "calibration": {
      "version": 2,
      "kind": "staged",
      "calibrationId": "eyes-closed-01",
      "calibrationStartSecs": 0.0,
      "calibrationEndSecs": 90.0,
      "trainingStartSecs": 90.0,
      "usedStartAnyway": false,
      "baseline": { "percentile": 60, "count": 45, "mean": 1.2, "stddev": 0.3 },
      "phases": [
        {
          "name": "eyesClosed",
          "durationSecs": 60.0,
          "sampleCount": 55,
          "eyes": "closed",
          "kind": "baseline"
        }
      ],
      "recalibrations": []
    },
    "sessionSettings": {
      "dynamicAdapt": true,
      "responsiveness": 0.5,
      "baselinePercentile": 60,
      "guardrailEnabled": true,
      "guardrailEngine": "ai.drowsiness:cbramod_a_vig",
      "guardFeature": "ai.drowsiness",
      "guardModel": "cbramod_a_vig",
      "warningThresholdPercentile": 80,
      "warningSound": "softBell",
      "musicFolder": null,
      "musicMinCutoffHz": 200.0,
      "musicMaxCutoffHz": 8000.0,
      "musicInvert": false,
      "musicShuffle": true,
      "binauralPresetId": "none",
      "binauralCarrierHz": 200.0,
      "binauralBeatHz": 0.0,
      "backgroundBinauralPresetId": "none",
      "backgroundBinauralCarrierHz": 200.0,
      "backgroundBinauralBeatHz": 0.0,
      "markersInFeedbackEnabled": true,
      "eyeMarkersEnabled": false,
      "modelSnapshot": {
        "engine": "cbramod_a_vig",
        "weightsSha256": "0792cb808c14e6b7a2bb2ce1dff379bc47bc54c49a779825bdfeb33bf8157178",
        "repoRevision": null,
        "loadedAt": "2026-09-24T10:14:50.000Z"
      }
    },
    "drowsiness": {
      "scoreTotalPct": 12.5,
      "meanSleepDir": 0.34,
      "threshold": 0.55
    },
    "music": {
      "trackCount": 2,
      "minCutoffHz": 200.0,
      "maxCutoffHz": 8000.0,
      "invert": false,
      "shuffle": true,
      "tracks": [
        { "at": 90.0, "name": "track01.opus" },
        { "at": 450.0, "name": "track02.opus" }
      ],
      "series": [
        { "at": 120.0, "hz": 1200.0 },
        { "at": 300.0, "hz": 2400.0 }
      ]
    },
    "training": {
      "pctInTarget": 62.0,
      "avgAlphaRel": 0.42,
      "guardrailWarnCount": 3,
      "avgSleepDir": 0.34
    }
  }
}
```

Notes on the example:

- Root has **no** `gestures[]`, flat device keys, or flat physio mirrors.
- `feedback` has **no** `gestures[]` (annotations SoT).
- Shared physio (`stillnessPct`, HR, SpO₂, peak-α, quality, battery) lives only under base `stats`.
- `durationMinutes` (15) is the **planned** length the user selected; `durationS` / `elapsedSeconds` (900) are **actual** elapsed store time — different meanings.
- `music` / `calibration` shapes match today’s nested writers (keep as-is).
- `modelSnapshot` stays **inside** `sessionSettings` (matches v5 README / `SessionSettings`); do not also mirror `modelKind` / `modelSha256` / `feedbackEngine` at `feedback` root.

### Field table — `feedback` object

| Field | Type | Notes |
|---|---|---|
| `protocol` | string | Protocol id / catalog name (e.g. `"drowsiness"`). Loosely ↔ BIDS `TaskName` on export. |
| `protocolVersion` | string | Catalog / document version token (today often `"1"`). |
| `protocolJson` | object? | Snapshot of resolved `ProtocolDocument` at save; omit if unavailable. |
| `durationMinutes` | number (int) | **Planned** session length in minutes (UI picker). Not redundant with root `durationS`. |
| `sound` | string | Ambient / background sound name. |
| `feedbackSound` | string? | Reward / feedback output name (e.g. `bowlChimes`). |
| `metadataDescription` | string? | Human protocol blurb from catalog (`ProtocolDocument.metadataDescription`). |
| `calibrationProfile` | string? | Optional profile id string; rarely set today — keep if writers populate it. |
| `calibration` | object? | Nested calibration blob — **keep shape as-is** (`version`, `kind`=`single`\|`staged`, `calibrationId`, timing, `baseline`, `phases[]`, `recalibrations[]`, …). |
| `sessionSettings` | object | Training knobs at save: adaptivity, baseline percentile, guardrail on/off + `guardFeature` / `guardModel` / `guardrailEngine`, warning sound, music/binaural knobs, marker flags. Optional nested `modelSnapshot` `{engine, weightsSha256?, configJson?, repoRevision?, loadedAt}`. |
| `drowsiness` | object? | Protocol session summary `{scoreTotalPct, meanSleepDir, threshold?}`. See Open questions for generic `protocolResults`. |
| `music` | object? | Playback summary — **keep shape as-is** (`trackCount`, cutoff min/max, `invert`, `shuffle`, `tracks[]` `{at,name}`, `series[]` `{at,hz}`). |
| `training` | object | Feedback-only training scalars (see below). |
| ~~`gestures[]`~~ | — | **Forbidden.** Use root `annotations[]`. |

#### `feedback.training` (feedback-only scalars)

| Field | Type | Notes |
|---|---|---|
| `pctInTarget` | number | % seconds in reward target (← `targetPct` / `pctInTarget`). |
| `avgAlphaRel` | number | Mean relative-α used by feedback charts. |
| `guardrailWarnCount` | number (int) | Count of guardrail warning seconds / events from assemble extract. |
| `avgSleepDir` | number | Mean guardrail `sleepDir` over session (also mirrored inside `drowsiness.meanSleepDir` when that nest is present — OK as protocol summary vs training scalar; do not also put under base `stats`). |

Do **not** put under `training`: `stillnessPct`, HR/SpO₂/peak-α/quality/battery (base `stats` only).

### Migrated away from `feedback` / flat dialect (do not leave duplicates)

Agents implementing writers/readers must **not** keep these under `feedback` or as flat root keys once v6 lands:

| Old location | New location | Why |
|---|---|---|
| Flat `deviceName` / `deviceModel` / `deviceId` | `device.{name,model/firmware,id}` | Base device nest |
| `recordedChannels` | `device.channelLabels` | Base |
| `recordedData` | `streams` | Base enablement map |
| `gestures[]` / any `feedback.gestures[]` | root `annotations[]` | Annotations SoT |
| `userId` | `subject.id` | Anonymous-first subject |
| Flat / nested save `stats` physio (`avgBpm`, `avgSpo2`, `peakAlpha*`, `avgMovement`, `stillnessPct`) | `stats.hr` / `spo2` / `peakAlpha` / `movement` | Shared stats |
| `signalQualityMean` / `pctQcOk` | `stats.quality` | Shared stats |
| Root timing already on base (`savedAt`, `startedAt`, `elapsedSeconds`, `durationS`, `notes`, `sessionId`) | base identity | Not under `feedback` |
| Top-level `modelKind` / `modelSha256` / `feedbackEngine` / lone `guardrailEngine` | `sessionSettings.modelSnapshot` + `sessionSettings.guard*` | Single engine nest |
| `training.stillnessPct` | `stats.movement.stillnessPct` | Shared physiology |

### Locks inside this draft

1. **No `feedback.gestures[]`** — annotations are the only marker timeline.
2. **Training-only scalars** live under `feedback.training` (or equivalent nest under `feedback`); shared physio stays in base `stats` only.
3. **`music` and `calibration` shapes** keep today’s nested field names (no rename pass in this draft).
4. **`modelSnapshot` nests under `sessionSettings`**, not as a second top-level `feedback.modelSnapshot` mirror.
5. **`durationMinutes` stays under `feedback`** as planned length (distinct from root `durationS`).
6. **`metadataDescription` stays under `feedback`** (protocol copy, not file-level `notes`).

Status of this section: **DRAFTED** — implementable as written; not stamped LOCKED until Open questions below are answered or explicitly deferred.

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
9. **`subject` is PREPARED (anonymous-first).** Always write `subject.id` on new v6 files; omit voluntary fields until collected; never put PII by default; keep `sessionId` at root. See Subject model.
10. **Feedback extension is DRAFTED.** When `kind=="feedback"`, write top-level `feedback` per **Feedback extension**; never duplicate base/annotations/stats fields into it; never write `feedback.gestures[]`. See migrated-away table + Open questions.

---

## Open questions

Feedback extension + base vocabulary are **schema-complete enough to implement**. Only real undecided product/schema choices remain:

1. **`drowsiness` nest vs generic `protocolResults`** — Today only the drowsiness protocol writes a named session summary (`feedback.drowsiness`). Keep the protocol-specific key (simple, matches code), or introduce `feedback.protocolResults: { "drowsiness": {…}, … }` so future protocols do not each mint a new root key under `feedback`? **Lean:** keep `drowsiness` for v6; revisit when a second protocol summary appears.
2. **Engine field surface** — Confirm single home: `sessionSettings.guardFeature` / `guardModel` / `guardrailEngine` + optional `sessionSettings.modelSnapshot`. No parallel `feedback.engine` object and no flat `modelKind` / `modelSha256` / `feedbackEngine` on `feedback` root. *(If agreed, this ceases to be open and can move to Locks.)*
3. **`avgSleepDir` dual home** — `feedback.training.avgSleepDir` and `feedback.drowsiness.meanSleepDir` can both be present. Accept as training scalar vs protocol summary, or drop one? **Lean:** keep both for now (different readers); do not put under base `stats`.

**Resolved in this draft (not open):**

- `durationMinutes` → `feedback` only (planned); root `durationS` / `elapsedSeconds` = actual.
- `metadataDescription` → `feedback`.
- `music` / `calibration` shapes → keep as-is under `feedback`.
- No `feedback.gestures[]`; shared stats (incl. `stillnessPct`) → base `stats` only.

**Basically done for schema design; remaining work is implementation** (writers/readers, `NFED6`, delete dual-dialect, update `README_feedback_format.md`) plus answering #1–#3 above if product wants them locked before code.

Non-schema leftovers (unchanged; do not block feedback draft):

- Exact named-band formulas under `stats.experimental`.
- Whether `% overshoot` / overshoot intervals are worth persisting later.
- Per-record length prefix / Athena tag 11.
- Whether feedback pause should stop the computed sampler.
- `subject.id` generation scheme and BIDS `sub-` normalization.
- Nickname export-as-EDF-name product toggle (default EDF name = `X`).

---

## Coverage / leftover checklist (gap check vs code)

Gap check of **v6 BASE** (+ locked annotations / subject / stats / streams / device) against current writers, models, sqlite, and docs. Categories: **A** covered · **B** belongs under `feedback` · **C** missing from base (should add) · **D** deferred/optional OK · **E** code has it / spec forgot.

### A) Covered by v6 base (OK)

| Source | Fields → v6 |
|---|---|
| `RecordingMetadata` | `formatVersion`, `appVersion`, `kind`, `savedAt`, `startedAt`, `elapsedSeconds`, `durationS`, `notes`, nested `device.*`, ten-key `streams` |
| `DeviceInfoV5` | `name`, `id`, `firmware`, `model`, `sensors`, `channelCount`, `channelLabels` |
| `StreamsConfig` | `eeg`…`gestures` as `{enabled,rateHz}` (gestures stub) |
| Feedback flat device / channels | `deviceName`/`deviceModel`/`deviceId` → `device`; `recordedChannels` → `device.channelLabels`; `recordedData` → `streams` |
| `extractComputedScalars` / sqlite physio | `avgHr`→`stats.hr.mean`; `avgSpo2`→`stats.spo2.mean`; `peakAlphaHz/Power`→`stats.peakAlpha` (max-power pair; `meanHz` is new); `avgMovement`→`stats.movement.mean` |
| Model/sqlite quality (rarely filled) | `signalQualityMean`/`pctQcOk` → `stats.quality.{mean,pctGood}` (+ new `channelUsable`) |
| Feedback `gestures[]` `{type,at}` | → root `annotations[]` `{onset,duration:0,type}` (snake_case types) |
| Sqlite `user_id` | → `subject.id` (anonymous-first) |
| Sqlite / feedback `session_id` | → root `sessionId` |
| New (not in v5 file JSON) | `subject`, `stats.*` (hr/spo2/peakAlpha/movement/quality/battery/annotationSeconds/experimental), `annotations`, recording `sessionId` |

### B) Belongs under `feedback` (not base)

Full draft + example + migrated-away table: **Feedback extension — DRAFTED** above. Do **not** treat these as base gaps:

| Field(s) | Notes |
|---|---|
| `protocol`, `protocolVersion`, `protocolJson` | Training protocol |
| `durationMinutes` | Planned session length (distinct from `durationS` / `elapsedSeconds`) |
| `sound`, `feedbackSound` | Ambient / reward audio |
| `metadataDescription` | Protocol copy; written by `buildSessionMetadata` today |
| `calibration` (+ optional `calibrationProfile`) | Nested calibration blob |
| `drowsiness` | Session drowsiness summary |
| `music` | Tracks / cutoff series |
| `sessionSettings` | Incl. `guardFeature` / `guardModel` / `guardrailEngine`, markers flags, music/binaural knobs; optional `modelSnapshot` |
| `training.pctInTarget` (← `targetPct` / `pctInTarget`) | Feedback-only |
| `training.avgAlphaRel` | Feedback chart relative-α |
| `training.guardrailWarnCount`, `training.avgSleepDir` | From `extractComputedScalars` / drowsiness |
| Top-level `modelKind` / `modelSha256` / `feedbackEngine` / `guardrailEngine` | On `SessionMetadata` + sqlite; migrate into `sessionSettings` / `modelSnapshot` — **not** base |
| Parallel `feedback.gestures[]` | **Rejected** — use root `annotations` only |

### C) Missing from v6 — should add to base

| Gap | Suggested key | Resolution in this pass |
|---|---|---|
| `stillnessPct` written today in `SessionStatsData` but locked vocab said “optional later”; also duplicated under `feedback.training` | `stats.movement.stillnessPct` (optional) | **Locked** above — shared movement-derived scalar; drop training duplicate when writers land |
| Design rule “fit / contact summary” vs no `stats.fit` | *(none)* — use `stats.quality.channelUsable` | **Clarified** above — no separate fit object |
| Recording files: v6 example has root `sessionId`; `RecordingMetadata` never writes it (sqlite only gets capture `id`) | root `sessionId` | Vocab already allows it — **writer must emit** (not a new key) |

No other current feedback/recording JSON keys need new base keys.

### D) Missing / deferred OK

- `stats.experimental.bands` formulas; `% overshoot` / overshoot annotations (paint-time today).
- Voluntary `subject` demographics; `yearOfBirth`; BIDS `handedness`; separate `device.manufacturer`.
- Per-stream `StreamInfo.electrodes` / `channels` / `sensors` (on Dart model, never written by `streamsConfig`).
- Session means for `lineNoise` / guardrail `clarity`; telemetry `fuel` / `temp` bookends (battery `%` only).
- Sqlite-only: section offsets, `file_size` / `mtime`, `thumbnail` BLOB, `notes_preview`, `marker_count` (derive from `annotations`), `state_markers` label/confidence table.
- Scratch `kind: "tmp"` (connect-time sidecar; never published — v6 `kind` remains `recording` \| `feedback`).
- Athena tag 11; per-record length prefix; pause stopping computed sampler.

### E) Code has it but specs forgot (callouts)

| Item | Where | Notes |
|---|---|---|
| `durationMinutes`, `metadataDescription` | `buildSessionMetadata()` | Were omitted from the brief `feedback` example — **added** above |
| `stillnessPct` dual home | `SessionStatsData` + draft `feedback.training` | Spec had it under training while candidates put stillness on movement — **resolved** → base `stats.movement` |
| Fit vs `stats.quality` | Design rules + candidates vs locked `stats` | Candidates listed “fit” as non-experimental; locked table had no `stats.fit` — **resolved** as quality map |
| Rarely filled `SessionMetadata` fields | Model + sqlite | Inventory already lists `signalQualityMean`, `pctQcOk`, `avgMovement`, `guardrailWarnCount`, `modelKind` / `modelSha256` / `feedbackEngine` / `userId`; also **`calibrationProfile`** and top-level **`guardrailEngine`** are almost never set by `buildSessionMetadata` (engine lives under `sessionSettings`) |
| `extractComputedScalars` incomplete vs locked `stats` | `assemble.dart` | Today: means + max-power peak-α + training counters only. **Does not** yet compute hr/spo2 min/max, `peakAlpha.meanHz`, `stillnessPct`, `stats.quality.*`, `stats.battery.*`, `annotationSeconds` — writers must when implementing v6 |
| Recording `sessionId` | `RecordingMetadata` vs `RecordingStore` | Store upserts `sessionId: id`; file JSON lacks the key |
| Feedback `deviceModel` = firmware string | `buildSessionMetadata` | Flat dialect has no `firmware`; nested `device` will carry both |

