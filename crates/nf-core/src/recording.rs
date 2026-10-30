//! In-memory recording to the NFEDBIN raw body (nf-format). The core has no
//! file system: `recording.export` returns bytes (base64) and the shell
//! (desktop, web download, Android) decides where they go.

use nf_format::body::BodyWriter;
use nf_format::Record;
use nf_types::{BandSnapshot, DeviceInfo, EegPacket, PpgPacket};
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
    pub ppg_samples: u64,
    pub feedback_seconds: u64,
    pub bytes: usize,
    /// Injected wall-clock start (Unix ms, UTC), if the shell provided one.
    pub wall_clock_unix_ms: Option<f64>,
}

#[derive(Debug, Clone)]
pub struct Recorder {
    pub device: DeviceInfo,
    writer: BodyWriter,
    last_flush: f64,
    /// Feedback seconds, appended at the end of the body (see nf-format tag 11).
    feedback: Vec<Record>,
    accel_seq: u16,
    pub info: RecordingInfo,
}

impl Recorder {
    pub fn start(device: DeviceInfo, now: f64, wall_clock_unix_ms: Option<f64>) -> Self {
        let info = RecordingInfo {
            active: true,
            device: device.id.clone(),
            started: now,
            duration: 0.0,
            eeg_samples: 0,
            ppg_samples: 0,
            feedback_seconds: 0,
            bytes: 12,
            wall_clock_unix_ms,
        };
        Self { device, writer: BodyWriter::new(), last_flush: now, feedback: Vec::new(), accel_seq: 0, info }
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

    pub fn ppg(&mut self, p: &PpgPacket) {
        self.writer.push(&Record::Ppg { ts: p.time, channel: i16::try_from(p.channel).unwrap_or(i16::MAX), samples: p.samples.clone() });
        self.info.ppg_samples += p.samples.len() as u64;
    }

    pub fn accel(&mut self, p: &nf_types::AccelPacket) {
        self.writer.push(&Record::Accelerometer { ts: p.time, seq: self.accel_seq, xyz: p.samples.clone() });
        self.accel_seq = self.accel_seq.wrapping_add(1);
    }

    /// 1 Hz movement score (legacy tag 8).
    pub fn movement(&mut self, t: f64, score: f64) {
        self.writer.push(&Record::Movement { ts: t, score: score as f32 });
    }

    pub fn feedback(&mut self, r: &crate::feedback::SecondResult) {
        use crate::feedback::Phase;
        use nf_format::feedback_flags as f;
        let rec = r.record.as_ref();
        let mut flags = 0;
        for (on, bit) in [
            (r.counted, f::COUNTED),
            (r.in_target, f::IN_TARGET),
            (r.chime, f::CHIME),
            (rec.is_some_and(|x| x.dirty.is_some()) || (r.second.is_some() && !r.counted), f::DIRTY),
            (rec.is_some_and(|x| x.held_back.as_ref().is_some_and(|h| !h.is_empty())), f::HELD_BACK),
            (matches!(r.phase, Phase::Paused { .. }), f::PAUSED),
            (r.phase == Phase::Calibrating, f::CALIBRATING),
        ] {
            if on {
                flags |= bit;
            }
        }
        let nan = |v: Option<f64>| v.map_or(f32::NAN, |x| x as f32);
        self.feedback.push(Record::Feedback { ts: r.time, value: nan(r.value), threshold: nan(r.threshold), flags });
        self.info.feedback_seconds += 1;
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
        let mut writer = self.writer;
        writer.flush_frame();
        for r in &self.feedback {
            writer.push(r);
        }
        let body = writer.finish();
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
                "wall_clock_unix_ms": f.info.wall_clock_unix_ms,
                "clock": "record timestamps are session seconds; started = session time at wall_clock_unix_ms",
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

/// UTC civil time (y, m, d, h, min, s) of a Unix-ms timestamp (Howard
/// Hinnant's days-from-civil inverse). Pure arithmetic, no clock.
pub fn civil_utc(unix_ms: f64) -> (u16, u16, u16, u16, u16, u16) {
    let secs = (unix_ms / 1000.0).floor() as i64;
    let (days, sod) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    let c = |v: i64| u16::try_from(v).unwrap_or(0);
    (c(y), c(m), c(d), c(sod / 3600), c(sod % 3600 / 60), c(sod % 60))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_known_answers() {
        assert_eq!(civil_utc(0.0), (1970, 1, 1, 0, 0, 0));
        assert_eq!(civil_utc(951_782_400_000.0), (2000, 2, 29, 0, 0, 0));
        assert_eq!(civil_utc(1_793_267_696_000.0), (2026, 10, 29, 9, 54, 56));
    }

    #[test]
    fn base64_known_answers() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }
}
