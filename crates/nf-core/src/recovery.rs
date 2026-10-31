//! Crash recovery (legacy recording_recovery): while recording, the flushed
//! body is appended to the store every [`CHECKPOINT_S`] seconds with a small
//! "recovery" doc. A clean stop clears it; after a crash the next start
//! offers Recover (save what was written) or Discard.

use serde::{Deserialize, Serialize};

pub const CHECKPOINT_S: f64 = 10.0;
pub const DOC: &str = "recovery";
pub const BODY: &str = "recovery.body";
pub const FEEDBACK: &str = "recovery.feedback";

/// What the recovery doc records (enough to build the history row).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Pending {
    pub device_name: String,
    pub device_id: String,
    pub device_json: String,
    pub started_unix_ms: Option<f64>,
    /// Recorded seconds at the last checkpoint.
    pub duration_s: f64,
    pub eeg_samples: u64,
    pub ppg_samples: u64,
    pub feedback_seconds: u64,
    pub protocol: Option<String>,
    #[serde(default)]
    pub context: Option<serde_json::Value>,
}

/// Remove every trace of a pending recovery.
pub fn clear(store: &mut dyn nf_store::Store) {
    let _ = store.put_doc(DOC, None);
    let _ = store.clear_blob(BODY);
    let _ = store.clear_blob(FEEDBACK);
}

pub fn load(store: &dyn nf_store::Store) -> Option<Pending> {
    serde_json::from_str(&store.get_doc(DOC).ok()??).ok()
}

/// Build the history row from the checkpoints.
pub fn restore(store: &dyn nf_store::Store, p: &Pending) -> Result<nf_store::StoredSession, String> {
    let mut body = store.get_blob(BODY).map_err(|e| e.0)?.ok_or("nothing was checkpointed")?;
    body.extend(store.get_blob(FEEDBACK).map_err(|e| e.0)?.unwrap_or_default());
    let meta = nf_store::SessionMeta {
        id: 0,
        started_unix_ms: p.started_unix_ms,
        duration_s: p.duration_s,
        device_id: p.device_id.clone(),
        device_name: p.device_name.clone(),
        protocol: p.protocol.clone(),
        summary: None,
        eeg_samples: p.eeg_samples,
        ppg_samples: p.ppg_samples,
        feedback_seconds: p.feedback_seconds,
        bytes: body.len() as u64,
        import: None,
        notes: "Recovered after the app closed unexpectedly.".into(),
        context: p.context.clone(),
    };
    Ok(nf_store::StoredSession { meta, device_json: p.device_json.clone(), body })
}
