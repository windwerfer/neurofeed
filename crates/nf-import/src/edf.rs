//! EDF / EDF+ import (ported from `edf_import.dart`).

use crate::montage::{match_montage, no_montage_message, reference_suffix, MontageMatch};
use crate::notes::{edf_patient_code, map_type};
use crate::{bad, device, eeg_records, time, Annotation, ImportError, Imported, Options, Provenance, Result, Run, NATIVE_EEG_HZ};
use nf_format::edf::{decode_edf_plus, EdfDecoded};
use nf_format::Record;

pub const BAND_NAMES: [&str; 5] = ["Delta", "Theta", "Alpha", "Beta", "Gamma"];
/// Record starts further apart than this (s) split a run (EDF+D gap).
const GAP_TOLERANCE_S: f64 = 0.05;

/// `Delta_TP9` → (band index, `TP9`).
pub fn parse_band_label(label: &str) -> Option<(usize, String)> {
    let cleaned = label.split_whitespace().collect::<Vec<_>>().join("_");
    BAND_NAMES.iter().enumerate().find_map(|(i, b)| {
        let head = cleaned.get(..=b.len())?;
        (head.eq_ignore_ascii_case(&format!("{b}_")) && cleaned.len() > b.len() + 1).then(|| (i, cleaned[b.len() + 1..].to_owned()))
    })
}

/// Contiguous record runs `(start s, first record, end record)`.
fn runs(starts: &[f64], dur: f64) -> Vec<(f64, usize, usize)> {
    let mut out = Vec::new();
    let mut first = 0;
    for i in 1..=starts.len() {
        if i == starts.len() || starts[i] - (starts[i - 1] + dur) > GAP_TOLERANCE_S {
            out.push((starts[first], first, i));
            first = i;
        }
    }
    out
}

struct Split<'a> {
    original: Vec<String>,
    eeg: Vec<&'a nf_format::edf::EdfSignal>,
    /// (band, channel, signal)
    bands: Vec<(usize, String, &'a nf_format::edf::EdfSignal)>,
}

fn split(d: &EdfDecoded) -> Split<'_> {
    let mut s = Split { original: Vec::new(), eeg: Vec::new(), bands: Vec::new() };
    for sig in &d.signals {
        let label = sig.label.trim();
        if label.is_empty() || label.to_lowercase().contains("annotation") {
            continue;
        }
        s.original.push(label.to_owned());
        match parse_band_label(label) {
            Some((b, ch)) => s.bands.push((b, ch, sig)),
            None => s.eeg.push(sig),
        }
    }
    s
}

pub fn import(bytes: &[u8], opts: Options<'_>) -> Result<Imported> {
    let d = decode_edf_plus(bytes).map_err(|e| ImportError::Format(format!("EDF: {e}")))?;
    let dur = if d.record_duration > 0.0 { d.record_duration } else { 1.0 };
    let sp = split(&d);
    let band_channels = unique(sp.bands.iter().map(|b| b.1.clone()));
    let source: Vec<String> =
        if sp.eeg.is_empty() { band_channels.clone() } else { sp.eeg.iter().map(|s| s.label.trim().to_owned()).collect() };
    let m = match_montage(&source).ok_or_else(|| ImportError::Refused(no_montage_message(&source)))?;
    let mut p = provenance(&d, &sp, &m, &source);
    let rs = runs(&d.record_starts, dur);
    let mut records = if sp.eeg.is_empty() { band_records(&sp.bands, &band_channels, &m) } else { eeg(&sp, &m, &rs, dur, &mut p) };
    if records.is_empty() {
        return bad("EDF contained no EEG/band samples");
    }
    notes(&d, &rs, dur, &mut p);
    if sp.eeg.is_empty() {
        p.bands_from_file = true;
    }
    let duration_s = duration(&d, &records, dur, sp.eeg.is_empty());
    let (y, mo, da, h, mi, s) = d.start;
    // NeuroFeed's own EDF export stamps UTC (recording field ends in "neurofeed").
    let ours = d.recording_id.split_whitespace().last() == Some("neurofeed");
    let offset = if ours { 0 } else { opts.utc_offset_minutes };
    let started = time::unix_ms((y.into(), mo.into(), da.into(), h.into(), mi.into(), s.into()), 0.0, offset);
    records.shrink_to_fit();
    let needs_bands = !sp.eeg.is_empty();
    Ok(Imported {
        device: device(m.kind, m.labels, &p.source_format),
        records,
        started_unix_ms: Some(started),
        duration_s,
        needs_bands,
        provenance: p,
    })
}

fn unique(it: impl Iterator<Item = String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for s in it {
        if !out.contains(&s) {
            out.push(s);
        }
    }
    out
}

fn provenance(d: &EdfDecoded, sp: &Split<'_>, m: &MontageMatch, source: &[String]) -> Provenance {
    let mut dropped = m.dropped.clone();
    if !sp.eeg.is_empty() {
        dropped.extend(sp.bands.iter().map(|b| b.2.label.trim().to_owned()));
    }
    let refs = unique(m.source.iter().filter_map(|&i| reference_suffix(&source[i]).map(str::to_owned)));
    let mut warnings = Vec::new();
    if !dropped.is_empty() {
        let dev = if m.kind == nf_types::DeviceKind::Muse { "Muse" } else { "Crown" };
        warnings.push(format!("dropped {} channel(s) outside the {dev} montage: {}", dropped.len(), dropped.join(", ")));
    }
    let code = edf_patient_code(&d.patient_id);
    if code.is_none() {
        warnings.push("EDF patient code missing".into());
    }
    Provenance {
        source_format: if d.reserved.trim().to_uppercase().starts_with("EDF+") { "edf+" } else { "edf" }.into(),
        original_channels: sp.original.clone(),
        lossy: !dropped.is_empty(),
        dropped_channels: dropped,
        raw_present: !sp.eeg.is_empty(),
        reference: (refs.len() == 1).then(|| refs[0].clone()),
        prefiltering: d
            .signals
            .iter()
            .filter(|s| !s.prefiltering.is_empty())
            .map(|s| (s.label.trim().to_owned(), s.prefiltering.clone()))
            .collect(),
        subject: code,
        warnings,
        ..Provenance::default()
    }
}

fn eeg(sp: &Split<'_>, m: &MontageMatch, rs: &[(f64, usize, usize)], dur: f64, p: &mut Provenance) -> Vec<Record> {
    let mut all = Vec::new();
    for (e, &src) in m.source.iter().enumerate() {
        let sig = sp.eeg[src];
        let spr = sig.samples_per_record;
        let rate = spr as f64 / dur;
        p.original_rate_hz.get_or_insert(rate);
        let resample = rate.round() != NATIVE_EEG_HZ;
        p.resampled |= resample;
        for &(start, first, end) in rs.iter().filter(|r| r.1 * spr < sig.data.len()) {
            let raw = &sig.data[first * spr..(end * spr).min(sig.data.len())];
            let samples = if resample { nf_dsp::resample(raw, rate, NATIVE_EEG_HZ) } else { raw.to_vec() };
            all.push(Run { electrode: e, start, samples });
        }
    }
    if p.resampled {
        let hz = p.original_rate_hz.unwrap_or(0.0);
        p.warnings.push(format!("EEG resampled from {} Hz to 256 Hz", fmt_hz(hz)));
        p.lossy = true;
    }
    eeg_records(&all)
}

fn fmt_hz(v: f64) -> String {
    if v.fract() == 0.0 {
        format!("{v:.0}")
    } else {
        format!("{v:.2}")
    }
}

/// Band-named signals, one row per sample (1 per second, legacy).
fn band_records(bands: &[(usize, String, &nf_format::edf::EdfSignal)], channels: &[String], m: &MontageMatch) -> Vec<Record> {
    let mut out = Vec::new();
    for (e, &src) in m.source.iter().enumerate() {
        let cols: Vec<Option<&[f32]>> =
            (0..5).map(|b| bands.iter().find(|x| x.0 == b && x.1 == channels[src]).map(|x| x.2.data.as_slice())).collect();
        let n = cols.iter().flatten().map(|c| c.len()).max().unwrap_or(0);
        for i in 0..n {
            let v: Option<Vec<f32>> = cols.iter().map(|c| c.and_then(|c| c.get(i).copied())).collect();
            if let Some(v) = v {
                let el = i16::try_from(e).unwrap_or(i16::MAX);
                out.push(Record::Bands { ts: i as f64, electrode: el, bands: [v[0], v[1], v[2], v[3], v[4]] });
            }
        }
    }
    out
}

fn notes(d: &EdfDecoded, rs: &[(f64, usize, usize)], dur: f64, p: &mut Provenance) {
    for a in &d.annotations {
        match map_type(&a.text) {
            Some(t) => p.annotations.push(Annotation { onset: a.onset_seconds, duration: a.duration_seconds, kind: t.into() }),
            None if !a.text.trim().is_empty() => p.warnings.push(format!("skipped EDF annotation \"{}\"", a.text.trim())),
            None => {}
        }
    }
    for w in rs.windows(2) {
        let end = d.record_starts[w[0].2 - 1] + dur;
        p.annotations.push(Annotation { onset: end, duration: w[1].0 - end, kind: "disconnect".into() });
    }
    if rs.len() > 1 {
        p.warnings.push(format!("{} recording gap(s) (EDF+D) kept as disconnect", rs.len() - 1));
    }
}

fn duration(d: &EdfDecoded, records: &[Record], dur: f64, bands_only: bool) -> f64 {
    if bands_only {
        return records.iter().map(crate::record_ts).fold(0.0, f64::max) + 1.0;
    }
    d.record_starts.last().map_or(0.0, |s| (s + dur).ceil())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use nf_format::edf::{encode_edf_plus, EdfAnnotation, EdfFileSpec, EdfSignal};

    fn edf(labels: &[&str], rate: usize, secs: usize, notes: &[EdfAnnotation]) -> Vec<u8> {
        let signals: Vec<_> = labels
            .iter()
            .enumerate()
            .map(|(k, l)| {
                let data = (0..rate * secs).map(|i| (10.0 * (i as f64 * 0.05 + k as f64).sin()) as f32).collect();
                EdfSignal::eeg((*l).to_owned(), rate, data)
            })
            .collect();
        let spec = EdfFileSpec {
            patient_id: "X X X X",
            recording_id: "Startdate X X X t",
            start: (2024, 3, 1, 12, 0, 0),
            physical_dimension: "uV",
            annotations: notes,
            discontinuous_starts: None,
        };
        encode_edf_plus(&signals, &spec).unwrap()
    }

    #[test]
    fn band_labels() {
        assert_eq!(parse_band_label("Alpha_TP9"), Some((2, "TP9".into())));
        assert_eq!(parse_band_label("delta AF7"), Some((0, "AF7".into())));
        assert_eq!(parse_band_label("TP9"), None);
    }

    #[test]
    fn muse_500hz_with_extra_channel() {
        let note = EdfAnnotation { onset_seconds: 2.0, duration_seconds: 0.0, text: "Double Blink".into() };
        let bytes = edf(&["TP9", "AF7", "AF8", "TP10", "ECG"], 500, 4, &[note]);
        let i = crate::import(&bytes, Options { file_name: "a.edf", utc_offset_minutes: 0 }).unwrap();
        assert_eq!(i.device.channels, vec!["TP9", "AF7", "AF8", "TP10"]);
        assert_eq!(i.eeg_samples(), 4 * 4 * 256);
        assert!(i.needs_bands && i.provenance.resampled && i.provenance.lossy);
        assert_eq!(i.provenance.dropped_channels, vec!["ECG"]);
        assert_eq!(i.provenance.annotations, vec![Annotation::at(2.0, "double_blink")]);
        assert_eq!(i.duration_s, 4.0);
    }

    #[test]
    fn no_montage_is_refused() {
        let bytes = edf(&["Fp1", "Fp2"], 256, 1, &[]);
        let e = crate::import(&bytes, Options { file_name: "a.edf", utc_offset_minutes: 0 });
        assert!(matches!(e, Err(ImportError::Refused(m)) if m.contains("Fp1, Fp2")));
    }
}
