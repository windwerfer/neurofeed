# TODO — File format v6 implementation

| Field | Value |
|---|---|
| Status | **Ready to implement** (schema design finished 2026-09-24). |
| Spec | [../contracts/fileformat_v6.md](../contracts/fileformat_v6.md) — annotations / base vocab / feedback / experimental bands / pause / overshoot-chart-only / timezone = **LOCKED**; `subject` = PREPARED. |
| Branch | `refactor/fileformat` |
| Do not mix | Athena tag 11 / optics; pipeline Key Decisions; History dashboard UI series; live device testing without windwerfer OK. |

Track coding work here. Schema decisions go in the contract, not this list.

---

## App identity (subject.id) — do early

**Goal:** every published file can carry a stable anonymous `subject.id` for later labeled uploads.

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

- [ ] Always write `startedAt` / `savedAt` as ISO-8601 with **explicit offset or `Z`** (never naive).
- [ ] Always write root **`timeZone`** (IANA from device at session start, e.g. `Asia/Bangkok`).
- [ ] Prefer local offset on the timestamp for History-friendly display; `Z` + `timeZone` also OK.
- [ ] App UI: render session times in `timeZone` (fallback: timestamp offset).
- [ ] EDF export: pack **local** `startdate`/`starttime` from `startedAt` in `timeZone` (EDF FAQ Q17); never put UTC digits into EDF starttime as if local. Include EDF+ `Startdate dd-MMM-yyyy` in Local Recording Identification.
- [ ] Sqlite / list queries: store instant in a sortable form; keep `timeZone` available for display.
- [ ] Fix both recording + feedback writer paths in the same effort.

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
