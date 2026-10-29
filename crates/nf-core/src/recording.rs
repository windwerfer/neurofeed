//! In-memory recording to the NFEDBIN raw body (nf-format). The core has no
//! file system: `recording.export` returns bytes (base64) and the shell
//! (desktop, web download, Android) decides where they go.

use nf_format::body::BodyWriter;
use nf_format::Record;
use nf_types::{BandSnapshot, DeviceInfo, EegPacket};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Frames are flushed every second of session time, like the legacy recorder.
const FLUSH_S: f64 = 1.0;
/// Hard cap so a forgotten recording cannot eat all memory (~1 h of Crown).
pub const MAX_BODY_BYTES: usize = 64 * 1024 * 1024;

/// Recording status as seen by enabled checks, the UI and MCP.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RecordingInfo {
    pub active: bool,
    pub device: String,
    /// Session time of the start (s).
    pub started: f64,
    pub duration: f64,
    pub eeg_samples: u64,
    pub bytes: usize,
}

#[derive(Debug, Clone)]
pub struct Recorder {
    pub device: DeviceInfo,
    writer: BodyWriter,
    last_flush: f64,
    pub info: RecordingInfo,
}

impl Recorder {
    pub fn start(device: DeviceInfo, now: f64) -> Self {
        let info = RecordingInfo { active: true, device: device.id.clone(), started: now, duration: 0.0, eeg_samples: 0, bytes: 12 };
        Self { device, writer: BodyWriter::new(), last_flush: now, info }
    }

    /// Returns false once the size cap is reached (caller stops).
    pub fn eeg(&mut self, p: &EegPacket) -> bool {
        self.writer.push(&Record::Eeg {
            ts: p.time,
            electrode: i16::try_from(p.electrode).unwrap_or(i16::MAX),
            samples: p.samples.clone(),
        });
        self.info.eeg_samples += p.samples.len() as u64;
        self.info.bytes = self.writer.len();
        self.info.bytes < MAX_BODY_BYTES
    }

    pub fn bands(&mut self, s: &BandSnapshot) {
        for (ch, b) in s.powers.iter().enumerate() {
            self.writer.push(&Record::Bands { ts: s.time, electrode: i16::try_from(ch).unwrap_or(i16::MAX), bands: *b });
        }
    }

    pub fn tick(&mut self, now: f64) {
        self.info.duration = (now - self.info.started).max(0.0);
        if now - self.last_flush >= FLUSH_S {
            self.writer.flush_frame();
            self.last_flush = now;
            self.info.bytes = self.writer.len();
        }
    }

    pub fn finish(self) -> Finished {
        let mut info = self.info;
        info.active = false;
        let body = self.writer.finish();
        info.bytes = body.len();
        Finished { device: self.device, info, body }
    }
}

#[derive(Debug, Clone)]
pub struct Finished {
    pub device: DeviceInfo,
    pub info: RecordingInfo,
    pub body: Vec<u8>,
}

/// Export targets for `recording.export`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ExportFormat {
    /// `.neurofeed` NFED6 container (metadata + raw body).
    Nfed6,
    /// Bare NFEDBIN raw body.
    RawBody,
    /// EDF+ (EEG channels only, raw µV).
    Edf,
}

impl ExportFormat {
    pub fn extension(self) -> &'static str {
        match self {
            ExportFormat::Nfed6 => "neurofeed",
            ExportFormat::RawBody => "raw",
            ExportFormat::Edf => "edf",
        }
    }
}

pub fn export(f: &Finished, format: ExportFormat, start: (u16, u16, u16, u16, u16, u16)) -> Result<Vec<u8>, String> {
    match format {
        ExportFormat::RawBody => Ok(f.body.clone()),
        ExportFormat::Nfed6 => {
            let meta = serde_json::json!({
                "format": "nfed6",
                "device": f.device,
                "started": f.info.started,
                "duration": f.info.duration,
                "eeg_samples": f.info.eeg_samples,
                "clock": "session seconds",
            });
            Ok(nf_format::encode_container(&nf_format::Container {
                thumbnail: Vec::new(),
                metadata_json: serde_json::to_vec(&meta).map_err(|e| e.to_string())?,
                computed_jsonl: Vec::new(),
                raw_body: f.body.clone(),
            }))
        }
        ExportFormat::Edf => {
            let records = nf_format::parse_body(&f.body).map_err(|e| e.0)?;
            let req = nf_format::edf::EdfRequest {
                labels: &f.device.channels,
                sample_rate_hz: f.device.sample_rate_hz.round() as usize,
                start,
                recording_id: "Startdate X X X neurofeed",
                prefiltering: "",
                annotations: &[],
            };
            nf_format::edf::records_to_edf(&records, &req).map_err(|e| e.0)
        }
    }
}

/// Standard base64 (RFC 4648, padded). Small enough not to need a crate.
pub fn base64(bytes: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for c in bytes.chunks(3) {
        let n = (u32::from(c[0]) << 16) | (u32::from(*c.get(1).unwrap_or(&0)) << 8) | u32::from(*c.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= c.len() {
                out.push(char::from(T[(n >> (18 - 6 * i) & 63) as usize]));
            } else {
                out.push('=');
            }
        }
    }
    out
}
