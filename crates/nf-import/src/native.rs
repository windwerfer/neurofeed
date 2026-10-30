//! Native imports: `.neurofeed` (NFED6) containers written by the legacy
//! Flutter app or by us, and bare NFEDBIN raw bodies.
//!
//! Clocks differ: we write session seconds; legacy wrote milliseconds
//! (wall-clock epoch of the last sample when live). Records are rebased to
//! seconds from the first EEG record; the unit is taken from our metadata
//! or, without it, from the EEG span vs. its sample count.

use crate::montage::{match_montage, CROWN, MUSE, MUSE_AUX};
use crate::{bad, device, record_ts, time, ImportError, Imported, Options, Provenance, Result, NATIVE_EEG_HZ};
use nf_format::body::HEADER_MAGIC_BYTES;
use nf_format::container::V6_MAGIC;
use nf_format::Record;
use nf_types::DeviceInfo;
use serde_json::Value;

pub fn sniff(bytes: &[u8]) -> bool {
    bytes.starts_with(&V6_MAGIC) || bytes.starts_with(&HEADER_MAGIC_BYTES)
}

struct Meta {
    device: Option<DeviceInfo>,
    labels: Vec<String>,
    started_unix_ms: Option<f64>,
    /// Our own export: session seconds already.
    ours: bool,
}

pub fn import(bytes: &[u8], _opts: Options<'_>) -> Result<Imported> {
    let fmt = |e: nf_format::FormatError| ImportError::Format(e.0);
    let (body, meta, source) = if bytes.starts_with(&V6_MAGIC) {
        let c = nf_format::decode_container(bytes).map_err(fmt)?;
        (c.raw_body, read_meta(&c.metadata_json), "neurofeed")
    } else {
        (bytes.to_vec(), Meta { device: None, labels: Vec::new(), started_unix_ms: None, ours: false }, "raw_body")
    };
    let mut records = nf_format::parse_body(&body).map_err(fmt)?;
    if !records.iter().any(|r| matches!(r, Record::Eeg { .. } | Record::Bands { .. })) {
        return bad("Recording has no EEG or band records");
    }
    let mut p = Provenance { source_format: source.into(), ..Provenance::default() };
    let dev = pick_device(&meta, &records, source, &mut p)?;
    let t0 = rebase(&mut records, meta.ours);
    let started_unix_ms = meta.started_unix_ms.or_else(|| (t0.1 && t0.0 > 1e12).then_some(t0.0));
    p.raw_present = records.iter().any(|r| matches!(r, Record::Eeg { .. }));
    p.bands_from_file = records.iter().any(|r| matches!(r, Record::Bands { .. }));
    p.original_channels = dev.channels.clone();
    let duration_s = records.iter().map(record_ts).fold(0.0, f64::max).ceil();
    let needs_bands = p.raw_present && !p.bands_from_file;
    Ok(Imported { device: dev, records, started_unix_ms, duration_s, needs_bands, provenance: p })
}

fn read_meta(json: &[u8]) -> Meta {
    let v: Value = serde_json::from_slice(json).unwrap_or(Value::Null);
    let ours = v["format"] == "nfed6";
    let device = if ours { serde_json::from_value::<DeviceInfo>(v["device"].clone()).ok() } else { None };
    let labels = v["device"]["channelLabels"]
        .as_array()
        .map(|a| a.iter().filter_map(|s| s.as_str().map(str::to_owned)).collect())
        .unwrap_or_default();
    let started = if ours { v["wall_clock_unix_ms"].as_f64() } else { v["startedAt"].as_str().and_then(parse_iso) };
    Meta { device, labels, started_unix_ms: started, ours }
}

/// ISO 8601 with optional `Z` / `±HH:MM` (missing = UTC).
pub fn parse_iso(s: &str) -> Option<f64> {
    let s = s.trim();
    let (body, off) = match s.rfind(['+', '-']).filter(|&i| i > 10) {
        Some(i) => (&s[..i], &s[i..]),
        None => (s.trim_end_matches('Z'), ""),
    };
    let minutes = if off.is_empty() {
        0
    } else {
        let sign = if off.starts_with('-') { -1 } else { 1 };
        let (h, m) = off[1..].split_once(':').unwrap_or((&off[1..], "0"));
        sign * (h.parse::<i32>().ok()? * 60 + m.parse::<i32>().ok()?)
    };
    let (c, ms) = time::parse_stamp(body)?;
    Some(time::unix_ms(c, ms, minutes))
}

fn electrodes(records: &[Record]) -> usize {
    records
        .iter()
        .filter_map(|r| {
            if let Record::Eeg { electrode, .. } | Record::Bands { electrode, .. } = r {
                usize::try_from(*electrode).ok()
            } else {
                None
            }
        })
        .max()
        .map_or(0, |m| m + 1)
}

fn pick_device(meta: &Meta, records: &[Record], source: &str, p: &mut Provenance) -> Result<DeviceInfo> {
    if let Some(d) = &meta.device {
        return Ok(d.clone());
    }
    let n = electrodes(records);
    let labels = if meta.labels.len() >= n && !meta.labels.is_empty() { meta.labels.clone() } else { default_labels(n, p)? };
    let m = match_montage(&labels).ok_or_else(|| ImportError::Refused(crate::montage::no_montage_message(&labels)))?;
    if m.source.iter().enumerate().any(|(i, &s)| i != s) {
        return Err(ImportError::Refused(format!("Unexpected channel order in recording: {}", labels.join(", "))));
    }
    let mut d = device(m.kind, m.labels, source);
    let ppg = records.iter().filter_map(|r| if let Record::Ppg { channel, .. } = r { usize::try_from(*channel).ok() } else { None }).max();
    d.ppg_channels = ppg.map(|m| ["ambient", "infrared", "red"].iter().take(m + 1).map(|s| (*s).to_owned()).collect()).unwrap_or_default();
    d.ppg_rate_hz = ppg.map(|_| 64.0);
    d.accel_rate_hz = records.iter().any(|r| matches!(r, Record::Accelerometer { .. })).then_some(52.0);
    Ok(d)
}

fn default_labels(n: usize, p: &mut Provenance) -> Result<Vec<String>> {
    let labels: Vec<&str> = match n {
        4..=7 => MUSE.iter().chain(MUSE_AUX.iter()).take(n).copied().collect(),
        8 => CROWN.to_vec(),
        _ => return Err(ImportError::Refused(format!("Recording has {n} EEG channels; expected 4–8 (Muse) or 8 (Crown)"))),
    };
    p.warnings.push(format!("no metadata — assumed {} channel labels", if n == 8 { "Crown" } else { "Muse" }));
    Ok(labels.into_iter().map(str::to_owned).collect())
}

/// Rebase to seconds from the first EEG (or any) record. Returns the
/// original first timestamp and whether it was in milliseconds.
fn rebase(records: &mut [Record], ours: bool) -> (f64, bool) {
    let eeg: Vec<f64> = records.iter().filter(|r| matches!(r, Record::Eeg { .. })).map(record_ts).collect();
    let t0 = eeg.iter().copied().fold(f64::INFINITY, f64::min);
    let t0 = if t0.is_finite() { t0 } else { records.iter().map(record_ts).fold(f64::INFINITY, f64::min) };
    let ms = !ours && is_millis(records, &eeg);
    let scale = if ms { 1e-3 } else { 1.0 };
    for r in records.iter_mut() {
        set_ts(r, |ts| ((ts - t0) * scale).max(0.0));
    }
    (t0, ms)
}

/// EEG span ≫ sample duration ⇒ the clock is in milliseconds.
fn is_millis(records: &[Record], eeg: &[f64]) -> bool {
    let n = electrodes(records).max(1);
    let samples: usize = records.iter().map(|r| if let Record::Eeg { samples, .. } = r { samples.len() } else { 0 }).sum();
    let secs = samples as f64 / n as f64 / NATIVE_EEG_HZ;
    let span = eeg.iter().copied().fold(f64::MIN, f64::max) - eeg.iter().copied().fold(f64::MAX, f64::min);
    secs > 0.0 && span > 100.0 * secs
}

fn set_ts(r: &mut Record, f: impl Fn(f64) -> f64) {
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
        | Record::Feedback { ts, .. } => *ts = f(*ts),
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use nf_format::BodyWriter;
    use nf_types::DeviceKind;

    fn body(ms: bool) -> Vec<u8> {
        let mut w = BodyWriter::new();
        let base = if ms { 1_709_290_800_000.0 } else { 0.0 };
        let step = if ms { 12_000.0 / 256.0 } else { 12.0 / 256.0 };
        for k in 0..100 {
            for e in 0..4 {
                w.push(&Record::Eeg { ts: base + k as f64 * step, electrode: e, samples: vec![1.0; 12] });
            }
        }
        w.finish()
    }

    #[test]
    fn legacy_millis_body_is_rebased() {
        let i = crate::import(&body(true), Options { file_name: "x.raw", utc_offset_minutes: 0 }).unwrap();
        assert_eq!(i.device.channels, vec!["TP9", "AF7", "AF8", "TP10"]);
        assert_eq!(i.started_unix_ms, Some(1_709_290_800_000.0));
        let last = i.records.iter().map(record_ts).fold(0.0, f64::max);
        assert!((last - 99.0 * 12.0 / 256.0).abs() < 1e-6, "{last}");
        assert!(i.needs_bands);
        assert_eq!(i.provenance.source_format, "raw_body");
    }

    #[test]
    fn our_container_round_trips() {
        let dev = device(DeviceKind::Muse, MUSE.iter().map(|s| (*s).to_owned()).collect(), "x");
        let meta = serde_json::json!({"format": "nfed6", "device": dev, "wall_clock_unix_ms": 5.0e12});
        let c = nf_format::Container {
            thumbnail: vec![],
            metadata_json: serde_json::to_vec(&meta).unwrap(),
            computed_jsonl: vec![],
            raw_body: body(false),
        };
        let bytes = nf_format::encode_container(&c);
        let i = crate::import(&bytes, Options { file_name: "s.neurofeed", utc_offset_minutes: 0 }).unwrap();
        assert_eq!(i.device, dev);
        assert_eq!(i.started_unix_ms, Some(5.0e12));
        assert_eq!(i.eeg_samples(), 4800);
    }

    #[test]
    fn iso_offsets() {
        assert_eq!(parse_iso("2024-03-01T13:00:00.000+01:00"), Some(1_709_294_400_000.0));
        assert_eq!(parse_iso("2024-03-01T12:00:00Z"), Some(1_709_294_400_000.0));
    }
}
