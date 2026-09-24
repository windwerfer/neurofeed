//! Minimal EDF+ (European Data Format Plus) writer for EEG time-series
//! export.
//!
//! Supports the subset needed by the NeuroFeed session export: continuous
//! (EDF+C) recordings, int16 sample encoding, and a single annotation
//! channel carrying time-stamped annotations (gestures, calibration
//! boundaries). The writer is deterministic and dependency-free, with
//! golden tests pinning the byte layout so readers (EEGLAB, MNE,
//! EDFbrowser) keep parsing our files.
//!
//! Layout summary (EDF / EDF+ spec, edfplus.info):
//! - 256-byte ASCII fixed header + **field-major** signal headers
//!   (`ns` labels, then `ns` transducers, … — 256 bytes × `ns` total).
//! - One data record per second of **constant** size: for each signal,
//!   `samples_per_record` int16 LE samples; annotation channel last,
//!   sized to fit the largest TAL blob (NUL-padded).
//! - Annotation samples carry Time-stamped Annotation Lists (TALs).

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
    /// Seconds; `0` omits the TAL Duration segment (instant / unknown).
    pub duration_seconds: f64,
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
    let ann_samples = annotation_samples_per_record(spec, records);

    let capacity = EDF_HEADER_BLOCK
        + (signals.len() + 1) * EDF_HEADER_BLOCK
        + records * (signals.iter().map(|s| s.samples_per_record).sum::<usize>() + ann_samples) * 2;
    let mut out = Vec::with_capacity(capacity);
    write_header(&mut out, signals, spec, records, ann_samples);
    write_records(&mut out, signals, spec, records, ann_samples);
    Ok(out)
}

/// Fixed annotation-channel samples/record (EDF+ requires constant record size).
fn annotation_samples_per_record(spec: &EdfFileSpec, records: usize) -> usize {
    let mut max_bytes = 2usize; // minimum one int16 slot
    for r in 0..records {
        max_bytes = max_bytes.max(record_annotations(spec, r).len());
    }
    max_bytes.div_ceil(2).max(1)
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
fn write_header(
    out: &mut Vec<u8>,
    signals: &[EdfSignal],
    spec: &EdfFileSpec,
    records: usize,
    ann_samples: usize,
) {
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
    // Field-major signal headers (EDF spec): all labels, then transducers, …
    for s in signals {
        pad_field(out, &s.label, 16);
    }
    pad_field(out, EDF_ANNOTATION_LABEL, 16);
    for _ in 0..nsig {
        pad_field(out, " ", 80); // transducer
    }
    for _ in signals {
        pad_field(out, spec.physical_dimension, 8);
    }
    pad_field(out, " ", 8); // annotation dimension
    for s in signals {
        num_field(out, scaled_header_value(s.physical_min), 8);
    }
    num_field(out, 0, 8); // annotation phys min
    for s in signals {
        num_field(out, scaled_header_value(s.physical_max), 8);
    }
    num_field(out, 0, 8); // annotation phys max
    for _ in 0..nsig {
        num_field(out, -32768_i32, 8);
    }
    for _ in 0..nsig {
        num_field(out, 32767_i32, 8);
    }
    for _ in 0..nsig {
        pad_field(out, " ", 80); // prefiltering
    }
    for s in signals {
        num_field(out, s.samples_per_record, 8);
    }
    num_field(out, ann_samples, 8); // annotation samples/record
    for _ in 0..nsig {
        pad_field(out, " ", 32); // reserved
    }
    debug_assert_eq!(out.len(), header_len, "EDF header must be exactly header_len bytes");
}

/// Encodes one physical sample as a clamped int16 LE pair (EDF linear map).
fn encode_sample(s: &EdfSignal, value: f32) -> [u8; 2] {
    let dig_min = -32768.0f64;
    let dig_max = 32767.0f64;
    let span_p = s.physical_max - s.physical_min;
    let dig = if span_p == 0.0 {
        0.0
    } else {
        (value as f64 - s.physical_min) / span_p * (dig_max - dig_min) + dig_min
    };
    let dig_i = dig.clamp(dig_min, dig_max).round() as i16;
    dig_i.to_le_bytes()
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
            if a.duration_seconds > 0.0 {
                // EDF+ TAL: Onset \x15 Duration \x14 text \x14 \x00
                buf.push(0x15);
                let dur = format!("{}", a.duration_seconds);
                buf.extend_from_slice(dur.as_bytes());
                buf.push(0x14);
            } else {
                buf.push(0x14); // no duration segment
            }
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

fn write_records(
    out: &mut Vec<u8>,
    signals: &[EdfSignal],
    spec: &EdfFileSpec,
    records: usize,
    ann_samples: usize,
) {
    let rate = signals[0].samples_per_record;
    let ann_bytes = ann_samples * 2;
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
        let mut ann = record_annotations(spec, r);
        if ann.len() > ann_bytes {
            ann.truncate(ann_bytes);
        } else {
            ann.resize(ann_bytes, 0x00);
        }
        out.extend_from_slice(&ann);
    }
}


/// Decoded EDF+ file (subset sufficient for neurofeed import round-trips).
#[derive(Debug, Clone, PartialEq)]
pub struct EdfDecoded {
    pub patient_id: String,
    pub recording_id: String,
    pub start: (u16, u16, u16, u16, u16, u16),
    pub reserved: String,
    pub signals: Vec<EdfSignal>,
    pub annotations: Vec<EdfAnnotation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EdfDecodeError {
    TooShort,
    BadVersion,
    BadHeaderField(&'static str),
    Truncated,
}

impl std::fmt::Display for EdfDecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EdfDecodeError::TooShort => write!(f, "EDF file too short"),
            EdfDecodeError::BadVersion => write!(f, "not an EDF version-0 header"),
            EdfDecodeError::BadHeaderField(s) => write!(f, "bad header field: {s}"),
            EdfDecodeError::Truncated => write!(f, "EDF file truncated"),
        }
    }
}

impl std::error::Error for EdfDecodeError {}

fn trim_ascii(s: &[u8]) -> &[u8] {
    let mut end = s.len();
    while end > 0 && s[end - 1] == b' ' {
        end -= 1;
    }
    &s[..end]
}

fn parse_ascii_int(field: &[u8]) -> Result<i64, EdfDecodeError> {
    let t = trim_ascii(field);
    if t.is_empty() {
        return Ok(0);
    }
    std::str::from_utf8(t)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .ok_or(EdfDecodeError::BadHeaderField("int"))
}

fn parse_ascii_f64(field: &[u8]) -> Result<f64, EdfDecodeError> {
    let t = trim_ascii(field);
    if t.is_empty() {
        return Ok(0.0);
    }
    std::str::from_utf8(t)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .ok_or(EdfDecodeError::BadHeaderField("float"))
}

/// Decode an EDF / EDF+ file produced by this crate (and typical EDF+C writers).
pub fn decode_edf_plus(bytes: &[u8]) -> Result<EdfDecoded, EdfDecodeError> {
    if bytes.len() < EDF_HEADER_BLOCK {
        return Err(EdfDecodeError::TooShort);
    }
    if trim_ascii(&bytes[0..8]) != b"0" {
        return Err(EdfDecodeError::BadVersion);
    }
    let patient_id = String::from_utf8_lossy(trim_ascii(&bytes[8..88])).into_owned();
    let recording_id = String::from_utf8_lossy(trim_ascii(&bytes[88..168])).into_owned();
    let date = trim_ascii(&bytes[168..176]);
    let time = trim_ascii(&bytes[176..184]);
    let header_len = parse_ascii_int(&bytes[184..192])? as usize;
    let reserved = String::from_utf8_lossy(trim_ascii(&bytes[192..236])).into_owned();
    let n_records = parse_ascii_int(&bytes[236..244])? as usize;
    let _record_duration = parse_ascii_f64(&bytes[244..252])?;
    let nsig = parse_ascii_int(&bytes[252..256])? as usize;
    if nsig == 0 || header_len < EDF_HEADER_BLOCK + nsig * EDF_HEADER_BLOCK {
        return Err(EdfDecodeError::BadHeaderField("nsig/header_len"));
    }
    if bytes.len() < header_len {
        return Err(EdfDecodeError::Truncated);
    }

    // Signal header layout: for each field, nsig consecutive  width-bytes slots.
    let sh = &bytes[EDF_HEADER_BLOCK..header_len];
    let mut off = 0usize;
    let mut take_owned = |width: usize, n: usize| -> Result<Vec<Vec<u8>>, EdfDecodeError> {
        let need = width * n;
        if off + need > sh.len() {
            return Err(EdfDecodeError::Truncated);
        }
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            out.push(sh[off + i * width..off + (i + 1) * width].to_vec());
        }
        off += need;
        Ok(out)
    };
    let labels = take_owned(16, nsig)?;
    let _trans = take_owned(80, nsig)?;
    let _dims = take_owned(8, nsig)?;
    let pmin = take_owned(8, nsig)?;
    let pmax = take_owned(8, nsig)?;
    let dmin = take_owned(8, nsig)?;
    let dmax = take_owned(8, nsig)?;
    let _pre = take_owned(80, nsig)?;
    let nsamp = take_owned(8, nsig)?;
    let _reserved_s = take_owned(32, nsig)?;

    let samples_per: Vec<usize> = nsamp
        .iter()
        .map(|f| parse_ascii_int(f.as_slice()).map(|v| v as usize))
        .collect::<Result<_, _>>()?;
    let record_bytes: usize = samples_per.iter().map(|n| n * 2).sum();
    let data = &bytes[header_len..];
    if n_records > 0 && data.len() < n_records * record_bytes {
        return Err(EdfDecodeError::Truncated);
    }

    // Parse start date/time dd.mm.yy / hh.mm.ss
    let parse_dot = |s: &[u8]| -> Result<(u16, u16, u16), EdfDecodeError> {
        let s = std::str::from_utf8(s).map_err(|_| EdfDecodeError::BadHeaderField("date"))?;
        let parts: Vec<_> = s.split('.').collect();
        if parts.len() != 3 {
            return Err(EdfDecodeError::BadHeaderField("date"));
        }
        let a: u16 = parts[0].parse().map_err(|_| EdfDecodeError::BadHeaderField("date"))?;
        let b: u16 = parts[1].parse().map_err(|_| EdfDecodeError::BadHeaderField("date"))?;
        let c: u16 = parts[2].parse().map_err(|_| EdfDecodeError::BadHeaderField("date"))?;
        Ok((a, b, c))
    };
    let (day, month, yy) = parse_dot(date)?;
    let (hour, minute, second) = parse_dot(time)?;
    let year = if yy >= 85 { 1900 + yy } else { 2000 + yy };

    // Accumulate samples per non-annotation signal; parse TAL texts.
    let mut signal_data: Vec<Vec<f32>> = vec![Vec::new(); nsig];
    let mut annotations = Vec::new();
    for r in 0..n_records {
        let mut roff = r * record_bytes;
        for si in 0..nsig {
            let n = samples_per[si];
            let chunk = &data[roff..roff + n * 2];
            roff += n * 2;
            let label = String::from_utf8_lossy(trim_ascii(&labels[si]));
            if label.as_ref() == EDF_ANNOTATION_LABEL {
                parse_tals(chunk, r as f64, &mut annotations);
                continue;
            }
            let phys_min = parse_ascii_f64(&pmin[si])?;
            let phys_max = parse_ascii_f64(&pmax[si])?;
            let dig_min = parse_ascii_int(&dmin[si])? as f64;
            let dig_max = parse_ascii_int(&dmax[si])? as f64;
            let span_d = (dig_max - dig_min).max(1.0);
            let span_p = phys_max - phys_min;
            for i in 0..n {
                let dig = i16::from_le_bytes([chunk[i * 2], chunk[i * 2 + 1]]) as f64;
                let phys = phys_min + (dig - dig_min) * span_p / span_d;
                signal_data[si].push(phys as f32);
            }
        }
    }

    let mut signals = Vec::new();
    for si in 0..nsig {
        let label = String::from_utf8_lossy(trim_ascii(&labels[si])).into_owned();
        if label == EDF_ANNOTATION_LABEL {
            continue;
        }
        let rate = samples_per[si];
        let phys_min = parse_ascii_f64(&pmin[si])?;
        let phys_max = parse_ascii_f64(&pmax[si])?;
        signals.push(EdfSignal {
            label,
            samples_per_record: rate,
            physical_min: phys_min,
            physical_max: phys_max,
            data: signal_data[si].clone(),
        });
    }

    Ok(EdfDecoded {
        patient_id,
        recording_id,
        start: (year, month, day, hour, minute, second),
        reserved,
        signals,
        annotations,
    })
}

fn parse_tals(buf: &[u8], record_start: f64, out: &mut Vec<EdfAnnotation>) {
    let mut i = 0;
    while i < buf.len() {
        if buf[i] == 0 {
            i += 1;
            continue;
        }
        // Onset: optional '+' then digits / '.' until \x14 or \x15
        let start = i;
        if buf[i] == b'+' || buf[i] == b'-' {
            i += 1;
        }
        while i < buf.len() && (buf[i].is_ascii_digit() || buf[i] == b'.') {
            i += 1;
        }
        let onset_str = std::str::from_utf8(&buf[start..i]).unwrap_or("");
        let onset_rel: f64 = onset_str.parse().unwrap_or(0.0);
        let mut duration: Option<f64> = None;
        if i < buf.len() && buf[i] == 0x15 {
            i += 1;
            let d0 = i;
            while i < buf.len() && (buf[i].is_ascii_digit() || buf[i] == b'.') {
                i += 1;
            }
            duration = std::str::from_utf8(&buf[d0..i]).ok().and_then(|s| s.parse().ok());
        }
        if i < buf.len() && buf[i] == 0x14 {
            i += 1;
        }
        // Zero or more texts terminated by 0x14; TAL ends with 0x00
        let mut texts = Vec::new();
        while i < buf.len() && buf[i] != 0x00 {
            if buf[i] == 0x14 {
                i += 1;
                continue;
            }
            let t0 = i;
            while i < buf.len() && buf[i] != 0x14 && buf[i] != 0x00 {
                i += 1;
            }
            if i > t0 {
                if let Ok(s) = std::str::from_utf8(&buf[t0..i]) {
                    if !s.is_empty() {
                        texts.push(s.to_string());
                    }
                }
            }
            if i < buf.len() && buf[i] == 0x14 {
                i += 1;
            }
        }
        if i < buf.len() && buf[i] == 0x00 {
            i += 1;
        }
        let onset = record_start + onset_rel;
        // Skip empty timekeeping TALs (no text).
        for t in texts {
            out.push(EdfAnnotation {
                onset_seconds: onset,
                duration_seconds: duration.unwrap_or(0.0),
                text: t,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATIENT: &str = "NeuroFeed";
    const RECORDING: &str = "NeuroFeed session 0.0.1-test-01";

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
        // Empty annotations: timekeeping TAL is 3 bytes → pad to 4 (2 samples).
        let ann_bytes = 4;
        assert_eq!(bytes.len(), 1024 + 2 * (512 + 512 + ann_bytes));
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
        // labels (field-major)
        assert_eq!(&header[256..272], format!("{:<16}", "TP9").as_bytes());
        assert_eq!(&header[272..288], format!("{:<16}", "AF7").as_bytes());
        assert_eq!(&header[288..304], format!("{:<16}", "EDF Annotations").as_bytes());
        // physical dimension for signal 0 / 1
        assert_eq!(&header[544..552], format!("{:<8}", "uV").as_bytes());
        assert_eq!(&header[552..560], format!("{:<8}", "uV").as_bytes());
        // phys min/max signal 0
        assert_eq!(&header[568..576], format!("{:>8}", "-2000").as_bytes());
        assert_eq!(&header[592..600], format!("{:>8}", "2000").as_bytes());
        // dig min/max signal 0
        assert_eq!(&header[616..624], format!("{:>8}", "-32768").as_bytes());
        assert_eq!(&header[640..648], format!("{:>8}", "32767").as_bytes());
        // samples/record: EEG 256, 256, ann 2
        assert_eq!(&header[904..912], format!("{:>8}", "256").as_bytes());
        assert_eq!(&header[912..920], format!("{:>8}", "256").as_bytes());
        assert_eq!(&header[920..928], format!("{:>8}", "2").as_bytes());
    }

    #[test]
    fn sample_scaling_is_int16_le() {
        let mut signals = two_signals();
        signals[0].data = vec![1.0, -1.0, 2000.0, -2000.0];
        let bytes = encode_edf_plus(&signals, &spec(&[])).unwrap();
        let read_i16 = |off: usize| i16::from_le_bytes([bytes[1024 + off], bytes[1024 + off + 1]]);
        // Standard EDF map: phys ∈ [-2000,2000] ↔ dig ∈ [-32768,32767].
        // 1 µV above midpoint (0) ≈ 65535/4000 ≈ 16 LSB.
        assert_eq!(read_i16(0), 16);
        assert_eq!(read_i16(2), -17); // -1 µV
        assert_eq!(read_i16(4), 32767); // +2000
        assert_eq!(read_i16(6), -32768); // -2000
        // Record 1 after record 0 (512+512 data + 4 ann bytes): hold last = -2000.
        assert_eq!(read_i16(1028), -32768);
        assert_eq!(read_i16(1030), -32768);
    }

    #[test]
    fn annotation_tals_land_in_their_record() {
        let annotations = vec![
            EdfAnnotation { onset_seconds: 0.5, duration_seconds: 0.0, text: "Double blink".to_string() },
            EdfAnnotation { onset_seconds: 1.25, duration_seconds: 0.0, text: "Eye up".to_string() },
        ];
        let signals = vec![EdfSignal::eeg("TP9", 256, vec![0.0; 400])];
        let bytes = encode_edf_plus(&signals, &spec(&annotations)).unwrap();
        let header_len = 256 + 2 * 256;
        // Record 0 needs 3 + 19 = 22 TAL bytes → 11 int16 samples (even).
        let ann_bytes = 22;
        let rec0 = &bytes[header_len + 512..header_len + 512 + 22];
        assert_eq!(rec0, b"0\x14\x00+0.5\x14Double blink\x14\x00");
        let rec1_start = header_len + 512 + ann_bytes + 512;
        let rec1 = &bytes[rec1_start..rec1_start + 14];
        assert_eq!(rec1, b"+0.25\x14Eye up\x14\x00");
        // Constant record size.
        let n_records = 2;
        assert_eq!(
            bytes.len(),
            header_len + n_records * (512 + ann_bytes)
        );
    }

    #[test]
    fn partial_trailing_second_holds_last_sample() {
        let signals = vec![EdfSignal::eeg("TP9", 256, vec![5.0; 300])];
        let bytes = encode_edf_plus(&signals, &spec(&[])).unwrap();
        let header_len = 256 + 2 * 256;
        let read_i16 = |off: usize| {
            i16::from_le_bytes([bytes[header_len + off], bytes[header_len + off + 1]])
        };
        // 5 µV → (5+2000)/4000*65535 - 32768 ≈ 81.42 → 81
        assert_eq!(read_i16(0), 81);
        assert_eq!(read_i16(512 - 2), 81); // record 0 last sample
        // Record 1 starts after record 0 (512 data + 4 annotation bytes padded).
        assert_eq!(read_i16(516), 81);
        assert_eq!(read_i16(516 + 510), 81);
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
        assert_eq!(&bytes[header_len + 512..header_len + 512 + 3], b"0\x14\x00");
        assert_eq!(bytes[header_len + 512 + 3], 0x00); // padded to 4 bytes
    }
    #[test]
    fn encode_decode_round_trip() {
        let annotations = vec![
            EdfAnnotation { onset_seconds: 0.5, duration_seconds: 0.0, text: "double_blink".to_string() },
            EdfAnnotation { onset_seconds: 1.25, duration_seconds: 0.0, text: "eye_up".to_string() },
        ];
        let signals = vec![
            EdfSignal::eeg("TP9", 256, vec![1.0; 400]),
            EdfSignal::eeg("AF7", 256, vec![-1.0; 400]),
        ];
        let bytes = encode_edf_plus(&signals, &spec(&annotations)).unwrap();
        let dec = decode_edf_plus(&bytes).unwrap();
        assert_eq!(dec.patient_id, PATIENT);
        assert_eq!(dec.recording_id, RECORDING);
        assert_eq!(dec.start, (2026, 8, 19, 10, 30, 5));
        assert!(dec.reserved.starts_with("EDF+C"));
        assert_eq!(dec.signals.len(), 2);
        assert_eq!(dec.signals[0].label, "TP9");
        assert_eq!(dec.signals[1].label, "AF7");
        // ±2000 µV range → 1 µV is ~1 LSB; allow half-µV error.
        assert!((dec.signals[0].data[0] - 1.0).abs() < 0.5, "{}", dec.signals[0].data[0]);
        assert!((dec.signals[1].data[0] + 1.0).abs() < 0.5, "{}", dec.signals[1].data[0]);
        let texts: Vec<_> = dec.annotations.iter().map(|a| a.text.as_str()).collect();
        assert!(texts.contains(&"double_blink"));
        assert!(texts.contains(&"eye_up"));
    }


    #[test]
    fn duration_round_trip_in_tal() {
        let signals = two_signals();
        let annotations = [
            EdfAnnotation {
                onset_seconds: 0.5,
                duration_seconds: 15.0,
                text: "bad_quality".to_string(),
            },
            EdfAnnotation {
                onset_seconds: 1.25,
                duration_seconds: 0.0,
                text: "double_blink".to_string(),
            },
        ];
        let bytes = encode_edf_plus(&signals, &spec(&annotations)).unwrap();
        let dec = decode_edf_plus(&bytes).unwrap();
        let bq = dec
            .annotations
            .iter()
            .find(|a| a.text == "bad_quality")
            .expect("bad_quality");
        assert!((bq.duration_seconds - 15.0).abs() < 1e-9, "got {}", bq.duration_seconds);
        let db = dec
            .annotations
            .iter()
            .find(|a| a.text == "double_blink")
            .expect("double_blink");
        assert!((db.duration_seconds).abs() < 1e-9);
    }
}
