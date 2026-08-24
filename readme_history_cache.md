# Muse ML — History Metadata Cache (SQLite)

## Overview

The history cache uses **SQLite** (`session_metadata.db`) to avoid re-reading and JSON-parsing every `.muse.feedback` file on every history list/open. The cache is **app-private** (stored in the app's documents directory) and works for both filesystem and SAF (Storage Access Framework) history locations.

The cache is a **read-through + write-through** layer:
- **Read path**: `SessionStore.list()` does one `listFilesMeta()` (name + mtime) + one `SELECT` against SQLite. Unchanged files render from cached columns; changed/new files are backfilled in the background and the list refreshes.
- **Write path**: `publishSession` / `updateNotes` / `delete` / `moveAllTo` upsert SQLite rows synchronously.

---

## Database Location

```
<app-documents-dir>/session_metadata.db
```

On Android with SAF, this is in the app-private directory (not the SAF folder). Thumbnails are stored as separate files:

```
<app-documents-dir>/thumbnails/<session_id>.png
```

---

## Schema

### Table: `sessions`

Stores one row per session file. Columns are a mix of **indexed filter columns** and **pre-computed scalar summary fields** for instant sorting/filtering without JSON decoding.

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PK | Session ID (e.g., `abc12345`) |
| `path` | TEXT | Filename (`session_abc12345.muse.feedback`) |
| `format_version` | INTEGER | Container format version (5) |
| `app_version` | TEXT | App version that wrote the file |
| `saved_at` | TEXT | ISO8601 wall-clock when saved |
| `started_at` | TEXT | ISO8601 wall-clock when recording started |
| `duration_s` | INTEGER | Total recording duration (seconds) |
| `protocol` | TEXT | Protocol type (e.g., `drowsiness`) |
| `protocol_version` | TEXT | Protocol schema version |
| `device_name` | TEXT | BLE display name |
| `device_model` | TEXT | Device model (`Classic`, `Athena`, `Crown`, `Unknown`) |
| `device_id` | TEXT | MAC address |
| `calibration_profile` | TEXT | Calibration ID (e.g., `eyes-closed-01`) |
| `recorded_channels` | TEXT | Comma-separated labels (e.g., `TP9,AF7,AF8,TP10`) |
| `recorded_streams` | TEXT | Comma-separated stream names |
| `off_meta` | INTEGER | Byte offset of metadata section in container |
| `len_meta` | INTEGER | Byte length of compressed metadata |
| `off_computed` | INTEGER | Byte offset of computed 1 Hz section |
| `len_computed` | INTEGER | Byte length of compressed computed section |
| `off_raw` | INTEGER | Byte offset of raw body section |
| `len_raw` | INTEGER | Byte length of compressed raw section |
| `avg_hr` | REAL | Average heart rate (BPM) over session |
| `avg_spo2` | REAL | Average SpO₂ (%) over session |
| `peak_alpha_hz` | REAL | Average peak alpha frequency (Hz) |
| `peak_alpha_power` | REAL | Average peak alpha power (µV²) |
| `pct_in_target` | REAL | % of feedback seconds above threshold |
| `avg_movement` | REAL | Average movement score (0–1.5g) |
| `guardrail_warn_count` | INTEGER | Seconds with guardrail warning active |
| `avg_sleep_dir` | REAL | Mean sleep-direction score |
| `signal_quality_mean` | REAL | Mean per-pad signal quality (0–100) |
| `pct_qc_ok` | REAL | % of seconds with good signal quality |
| `marker_count` | INTEGER | Total gesture markers in session |
| `guardrail_engine` | TEXT | `bandMath`, `lunaBase`, `lunaLarge`, `reveBase`, `none` |
| `model_kind` | TEXT | Model kind used (if any) |
| `model_sha256` | TEXT | SHA-256 of model weights |
| `feedback_engine` | TEXT | `ratio`, `none`, etc. |
| `user_id` | TEXT | Optional user identifier |
| `session_id` | TEXT | Optional session UUID |
| `notes_preview` | TEXT | First 50 chars of notes |
| `file_size` | INTEGER | Total file size (bytes) |
| `mtime` | INTEGER | File modification time (ms since epoch) |
| `created_at` | INTEGER | Row creation time (ms since epoch) |
| `updated_at` | INTEGER | Row last update time (ms since epoch) |

**Indexes:**
- `idx_sessions_saved_at` (DESC) — default history sort
- `idx_sessions_started_at` (DESC) — sort by recording time
- `idx_sessions_protocol` — filter by protocol
- `idx_sessions_device_id` — filter by device
- `idx_sessions_user_id` — filter by user
- `idx_sessions_guardrail_engine` — filter by AI engine
- `idx_sessions_session_id` — lookup by session UUID

### Table: `state_markers`

User-added or auto-detected markers for self-labeling and retrospective analysis.

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK AUTOINCREMENT | |
| `session_id` | TEXT FK → sessions(id) | Cascades on session delete |
| `t` | REAL | Seconds from recording start |
| `source` | TEXT | `gesture`, `user`, `guardrail`, etc. |
| `label` | TEXT | Optional label (e.g., `doubleBlink`) |
| `confidence` | INTEGER? | 0–10 (user confidence) |
| `intensity` | INTEGER? | Intensity rating |
| `created_at` | INTEGER | ms since epoch |
| `updated_at` | INTEGER | ms since epoch |

**Index:** `idx_state_markers_session_t` on `(session_id, t)`

---

## Reconciliation Algorithm

`SessionStore.list()` performs a **single-pass reconciliation**:

1. **`listFilesMeta()`** → returns `[{name, mtime}]` for all `.muse.feedback` files in the history folder (one syscall per file, but batched on Android via `MainActivity.kt`).
2. **Single `SELECT`** → `SELECT * FROM sessions WHERE storage_key=? ORDER BY saved_at_ms DESC`
3. For each file:
   - **Unchanged** (`mtime` matches): render from cached columns (instant, no I/O).
   - **Changed / new**: backfill asynchronously:
     - Read container head (`v5_parse_head`) → metadata JSON + thumbnail
     - Decode metadata JSON → extract scalar summary fields
     - `upsertSession()` with new values
     - `SessionListNotifier.invalidateSelf()` → triggers re-read (lazy two-stage emission)
4. **Deleted files**: rows with `mtime=0` and missing from `listFilesMeta()` are deleted from SQLite.

---

## Storage Key Namespace

Sessions are namespaced by **storage location** so two history folders never share rows even if IDs collide:

```
storage_key = sha256(folder_location).substring(0, 16)
```

- Filesystem path → `sha256("/home/user/Documents/meditation feedback")`
- SAF tree URI → `sha256("content://com.android.externalstorage.documents/tree/...")`

`moveAllTo(newFolder)` re-namespaces all rows by computing the new `storage_key` and updating the `storage_key` column (or re-inserting with new key).

---

## Fault Tolerance

- `SessionSqlite.open()` catches **any** error (corrupt DB, missing native lib, permission denied) and falls back to a **no-op implementation** that returns empty lists. History degrades gracefully to file reads.
- `SessionStore` takes an injectable `SessionCache` (tests inject a real SQLite instance; production uses the fallback on failure).
- Thumbnail cache is separate (`<app-documents-dir>/thumbnails/<id>.png`) — never written to SAF folders.

---

## "Clear Cache" Button

Settings → History → **Clear Cache** runs:
```sql
DELETE FROM state_markers;
DELETE FROM sessions;
```
Next history open re-imports all v5 files (reads metadata + computed from each file).

---

## Implementation Files

| File | Purpose |
|------|---------|
| `lib/src/feedback/session_sqlite.dart` | SQLite schema, CRUD, reconciliation |
| `lib/src/feedback/session_cache.dart` | `SessionCache` interface + no-op fallback |
| `lib/src/feedback/session_store_core.dart` | `SessionStore.list()` reconciliation logic |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `listFilesMeta()` native implementation |

---

## Query Examples

```sql
-- Most recent 50 sessions
SELECT * FROM sessions ORDER BY saved_at DESC LIMIT 50;

-- All drowsiness sessions with guardrail warnings
SELECT * FROM sessions 
WHERE protocol = 'drowsiness' AND guardrail_warn_count > 0 
ORDER BY started_at DESC;

-- Sessions using LUNA Large model
SELECT * FROM sessions 
WHERE model_kind = 'lunaLarge' 
ORDER BY saved_at DESC;

-- Average session duration per protocol
SELECT protocol, AVG(duration_s) FROM sessions GROUP BY protocol;
```