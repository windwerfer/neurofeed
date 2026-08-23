-- sessions table: one row per .muse.feedback file
CREATE TABLE sessions (
  -- Primary key (stable session id, derived from filename)
  id           TEXT PRIMARY KEY NOT NULL,

  -- File location (path or content URI for SAF) — unique per row
  path         TEXT NOT NULL UNIQUE,

  -- Format & app versioning
  format_version   INTEGER NOT NULL DEFAULT 5,
  app_version      TEXT NOT NULL,

  -- Session identification & sorting
  saved_at         TEXT NOT NULL,           -- ISO8601 UTC (session end)
  started_at       TEXT NOT NULL,           -- ISO8601 UTC (session start)
  duration_s       INTEGER NOT NULL,        -- elapsedSeconds
  protocol         TEXT NOT NULL,           -- e.g. 'drowsiness', 'twilight', 'alertnessOpen', 'alertnessClosed'
  protocol_version TEXT,                    -- instructions/label schema version

  -- Device info
  device_name      TEXT,
  device_model     TEXT,                    -- 'Classic', 'Athena', 'Crown', 'Unknown'
  device_id        TEXT,                    -- MAC address

  -- Calibration
  calibration_profile TEXT,                -- 'single' | 'staged'

  -- Streams recorded
  recorded_channels  TEXT NOT NULL,         -- JSON array: ['TP9','AF7','AF8','TP10']
  recorded_streams   TEXT NOT NULL,         -- JSON array: ['eeg','bands','pulse','spo2','movement','peakAlpha','imu','ppg','telemetry','gestures']

  -- File layout offsets (for fast range reads without full parse)
  off_meta         INTEGER NOT NULL,
  len_meta         INTEGER NOT NULL,
  off_computed     INTEGER NOT NULL,
  len_computed     INTEGER NOT NULL,
  off_raw          INTEGER NOT NULL,
  len_raw          INTEGER NOT NULL,

  -- Summary statistics (for history list / monthly tracking / sorting)
  duration_s       INTEGER NOT NULL,        -- = duration_s (redundant with duration_s, kept for clarity)
  avg_hr           REAL,
  avg_spo2         REAL,
  peak_alpha_hz    REAL,
  peak_alpha_power REAL,
  pct_in_target    REAL,                    -- % time in target
  avg_movement     REAL,
  guardrail_warn_count INTEGER,
  avg_sleep_dir    REAL,
  signal_quality_mean REAL,
  pct_qc_ok        REAL,                    -- fraction of time signal quality ≥ threshold
  marker_count     INTEGER DEFAULT 0,

  -- Protocol / guardrail / feedback metadata
  guardrail_engine   TEXT,                  -- 'bandMath' | 'lunaBase' | 'lunaLarge' | 'reveBase' | 'none'
  model_kind         TEXT,                   -- 'lunaBase' | 'lunaLarge' | 'reveBase' | NULL
  model_sha256       TEXT,                   -- weights SHA-256 when AI guardrail used
  feedback_engine    TEXT,                   -- 'atr' | future AI feedback types
  calibration_profile TEXT,                 -- 'single' | 'staged'

  -- User/session identity (for future multi-user / export packs)
  user_id          TEXT,                    -- anonymous id
  session_id       TEXT,                    -- anonymous session id for export packs

  -- Notes preview for list UI
  notes_preview    TEXT,                    -- first ~80 chars

  -- File metadata
  file_size        INTEGER NOT NULL,
  mtime            INTEGER NOT NULL,         -- file mtime (ms since epoch)

  -- Timestamps
  started_at       TEXT NOT NULL,           -- ISO8601 UTC (session start)
  saved_at         TEXT NOT NULL,           -- ISO8601 UTC (session end)
  created_at       INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
  updated_at       INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
);

-- Indexes for common queries
CREATE INDEX idx_sessions_saved_at       ON sessions(saved_at DESC);
CREATE INDEX idx_sessions_started_at     ON sessions(started_at DESC);
CREATE INDEX idx_sessions_protocol       ON sessions(protocol);
CREATE INDEX idx_sessions_device_id      ON sessions(device_id);
CREATE INDEX idx_sessions_user_id        ON sessions(user_id);
CREATE INDEX idx_sessions_guardrail_engine ON sessions(guardrail_engine);
CREATE INDEX idx_sessions_session_id     ON sessions(session_id);

-- state_markers: user/gesture markers (tiny, high value for labeling)
CREATE TABLE state_markers (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id      TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  t               REAL NOT NULL,          -- seconds from recording start (same time base as computed)
  source          TEXT NOT NULL,          -- 'jaw_clench' | 'eye_pinch' | 'button' | 'double_clench' | 'double_blink' | ...
  label           TEXT,                   -- user-assigned: 'access' | 'j1' | 'mind_wandering' | 'dullness' | free text
  confidence      INTEGER CHECK (confidence IS NULL OR (confidence BETWEEN 0 AND 10)),
  intensity       INTEGER,                -- 1=shallow, 2=mid, 3=deep
  created_at      INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
  updated_at      INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
);

CREATE INDEX idx_state_markers_session_t ON state_markers(session_id, t);

-- Thumbnails are external files: .cache/thumbnails/<session_id>.webp
-- thumb_path in sessions table stores relative path for easy migration/clear.