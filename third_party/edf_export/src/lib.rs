//! Minimal EDF+ (European Data Format Plus) writer for EEG time-series
//! export.
//!
//! Supports the subset needed by the Muse ML session export: continuous
//! (EDF+C) recordings, int16 sample encoding, and a single annotation
//! channel carrying time-stamped annotations (gestures, calibration
//! boundaries). The writer is deterministic and dependency-free, with
//! golden tests pinning the byte layout so readers (EEGLAB, MNE,
//! EDFbrowser) keep parsing our files.
//!
//! Layout summary (EDF spec, edfplus.info):
//! - 256-byte ASCII header + 256 bytes per signal (the annotation
//!   channel included), fixed offsets described in `write_header`.
//! - One data record per second: for each signal, `samples_per_record`
//!   int16 little-endian samples scaled from physical units (µV).
//! - The annotation signal is the last signal and carries one
//!   variable-length "sample" per record: a concatenation of
//!   Time-stamped Annotation Lists (TALs). Because annotation samples
//!   are variable length, data records themselves are variable length;
//!   readers locate boundaries by scanning the self-terminating TALs.

/// Label used for the EDF+ annotation channel.
pub const EDF_ANNOTATION_LABEL: &str = "EDF Annotations";

/// Number of bytes in the fixed EDF header block (plus 256 per signal).
pub const EDF_HEADER_BLOCK: usize = 256;

/// One continuous signal (e.g. a single EEG electrode).
#[derive(Debug, Clone, PartialEq)]
pub struct EdfSignal {
    /// Short label (e.g. `"TP9"`), max 16 bytes.
    pub label: String,
    /// Samples per data record (== sample rate for 1-second records).
    pub samples_per_record: usize,
    /// Physical (µV) range of the raw data; digital range is always
    /// [-32768, 32767].
    pub physical_min: f64,
    pub physical_max: f64,
    /// Continuous physical-domain samples, one per sample point.
    pub data: Vec<f32>,
}

impl EdfSignal {
    /// Builds a signal with the standard EEG physical range ±2000 µV.
    pub fn eeg(label: impl Into<String>, samples_per_record: usize, data: Vec<f32>) -> Self {
        Self {
            label: label.into(),
            samples_per_record,
            physical_min: -2000.0,
            physical_max: 2000.0,
            data,
        }
    }
}

/// A time-stamped annotation, onset relative to recording start.
#[derive(Debug, Clone, PartialEq)]
pub struct EdfAnnotation {
    pub onset_seconds: f64,
    pub text: String,
}

/// Recording-level parameters for an EDF+ file.
#[derive(Debug, Clone, PartialEq)]
pub struct EdfFileSpec<'a> {
    /// Patient identification (written verbatim, max 80 bytes).
    pub patient_id: &'a str,
    /// Recording identification (max 80 bytes).
    pub recording_id: &'a str,
    /// Start of the recording: (year, month, day, hour, minute, second).
    /// Year must be 1985–2084 inclusive (two-digit year in the header).
    pub start: (u16, u16, u16, u16, u16, u16),
    /// Physical dimension of the samples, e.g. `"uV"` (max 8 bytes).
    pub physical_dimension: &'a str,
    /// Annotations, sorted ascending; onsets beyond the covered duration
    /// are dropped, onsets in a gap between records land in the record
    /// that contains them.
    pub annotations: &'a [EdfAnnotation],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EdfError {
    /// No signals provided.
    EmptySignals,
    /// Signals disagree on samples-per-record.
    MixedSampleRate,
    /// A signal has no samples.
    EmptySignal(usize),
    /// A signal label exceeds 16 bytes.
    LabelTooLong(String),
    /// The physical dimension exceeds 8 bytes.
    DimensionTooLong(String),
    /// The recording start fields are out of range.
    InvalidStart(&'static str),
    /// Physical min >= physical max.
    InvalidPhysicalRange(usize),
}

impl std::fmt::Display for EdfError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EdfError::EmptySignals => write!(f, "no signals provided"),
            EdfError::MixedSampleRate => {
                write!(f, "signals disagree on samples per record")
            }
            EdfError::EmptySignal(i) => write!(f, "signal {i} has no samples"),
            EdfError::LabelTooLong(l) => write!(f, "signal label exceeds 16 bytes: {l:?}"),
            EdfError::DimensionTooLong(d) => {
                write!(f, "physical dimension exceeds 8 bytes: {d:?}")
            }
            EdfError::InvalidStart(field) => {
                write!(f, "invalid recording start field: {field}")
            }
            EdfError::InvalidPhysicalRange(i) => {
                write!(f, "signal {i} has physical_min >= physical_max")
            }
        }
    }
}

impl std::error::Error for EdfError {}

/// Serializes the given signals and annotations into a complete EDF+ file.
pub fn encode_edf_plus(signals: &[EdfSignal], spec: &EdfFileSpec) -> Result<Vec<u8>, EdfError> {
    validate(signals, spec)?;

    let rate = signals[0].samples_per_record;
    let max_len = signals.iter().map(|s| s.data.len()).max().unwrap_or(0);
    let records = max_len.div_ceil(rate).max(1);

    let capacity = EDF_HEADER_BLOCK + signals.len() * EDF_HEADER_BLOCK
        + records * signals.iter().map(|s| s.samples_per_record).sum::<usize>() * 2
        + records * 64;
    let mut out = Vec::with_capacity(capacity);
    write_header(&mut out, signals, spec, records);
    write_records(&mut out, signals, spec, records);
    Ok(out)
}

fn validate(signals: &[EdfSignal], spec: &EdfFileSpec) -> Result<(), EdfError> {
    if signals.is_empty() {
        return Err(EdfError::EmptySignals);
    }
    let rate = signals[0].samples_per_record;
    if rate == 0 {
        return Err(EdfError::InvalidStart("samples_per_record"));
    }
    for (i, s) in signals.iter().enumerate() {
        if s.samples_per_record != rate {
            return Err(EdfError::MixedSampleRate);
        }
        if s.data.is_empty() {
            return Err(EdfError::EmptySignal(i));
        }
        if s.label.len() > 16 {
            return Err(EdfError::LabelTooLong(s.label.clone()));
        }
        if s.physical_min >= s.physical_max {
            return Err(EdfError::InvalidPhysicalRange(i));
        }
    }
    if spec.physical_dimension.len() > 8 {
        return Err(EdfError::DimensionTooLong(
            spec.physical_dimension.to_string(),
        ));
    }
    let (y, m, d, h, mi, se) = spec.start;
    if !(1985..=2084).contains(&y) || !(1..=12).contains(&m) || !(1..=31).contains(&d)
        || h > 23 || mi > 59 || se > 59
    {
        return Err(EdfError::InvalidStart("(y, m, d, h, min, s)"));
    }
    Ok(())
}

fn pad_field(buf: &mut Vec<u8>, text: &str, width: usize) {
    let bytes = text.as_bytes();
    let n = bytes.len().min(width);
    buf.extend_from_slice(&bytes[..n]);
    buf.extend(std::iter::repeat(b' ').take(width - n));
}

fn num_field(buf: &mut Vec<u8>, value: impl std::fmt::Display, width: usize) {
    let s = format!("{value}");
    let mut text = s;
    if text.len() > width {
        text.truncate(width);
    }
    let pad = width - text.len();
    buf.extend(std::iter::repeat(b' ').take(pad));
    buf.extend_from_slice(text.as_bytes());
}

fn scaled_header_value(v: f64) -> String {
    if v == v.trunc() && v.abs() < 1e15 {
        format!("{v}")
    } else {
        format!("{v:.4}")
    }
}

/// Writes the 256-byte header plus one 256-byte block per signal.
fn write_header(out: &mut Vec<u8>, signals: &[EdfSignal], spec: &EdfFileSpec, records: usize) {
    let nsig = signals.len() + 1; // + annotation channel
    let header_len = EDF_HEADER_BLOCK + nsig * EDF_HEADER_BLOCK;
    let (y, m, d, h, mi, se) = spec.start;
    // 0..8 version; 8..88 patient; 88..168 recording; 168..176 date;
    // 176..184 time; 184..192 header length; 192..236 reserved (EDF+C);
    // 236..244 number of data records; 244..252 record duration;
    // 252..256 number of signals.
    pad_field(out, "0", 8);
    pad_field(out, spec.patient_id, 80);
    pad_field(out, spec.recording_id, 80);
    let date = format!("{d:02}.{m:02}.{:02}", y % 100);
    let time = format!("{h:02}.{mi:02}.{se:02}");
    pad_field(out, &date, 8);
    pad_field(out, &time, 8);
    num_field(out, header_len, 8);
    pad_field(out, "EDF+C", 44); // continuous
    num_field(out, records, 8);
    num_field(out, 1, 8); // record duration in seconds
    num_field(out, nsig, 4);
    for s in signals {
        pad_field(out, &s.label, 16);
        pad_field(out, " ", 80); // transducer
        pad_field(out, spec.physical_dimension, 8);
        num_field(out, scaled_header_value(s.physical_min), 8);
        num_field(out, scaled_header_value(s.physical_max), 8);
        num_field(out, -32768_i32, 8);
        num_field(out, 32767_i32, 8);
        pad_field(out, " ", 80); // prefiltering
        num_field(out, s.samples_per_record, 8);
        pad_field(out, " ", 32);
    }
    // Annotation channel block.
    pad_field(out, EDF_ANNOTATION_LABEL, 16);
    pad_field(out, " ", 80);
    pad_field(out, " ", 8);
    num_field(out, 0, 8);
    num_field(out, 0, 8);
    num_field(out, -32768_i32, 8);
    num_field(out, 32767_i32, 8);
    pad_field(out, " ", 80);
    num_field(out, 1, 8);
    pad_field(out, " ", 32);
    debug_assert_eq!(out.len(), header_len, "EDF header must be exactly header_len bytes");
}

/// Encodes one physical sample as a clamped int16 LE pair.
fn encode_sample(s: &EdfSignal, value: f32) -> [u8; 2] {
    let span = (s.physical_max - s.physical_min) as f32;
    let dig = (value / span * 65535.0).clamp(-32768.0, 32767.0).round() as i16;
    (dig as u16).to_le_bytes()
}

/// Builds the annotation bytes for one data record: a time-keeping TAL in
/// record 0 plus one TAL per annotation whose onset falls inside the
/// record. Onset is written relative to the record start (EDF+ `+` form).
fn record_annotations(spec: &EdfFileSpec, record: usize) -> Vec<u8> {
    let start = record as f64;
    let mut buf = Vec::new();
    if record == 0 {
        // Time-keeping TAL: onset "0", no duration, no text.
        buf.extend_from_slice(b"0\x14\x00");
    }
    for a in spec.annotations {
        if a.onset_seconds >= start && a.onset_seconds < start + 1.0 {
            let onset = format!("+{}", a.onset_seconds - start);
            buf.extend_from_slice(onset.as_bytes());
            buf.push(0x14);
            buf.push(0x14); // empty duration
            buf.extend_from_slice(a.text.as_bytes());
            buf.push(0x14);
            buf.push(0x00);
        }
    }
    // Every record's annotation sample is at least 2 bytes (one int16
    // nominal sample); NUL padding is skipped by TAL scanning readers.
    while buf.len() < 2 {
        buf.push(0x00);
    }
    buf
}

fn write_records(out: &mut Vec<u8>, signals: &[EdfSignal], spec: &EdfFileSpec, records: usize) {
    let rate = signals[0].samples_per_record;
    for r in 0..records {
        for s in signals {
            for i in 0..rate {
                let idx = r * rate + i;
                let value = if idx < s.data.len() {
                    s.data[idx]
                } else {
                    // Trailing partial second: hold the last sample.
                    s.data[s.data.len() - 1]
                };
                out.extend_from_slice(&encode_sample(s, value));
            }
        }
        out.extend_from_slice(&record_annotations(spec, r));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATIENT: &str = "Muse ML";
    const RECORDING: &str = "Muse ML session 0.0.1-test-01";

    fn spec(annotations: &[EdfAnnotation]) -> EdfFileSpec<'_> {
        EdfFileSpec {
            patient_id: PATIENT,
            recording_id: RECORDING,
            start: (2026, 8, 19, 10, 30, 5),
            physical_dimension: "uV",
            annotations,
        }
    }

    fn two_signals() -> Vec<EdfSignal> {
        let t: Vec<f32> = (0..512).map(|i| (i as f32) * 0.5).collect();
        vec![EdfSignal::eeg("TP9", 256, t.clone()), EdfSignal::eeg("AF7", 256, t)]
    }

    #[test]
    fn header_layout_is_pinned() {
        let signals = two_signals();
        let bytes = encode_edf_plus(&signals, &spec(&[])).unwrap();
        // 1024 header + 2 records; each record = 2 signals * 256 * 2 bytes;
        // record 0 annotation = timekeeping TAL (4 bytes), record 1 = 2-byte pad.
        assert_eq!(bytes.len(), 1024 + 512 + 4 + 512 + 2);
        let header = &bytes[..1024];
        assert_eq!(&header[0..8], b"0       ");
        assert_eq!(&header[8..88], format!("{PATIENT:<80}").as_bytes());
        assert_eq!(&header[88..168], format!("{RECORDING:<80}").as_bytes());
        assert_eq!(&header[168..176], b"19.08.26");
        assert_eq!(&header[176..184], b"10.30.05");
        assert_eq!(&header[184..192], b"    1024");
        assert_eq!(&header[192..236], format!("{:<44}", "EDF+C").as_bytes());
        assert_eq!(&header[236..244], b"       2");
        assert_eq!(&header[244..252], b"       1");
        assert_eq!(&header[252..256], b"   3");
        assert_eq!(&header[256..272], format!("{:<16}", "TP9").as_bytes());
        assert_eq!(&header[512..528], format!("{:<16}", "AF7").as_bytes());
        assert_eq!(&header[768..784], format!("{:<16}", "EDF Annotations").as_bytes());
        assert_eq!(&header[512 + 64..512 + 72], format!("{:>8}", "uV").as_bytes());
        assert_eq!(&header[512 + 72..512 + 80], format!("{:>8}", "-2000").as_bytes());
        assert_eq!(&header[512 + 80..512 + 88], format!("{:>8}", "2000").as_bytes());
        assert_eq!(&header[512 + 88..512 + 96], format!("{:>8}", "-32768").as_bytes());
        assert_eq!(&header[512 + 96..512 + 104], format!("{:>8}", "32767").as_bytes());
        assert_eq!(&header[512 + 128..512 + 136], format!("{:>8}", "256").as_bytes());
        assert_eq!(&header[768 + 144..768 + 152], format!("{:>8}", "1").as_bytes());
    }

    #[test]
    fn sample_scaling_is_int16_le() {
        let mut signals = two_signals();
        signals[0].data = vec![1.0, -1.0, 2000.0, -2000.0];
        let bytes = encode_edf_plus(&signals, &spec(&[])).unwrap();
        let read_i16 = |off: usize| i16::from_le_bytes([bytes[1024 + off], bytes[1024 + off + 1]]);
        assert_eq!(read_i16(0), 16); // 1.0 µV * 65535/4000
        assert_eq!(read_i16(2), -16);
        assert_eq!(read_i16(4), 32767);
        assert_eq!(read_i16(6), -32768);
        // Record 1 (after record 0 = 512 data + 4 annotation bytes): all
        // samples hold the last value (-2000 µV → -32768).
        assert_eq!(read_i16(512 + 4), -32768);
        assert_eq!(read_i16(512 + 4 + 2), -32768);
    }

    #[test]
    fn annotation_tals_land_in_their_record() {
        let annotations = vec![
            EdfAnnotation { onset_seconds: 0.5, text: "Double blink".to_string() },
            EdfAnnotation { onset_seconds: 1.25, text: "Eye up".to_string() },
        ];
        let signals = vec![EdfSignal::eeg("TP9", 256, vec![0.0; 400])];
        let bytes = encode_edf_plus(&signals, &spec(&annotations)).unwrap();
        let header_len = 256 + 2 * 256;
        // Record 0: 512 data bytes, then timekeeping TAL + "+0.5" blink TAL.
        let rec0 = &bytes[header_len + 512..header_len + 512 + 4 + 19];
        assert_eq!(rec0, b"0\x14\x00+0.5\x14\x14Double blink\x14\x00");
        // Record 1: 512 data bytes, then "+0.25" eye TAL.
        let rec1_start = header_len + 512 + 4 + 19 + 512;
        let rec1 = &bytes[rec1_start..rec1_start + 16];
        assert_eq!(rec1, b"+0.25\x14\x14Eye up\x14\x00");
    }

    #[test]
    fn partial_trailing_second_holds_last_sample() {
        let signals = vec![EdfSignal::eeg("TP9", 256, vec![5.0; 300])];
        let bytes = encode_edf_plus(&signals, &spec(&[])).unwrap();
        let header_len = 256 + 2 * 256;
        let read_i16 = |off: usize| {
            i16::from_le_bytes([bytes[header_len + off], bytes[header_len + off + 1]])
        };
        assert_eq!(read_i16(0), 82); // 5.0 * 65535/4000 = 81.92 → 82
        assert_eq!(read_i16(512 - 2), 82); // record 0 last sample
        // Record 1 starts after record 0 (512 data + 4 annotation bytes);
        // all samples hold 5.0 µV → 82.
        assert_eq!(read_i16(516), 82);
        assert_eq!(read_i16(516 + 512 - 2), 82);
    }

    #[test]
    fn validation_errors() {
        let spec = spec(&[]);
        assert_eq!(encode_edf_plus(&[], &spec), Err(EdfError::EmptySignals));
        let a = EdfSignal::eeg("TP9", 256, vec![0.0; 10]);
        let b = EdfSignal::eeg("AF7", 512, vec![0.0; 10]);
        assert_eq!(
            encode_edf_plus(&[a, b], &spec),
            Err(EdfError::MixedSampleRate)
        );
        assert_eq!(
            encode_edf_plus(&[EdfSignal::eeg("TP9", 256, vec![])], &spec),
            Err(EdfError::EmptySignal(0))
        );
        assert_eq!(
            encode_edf_plus(
                &[EdfSignal::eeg("a-very-long-electrode-name", 256, vec![0.0; 4])],
                &spec
            ),
            Err(EdfError::LabelTooLong("a-very-long-electrode-name".to_string()))
        );
        let mut bad = EdfFileSpec {
            patient_id: PATIENT,
            recording_id: RECORDING,
            start: (1900, 1, 1, 0, 0, 0),
            physical_dimension: "uV",
            annotations: &[],
        };
        assert_eq!(
            encode_edf_plus(&[EdfSignal::eeg("TP9", 256, vec![0.0; 4])], &bad),
            Err(EdfError::InvalidStart("(y, m, d, h, min, s)"))
        );
        bad.start = (2026, 1, 1, 0, 0, 0);
        assert!(encode_edf_plus(&[EdfSignal::eeg("TP9", 256, vec![0.0; 4])], &bad).is_ok());
    }

    #[test]
    fn empty_annotation_list_still_has_timekeeping() {
        let signals = vec![EdfSignal::eeg("TP9", 256, vec![0.0; 256])];
        let bytes = encode_edf_plus(&signals, &spec(&[])).unwrap();
        let header_len = 256 + 2 * 256;
        assert_eq!(&bytes[header_len + 512..header_len + 512 + 4], b"0\x14\x00");
    }
}
