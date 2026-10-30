//! SQLite backend (native only). One table; the body is a BLOB.

use crate::{Result, SessionMeta, Store, StoreError, StoredSession};
use rusqlite::{params, Connection, OptionalExtension, Row};

const SCHEMA: &str = "CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_unix_ms REAL,
    duration_s REAL NOT NULL,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    protocol TEXT,
    summary_json TEXT,
    eeg_samples INTEGER NOT NULL,
    ppg_samples INTEGER NOT NULL,
    feedback_seconds INTEGER NOT NULL,
    device_json TEXT NOT NULL,
    body BLOB NOT NULL
);
PRAGMA user_version = 1;";

const META: &str = "id, started_unix_ms, duration_s, device_id, device_name, protocol, summary_json, eeg_samples, ppg_samples, feedback_seconds, length(body)";

fn err(e: impl std::fmt::Display) -> StoreError {
    StoreError(e.to_string())
}

fn meta(r: &Row<'_>) -> rusqlite::Result<SessionMeta> {
    let summary: Option<String> = r.get(6)?;
    Ok(SessionMeta {
        id: r.get::<_, i64>(0)?.unsigned_abs(),
        started_unix_ms: r.get(1)?,
        duration_s: r.get(2)?,
        device_id: r.get(3)?,
        device_name: r.get(4)?,
        protocol: r.get(5)?,
        summary: summary.and_then(|s| serde_json::from_str(&s).ok()),
        eeg_samples: r.get::<_, i64>(7)?.unsigned_abs(),
        ppg_samples: r.get::<_, i64>(8)?.unsigned_abs(),
        feedback_seconds: r.get::<_, i64>(9)?.unsigned_abs(),
        bytes: r.get::<_, i64>(10)?.unsigned_abs(),
    })
}

fn i(v: u64) -> i64 {
    i64::try_from(v).unwrap_or(i64::MAX)
}

pub struct SqliteStore {
    conn: Connection,
    location: String,
}

impl SqliteStore {
    /// Open (creating parent dirs and the schema) at `path`.
    pub fn open(path: &std::path::Path) -> Result<Self> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(err)?;
        }
        Self::init(Connection::open(path).map_err(err)?, path.display().to_string())
    }

    pub fn in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory().map_err(err)?, ":memory:".into())
    }

    fn init(conn: Connection, location: String) -> Result<Self> {
        conn.execute_batch(SCHEMA).map_err(err)?;
        Ok(Self { conn, location })
    }
}

impl Store for SqliteStore {
    fn insert(&mut self, s: StoredSession) -> Result<u64> {
        let m = &s.meta;
        let summary = m.summary.as_ref().map(serde_json::Value::to_string);
        self.conn
            .execute(
                "INSERT INTO sessions (started_unix_ms, duration_s, device_id, device_name, protocol, summary_json, eeg_samples, ppg_samples, feedback_seconds, device_json, body) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                params![m.started_unix_ms, m.duration_s, m.device_id, m.device_name, m.protocol, summary, i(m.eeg_samples), i(m.ppg_samples), i(m.feedback_seconds), s.device_json, s.body],
            )
            .map_err(err)?;
        Ok(self.conn.last_insert_rowid().unsigned_abs())
    }

    fn list(&self) -> Result<Vec<SessionMeta>> {
        let mut st = self.conn.prepare(&format!("SELECT {META} FROM sessions ORDER BY id DESC")).map_err(err)?;
        let rows = st.query_map([], meta).map_err(err)?;
        rows.collect::<rusqlite::Result<Vec<_>>>().map_err(err)
    }

    fn get(&self, id: u64) -> Result<Option<StoredSession>> {
        self.conn
            .query_row(&format!("SELECT {META}, device_json, body FROM sessions WHERE id = ?1"), [i(id)], |r| {
                Ok(StoredSession { meta: meta(r)?, device_json: r.get(11)?, body: r.get(12)? })
            })
            .optional()
            .map_err(err)
    }

    fn delete(&mut self, id: u64) -> Result<bool> {
        Ok(self.conn.execute("DELETE FROM sessions WHERE id = ?1", [i(id)]).map_err(err)? > 0)
    }

    fn location(&self) -> String {
        self.location.clone()
    }
}
