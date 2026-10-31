//! Session history (L1, UI-free). A [`Store`] keeps finished sessions: their
//! metadata (device, protocol, feedback summary) and the raw NFEDBIN body
//! (EEG, PPG, accelerometer, bands, feedback seconds). Backends:
//! [`MemoryStore`] (wasm, tests) and `SqliteStore` (feature `sqlite`, native).

use serde::{Deserialize, Serialize};

#[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
mod sqlite;
#[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
pub use sqlite::{sqlite_exec_for_tests, SqliteStore};
#[cfg(all(feature = "indexeddb", target_arch = "wasm32"))]
mod idb;
#[cfg(all(feature = "indexeddb", target_arch = "wasm32"))]
pub use idb::IdbStore;

#[derive(Debug, thiserror::Error)]
#[error("store: {0}")]
pub struct StoreError(pub String);

pub type Result<T> = std::result::Result<T, StoreError>;

/// What a list row shows (no body).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
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
    /// Import provenance (`nf_import::Provenance` as JSON) for imported sessions.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub import: Option<serde_json::Value>,
    /// Free-text notes the user wrote about the session (editable later).
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub notes: String,
    /// Recording context snapshot (time zone, protocol, settings, app version).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<serde_json::Value>,
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
    /// Replace a session's notes. True if the session exists.
    fn set_notes(&mut self, id: u64, notes: &str) -> Result<bool>;
    /// A small named JSON document (custom protocols, ...).
    fn get_doc(&self, key: &str) -> Result<Option<String>>;
    /// Write a named document; `None` removes it.
    fn put_doc(&mut self, key: &str, value: Option<&str>) -> Result<()>;
    /// True once after the backend changed behind the caller's back (e.g. an
    /// async IndexedDB load finished); the session then re-lists.
    fn take_changed(&mut self) -> bool {
        false
    }
    /// Append bytes to a named blob (crash-recovery checkpoints). Backends
    /// without blob support (IndexedDB today) keep nothing.
    fn append_blob(&mut self, _key: &str, _bytes: &[u8]) -> Result<()> {
        Ok(())
    }
    /// The whole blob, `None` if absent.
    fn get_blob(&self, _key: &str) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }
    fn clear_blob(&mut self, _key: &str) -> Result<()> {
        Ok(())
    }
    /// Copy the whole store to `path` (Settings → Storage → Move). Only file
    /// backends support it.
    fn copy_to(&self, _path: &std::path::Path) -> Result<()> {
        Err(StoreError("this storage cannot be moved".into()))
    }
}

/// Volatile store (wasm today, tests).
#[derive(Debug, Default)]
pub struct MemoryStore {
    next: u64,
    rows: Vec<StoredSession>,
    docs: std::collections::BTreeMap<String, String>,
    blobs: std::collections::BTreeMap<String, Vec<u8>>,
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
    fn set_notes(&mut self, id: u64, notes: &str) -> Result<bool> {
        Ok(self.rows.iter_mut().find(|s| s.meta.id == id).map(|s| s.meta.notes = notes.to_owned()).is_some())
    }
    fn location(&self) -> String {
        "memory".into()
    }
    fn get_doc(&self, key: &str) -> Result<Option<String>> {
        Ok(self.docs.get(key).cloned())
    }
    fn put_doc(&mut self, key: &str, value: Option<&str>) -> Result<()> {
        match value {
            Some(v) => self.docs.insert(key.to_owned(), v.to_owned()),
            None => self.docs.remove(key),
        };
        Ok(())
    }
    fn append_blob(&mut self, key: &str, bytes: &[u8]) -> Result<()> {
        self.blobs.entry(key.to_owned()).or_default().extend_from_slice(bytes);
        Ok(())
    }
    fn get_blob(&self, key: &str) -> Result<Option<Vec<u8>>> {
        Ok(self.blobs.get(key).cloned())
    }
    fn clear_blob(&mut self, key: &str) -> Result<()> {
        self.blobs.remove(key);
        Ok(())
    }
}
