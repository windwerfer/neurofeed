//! Session history (L1, UI-free). A [`Store`] keeps finished sessions: their
//! metadata (device, protocol, feedback summary) and the raw NFEDBIN body
//! (EEG, PPG, accelerometer, bands, feedback seconds). Backends:
//! [`MemoryStore`] (wasm, tests) and `SqliteStore` (feature `sqlite`, native).

use serde::{Deserialize, Serialize};

#[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
mod sqlite;
#[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
pub use sqlite::SqliteStore;
#[cfg(all(feature = "indexeddb", target_arch = "wasm32"))]
mod idb;
#[cfg(all(feature = "indexeddb", target_arch = "wasm32"))]
pub use idb::IdbStore;

#[derive(Debug, thiserror::Error)]
#[error("store: {0}")]
pub struct StoreError(pub String);

pub type Result<T> = std::result::Result<T, StoreError>;

/// What a list row shows (no body).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionMeta {
    /// Assigned by the store, increasing.
    pub id: u64,
    /// Wall-clock start (Unix ms, UTC) if the shell injected one.
    pub started_unix_ms: Option<f64>,
    pub duration_s: f64,
    pub device_id: String,
    pub device_name: String,
    /// Feedback protocol id, `None` for a plain recording.
    pub protocol: Option<String>,
    /// Feedback summary (JSON of `nf_core::feedback::Summary`), if any.
    pub summary: Option<serde_json::Value>,
    pub eeg_samples: u64,
    pub ppg_samples: u64,
    pub feedback_seconds: u64,
    pub bytes: u64,
}

/// A full stored session.
#[derive(Debug, Clone, PartialEq)]
pub struct StoredSession {
    pub meta: SessionMeta,
    /// `DeviceInfo` as JSON (kept opaque here so this crate stays L1-free).
    pub device_json: String,
    /// NFEDBIN body.
    pub body: Vec<u8>,
}

/// Session storage. `insert` ignores `meta.id` and returns the new id.
pub trait Store: Send {
    fn insert(&mut self, session: StoredSession) -> Result<u64>;
    /// Newest first.
    fn list(&self) -> Result<Vec<SessionMeta>>;
    fn get(&self, id: u64) -> Result<Option<StoredSession>>;
    /// True if it existed.
    fn delete(&mut self, id: u64) -> Result<bool>;
    /// Where the data lives (for status / UI), e.g. `memory` or a file path.
    fn location(&self) -> String;
    /// True once after the backend changed behind the caller's back (e.g. an
    /// async IndexedDB load finished); the session then re-lists.
    fn take_changed(&mut self) -> bool {
        false
    }
}

/// Volatile store (wasm today, tests).
#[derive(Debug, Default)]
pub struct MemoryStore {
    next: u64,
    rows: Vec<StoredSession>,
}

impl MemoryStore {
    /// Add rows read from a persistent backend, keeping their ids. Rows
    /// inserted locally before the load are renumbered above them.
    /// Returns the new ids of the renumbered local rows.
    pub fn merge_loaded(&mut self, loaded: Vec<StoredSession>) -> Vec<u64> {
        let local = std::mem::take(&mut self.rows);
        self.next = loaded.iter().map(|s| s.meta.id).max().unwrap_or(0);
        self.rows = loaded;
        self.rows.sort_by_key(|s| s.meta.id);
        local.into_iter().filter_map(|s| self.insert(s).ok()).collect()
    }
}

impl Store for MemoryStore {
    fn insert(&mut self, mut s: StoredSession) -> Result<u64> {
        self.next += 1;
        s.meta.id = self.next;
        self.rows.push(s);
        Ok(self.next)
    }
    fn list(&self) -> Result<Vec<SessionMeta>> {
        Ok(self.rows.iter().rev().map(|s| s.meta.clone()).collect())
    }
    fn get(&self, id: u64) -> Result<Option<StoredSession>> {
        Ok(self.rows.iter().find(|s| s.meta.id == id).cloned())
    }
    fn delete(&mut self, id: u64) -> Result<bool> {
        let n = self.rows.len();
        self.rows.retain(|s| s.meta.id != id);
        Ok(self.rows.len() != n)
    }
    fn location(&self) -> String {
        "memory".into()
    }
}
