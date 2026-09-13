# Muse ML — History Metadata Cache (SQLite)

## Overview

The history cache is SQLite (`session_metadata.db`) so History does not
re-read every `.muse.feedback` file on each list/open. It is **not** written
into the SAF history folder. Thumbnails live as a **BLOB** on the `sessions`
row.

One database lists **both** feedback sessions and recordings (`kind`).

**List path:** `SessionStore.list()` is **sqlite-only**
(`listSessions()` ordered by `saved_at DESC`). There is no directory scan
and no background backfill of orphan files. A history-folder file with no
row is invisible until something upserts it (`publishSession` /
`RecordingStore.publish`).

**Write path:** `publishSession` / `RecordingStore.publish` / `updateNotes` /
`delete` / `moveAllTo` upsert or delete rows. `backfillPending()` is a no-op.

---

## Database location

```
<cache-dir>/session_metadata.db
```

`resolveSessionCacheDir` in `session_sqlite.dart`:

- Linux/Windows/macOS: `<history-folder>/.cache/`
- Android/iOS: `getApplicationCacheDirectory()`

Isolation is the **database path**, not a column. Changing the save folder
moves `session_*.muse.feedback` **and** `recording_*.muse.feedback` and
opens the destination cache dir.

---

## Schema

### Table: `sessions`

One row per published file. `kind` is added with
`ALTER TABLE … DEFAULT 'feedback'` (`_ensureKindColumn`) so older DBs keep
working.

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PK | Id in the filename (`session_$id` / `recording_$id`) |
| `path` | TEXT | History-root filename (`session_….muse.feedback` or `recording_….muse.feedback`) |
| `kind` | TEXT | `feedback` (default) or `recording` |
| `format_version` | INTEGER | Container format version (5) |
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
| `avg_hr` | REAL | Average heart rate (BPM) |
| `avg_spo2` | REAL | Average SpO₂ (%) |
| `peak_alpha_hz` | REAL | Average peak alpha frequency (Hz) |
| `peak_alpha_power` | REAL | Average peak alpha power |
| `pct_in_target` | REAL | % of feedback seconds in target (feedback) |
| `avg_movement` | REAL | Average movement score |
| `guardrail_warn_count` | INTEGER | Seconds with guard warning |
| `avg_sleep_dir` | REAL | Mean sleep-direction score |
| `signal_quality_mean` | REAL | Mean pad quality (0–100) |
| `pct_qc_ok` | REAL | % of seconds with good quality |
| `marker_count` | INTEGER | Gesture markers (feedback) |
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
| `lib/src/feedback/session_sqlite.dart` | Schema, CRUD, thumbnail BLOB, `kind` |
| `lib/src/feedback/session_store_core.dart` | Feedback publish / list / move / delete |
| `lib/src/monitor/recording/recording_store.dart` | Recording publish upserts `kind=recording` |
| `android/app/src/main/kotlin/…/MainActivity.kt` | SAF `listFilesMeta()` (tree root only) |
