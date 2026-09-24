# NeuroFeed — History Metadata Cache (SQLite)

## Overview

File format authority: [`.ai/contracts/fileformat_v6.md`](.ai/contracts/fileformat_v6.md) (NFED6 / `formatVersion: 6`). Human layout: [README_feedback_format.md](README_feedback_format.md).


The history cache is SQLite (`session_metadata.db`) so History does not
re-read every `.neurofeed` file on each list/open. It is **not** written
into the SAF history folder. Thumbnails live as a **BLOB** on the `sessions`
row.

One database lists **both** feedback sessions and recordings (`kind`).

**List path:** `SessionStore.list()` is **sqlite-only**
(`listSessions()` ordered by `COALESCE(saved_at_ms, 0) DESC, saved_at DESC`).
A history-folder file with no row is invisible until something upserts it
(`publishSession` / `RecordingStore.publish` / `reindexFromFiles`).

**Write path:** `publishSession` / `RecordingStore.publish` / `updateNotes` /
`delete` / `moveAllTo` upsert or delete rows.

**Schema wipe + reindex:** On open, if `sessions` lacks `experimental_scalars`,
SQLite **drops** `sessions` + `state_markers` and recreates the full schema
(clean cut — no ALTER-add). That sets a one-shot `needsReindex` flag;
`SessionStore.list()` schedules `backfillPending()` → `reindexFromFiles()`,
which lists history `.neurofeed` files, parses metadata (+ assembles stats
from computed frames when the file lacks `stats`), and upserts full scalar
columns. The same reindex runs when the DB is empty but files exist on disk.

---

## Database location

```
<cache-dir>/session_metadata.db
```

`resolveSessionCacheDir` in `session_sqlite.dart`:

- Linux/Windows/macOS: `<history-folder>/.cache/`
- Android/iOS: `getApplicationCacheDirectory()`

Isolation is the **database path**, not a column. Changing the save folder
moves `session_*.neurofeed` **and** `recording_*.neurofeed` and
opens the destination cache dir.

---

## Schema

### Table: `sessions`

One row per published file. Schema bumps that add default
scalar columns wipe and recreate the table (see wipe + reindex above);
`PRAGMA user_version = 2` marks the promoted-scalar schema.

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PK | Id in the filename (`session_$id` / `recording_$id`) |
| `path` | TEXT | History-root filename (`session_….neurofeed` or `recording_….neurofeed`) |
| `kind` | TEXT | `feedback` (default) or `recording` |
| `format_version` | INTEGER | Container format version (6 = NFED6) |
| `app_version` | TEXT | App version that wrote the file |
| `saved_at` | TEXT | ISO8601 when saved |
| `started_at` | TEXT | ISO8601 when capture started |
| `duration_s` | INTEGER | Duration (seconds) |
| `protocol` | TEXT | Protocol id (empty on recordings) |
| `protocol_version` | TEXT | Protocol schema version |
| `device_name` | TEXT | Display name |
| `device_model` | TEXT | `Classic`, `Athena`, `Crown`, `Unknown` |
| `device_id` | TEXT | MAC / `sim:*` id |
| `calibration_profile` | TEXT | Calibration id (feedback) |
| `recorded_channels` | TEXT | Comma-separated labels |
| `recorded_streams` | TEXT | Comma-separated stream names (recordings) |
| `off_meta` / `len_meta` | INTEGER | Byte offset/length of metadata section |
| `off_computed` / `len_computed` | INTEGER | Computed 1 Hz section |
| `off_raw` / `len_raw` | INTEGER | Raw body section |
| `avg_hr` | REAL | `stats.hr.mean` |
| `hr_min` / `hr_max` | REAL | `stats.hr.min` / `max` |
| `avg_spo2` | REAL | `stats.spo2.mean` |
| `spo2_min` / `spo2_max` | REAL | `stats.spo2.min` / `max` |
| `peak_alpha_hz` | REAL | `stats.peakAlpha.maxPowerHz` |
| `peak_alpha_power` | REAL | `stats.peakAlpha.maxPower` |
| `peak_alpha_mean_hz` | REAL | `stats.peakAlpha.meanHz` |
| `pct_in_target` | REAL | `feedback.outcomeScalars.pctInTarget` (null on recordings) |
| `avg_movement` | REAL | `stats.movement.mean` |
| `stillness_pct` | REAL | `stats.movement.stillnessPct` |
| `guardrail_warn_count` | INTEGER | `feedback.outcomeScalars.guardrailWarnCount` |
| `avg_sleep_dir` | REAL | `feedback.outcomeScalars.avgSleepDir` |
| `avg_alpha_rel` | REAL | `feedback.outcomeScalars.avgAlphaRel` |
| `guard_warn_pct` | REAL | `feedback.outcomeScalars.guardWarnPct` |
| `guard_threshold` | REAL | `feedback.outcomeScalars.guardThreshold` |
| `signal_quality_mean` | REAL | `stats.quality.mean` |
| `pct_qc_ok` | REAL | `stats.quality.pctGood` |
| `quality_channel_usable` | TEXT | JSON map of `stats.quality.channelUsable` |
| `annotation_pause_s` | REAL | `stats.annotationSeconds.pause` |
| `annotation_bad_quality_s` | REAL | `stats.annotationSeconds.bad_quality` |
| `annotation_disconnect_s` | REAL | `stats.annotationSeconds.disconnect` |
| `battery_start_pct` / `battery_end_pct` | REAL | `stats.battery.startPct` / `endPct` |
| `experimental_scalars` | TEXT | JSON of `stats.experimental` (or null) |
| `marker_count` | INTEGER | Gesture markers (feedback) |
| `time_zone` | TEXT | IANA id at session start |
| `saved_at_ms` | INTEGER | UTC epoch ms sort key |
| `guardrail_engine` | TEXT | Engine id or empty |
| `model_kind` | TEXT | Model kind if any |
| `model_sha256` | TEXT | SHA-256 of weights |
| `feedback_engine` | TEXT | `ratio`, etc. |
| `user_id` | TEXT | Optional |
| `session_id` | TEXT | Optional UUID |
| `notes_preview` | TEXT | First 50 chars of notes |
| `file_size` | INTEGER | File size (bytes) |
| `mtime` | INTEGER | File mtime (ms epoch) |
| `thumbnail` | BLOB | WebP bytes |
| `created_at` / `updated_at` | INTEGER | Row times (ms epoch) |

**Indexes:** `saved_at`, `started_at`, `protocol`, `device_id`, `user_id`,
`guardrail_engine`, `session_id`. There is no `kind` index.

Read/delete use sqlite **`path`**, not a reconstructed name from `id` alone.

### Table: `state_markers`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK AUTOINCREMENT | |
| `session_id` | TEXT FK → sessions(id) | Cascades on delete |
| `t` | REAL | Seconds from recording start |
| `source` | TEXT | `gesture`, `user`, `guardrail`, … |
| `label` | TEXT | Optional |
| `confidence` | INTEGER? | 0–10 |
| `intensity` | INTEGER? | |
| `created_at` / `updated_at` | INTEGER | ms epoch |

**Index:** `idx_state_markers_session_t` on `(session_id, t)`.

---

## Fault tolerance

`SessionSqlite.open()` catches any error (corrupt DB, missing native lib,
permission) and falls back to a no-op so History degrades rather than
crashing. Thumbnails are never written to SAF as sidecar PNGs.

---

## Implementation files

| File | Purpose |
|------|---------|
| `lib/src/feedback/session_sqlite.dart` | Schema, CRUD, wipe+reindex flag, scalar columns |
| `lib/src/feedback/session_scalars.dart` | Fill row scalars from v6 `stats` / `outcomeScalars` |
| `lib/src/feedback/session_store_core.dart` | Feedback publish / list / move / delete |
| `lib/src/monitor/recording/recording_store.dart` | Recording publish upserts `kind=recording` |
| `android/app/src/main/kotlin/…/MainActivity.kt` | SAF `listFilesMeta()` (tree root only) |
