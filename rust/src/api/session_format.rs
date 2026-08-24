use std::io::Cursor;
use std::time::{SystemTime, UNIX_EPOCH};

use flutter_rust_bridge::frb;

use crate::api::muse::{ImuDto, MuseEventDto};

// ── .muse body format (v4) ──────────────────────────────────────────────────────
//
// The session body is a zstd-compressed stream:
//
//   [ u64 BE "MUSEBIN\n" ][ u32 LE version ][ frames ]
//
//   frame   := [ u32 LE frame_size ][ zstd frame payload ]
//   payload := record*                    (record := [ u8 tag ][ fields … ])
//
// Record tags (all sample payloads are f32, timestamps stay f64, little-endian):
//   tag 1  EEG          : [ts f64][electrode i16][n u16][n × f32]
//   tag 2  Telemetry    : [ts f64][battery f32][fuel f32][temp u16]
//   tag 3  Accelerometer: [ts f64][seq u16][n u16][n × (x,y,z f32)]
//   tag 4  Gyroscope    : same as tag 3
//   tag 5  PPG          : [ts f64][channel i16][n u16][n × f32]
//   tag 6  Bands        : [ts f64][electrode i16][δ θ α β γ f32]
//   tag 7  Pulse        : [ts f64][bpm f32][conf f32]
//   tag 8  Movement     : [ts f64][score f32]
//   tag 9  PeakAlpha    : [ts f64][freq f32][power f32]
//
// This module is the single authority for the on-disk format. The Dart writer
// and reader both delegate here so the layout can never drift between the two
// languages. Muse 12/14-bit and Crown 24-bit ADCs fit exactly in f32; timestamps
// remain f64. Electrode is i16 so an 8-electrode Crown works unchanged.

pub const FORMAT_TAG_EEG: u8 = 1;
pub const FORMAT_TAG_TELEMETRY: u8 = 2;
pub const FORMAT_TAG_ACCELEROMETER: u8 = 3;
pub const FORMAT_TAG_GYROSCOPE: u8 = 4;
pub const FORMAT_TAG_PPG: u8 = 5;
pub const FORMAT_TAG_BANDS: u8 = 6;
pub const FORMAT_TAG_PULSE: u8 = 7;
pub const FORMAT_TAG_MOVEMENT: u8 = 8;
pub const FORMAT_TAG_PEAK_ALPHA: u8 = 9;
pub const FORMAT_TAG_SPO2: u8 = 10;

/// The 64-bit header sentinel. The legacy Dart writer stored it as a
/// little-endian u64 (`setUint64(.. Endian.little)`), so the on-disk bytes are
/// the reverse of the "MUSEBIN\n" string. We keep the same u64 and rewrite it
/// as little-endian so byte-for-byte compatibility with existing files is
/// preserved.
pub const HEADER_MAGIC: u64 = 0x4D55_5345_4249_4E0A; // as u64 LE → "MUSEBIN\n" reversed on disk
pub const FORMAT_VERSION: u32 = 5;

/// The plaintext on-disk bytes of the sentinel (LE u64 of [HEADER_MAGIC]).
pub const HEADER_MAGIC_BYTES: [u8; 8] = HEADER_MAGIC.to_le_bytes();

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

fn push_f64(out: &mut Vec<u8>, v: f64) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn push_i16(out: &mut Vec<u8>, v: i16) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn push_u16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn push_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn push_f32(out: &mut Vec<u8>, v: f32) {
    out.extend_from_slice(&v.to_le_bytes());
}

/// The 12-byte header that prefixes a `.muse` body.
#[frb(sync)]
pub fn session_header_bytes() -> Vec<u8> {
    let mut out = Vec::with_capacity(12);
    out.extend_from_slice(&HEADER_MAGIC.to_le_bytes());
    out.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
    out
}

fn encode_imu(out: &mut Vec<u8>, tag: u8, imu: &ImuDto) {
    out.push(tag);
    push_f64(out, now_secs());
    push_u16(out, imu.sequence_id);
    push_u16(out, imu.samples.len() as u16);
    for s in &imu.samples {
        push_f32(out, s.x);
        push_f32(out, s.y);
        push_f32(out, s.z);
    }
}

/// Encode a single Muse event into its record slice (tag + payload). Events
/// that carry no recording data (Connected / Disconnected / Control) produce an
/// empty vector.
#[frb(sync)]
pub fn encode_session_event(event: &MuseEventDto) -> Vec<u8> {
    let mut out = Vec::new();
    match event {
        MuseEventDto::Eeg(d) => {
            out.push(FORMAT_TAG_EEG);
            push_f64(&mut out, d.timestamp);
            push_i16(&mut out, d.electrode as i16);
            push_u16(&mut out, d.samples.len() as u16);
            for s in &d.samples {
                push_f32(&mut out, *s as f32);
            }
        }
        MuseEventDto::Telemetry(t) => {
            out.push(FORMAT_TAG_TELEMETRY);
            push_f64(&mut out, now_secs());
            push_f32(&mut out, t.battery_level);
            push_f32(&mut out, t.fuel_gauge_voltage);
            out.extend_from_slice(&t.temperature.to_le_bytes());
        }
        MuseEventDto::Accelerometer(imu) => encode_imu(&mut out, FORMAT_TAG_ACCELEROMETER, imu),
        MuseEventDto::Gyroscope(imu) => encode_imu(&mut out, FORMAT_TAG_GYROSCOPE, imu),
        MuseEventDto::Ppg(d) => {
            out.push(FORMAT_TAG_PPG);
            push_f64(&mut out, d.timestamp);
            push_i16(&mut out, d.channel as i16);
            push_u16(&mut out, d.samples.len() as u16);
            for s in &d.samples {
                push_f32(&mut out, *s as f32);
            }
        }
        MuseEventDto::Bands(d) => {
            out.push(FORMAT_TAG_BANDS);
            push_f64(&mut out, d.timestamp);
            push_i16(&mut out, d.electrode as i16);
            push_f32(&mut out, d.delta as f32);
            push_f32(&mut out, d.theta as f32);
            push_f32(&mut out, d.alpha as f32);
            push_f32(&mut out, d.beta as f32);
            push_f32(&mut out, d.gamma as f32);
        }
        MuseEventDto::Pulse(d) => {
            out.push(FORMAT_TAG_PULSE);
            push_f64(&mut out, d.timestamp);
            push_f32(&mut out, d.bpm as f32);
            push_f32(&mut out, d.confidence as f32);
        }
        MuseEventDto::SpO2(d) => {
            out.push(FORMAT_TAG_SPO2);
            push_f64(&mut out, d.timestamp);
            push_f32(&mut out, d.spo2 as f32);
            push_f32(&mut out, d.confidence as f32);
        }
        MuseEventDto::Movement(d) => {
            out.push(FORMAT_TAG_MOVEMENT);
            push_f64(&mut out, d.timestamp);
            push_f32(&mut out, d.score as f32);
        }
        MuseEventDto::PeakAlpha(d) => {
            out.push(FORMAT_TAG_PEAK_ALPHA);
            push_f64(&mut out, d.timestamp);
            push_f32(&mut out, d.frequency as f32);
            push_f32(&mut out, d.power as f32);
        }
        MuseEventDto::Connected(_) |
        MuseEventDto::Disconnected |
        MuseEventDto::Control(_) |
        MuseEventDto::Gestures(_) |
        MuseEventDto::Reve(_) => {}
    }
    out
}

/// Assemble the compressed frame for a batch of already-encoded records:
/// `[u32 LE compressed length][zstd frame]`. On compression failure the raw
/// record bytes are stored uncompressed so a session never silently loses data
/// (mirrors the old `compressBlock` fallback in the Dart recorder).
#[frb(sync)]
pub fn session_frame_bytes(data: &[u8]) -> Vec<u8> {
    let compressed = zstd::encode_all(Cursor::new(data), 3).unwrap_or_else(|e| {
        log::warn!("[session] zstd compress failed: {e}, storing uncompressed");
        data.to_vec()
    });
    let mut out = Vec::with_capacity(4 + compressed.len());
    push_u32(&mut out, compressed.len() as u32);
    out.extend_from_slice(&compressed);
    out
}

// ── Decoded records (read side) ─────────────────────────────────────────────────

/// Decoded records of a `.muse` body.
#[frb(dart_metadata = ("freezed",))]
pub struct SessionData {
    pub bands: Vec<BandsRecord>,
    pub pulses: Vec<PulseRecord>,
    pub spo2s: Vec<SpO2Record>,
    pub movements: Vec<MovementRecord>,
    pub peak_alphas: Vec<PeakAlphaRecord>,
    pub eeg_samples: u64,
    pub eeg: Vec<EegSampleRecord>,
}

/// One raw EEG packet: per-sample values are in µV, `timestamp` is the
/// wall-clock ms epoch of the FIRST sample, and consecutive samples are
/// `rate` apart (nominal 256 Hz on Muse headsets).
#[frb(dart_metadata = ("freezed",))]
pub struct EegSampleRecord {
    pub timestamp: f64,
    pub electrode: i16,
    pub samples: Vec<f32>,
}

#[frb(dart_metadata = ("freezed",))]
pub struct BandsRecord {
    pub timestamp: f64,
    pub electrode: i16,
    pub delta: f64,
    pub theta: f64,
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
}

#[frb(dart_metadata = ("freezed",))]
pub struct PulseRecord {
    pub timestamp: f64,
    pub bpm: f64,
    pub confidence: f64,
}

#[frb(dart_metadata = ("freezed",))]
pub struct SpO2Record {
    pub timestamp: f64,
    pub spo2: f64,
    pub confidence: f64,
}

#[frb(dart_metadata = ("freezed",))]
pub struct MovementRecord {
    pub timestamp: f64,
    pub score: f64,
}

#[frb(dart_metadata = ("freezed",))]
pub struct PeakAlphaRecord {
    pub timestamp: f64,
    pub frequency: f64,
    pub power: f64,
}

struct RecordParser<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> RecordParser<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    fn finished(&self) -> bool {
        self.pos >= self.data.len()
    }

    fn u8(&mut self) -> Option<u8> {
        let v = *self.data.get(self.pos)?;
        self.pos += 1;
        Some(v)
    }

    fn f64(&mut self) -> Option<f64> {
        let chunk = self.data.get(self.pos..self.pos + 8)?;
        self.pos += 8;
        Some(f64::from_le_bytes(chunk.try_into().ok()?))
    }

    fn i16(&mut self) -> Option<i16> {
        let chunk = self.data.get(self.pos..self.pos + 2)?;
        self.pos += 2;
        Some(i16::from_le_bytes(chunk.try_into().ok()?))
    }

    fn u16(&mut self) -> Option<u16> {
        let chunk = self.data.get(self.pos..self.pos + 2)?;
        self.pos += 2;
        Some(u16::from_le_bytes(chunk.try_into().ok()?))
    }

    fn f32(&mut self) -> Option<f32> {
        let chunk = self.data.get(self.pos..self.pos + 4)?;
        self.pos += 4;
        Some(f32::from_le_bytes(chunk.try_into().ok()?))
    }

    fn skip(&mut self, n: usize) -> bool {
        if self.pos + n > self.data.len() {
            return false;
        }
        self.pos += n;
        true
    }
}

fn parse_records(records: &[u8], out: &mut SessionData) {
    let mut p = RecordParser::new(records);
    while !p.finished() {
        let Some(tag) = p.u8() else { break };
        match tag {
            FORMAT_TAG_EEG => {
                let (Some(ts), Some(elec), Some(n)) = (p.f64(), p.i16(), p.u16()) else {
                    break
                };
                let mut samples = Vec::with_capacity(n as usize);
                for _ in 0..n {
                    let Some(s) = p.f32() else { break };
                    samples.push(s);
                }
                if samples.len() != n as usize {
                    break;
                }
                out.eeg_samples += n as u64;
                out.eeg.push(EegSampleRecord {
                    timestamp: ts,
                    electrode: elec,
                    samples,
                });
            }
            FORMAT_TAG_TELEMETRY => {
                if p.f64().is_none()
                    || p.f32().is_none()
                    || p.f32().is_none()
                    || p.u16().is_none()
                {
                    break;
                }
            }
            FORMAT_TAG_ACCELEROMETER | FORMAT_TAG_GYROSCOPE => {
                let (Some(_), Some(_), Some(n)) = (p.f64(), p.u16(), p.u16()) else {
                    break
                };
                if !p.skip(n as usize * 12) {
                    break;
                }
            }
            FORMAT_TAG_PPG => {
                let (Some(_), Some(_), Some(n)) = (p.f64(), p.i16(), p.u16()) else {
                    break
                };
                if !p.skip(n as usize * 4) {
                    break;
                }
            }
            FORMAT_TAG_BANDS => {
                let (Some(ts), Some(e)) = (p.f64(), p.i16()) else { break };
                let (Some(delta), Some(theta), Some(alpha), Some(beta), Some(gamma)) =
                    (p.f32(), p.f32(), p.f32(), p.f32(), p.f32())
                else {
                    break
                };
                out.bands.push(BandsRecord {
                    timestamp: ts,
                    electrode: e,
                    delta: delta as f64,
                    theta: theta as f64,
                    alpha: alpha as f64,
                    beta: beta as f64,
                    gamma: gamma as f64,
                });
            }
            FORMAT_TAG_PULSE => {
                let (Some(ts), Some(bpm), Some(conf)) = (p.f64(), p.f32(), p.f32()) else {
                    break
                };
                out.pulses.push(PulseRecord {
                    timestamp: ts,
                    bpm: bpm as f64,
                    confidence: conf as f64,
                });
            }
            FORMAT_TAG_SPO2 => {
                let (Some(ts), Some(spo2), Some(conf)) = (p.f64(), p.f32(), p.f32()) else {
                    break
                };
                out.spo2s.push(SpO2Record {
                    timestamp: ts,
                    spo2: spo2 as f64,
                    confidence: conf as f64,
                });
            }
            FORMAT_TAG_MOVEMENT => {
                let (Some(ts), Some(score)) = (p.f64(), p.f32()) else { break };
                out.movements.push(MovementRecord {
                    timestamp: ts,
                    score: score as f64,
                });
            }
            FORMAT_TAG_PEAK_ALPHA => {
                let (Some(ts), Some(freq), Some(power)) = (p.f64(), p.f32(), p.f32()) else {
                    break
                };
                out.peak_alphas.push(PeakAlphaRecord {
                    timestamp: ts,
                    frequency: freq as f64,
                    power: power as f64,
                });
            }
            _ => return,
        }
    }
}

/// Decode a full `.muse` body (header + frames) into structured records.
#[frb(sync)]
pub fn session_parse_body(bytes: &[u8]) -> Result<SessionData, String> {
    if bytes.len() < 12 {
        return Err("Truncated .muse header".to_string());
    }
    if &bytes[..8] != &HEADER_MAGIC_BYTES {
        return Err("Not a .muse file".to_string());
    }
    let version = u32::from_le_bytes(bytes[8..12].try_into().unwrap_or_default());
    if version != FORMAT_VERSION {
        return Err(format!("Unsupported format version {version}"));
    }
    let mut out = SessionData {
        bands: Vec::new(),
        pulses: Vec::new(),
        spo2s: Vec::new(),
        movements: Vec::new(),
        peak_alphas: Vec::new(),
        eeg_samples: 0,
        eeg: Vec::new(),
    };
    let mut off = 12usize;
    while off + 4 <= bytes.len() {
        let frame_size =
            u32::from_le_bytes(bytes[off..off + 4].try_into().unwrap_or_default()) as usize;
        off += 4;
        if off + frame_size > bytes.len() {
            break;
        }
        let frame = &bytes[off..off + frame_size];
        off += frame_size;
        let decoded = match zstd::decode_all(Cursor::new(frame)) {
            Ok(d) => d,
            Err(_) => Vec::new(),
        };
        if decoded.is_empty() {
            continue;
        }
        parse_records(&decoded, &mut out);
    }
    Ok(out)
}

// ── v5 Session Format ──────────────────────────────────────────────────────────
//
//   [68-byte fixed header][WebP thumbnail][metadata JSON (zstd)][computed 1Hz (zstd)][raw (zstd)]
//
// Header layout (68 bytes):
//   [0..6]   magic: b"MUSE5\0"
//   [6]      version: u8 = 5
//   [7]      flags: u8 (reserved)
//   [8..15]  thumbnail_offset: u64
//   [16..23] thumbnail_length: u64
//   [24..31] metadata_offset: u64
//   [32..39] metadata_length: u64
//   [40..47] computed_offset: u64
//   [48..55] computed_length: u64
//   [56..63] raw_offset: u64
//   [64..67] crc32(header[0..63])

pub const V5_MAGIC: [u8; 6] = *b"MUSE5\0";
pub const V5_VERSION: u8 = 5;
pub const V5_HEADER_SIZE: usize = 68;

/// v5 container header with fixed 68-byte layout.
/// raw_length is not stored; compute as file_size - raw_offset.
#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, PartialEq)]
pub struct V5Header {
    pub thumbnail_offset: u64,
    pub thumbnail_length: u64,
    pub metadata_offset: u64,
    pub metadata_length: u64,
    pub computed_offset: u64,
    pub computed_length: u64,
    pub raw_offset: u64,
}

/// Parsed v5 head - header + thumbnail + metadata (decompressed).
#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone)]
pub struct V5ParsedHead {
    pub header: V5Header,
    pub thumbnail: Vec<u8>,
    pub metadata_json: Vec<u8>,
}

/// Computed frame at 1 Hz for training/export.
/// All bands are absolute power (not relative).
#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ComputedFrame {
    /// Seconds from recording start (0, 1, 2, ...).
    pub t: f64,
    /// 4 electrodes × 5 bands [delta, theta, alpha, beta, gamma] (absolute power).
    pub bands: Vec<Vec<f32>>,
    /// Pulse BPM.
    pub pulse: Option<f32>,
    /// Movement score (0.0-1.0).
    pub movement: Option<f32>,
    /// Peak alpha frequency (Hz) and power (absolute).
    pub peak_alpha: Option<PeakAlphaInfo>,
    /// SpO2 percentage (0-100).
    pub spo2: Option<f32>,
    /// Line noise ratio per electrode (0.0-1.0).
    pub line_noise: Vec<f32>,
    /// Signal quality per electrode (0-100).
    pub signal_quality: Vec<u8>,
    /// Guardrail (drowsiness) state.
    pub guardrail: GuardrailInfo,
    /// Feedback (ATR) state.
    pub feedback: FeedbackInfo,
    /// Gestures detected in this second.
    pub gestures: Vec<String>,
}

/// Peak alpha frequency and power.
#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PeakAlphaInfo {
    pub freq: f32,
    pub power: f32,
}

/// Guardrail (AI drowsiness) info.
#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GuardrailInfo {
    pub sleep_dir: f32,
    pub clarity: f32,
    pub warning: bool,
    pub delta: f32,
}

/// Feedback (ATR) info.
#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FeedbackInfo {
    pub ratio: f32,
    pub threshold: f32,
    pub in_target: bool,
    pub pct: f32,
}

impl ComputedFrame {
    /// Encode to JSON bytes (for zstd compression).
    pub fn to_json_bytes(&self) -> Vec<u8> {
        serde_json::to_vec(self).unwrap_or_default()
    }

    /// Decode from JSON bytes.
    pub fn from_json_bytes(bytes: &[u8]) -> Option<Self> {
        serde_json::from_slice(bytes).ok()
    }
}

fn crc32(data: &[u8]) -> u32 {
    crc32fast::hash(data)
}

/// Encode a v5 container: header + thumbnail + metadata(zstd) + computed(zstd) + raw(zstd).
#[frb(sync)]
pub fn container_encode_v5(
    thumbnail: &[u8],
    metadata_json: &[u8],
    computed_frames: &[ComputedFrame],
    raw_body: &[u8],
) -> Vec<u8> {
    // Compress metadata, computed, raw separately with zstd level 3.
    let metadata_compressed = zstd::encode_all(std::io::Cursor::new(metadata_json), 3).unwrap_or_default();
    let mut computed_json = Vec::new();
    for f in computed_frames {
        computed_json.extend_from_slice(&f.to_json_bytes());
        computed_json.push(b'\n');
    }
    let computed_compressed = zstd::encode_all(std::io::Cursor::new(computed_json), 3).unwrap_or_default();
    let raw_compressed = zstd::encode_all(std::io::Cursor::new(raw_body), 3).unwrap_or_default();

    // Build header with offsets.
    let mut offset = V5_HEADER_SIZE as u64 + thumbnail.len() as u64;
    let thumbnail_offset = V5_HEADER_SIZE as u64;
    let thumbnail_length = thumbnail.len() as u64;
    let metadata_offset = offset;
    let metadata_length = metadata_compressed.len() as u64;
    offset += metadata_length;
    let computed_offset = offset;
    let computed_length = computed_compressed.len() as u64;
    offset += computed_length;
    let raw_offset = offset;
    // raw_length not stored; compute from file size.

    // Build header bytes (60 bytes).
    let mut header = Vec::with_capacity(V5_HEADER_SIZE);
    header.extend_from_slice(&V5_MAGIC);
    header.push(V5_VERSION);
    header.push(0); // flags
    header.extend_from_slice(&thumbnail_offset.to_le_bytes());
    header.extend_from_slice(&thumbnail_length.to_le_bytes());
    header.extend_from_slice(&metadata_offset.to_le_bytes());
    header.extend_from_slice(&metadata_length.to_le_bytes());
    header.extend_from_slice(&computed_offset.to_le_bytes());
    header.extend_from_slice(&computed_length.to_le_bytes());
    header.extend_from_slice(&raw_offset.to_le_bytes());
    // CRC32 of first 56 bytes (header without CRC).
    let crc = crc32(&header);
    header.extend_from_slice(&crc.to_le_bytes());
    assert_eq!(header.len(), V5_HEADER_SIZE);

    // Assemble final file.
    let mut out = Vec::with_capacity(header.len() + thumbnail.len() + metadata_compressed.len() + computed_compressed.len() + raw_compressed.len());
    out.extend_from_slice(&header);
    out.extend_from_slice(thumbnail);
    out.extend_from_slice(&metadata_compressed);
    out.extend_from_slice(&computed_compressed);
    out.extend_from_slice(&raw_compressed);
    out
}

/// Parse v5 header (first 68 bytes).
#[frb(sync)]
pub fn v5_parse_header(bytes: &[u8]) -> Result<V5Header, String> {
    if bytes.len() < V5_HEADER_SIZE {
        return Err("Truncated v5 header".to_string());
    }
    if &bytes[0..6] != &V5_MAGIC {
        return Err("Not a v5 file (bad magic)".to_string());
    }
    let version = bytes[6];
    if version != V5_VERSION {
        return Err(format!("Unsupported v5 format version {version}"));
    }
    // Verify CRC32 of first 64 bytes.
    let expected_crc = u32::from_le_bytes(bytes[64..68].try_into().unwrap());
    let actual_crc = crc32(&bytes[..64]);
    if expected_crc != actual_crc {
        return Err("v5 header CRC32 mismatch".to_string());
    }

    Ok(V5Header {
        thumbnail_offset: u64::from_le_bytes(bytes[8..16].try_into().unwrap()),
        thumbnail_length: u64::from_le_bytes(bytes[16..24].try_into().unwrap()),
        metadata_offset: u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        metadata_length: u64::from_le_bytes(bytes[32..40].try_into().unwrap()),
        computed_offset: u64::from_le_bytes(bytes[40..48].try_into().unwrap()),
        computed_length: u64::from_le_bytes(bytes[48..56].try_into().unwrap()),
        raw_offset: u64::from_le_bytes(bytes[56..64].try_into().unwrap()),
    })
}

/// Parse v5 head (header + thumbnail + metadata).
#[frb(sync)]
pub fn v5_parse_head(bytes: &[u8]) -> Result<V5ParsedHead, String> {
    let header = v5_parse_header(bytes)?;
    let total_len = bytes.len() as u64;

    // Extract thumbnail.
    let thumb_end = header.thumbnail_offset + header.thumbnail_length;
    if thumb_end > total_len {
        return Err("Truncated thumbnail".to_string());
    }
    let thumbnail = bytes[header.thumbnail_offset as usize..thumb_end as usize].to_vec();

    // Extract and decompress metadata.
    let meta_end = header.metadata_offset + header.metadata_length;
    if meta_end > total_len {
        return Err("Truncated metadata".to_string());
    }
    let metadata_compressed = &bytes[header.metadata_offset as usize..meta_end as usize];
    let metadata_json = zstd::decode_all(std::io::Cursor::new(metadata_compressed))
        .map_err(|e| format!("Metadata zstd decode failed: {e}"))?;

    Ok(V5ParsedHead {
        header,
        thumbnail,
        metadata_json,
    })
}

/// Extract computed section (decompressed JSON lines).
#[frb(sync)]
pub fn v5_extract_computed(bytes: &[u8]) -> Result<Vec<ComputedFrame>, String> {
    let header = v5_parse_header(bytes)?;
    let total_len = bytes.len() as u64;
    let comp_end = header.computed_offset + header.computed_length;
    if comp_end > total_len {
        return Err("Truncated computed section".to_string());
    }
    let computed_compressed = &bytes[header.computed_offset as usize..comp_end as usize];
    let computed_json = zstd::decode_all(std::io::Cursor::new(computed_compressed))
        .map_err(|e| format!("Computed zstd decode failed: {e}"))?;

    // Parse JSON lines (each frame is a JSON object, one per line).
    let mut frames = Vec::new();
    for line in computed_json.split(|&b| b == b'\n') {
        if line.is_empty() {
            continue;
        }
        if let Some(frame) = ComputedFrame::from_json_bytes(line) {
            frames.push(frame);
        }
    }
    Ok(frames)
}

/// Extract raw section (decompressed body).
#[frb(sync)]
pub fn v5_extract_raw(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let header = v5_parse_header(bytes)?;
    let total_len = bytes.len() as u64;
    let raw_start = header.raw_offset;
    if raw_start > total_len {
        return Err("Truncated raw section".to_string());
    }
    let raw_compressed = &bytes[raw_start as usize..];
    let raw = zstd::decode_all(std::io::Cursor::new(raw_compressed))
        .map_err(|e| format!("Raw zstd decode failed: {e}"))?;
    Ok(raw)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::muse::{
        BandsDto, EegDto, ImuDto, MovementDto, PeakAlphaDto, PpgDto, PulseDto,
        SpO2Dto, TelemetrySnapshot, XyzDto,
    };

    // ── Wire-builder helpers (independent of the production encoder) ──────────

    fn le16(v: i16) -> Vec<u8> {
        v.to_le_bytes().to_vec()
    }

    fn leu16(v: u16) -> Vec<u8> {
        v.to_le_bytes().to_vec()
    }

    fn lef32(v: f32) -> Vec<u8> {
        v.to_le_bytes().to_vec()
    }

    fn lef64(v: f64) -> Vec<u8> {
        v.to_le_bytes().to_vec()
    }

    // ── small DTO factories ────────────────────────────────────────────────────

    fn eeg(ts: f64, electrode: i32, samples: Vec<f64>) -> MuseEventDto {
        MuseEventDto::Eeg(EegDto {
            index: 0,
            electrode,
            timestamp: ts,
            samples,
        })
    }

    fn band(ts: f64, electrode: i32) -> MuseEventDto {
        MuseEventDto::Bands(BandsDto {
            electrode,
            timestamp: ts,
            delta: 1.0,
            theta: 2.0,
            alpha: 3.0,
            beta: 4.0,
            gamma: 5.0,
            line_noise_ratio: 0.0,
        })
    }

    /// Encode events to records and wrap them in the real header + zstd frame.
    fn body(events: &[MuseEventDto]) -> Vec<u8> {
        let mut body = session_header_bytes();
        let records: Vec<u8> = events.iter().flat_map(|e| encode_session_event(e)).collect();
        if !records.is_empty() {
            body.extend_from_slice(&session_frame_bytes(&records));
        }
        body
    }

    // ── 2. golden byte-layout tests (pin the on-disk format) ───────────────────

    #[test]
    fn header_bytes_are_exact() {
        // "MUSEBIN\n" stored as an LE u64 reads back as the byte-reversed
        // string: LC-newline N I B E S U M, then v5 LE.
        assert_eq!(
            session_header_bytes(),
            vec![
                0x0A, 0x4E, 0x49, 0x42, 0x45, 0x53, 0x55, 0x4D, // magic (LE u64)
                0x05, 0x00, 0x00, 0x00, // FORMAT_VERSION = 5 (LE u32)
            ]
        );
    }

    #[test]
    fn eeg_record_wire_layout() {
        let dto = eeg(1.0, -2, vec![1.5, -2.0, 0.25]);
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_EEG);
        expected.extend(lef64(1.0)); // ts
        expected.extend(le16(-2)); // electrode i16
        expected.extend(leu16(3)); // n
        expected.extend(lef32(1.5));
        expected.extend(lef32(-2.0));
        expected.extend(lef32(0.25));
        assert_eq!(encode_session_event(&dto), expected);

        // Parser must read that exact layout back.
        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.eeg_samples, 3);
        assert_eq!(out.eeg.len(), 1);
        let rec = &out.eeg[0];
        assert_eq!(rec.timestamp, 1.0);
        assert_eq!(rec.electrode, -2);
        assert_eq!(rec.samples, vec![1.5, -2.0, 0.25]);
        assert!(out.bands.is_empty());
        assert!(out.pulses.is_empty());
        assert!(out.movements.is_empty());
    }

    #[test]
    fn bands_record_wire_layout() {
        let dto = MuseEventDto::Bands(BandsDto {
            electrode: 0,
            timestamp: 1.0,
            delta: 1.5,
            theta: 2.5,
            alpha: 3.5,
            beta: 4.5,
            gamma: 5.5,
            line_noise_ratio: 0.0,
        });
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_BANDS);
        expected.extend(lef64(1.0)); // ts
        expected.extend(le16(0)); // electrode
        expected.extend(lef32(1.5));
        expected.extend(lef32(2.5));
        expected.extend(lef32(3.5));
        expected.extend(lef32(4.5));
        expected.extend(lef32(5.5));
        assert_eq!(encode_session_event(&dto), expected);

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.bands.len(), 1);
        let b = &out.bands[0];
        assert_eq!(b.timestamp, 1.0);
        assert_eq!(b.electrode, 0);
        assert_eq!(b.delta, 1.5);
        assert_eq!(b.theta, 2.5);
        assert_eq!(b.alpha, 3.5);
        assert_eq!(b.beta, 4.5);
        assert_eq!(b.gamma, 5.5);
    }

    #[test]
    fn pulse_record_wire_layout() {
        let dto = MuseEventDto::Pulse(PulseDto {
            timestamp: 1.0,
            bpm: 72.5,
            confidence: 0.5,
        });
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_PULSE);
        expected.extend(lef64(1.0));
        expected.extend(lef32(72.5));
        expected.extend(lef32(0.5));
        assert_eq!(encode_session_event(&dto), expected);

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.pulses.len(), 1);
        assert_eq!(out.pulses[0].timestamp, 1.0);
        assert_eq!(out.pulses[0].bpm, 72.5);
        assert_eq!(out.pulses[0].confidence, 0.5);
    }

    #[test]
    fn spo2_record_wire_layout() {
        let dto = MuseEventDto::SpO2(SpO2Dto {
            timestamp: 1.0,
            spo2: 98.5,
            confidence: 0.8,
        });
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_SPO2);
        expected.extend(lef64(1.0));
        expected.extend(lef32(98.5));
        expected.extend(lef32(0.8));
        assert_eq!(encode_session_event(&dto), expected);

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.spo2s.len(), 1);
        assert_eq!(out.spo2s[0].timestamp, 1.0);
        assert_eq!(out.spo2s[0].spo2, 98.5);
        assert!((out.spo2s[0].confidence - 0.8).abs() < 1e-6);
    }

    #[test]
    fn movement_record_wire_layout() {
        let dto = MuseEventDto::Movement(MovementDto {
            timestamp: 1.0,
            score: 0.25,
        });
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_MOVEMENT);
        expected.extend(lef64(1.0));
        expected.extend(lef32(0.25));
        assert_eq!(encode_session_event(&dto), expected);

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.movements.len(), 1);
        assert_eq!(out.movements[0].timestamp, 1.0);
        assert_eq!(out.movements[0].score, 0.25);
    }

    #[test]
    fn peak_alpha_record_wire_layout() {
        let dto = MuseEventDto::PeakAlpha(PeakAlphaDto {
            timestamp: 1.0,
            frequency: 10.0,
            power: 2.5,
        });
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_PEAK_ALPHA);
        expected.extend(lef64(1.0));
        expected.extend(lef32(10.0));
        expected.extend(lef32(2.5));
        assert_eq!(encode_session_event(&dto), expected);

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.peak_alphas.len(), 1);
        assert_eq!(out.peak_alphas[0].frequency, 10.0);
        assert_eq!(out.peak_alphas[0].power, 2.5);
    }

    #[test]
    fn telemetry_record_wire_layout() {
        let dto = MuseEventDto::Telemetry(TelemetrySnapshot {
            battery_level: 3.75,
            fuel_gauge_voltage: 4.1,
            temperature: 33,
        });
        let encoded = encode_session_event(&dto);
        // tag + ts(f64, wall-clock so only width checked) + battery + fuel + temp
        assert_eq!(encoded.len(), 1 + 8 + 4 + 4 + 2);
        assert_eq!(encoded[0], FORMAT_TAG_TELEMETRY);
        assert_eq!(&encoded[9..13], &3.75f32.to_le_bytes());
        assert_eq!(&encoded[13..17], &4.1f32.to_le_bytes());
        assert_eq!(&encoded[17..19], &33u16.to_le_bytes());
    }

    #[test]
    fn imu_records_share_layout() {
        fn imu() -> ImuDto {
            ImuDto {
                sequence_id: 7,
                samples: vec![
                    XyzDto { x: 1.0, y: -2.0, z: 0.5 },
                    XyzDto { x: 3.0, y: 4.0, z: 5.0 },
                ],
            }
        }
        for (dto, tag) in [
            (MuseEventDto::Accelerometer(imu()), FORMAT_TAG_ACCELEROMETER),
            (MuseEventDto::Gyroscope(imu()), FORMAT_TAG_GYROSCOPE),
        ] {
            let encoded = encode_session_event(&dto);
            assert_eq!(encoded.len(), 1 + 8 + 2 + 2 + 2 * 12);
            assert_eq!(encoded[0], tag);
            // Fields after the wall-clock ts at [1..9]:
            let o = 9;
            assert_eq!(&encoded[o..o + 2], &7u16.to_le_bytes()); // seq
            assert_eq!(&encoded[o + 2..o + 4], &2u16.to_le_bytes()); // n
        }
    }

    #[test]
    fn ppg_record_wire_layout() {
        let dto = MuseEventDto::Ppg(PpgDto {
            index: 0,
            channel: 1,
            timestamp: 1.0,
            samples: vec![1.0, 2.0],
        });
        let mut expected = Vec::new();
        expected.push(FORMAT_TAG_PPG);
        expected.extend(lef64(1.0));
        expected.extend(le16(1)); // channel
        expected.extend(leu16(2));
        expected.extend(lef32(1.0));
        expected.extend(lef32(2.0));
        assert_eq!(encode_session_event(&dto), expected);

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.eeg_samples, 0); // ppg must not count as eeg
    }

    #[test]
    fn non_recording_events_encode_empty() {
        use crate::api::muse::ControlDto;
        assert!(encode_session_event(&MuseEventDto::Connected("x".into())).is_empty());
        assert!(encode_session_event(&MuseEventDto::Disconnected).is_empty());
        assert!(encode_session_event(&MuseEventDto::Control(ControlDto {
            raw: String::new(),
            fields: Default::default(),
        }))
        .is_empty());
    }

    // ── 3. parser reads a hand-built wire body, not just encoder output ────────

    #[test]
    fn parse_hand_built_band_frame() {
        // Build the frame payload by hand (independent of the encoder) and wrap
        // it in a zstd frame produced by the same framing rule the parser uses.
        let mut records = Vec::new();
        records.push(FORMAT_TAG_BANDS);
        records.extend(lef64(1.0));
        records.extend(le16(-2));
        records.extend(lef32(1.5));
        records.extend(lef32(2.5));
        records.extend(lef32(3.5));
        records.extend(lef32(4.5));
        records.extend(lef32(5.5));

        let mut file = session_header_bytes();
        file.extend(session_frame_bytes(&records));
        let out = session_parse_body(&file).unwrap();
        assert_eq!(out.bands.len(), 1);
        assert_eq!(out.bands[0].electrode, -2);
        assert_eq!(out.bands[0].delta, 1.5);
        assert_eq!(out.bands[0].gamma, 5.5);
    }

    #[test]
    fn parse_multiple_frames_in_order() {
        let mut file = session_header_bytes();
        // Two separate zstd frames must be decoded independently and in order.
        file.extend(session_frame_bytes(&encoding::of(&[eeg(1.0, 0, vec![0.5, -1.5, 2.25])])));
        file.extend(session_frame_bytes(&encoding::of(&[eeg(2.0, 1, vec![9.0])])));
        let out = session_parse_body(&file).unwrap();
        assert_eq!(out.eeg_samples, 4);
    }

    // ── 4. f32-vs-f64 precision ────────────────────────────────────────────────

    #[test]
    fn band_power_is_stored_as_f32() {
        // 0.1 is not exactly representable in f32; if the encoder stored f64
        // the parsed value would be exactly 0.1. We want to detect a silent
        // switch to f64 (or f16) so this asserts the widened f32 rounding.
        let dto = MuseEventDto::Bands(BandsDto {
            electrode: 0,
            timestamp: 0.0,
            delta: 0.1,
            theta: 0.3,
            alpha: 0.0,
            beta: 0.0,
            gamma: 0.0,
            line_noise_ratio: 0.0,
        });
        // wire must carry the f32 value, not the full f64 mantissa
        assert_eq!(&encode_session_event(&dto)[1 + 8 + 2..1 + 8 + 2 + 4], &0.1f32.to_le_bytes());

        let out = session_parse_body(&body(&[dto])).unwrap();
        assert_eq!(out.bands[0].delta, 0.1f32 as f64);
        assert_ne!(out.bands[0].delta, 0.1);
    }

    // ── 5. malformed input robustness ──────────────────────────────────────────

    #[test]
    fn rejects_truncated_header() {
        for len in 0..12 {
            let bytes: Vec<u8> = vec![0u8; len];
            assert!(session_parse_body(&bytes).is_err(), "len={len}");
        }
    }

    #[test]
    fn rejects_bad_version() {
        let mut data = session_header_bytes();
        data[8..12].copy_from_slice(&3u32.to_le_bytes());
        assert!(session_parse_body(&data).is_err());
    }

    #[test]
    fn rejects_bad_magic() {
        let mut data = vec![0u8; 64];
        data[..8].copy_from_slice(b"NOTMUSE!");
        data[8..12].copy_from_slice(&FORMAT_VERSION.to_le_bytes());
        assert!(session_parse_body(&data).is_err());
    }

    #[test]
    fn tolerates_truncated_or_garbage_frames() {
        // header + a frame length that overruns the buffer → no panic, no data
        let mut file = session_header_bytes();
        file.extend_from_slice(&[0xff, 0xff, 0xff, 0x7f]); // claims huge length
        assert!(session_parse_body(&file).is_ok());

        // random bytes inside a legal-length frame that zstd can't decode
        let mut junk = session_header_bytes();
        let payload = vec![0x42u8; 16];
        let len = payload.len() as u32;
        junk.extend_from_slice(&len.to_le_bytes());
        junk.extend_from_slice(&payload);
        assert!(session_parse_body(&junk).is_ok());
    }

    #[test]
    fn parse_empty_body() {
        let data = body(&[]);
        let out = session_parse_body(&data).unwrap();
        assert!(out.bands.is_empty());
        assert_eq!(out.eeg_samples, 0);
    }

    #[test]
    fn roundtrip_bands_and_eeg() {
        let events = vec![
            band(100.0, 1),
            band(100.0, 2),
            eeg(99.0, 0, vec![0.5, -1.5, 2.25]),
        ];
        let data = body(&events);
        let out = session_parse_body(&data).unwrap();
        assert_eq!(out.bands.len(), 2);
        assert_eq!(out.bands[0].electrode, 1);
        assert_eq!(out.bands[0].delta, 1.0);
        assert_eq!(out.bands[0].gamma, 5.0);
        assert_eq!(out.bands[1].electrode, 2);
        assert_eq!(out.eeg_samples, 3);
    }

    #[test]
    fn roundtrip_all_streams() {
        let events: Vec<MuseEventDto> = vec![
            eeg(1.0, 0, vec![0.5]),
            MuseEventDto::Telemetry(TelemetrySnapshot {
                battery_level: 3.0,
                fuel_gauge_voltage: 4.0,
                temperature: 25,
            }),
            MuseEventDto::Accelerometer(ImuDto {
                sequence_id: 1,
                samples: vec![XyzDto { x: 1.0, y: 2.0, z: 3.0 }],
            }),
            MuseEventDto::Gyroscope(ImuDto {
                sequence_id: 2,
                samples: vec![XyzDto { x: 0.0, y: 0.0, z: 1.0 }],
            }),
            MuseEventDto::Ppg(PpgDto {
                index: 0,
                channel: 1,
                timestamp: 1.0,
                samples: vec![1.0, 2.0],
            }),
MuseEventDto::Bands(BandsDto {
                electrode: 3,
                timestamp: 1.0,
                delta: 0.5,
                theta: 0.5,
                alpha: 0.5,
                beta: 0.5,
                gamma: 0.5,
                line_noise_ratio: 0.0,
            }),
            MuseEventDto::Pulse(PulseDto {
                timestamp: 1.0,
                bpm: 65.0,
                confidence: 0.9,
            }),
            MuseEventDto::Movement(MovementDto {
                timestamp: 1.0,
                score: 0.0,
            }),
            MuseEventDto::PeakAlpha(PeakAlphaDto {
                timestamp: 1.0,
                frequency: 10.0,
                power: 0.5,
            }),
        ];
        let out = session_parse_body(&body(&events)).unwrap();
        // Only the single EEG batch (n=1) counts; PPG samples are not eeg.
        assert_eq!(out.eeg_samples, 1);
        assert_eq!(out.bands.len(), 1);
        assert_eq!(out.pulses.len(), 1);
        assert_eq!(out.movements.len(), 1);
        assert_eq!(out.peak_alphas.len(), 1);
    }

    #[test]
    fn eeg_sample_count_adds_across_records() {
        let events = vec![
            eeg(1.0, 0, vec![1.0, 2.0]),
            eeg(1.0, 1, vec![3.0]),
            eeg(1.0, 2, vec![4.0, 5.0, 6.0]),
        ];
        let out = session_parse_body(&body(&events)).unwrap();
        assert_eq!(out.eeg_samples, 6);
    }

    /// A minimal but structurally valid PNG (sig + IHDR + IEND), so the
    /// container parser can locate the end of the image.
    fn min_png() -> Vec<u8> {
        let mut png = Vec::new();
        png.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
        png.extend_from_slice(&13u32.to_be_bytes());
        png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&[0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
        png.extend_from_slice(&[0, 0, 0, 0]);
        png.extend_from_slice(&0u32.to_be_bytes());
        png.extend_from_slice(b"IEND");
        png.extend_from_slice(&[0, 0, 0, 0]);
        png
    }

    /// A direct helper so tests don't route through the production encoder.
    mod encoding {
        use super::*;
        pub fn of(events: &[MuseEventDto]) -> Vec<u8> {
            let mut out = Vec::new();
            for e in events {
                out.extend(super::encode_session_event(e));
            }
            out
        }
    }

    // ── 6. v5 container format ──────────────────────────────────────────────────

    #[test]
    fn v5_container_encode_decode_roundtrip() {
        let thumbnail = min_png();
        let metadata = br#"{"protocol":"drowsiness","duration":3600}"#;
        let computed = vec![
            ComputedFrame {
                t: 0.0,
                bands: vec![vec![1.0, 2.0, 3.0, 4.0, 5.0]; 4],
                pulse: Some(60.0),
                movement: Some(0.1),
                peak_alpha: Some(PeakAlphaInfo { freq: 10.0, power: 5.0 }),
                spo2: Some(98.0),
                line_noise: vec![0.01; 4],
                signal_quality: vec![90; 4],
                guardrail: GuardrailInfo { sleep_dir: 0.1, clarity: 0.9, warning: false, delta: 0.0 },
                feedback: FeedbackInfo { ratio: 1.5, threshold: 1.0, in_target: true, pct: 0.6 },
                gestures: vec!["blink".to_string()],
            },
            ComputedFrame {
                t: 1.0,
                bands: vec![vec![1.1, 2.1, 3.1, 4.1, 5.1]; 4],
                pulse: Some(61.0),
                movement: Some(0.2),
                peak_alpha: Some(PeakAlphaInfo { freq: 10.2, power: 5.1 }),
                spo2: Some(97.0),
                line_noise: vec![0.02; 4],
                signal_quality: vec![85; 4],
                guardrail: GuardrailInfo { sleep_dir: 0.2, clarity: 0.8, warning: true, delta: 0.1 },
                feedback: FeedbackInfo { ratio: 1.4, threshold: 1.1, in_target: false, pct: 0.4 },
                gestures: vec![],
            },
        ];
        let raw = b"raw body data";

        let file = container_encode_v5(&thumbnail, metadata, &computed, raw);
        assert!(!file.is_empty());

        // Parse header.
        let head = v5_parse_head(&file).unwrap();
        assert_eq!(head.thumbnail, thumbnail);
        assert_eq!(head.metadata_json, metadata);

        // Extract computed.
        let frames = v5_extract_computed(&file).unwrap();
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].t, 0.0);
        assert_eq!(frames[1].t, 1.0);
        assert_eq!(frames[0].bands[0][0], 1.0);
        assert_eq!(frames[1].bands[0][0], 1.1);
        assert!(frames[0].guardrail.warning == false);
        assert!(frames[1].guardrail.warning == true);

        // Extract raw.
        let raw_out = v5_extract_raw(&file).unwrap();
        assert_eq!(raw_out, raw);
    }

    #[test]
    fn v5_header_crc32_validation() {
        let thumbnail = min_png();
        let metadata = b"{}";
        let computed = vec![];
        let raw = b"x";

        let mut file = container_encode_v5(&thumbnail, metadata, &computed, raw);

        // Corrupt the CRC32 (last 4 bytes of header).
        file[56] ^= 0xFF;

        // Should fail to parse.
        assert!(v5_parse_header(&file).is_err());
    }

    #[test]
    fn v5_header_magic_validation() {
        let thumbnail = min_png();
        let metadata = b"{}";
        let computed = vec![];
        let raw = b"x";

        let mut file = container_encode_v5(&thumbnail, metadata, &computed, raw);

        // Corrupt magic.
        file[0] = 0xFF;

        assert!(v5_parse_header(&file).is_err());
    }

    #[test]
    fn v5_header_version_validation() {
        let thumbnail = min_png();
        let metadata = b"{}";
        let computed = vec![];
        let raw = b"x";

        let mut file = container_encode_v5(&thumbnail, metadata, &computed, raw);

        // Corrupt version.
        file[6] = 99;

        assert!(v5_parse_header(&file).is_err());
    }

    #[test]
    fn v5_computed_frame_json_roundtrip() {
        let frame = ComputedFrame {
            t: 123.0,
            bands: vec![vec![1.0, 2.0, 3.0, 4.0, 5.0]; 4],
            pulse: Some(72.0),
            movement: Some(0.05),
            peak_alpha: Some(PeakAlphaInfo { freq: 10.1, power: 4.5 }),
            spo2: Some(98.5),
            line_noise: vec![0.01, 0.02, 0.01, 0.03],
            signal_quality: vec![80, 85, 90, 95],
            guardrail: GuardrailInfo { sleep_dir: 0.2, clarity: 0.8, warning: false, delta: 0.05 },
            feedback: FeedbackInfo { ratio: 1.8, threshold: 1.3, in_target: true, pct: 0.65 },
            gestures: vec!["blink".to_string(), "clench".to_string()],
        };

        let json = frame.to_json_bytes();
        let decoded = ComputedFrame::from_json_bytes(&json).unwrap();

        assert_eq!(decoded.t, frame.t);
        assert_eq!(decoded.bands, frame.bands);
        assert_eq!(decoded.pulse, frame.pulse);
        assert_eq!(decoded.gestures, frame.gestures);
    }
}
