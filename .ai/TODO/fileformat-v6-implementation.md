# TODO — File format v6 implementation

| Field | Value |
|---|---|
| Status | **Ready to implement** (schema design finished 2026-09-24). **Computed Trust extras + sparse `feedback.audioEvents` + `baselineSamples` / `inhibitCeilingOverrides` = LOCKED.** Implement **metadata first**, then computed. |
| Spec | [../contracts/fileformat_v6.md](../contracts/fileformat_v6.md) — annotations / base vocab / feedback / experimental bands / pause / overshoot-chart-only / timezone / **computed Trust extras** / **`feedback.audioEvents`** / **`calibration.baselineSamples`** / **`sessionSettings.inhibitCeilingOverrides`** = **LOCKED**; `subject` = PREPARED. |
| Branch | `refactor/fileformat` |
| Do not mix | Athena tag 11 / optics; pipeline Key Decisions; History dashboard UI series (field names may be reused from History OQ 8 — UI remains out of scope); live device testing without windwerfer OK. |

Track coding work here. Schema decisions go in the contract, not this list.

---

## App identity (subject.id) — do early

**Goal:** every published file can carry a stable anonymous `subject.id` for later labeled uploads.

- [x] Settings keys `subjectId` / `subjectNickname`; generate UUID v4 on load when empty; Settings UI nickname; `SubjectInfo` helper (writers wire later).

1. **App settings** (`lib/src/settings.dart` / SharedPreferences):
   - Keys: `subjectId` (required once generated), `subjectNickname` (optional, user-editable).
   - **On app start** (settings load): if `subjectId` is missing/empty → generate and persist immediately.
2. **Generation (offline, no network):**
   - Prefer **UUID v4** (128-bit; collision risk negligible for device-local install base). Dart: `Uuid().v4()` from `uuid` package, or `Random.secure()` → 16 bytes → hex/canonical UUID string.
   - Do **not** require internet. Do **not** use advertising IDs / device serials as the id (privacy + reset issues).
   - If a platform ever cannot provide secure random (unlikely on our targets), leave `subject.id` **blank/omit** and treat as placeholder — do not invent a weak sequential id.
3. **Nickname:** user-settable in Settings UI; optional; never auto-filled from the random id.
4. **Writers:** map settings → metadata `subject: { id, nickname? }`. Root `sessionId` stays the **file/capture** id (new per recording), not the person.
5. **BIDS export later:** `participant_id` = `sub-{subject.id}` (normalize once at export; do not store the `sub-` prefix in app settings).
6. **EDF export later:** patient **code** = `subject.id`; name = `X` unless nickname-export toggle is on (toggle is a separate product decision; default name `X`).

---

## Container / clean cut

- [ ] Pick and write `NFED6` magic + `formatVersion: 6` on new files.
- [ ] Delete dual-dialect readers / “accept both shapes” paths in the same effort (no v5 metadata compat).
- [ ] Update [../../README_feedback_format.md](../../README_feedback_format.md) in the same PR that lands writers.
- [ ] Recording files emit root `sessionId` (today sqlite has it; file JSON often lacks it).

---

## Metadata writers / readers

- [ ] Base recording metadata writer (identity, `subject`, `device`, `streams`, `stats`, `annotations`).
- [ ] Feedback writer: base + locked `feedback{}` only (no `gestures[]`, no `drowsiness` nest, no shared-stats duplicates).
- [ ] Feedback Trust metadata extras (see dedicated section below — **implement before computed Trust extras**): `baselineSamples`, `inhibitCeilingOverrides`, `audioEvents`.
- [ ] Readers for History / export / assemble paths — single dialect.
- [ ] `extractComputedScalars` (and assemble): fill locked `stats.*` gaps vs today (hr/spo2 min/max, `peakAlpha.meanHz`, `stillnessPct`, `quality.*`, `battery.*`, `annotationSeconds`).
- [ ] Build `annotations[]` from pause / bad_quality / disconnect intervals + gesture instants (`duration: 0`, snake_case types).
- [ ] Map sqlite `user_id` ←→ `subject.id`; keep promoting a small scalar set into sqlite later (not blocking first writer PR).

---

## `stats.experimental.bands`

- [ ] Implement locked formulas from contract **Experimental band metrics** (usable-seconds gate; omit nest if < 30 usable secs).
- [ ] Ship **Must** keys first; add Sensible / Cool in same or follow-up PR — do not invent synonym keys.
- [ ] Unit tests with synthetic `ComputedFrame` bands (known α/θ, AF7/AF8 asymmetry).

---

## Pause (LOCKED behavior — implement)

Contract: pause **stops raw + computed**; metadata gets `annotations` `pause` interval; `elapsedSeconds` does not advance.

- [ ] Feedback pause/resume: stop/restart computed sampler (today pause keeps sampling — change).
- [ ] Recording pause (if exposed): stop/restart raw capture writer the same way.
- [ ] Write/extend `annotations[]` `{ type: "pause", onset, duration }` on pause/resume/end.
- [ ] Ensure no fabricated computed/raw samples during pause; History charts treat pause as a gap via annotations (not chart-overshoot logic).

---

## Timezone awareness (LOCKED — implement)

Contract: **Timing + time zones**. Today recording metadata forces UTC `…Z` (loses site zone); feedback often writes **naive local** ISO strings (no offset).

- [x] Always write `startedAt` / `savedAt` as ISO-8601 with **explicit offset or `Z`** (never naive).
- [x] Always write root **`timeZone`** (IANA from device at session start, e.g. `Asia/Bangkok`).
- [x] Prefer local offset on the timestamp for History-friendly display; `Z` + `timeZone` also OK.
- [ ] App UI: render session times in `timeZone` (fallback: timestamp offset).
- [x] EDF export: pack **local** `startdate`/`starttime` from `startedAt` in `timeZone` (EDF FAQ Q17); never put UTC digits into EDF starttime as if local. Include EDF+ `Startdate dd-MMM-yyyy` in Local Recording Identification.
- [ ] Sqlite / list queries: store instant in a sortable form; keep `timeZone` available for display.
- [x] Fix both recording + feedback writer paths in the same effort.

---

## Feedback Trust metadata extras (implement FIRST)

Contract: **Feedback extension** + **Computed feedback extras** (metadata prerequisites). Do this **before** computed Trust extras.

- [ ] Persist `feedback.calibration.baselineSamples: number[]` — raw native reward samples used by `percentileOf` after initial calibration (~50 doubles). Keep existing `baseline` stats summary as-is.
- [ ] Persist `feedback.calibration.recalibrations[].baselineSamples: number[]` when present (alongside existing `atSecs` + `baseline` stats).
- [ ] Persist `feedback.sessionSettings.inhibitCeilingOverrides?: { "beta"?: number, "delta"?: number }` — Settings slider overlays (only set keys).
- [ ] Writer for sparse `feedback.audioEvents: [{ "onset": number, "type": string }]` — types locked: `reward_chime` | `guard_chime`. `onset` = seconds from capture start (same clock as computed `t` / annotations). Omit array or empty when none fired. Record **actual** play times from `FeedbackAudioController` (do not reconstruct from reward 2.5s hold + 8s cooldown / guard 20s cooldown constants).
- [ ] Do **not** put chimes in root `annotations[]`. Continuous musicFilter / rain / binaural do **not** get per-second audio events.
- [ ] Round-trip tests: `baselineSamples`, `inhibitCeilingOverrides`, `audioEvents` in metadata JSON.

---

## Computed Trust extras (implement SECOND)

Contract: **Computed feedback extras — LOCKED**. Wire = camelCase JSONL (Dart `ComputedFrame.toJson`); Rust extract must accept (serde rename). Names aligned with History OQ 8 field list; History UI series remains out of scope.

- [ ] Dart `ComputedFrame` / feedback sampler: **KEEP** `ratio`, `threshold`, `inTarget`, `pct`; **ADD** `percentile`, `thresholdPercentile`, `heldBack`, `inhibitTags`, `clean`, `dirtyReason`, `betaRel`, `deltaRel`.
- [ ] Dart guardrail on same tick: **KEEP** `sleepDir`, `clarity`, `warning`, `delta`; **ADD** `featurePercentile`, `warnOver`, `ceilingOver`, `clean`, `dirtyReason`.
- [ ] **Dirty-latch fix:** dirty seconds MUST write `clean:false`, `inTarget:false`, finite dirty `percentile` (do not skip sampler update). Do **not** store `plotPercentile` / hold-last-clean Y.
- [ ] Recordings (`MonitorSampler`): omit/null NEW feedback/guard Trust extras (never fake `percentile:0` or `clean:false`). Zeroed legacy keys OK for chart shape.
- [ ] Rust `FeedbackInfo` / `GuardrailInfo` + FRB: accept camelCase wire keys; extract tests (`toJsonBytes` → extract → `percentile`/`clean` are `Some` on feedback).
- [ ] Do **not** store: full relative-band series, `plotPercentile`, parallel `feedback.gestures[]`. Per-second frame `gestures[]` string ids OK.
- [ ] Unit tests: dirty playing second has `clean:false` + finite dirty `percentile`; recordings leave NEW fields null/absent.

---

## Explicitly out of this list

| Item | Where it lives |
|---|---|
| Athena raw optical stream / session **tag 11** | [athena-optics-contract.md](athena-optics-contract.md) |
| Per-record length prefix (skip unknown tags) | [../contracts/session-format-contract.md](../contracts/session-format-contract.md) |
| Monitor Bands **overshoot** | **LOCKED chart-only** — do not persist |
| Nickname → EDF name export toggle | Product; default EDF name = `X` |
| History dashboard UI | [history-dashboard-unification.md](history-dashboard-unification.md) |

---

## Suggested order

1. `subjectId` / nickname in app settings (unblocks labeled uploads even before full v6 writers).
2. Timezone-aware `startedAt`/`savedAt`/`timeZone` helpers (used by all writers).
3. Pause stops raw+computed + `pause` annotations.
4. Annotations + base `stats` assemble helpers.
5. `NFED6` writers/readers + delete dual dialect + README.
6. `stats.experimental.bands` Must set.
7. Feedback `outcomeScalars` / `sessionSettings` migration from flat v5 fields.
8. **Metadata first — Trust metadata extras:** `calibration.baselineSamples` (+ per-recal), `sessionSettings.inhibitCeilingOverrides`, sparse `feedback.audioEvents` writer (with feedback migration / metadata writers).
9. **Then computed — Trust extras:** Dart `ComputedFrame` keep+add + sampler dirty-latch fix + Rust `FeedbackInfo`/`GuardrailInfo` + FRB + extract tests.

**User-stated order (crystal clear):** implement **metadata** Trust extras (`baselineSamples`, `inhibitCeilingOverrides`, `audioEvents`) **first**, then **computed** Trust extras + dirty-latch + FRB.
