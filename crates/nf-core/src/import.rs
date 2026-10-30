//! History import: `nf_import` parses the file; EEG imports then run
//! through the live band pipeline ([`Signal`]) so their bands match what a
//! live session of the same signal would have recorded.

use crate::signal::{MainsMode, Signal};
use crate::CoreError;
use nf_format::BodyWriter;
pub use nf_format::Record;
use nf_import::{Imported, Options, Summary};
use nf_types::EegPacket;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Raw upload cap (base64-decoded), ~1.5 h of Crown EDF.
pub const MAX_IMPORT_BYTES: usize = 96 * 1024 * 1024;
/// Records per body frame (≈ 1 s of Muse EEG + bands).
const FRAME_RECORDS: usize = 96;

/// `history.import` / `history.import_preview` parameters.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct ImportRequest {
    /// Source name; the extension picks the format (`.edf`, `.csv`,
    /// `.neurofeed`, `.raw`), else the bytes are sniffed.
    pub file_name: String,
    /// File contents, standard base64.
    pub data_base64: String,
    /// Local UTC offset for local wall-clock stamps (EDF, Mind Monitor).
    #[serde(default)]
    pub utc_offset_minutes: Option<i32>,
}

/// What the pre-save dialog shows.
#[derive(Debug, Clone, PartialEq, Serialize, JsonSchema)]
pub struct Preview {
    pub summary: Summary,
    pub device: nf_types::DeviceInfo,
    pub duration_s: f64,
    pub started_unix_ms: Option<f64>,
    pub provenance: nf_import::Provenance,
}

/// A parsed import, bands filled in, ready to store.
pub struct Prepared {
    pub imported: Imported,
    pub body: Vec<u8>,
}

impl Prepared {
    /// The row for [`crate::Session::import_save`].
    pub fn into_stored(self) -> nf_store::StoredSession {
        let meta = meta(&self);
        nf_store::StoredSession { meta, device_json: serde_json::to_string(&self.imported.device).unwrap_or_default(), body: self.body }
    }

    pub fn preview(&self) -> Preview {
        let i = &self.imported;
        Preview {
            summary: nf_import::summary(i),
            device: i.device.clone(),
            duration_s: i.duration_s,
            started_unix_ms: i.started_unix_ms,
            provenance: i.provenance.clone(),
        }
    }
}

pub fn prepare(bytes: &[u8], file_name: &str, utc_offset_minutes: i32, mains: MainsMode) -> Result<Prepared, CoreError> {
    if bytes.len() > MAX_IMPORT_BYTES {
        return Err(CoreError::InvalidArgs(format!("file is larger than {} MB", MAX_IMPORT_BYTES >> 20)));
    }
    let mut imported =
        nf_import::import(bytes, Options { file_name, utc_offset_minutes }).map_err(|e| CoreError::BadRequest(e.to_string()))?;
    if imported.needs_bands {
        add_bands(&mut imported, mains);
    }
    let body = write_body(&imported.records);
    Ok(Prepared { imported, body })
}

/// Replay EEG through the live pipeline; bands land after the packet that
/// completed them, as in a live recording.
fn add_bands(i: &mut Imported, mains: MainsMode) {
    let mut sig = Signal::new(&i.device, mains);
    let mut out = Vec::with_capacity(i.records.len() + i.records.len() / 4);
    for r in i.records.drain(..) {
        let snap = match &r {
            Record::Eeg { ts, electrode, samples } => {
                sig.push(&EegPacket { time: *ts, electrode: u16::try_from(*electrode).unwrap_or(u16::MAX), samples: samples.clone() })
            }
            _ => None,
        };
        out.push(r);
        if let Some(s) = snap {
            out.extend(s.powers.iter().enumerate().map(|(ch, b)| Record::Bands {
                ts: s.time,
                electrode: i16::try_from(ch).unwrap_or(i16::MAX),
                bands: *b,
            }));
        }
    }
    i.records = out;
    i.needs_bands = false;
}

fn write_body(records: &[Record]) -> Vec<u8> {
    let mut w = BodyWriter::new();
    for chunk in records.chunks(FRAME_RECORDS) {
        for r in chunk {
            w.push(r);
        }
        w.flush_frame();
    }
    w.finish()
}

/// Store metadata for a prepared import.
pub fn meta(p: &Prepared) -> nf_store::SessionMeta {
    let i = &p.imported;
    nf_store::SessionMeta {
        id: 0,
        started_unix_ms: i.started_unix_ms,
        duration_s: i.duration_s,
        device_id: i.device.id.clone(),
        device_name: i.device.name.clone(),
        protocol: None,
        summary: None,
        eeg_samples: i.eeg_samples(),
        ppg_samples: i.ppg_samples(),
        feedback_seconds: 0,
        bytes: p.body.len() as u64,
        import: serde_json::to_value(&i.provenance).ok(),
    }
}

/// Standard base64 encode (same as `recording.export`).
pub fn base64_encode(bytes: &[u8]) -> String {
    crate::recording::base64(bytes)
}

/// Standard base64 decode (padding optional, whitespace ignored).
pub fn base64_decode(s: &str) -> Result<Vec<u8>, CoreError> {
    let val = |c: u8| -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            _ => return None,
        } as u32)
    };
    let clean: Vec<u8> = s.bytes().filter(|b| !b.is_ascii_whitespace() && *b != b'=').collect();
    let mut out = Vec::with_capacity(clean.len() * 3 / 4);
    for chunk in clean.chunks(4) {
        let mut n = 0u32;
        for (k, &c) in chunk.iter().enumerate() {
            n |= val(c).ok_or_else(|| CoreError::InvalidArgs("data_base64 is not base64".into()))? << (18 - 6 * k);
        }
        let bytes = n.to_be_bytes();
        out.extend_from_slice(&bytes[1..chunk.len()]);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn base64_round_trip() {
        for data in [&b""[..], b"f", b"fo", b"foo", b"foob", b"\x00\xff\x10"] {
            assert_eq!(base64_decode(&crate::recording::base64(data)).unwrap(), data);
        }
        assert!(base64_decode("!!").is_err());
    }
}
