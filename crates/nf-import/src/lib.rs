//! L1 import of foreign and legacy recordings into NeuroFeed records
//! (ported from `lib/src/feedback/import/*.dart`):
//!
//! - EDF / EDF+ (C and D): one supported montage kept, others dropped,
//!   non-256 Hz EEG resampled, gaps kept as `disconnect` notes.
//! - Mind Monitor CSV: Constant (RAW + IMU + PPG) or Interval (bands only).
//! - Native: legacy / our `.neurofeed` (NFED6) containers and bare NFEDBIN
//!   raw bodies.
//!
//! Output records use session seconds from 0 (EEG `ts` = last sample, like
//! live packets). Bands for EEG imports are left to the caller's live band
//! pipeline (`Imported::needs_bands`) so imports and live sessions match.
//! Pure: no file system, no clock (callers pass the UTC offset).

mod csv;
mod edf;
pub mod montage;
mod native;
pub mod notes;
mod time;

use nf_format::Record;
use nf_types::{DeviceInfo, DeviceKind};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Every stored recording holds EEG at this rate.
pub const NATIVE_EEG_HZ: f64 = 256.0;
/// Samples per written EEG record (Muse packet shape).
pub const EEG_PACKET: usize = 12;
/// Interval CSV rows this slow (s) get the coverage warning.
pub const CSV_COVERAGE_WARN_S: f64 = 1.9;

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum ImportError {
    /// Readable but not importable (no montage, interval CSV without bands).
    #[error("{0}")]
    Refused(String),
    /// Not a file we can parse.
    #[error("{0}")]
    Format(String),
}

pub type Result<T> = std::result::Result<T, ImportError>;

fn bad<T>(msg: impl Into<String>) -> Result<T> {
    Err(ImportError::Format(msg.into()))
}

/// A locked-type note, seconds from recording start.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Annotation {
    pub onset: f64,
    pub duration: f64,
    #[serde(rename = "type")]
    pub kind: String,
}

impl Annotation {
    pub fn at(onset: f64, kind: &str) -> Self {
        Self { onset, duration: 0.0, kind: kind.to_owned() }
    }
}

/// Where an import came from and what it lost (the legacy `import` block).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Provenance {
    /// `edf` | `edf+` | `mind_monitor_csv` | `neurofeed` | `raw_body`.
    pub source_format: String,
    pub source_file_name: String,
    pub original_channels: Vec<String>,
    pub original_rate_hz: Option<f64>,
    pub dropped_channels: Vec<String>,
    pub resampled: bool,
    pub raw_present: bool,
    /// Mind Monitor interval (s) when rows are snapshots.
    pub recording_interval: Option<f64>,
    /// Fraction of time covered by 1 s band windows (interval files).
    pub interval_coverage: Option<f64>,
    pub reference: Option<String>,
    pub prefiltering: Vec<(String, String)>,
    /// Bands came from the file in log10 Bels (Mind Monitor) instead of
    /// our FFT.
    pub bands_from_file: bool,
    pub subject: Option<String>,
    pub lossy: bool,
    pub warnings: Vec<String>,
    pub annotations: Vec<Annotation>,
}

/// An imported recording, ready to store.
#[derive(Debug, Clone, PartialEq)]
pub struct Imported {
    pub device: DeviceInfo,
    /// Time-ordered records (no bands when `needs_bands`).
    pub records: Vec<Record>,
    pub started_unix_ms: Option<f64>,
    pub duration_s: f64,
    /// EEG present without bands: run it through the live band pipeline.
    pub needs_bands: bool,
    pub provenance: Provenance,
}

impl Imported {
    pub fn eeg_samples(&self) -> u64 {
        self.records.iter().map(|r| if let Record::Eeg { samples, .. } = r { samples.len() as u64 } else { 0 }).sum()
    }

    pub fn ppg_samples(&self) -> u64 {
        self.records.iter().map(|r| if let Record::Ppg { samples, .. } = r { samples.len() as u64 } else { 0 }).sum()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Options<'a> {
    pub file_name: &'a str,
    /// Local offset for files with local wall-clock times (EDF, CSV).
    pub utc_offset_minutes: i32,
}

/// File extensions the importer understands.
pub const EXTENSIONS: [&str; 4] = ["edf", "csv", "neurofeed", "raw"];

/// Detect the format (extension, then magic bytes) and import.
pub fn import(bytes: &[u8], opts: Options<'_>) -> Result<Imported> {
    let ext = opts.file_name.rsplit_once('.').map(|(_, e)| e.to_lowercase()).unwrap_or_default();
    let mut out = match ext.as_str() {
        "edf" => edf::import(bytes, opts)?,
        "csv" => csv::import(text(bytes)?, opts)?,
        _ if bytes.starts_with(b"0       ") => edf::import(bytes, opts)?,
        _ if native::sniff(bytes) => native::import(bytes, opts)?,
        _ if bytes.starts_with(b"TimeStamp") => csv::import(text(bytes)?, opts)?,
        _ => return bad(format!("Unsupported import format: {}", opts.file_name)),
    };
    out.provenance.source_file_name = opts.file_name.to_owned();
    out.records.sort_by(|a, b| record_ts(a).total_cmp(&record_ts(b)));
    Ok(out)
}

fn text(bytes: &[u8]) -> Result<&str> {
    std::str::from_utf8(bytes.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(bytes)).map_err(|_| ImportError::Format("CSV is not UTF-8".into()))
}

pub fn record_ts(r: &Record) -> f64 {
    match r {
        Record::Eeg { ts, .. }
        | Record::Telemetry { ts, .. }
        | Record::Accelerometer { ts, .. }
        | Record::Gyroscope { ts, .. }
        | Record::Ppg { ts, .. }
        | Record::Bands { ts, .. }
        | Record::Pulse { ts, .. }
        | Record::Movement { ts, .. }
        | Record::PeakAlpha { ts, .. }
        | Record::SpO2 { ts, .. }
        | Record::Feedback { ts, .. }
        | Record::Trust { ts, .. } => *ts,
    }
}

/// What an import keeps and loses (the pre-save dialog).
#[derive(Debug, Clone, PartialEq, Serialize, JsonSchema)]
pub struct Summary {
    pub kept: Vec<String>,
    pub lost: Vec<String>,
    /// Interval CSV coverage warning, if any.
    pub coverage: Option<String>,
}

pub fn summary(i: &Imported) -> Summary {
    let p = &i.provenance;
    let mut kept = vec![format!("Channels: {}", i.device.channels.join(", "))];
    kept.push(if p.raw_present { "RAW EEG at 256 Hz".into() } else { "Bands only (no RAW EEG)".into() });
    kept.push(format!("Duration: {}", duration(i.duration_s.round() as u64)));
    if !p.annotations.is_empty() {
        kept.push(format!("{} note(s)", p.annotations.len()));
    }
    Summary { kept, lost: p.warnings.clone(), coverage: coverage_warning(p) }
}

/// Legacy `intervalCoverageWarning`.
pub fn coverage_warning(p: &Provenance) -> Option<String> {
    let (interval, cov) = (p.recording_interval?, p.interval_coverage?);
    (interval >= CSV_COVERAGE_WARN_S).then(|| {
        let secs = if interval.fract() == 0.0 { format!("{interval:.0}") } else { format!("{interval:.1}") };
        format!(
            "This Mind Monitor file was recorded with one row every {secs} seconds, so it covers only about {}% of the session. \
             Short events can be missed, so expect lower result quality. For better results, set Mind Monitor's recording interval to 1 second.",
            (cov * 100.0).round()
        )
    })
}

fn duration(s: u64) -> String {
    if s < 60 {
        format!("{s} s")
    } else {
        format!("{} min {:02} s", s / 60, s % 60)
    }
}

/// Device record for an import.
pub(crate) fn device(kind: DeviceKind, channels: Vec<String>, source: &str) -> DeviceInfo {
    let name = match kind {
        DeviceKind::Muse => "Imported (Muse montage)",
        DeviceKind::Crown => "Imported (Crown montage)",
    };
    DeviceInfo {
        id: format!("import:{source}"),
        name: name.into(),
        kind,
        channels,
        sample_rate_hz: NATIVE_EEG_HZ,
        simulated: false,
        ppg_channels: Vec::new(),
        ppg_rate_hz: None,
        accel_rate_hz: None,
    }
}

/// Contiguous 256 Hz samples for one electrode, starting at `start` (s).
pub(crate) struct Run {
    pub electrode: usize,
    pub start: f64,
    pub samples: Vec<f32>,
}

/// Runs → EEG records of [`EEG_PACKET`] samples, `ts` = last sample.
pub(crate) fn eeg_records(runs: &[Run]) -> Vec<Record> {
    let mut out = Vec::new();
    for r in runs {
        let el = i16::try_from(r.electrode).unwrap_or(i16::MAX);
        for (k, chunk) in r.samples.chunks(EEG_PACKET).enumerate() {
            let last = (k * EEG_PACKET + chunk.len() - 1) as f64;
            out.push(Record::Eeg { ts: r.start + last / NATIVE_EEG_HZ, electrode: el, samples: chunk.to_vec() });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packets_stamp_last_sample() {
        let r = eeg_records(&[Run { electrode: 1, start: 2.0, samples: vec![0.0; 30] }]);
        assert_eq!(r.len(), 3);
        assert!(
            matches!(&r[2], Record::Eeg { ts, electrode: 1, samples } if samples.len() == 6 && (*ts - (2.0 + 29.0 / 256.0)).abs() < 1e-9)
        );
    }

    #[test]
    fn unknown_format_is_refused() {
        let e = import(b"hello", Options { file_name: "x.txt", utc_offset_minutes: 0 });
        assert!(matches!(e, Err(ImportError::Format(m)) if m.contains("x.txt")));
    }

    #[test]
    fn coverage_text() {
        let p = Provenance { recording_interval: Some(2.0), interval_coverage: Some(0.5), ..Default::default() };
        assert!(coverage_warning(&p).is_some_and(|w| w.contains("every 2 seconds") && w.contains("50%")));
        let fast = Provenance { recording_interval: Some(1.0), interval_coverage: Some(1.0), ..Default::default() };
        assert_eq!(coverage_warning(&fast), None);
    }
}
