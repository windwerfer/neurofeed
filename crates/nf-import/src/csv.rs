//! Mind Monitor CSV import (ported from `csv_import.dart`).
//!
//! Constant files (rows < 0.25 s apart) carry RAW at 256 or 220 Hz plus IMU
//! and PPG; Interval files are one snapshot per interval and import as
//! bands only. Mind Monitor repeats the last IMU / PPG value on rows without
//! a new sample, so repeats are dropped and the rate is measured.

use crate::edf::BAND_NAMES;
use crate::montage::{match_montage, no_montage_message, MontageMatch, MUSE, MUSE_AUX};
use crate::{device, eeg_records, notes, time, ImportError, Imported, Options, Provenance, Result, Run, NATIVE_EEG_HZ};
use nf_format::Record;
use std::collections::HashMap;

pub const CONSTANT_MAX_ROW_S: f64 = 0.25;
/// Each band row covers this window, so coverage = min(1, window / interval).
pub const BAND_WINDOW_S: f64 = 1.0;
const PPG_NAMES: [(&str, usize); 8] =
    [("PPG_Ambient", 0), ("PPG_Green", 0), ("PPG_IR", 1), ("PPG_IR-H16", 1), ("PPG_Red", 2), ("PPG_1", 0), ("PPG_2", 1), ("PPG_3", 2)];
const PPG_LABELS: [&str; 3] = ["ambient", "infrared", "red"];

struct Table<'a> {
    col: HashMap<&'a str, usize>,
    headers: Vec<&'a str>,
    /// Seconds from the first row.
    t: Vec<f64>,
    start_ms: f64,
    rows: Vec<Vec<&'a str>>,
}

impl Table<'_> {
    fn get(&self, row: usize, name: &str) -> Option<f32> {
        let i = *self.col.get(name)?;
        self.rows[row].get(i)?.trim().parse().ok()
    }

    fn has_prefix(&self, p: &str) -> bool {
        self.headers.iter().any(|h| h.starts_with(p))
    }
}

fn parse(text: &str, offset_min: i32) -> Result<Table<'_>> {
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let headers: Vec<&str> = lines.next().ok_or_else(|| ImportError::Format("CSV is empty".into()))?.split(',').map(str::trim).collect();
    if headers.first() != Some(&"TimeStamp") {
        return Err(ImportError::Format("CSV must start with TimeStamp column".into()));
    }
    let col = headers.iter().enumerate().map(|(i, h)| (*h, i)).collect();
    let (mut t, mut rows, mut start_ms) = (Vec::new(), Vec::new(), None);
    for (n, line) in lines.enumerate() {
        let cells: Vec<&str> = line.split(',').collect();
        let (c, ms) =
            time::parse_stamp(cells[0]).ok_or_else(|| ImportError::Format(format!("bad TimeStamp on line {}: {}", n + 2, cells[0])))?;
        let abs = time::unix_ms(c, ms, offset_min);
        let s = *start_ms.get_or_insert(abs);
        t.push((abs - s) / 1000.0);
        rows.push(cells);
    }
    if rows.len() < 2 {
        return Err(ImportError::Format("CSV needs at least two data rows".into()));
    }
    Ok(Table { col, headers, t, start_ms: start_ms.unwrap_or(0.0), rows })
}

/// Montage over RAW_/band channel names plus AUX columns (as AUX1..4).
fn montage(tb: &Table<'_>) -> Result<Columns> {
    let mut eeg: Vec<String> = Vec::new();
    for h in &tb.headers {
        let ch = h.strip_prefix("RAW_").or_else(|| BAND_NAMES.iter().find_map(|b| h.strip_prefix(&format!("{b}_"))));
        if let Some(ch) = ch.filter(|c| !eeg.iter().any(|e| e == c)) {
            eeg.push(ch.to_owned());
        }
    }
    let aux: Vec<String> = tb.headers.iter().filter(|h| h.to_uppercase().starts_with("AUX")).take(4).map(|h| (*h).to_owned()).collect();
    let mut names = eeg.clone();
    names.extend(MUSE_AUX.iter().take(aux.len()).map(|s| (*s).to_owned()));
    let m = match_montage(&names).ok_or_else(|| ImportError::Refused(no_montage_message(&[eeg.clone(), aux.clone()].concat())))?;
    // Column for each kept label: `RAW_<src>` / band prefix, or the AUX column.
    let cols = m.source.iter().map(|&i| if i < eeg.len() { eeg[i].clone() } else { aux[i - eeg.len()].clone() }).collect();
    let mut sources = eeg;
    sources.extend(aux);
    Ok(Columns { m, cols, sources })
}

struct Columns {
    m: MontageMatch,
    /// Source column stem per kept label (`TP9` for `RAW_TP9`, or the AUX column).
    cols: Vec<String>,
    /// All source EEG / AUX names.
    sources: Vec<String>,
}

fn median(mut v: Vec<f64>) -> Option<f64> {
    v.sort_by(f64::total_cmp);
    v.get(v.len() / 2).copied()
}

pub fn import(text: &str, opts: Options<'_>) -> Result<Imported> {
    let tb = parse(text, opts.utc_offset_minutes)?;
    let Columns { m, cols, sources } = montage(&tb)?;
    let dt = median(tb.t.windows(2).map(|w| w[1] - w[0]).collect()).unwrap_or(1.0);
    let mut p = Provenance { source_format: "mind_monitor_csv".into(), original_channels: sources.clone(), ..Provenance::default() };
    p.reference = MUSE.contains(&m.labels[0].as_str()).then(|| "FPz".into());
    let optics: Vec<String> = tb.headers.iter().filter(|h| h.starts_with("Optics")).map(|h| (*h).to_owned()).collect();
    if !optics.is_empty() {
        p.warnings.push(format!("dropped {} Optics (fNIRS) column(s)", optics.len()));
        p.dropped_channels.extend(optics);
    }
    let mut dev = device(m.kind, m.labels.clone(), "mind_monitor_csv");
    let mut records =
        if dt < CONSTANT_MAX_ROW_S { constant(&tb, &m, &cols, &mut p, &mut dev)? } else { interval(&tb, &m, &cols, &sources, &mut p)? };
    elements(&tb, &mut p);
    p.lossy |= p.resampled || !p.dropped_channels.is_empty();
    records.shrink_to_fit();
    let needs_bands = p.raw_present && !p.bands_from_file;
    let duration_s = tb.t.last().copied().unwrap_or(0.0).max(1.0).ceil();
    Ok(Imported { device: dev, records, started_unix_ms: Some(tb.start_ms), duration_s, needs_bands, provenance: p })
}

fn is_aux(label: &str) -> bool {
    label.starts_with("AUX")
}

/// Band rows (log Bels as Mind Monitor writes them); `dedupe` drops rows
/// that repeat the previous values (Constant files repeat bands).
fn band_records(tb: &Table<'_>, m: &MontageMatch, cols: &[String], dedupe: bool) -> Vec<Record> {
    let mut out = Vec::new();
    let mut last: Vec<Option<[f32; 5]>> = vec![None; m.labels.len()];
    for row in 0..tb.rows.len() {
        for (e, _) in m.labels.iter().enumerate().filter(|(_, l)| !is_aux(l)) {
            let v: Option<Vec<f32>> = BAND_NAMES.iter().map(|b| tb.get(row, &format!("{b}_{}", cols[e]))).collect();
            let Some(v) = v.map(|v| [v[0], v[1], v[2], v[3], v[4]]) else { continue };
            if dedupe && last[e] == Some(v) {
                continue;
            }
            last[e] = Some(v);
            out.push(Record::Bands { ts: tb.t[row], electrode: i16::try_from(e).unwrap_or(i16::MAX), bands: v });
        }
    }
    out
}

fn interval(tb: &Table<'_>, m: &MontageMatch, cols: &[String], sources: &[String], p: &mut Provenance) -> Result<Vec<Record>> {
    let bands = band_records(tb, m, cols, false);
    let has_raw = m.labels.iter().enumerate().any(|(e, _)| (0..tb.rows.len()).any(|r| tb.get(r, &format!("RAW_{}", cols[e])).is_some()));
    if bands.is_empty() {
        return Err(ImportError::Refused(
            "This Mind Monitor CSV uses a recording interval and has no band columns — one RAW snapshot per interval is not importable EEG."
                .into(),
        ));
    }
    let gap = median(band_gaps(&bands)).unwrap_or(1.0);
    let interval = (gap * 10.0).round() / 10.0;
    p.recording_interval = Some(interval);
    p.interval_coverage = Some(((BAND_WINDOW_S / interval).min(1.0) * 1000.0).round() / 1000.0);
    p.bands_from_file = true;
    let aux: Vec<String> = sources.iter().filter(|c| c.to_uppercase().starts_with("AUX")).cloned().collect();
    p.dropped_channels.extend(aux.iter().cloned());
    let skipped: Vec<&str> = [
        (has_raw, "RAW"),
        (!aux.is_empty(), "AUX"),
        (tb.has_prefix("Accelerometer_") || tb.has_prefix("Gyro_"), "IMU"),
        (tb.has_prefix("PPG_"), "PPG"),
    ]
    .iter()
    .filter_map(|(on, s)| on.then_some(*s))
    .collect();
    if !skipped.is_empty() {
        let secs = if interval.fract() == 0.0 { format!("{interval:.0}") } else { format!("{interval:.1}") };
        p.warnings
            .push(format!("Recording interval {secs} s: {} are one snapshot per interval — not imported (bands only)", skipped.join("/")));
    }
    p.lossy = has_raw;
    Ok(bands)
}

fn band_gaps(bands: &[Record]) -> Vec<f64> {
    let ts: Vec<f64> = bands.iter().filter(|r| matches!(r, Record::Bands { electrode: 0, .. })).map(crate::record_ts).collect();
    ts.windows(2).map(|w| w[1] - w[0]).collect()
}

fn constant(tb: &Table<'_>, m: &MontageMatch, cols: &[String], p: &mut Provenance, dev: &mut nf_types::DeviceInfo) -> Result<Vec<Record>> {
    let runs = raw_runs(tb, m, cols, p);
    p.raw_present = !runs.is_empty();
    let mut out = eeg_records(&runs);
    let bands = band_records(tb, m, cols, true);
    p.bands_from_file = !bands.is_empty();
    if !p.raw_present && bands.is_empty() {
        return Err(ImportError::Format("CSV has no RAW or band values".into()));
    }
    if !p.raw_present {
        p.warnings.push("no RAW columns — bands only".into());
    } else if bands.is_empty() {
        p.warnings.push("no band columns — bands computed from RAW".into());
    }
    out.extend(bands);
    imu(tb, p, dev, &mut out);
    ppg(tb, p, dev, &mut out);
    Ok(out)
}

/// RAW per electrode; the rate (256 or 220 Hz) is estimated from the span.
fn raw_runs(tb: &Table<'_>, m: &MontageMatch, cols: &[String], p: &mut Provenance) -> Vec<Run> {
    let mut runs = Vec::new();
    for (e, label) in m.labels.iter().enumerate() {
        let name = if is_aux(label) { cols[e].clone() } else { format!("RAW_{}", cols[e]) };
        let vals: Vec<(f64, f32)> = (0..tb.rows.len()).filter_map(|r| tb.get(r, &name).map(|v| (tb.t[r], v))).collect();
        let (Some(first), Some(last)) = (vals.first(), vals.last()) else { continue };
        if vals.len() < 2 {
            continue;
        }
        let span = last.0 - first.0;
        let rate = *p.original_rate_hz.get_or_insert_with(|| estimate_rate(vals.len(), span));
        let samples: Vec<f32> = vals.iter().map(|v| v.1).collect();
        let resample = rate != NATIVE_EEG_HZ;
        p.resampled |= resample;
        runs.push(Run {
            electrode: e,
            start: first.0,
            samples: if resample { nf_dsp::resample(&samples, rate, NATIVE_EEG_HZ) } else { samples },
        });
    }
    if p.resampled {
        p.warnings.push(format!("RAW resampled from {:.0} Hz to 256 Hz", p.original_rate_hz.unwrap_or(0.0)));
    }
    runs
}

fn estimate_rate(n: usize, span: f64) -> f64 {
    let est = if span > 0.0 { (n - 1) as f64 / span } else { NATIVE_EEG_HZ };
    if (est - 220.0).abs() < (est - NATIVE_EEG_HZ).abs() {
        220.0
    } else {
        NATIVE_EEG_HZ
    }
}

/// Rows whose values differ from the previous row (Mind Monitor repeats).
fn changes<const N: usize>(tb: &Table<'_>, names: [&str; N]) -> Vec<(f64, [f32; N])> {
    let mut out: Vec<(f64, [f32; N])> = Vec::new();
    for r in 0..tb.rows.len() {
        let mut v = [0.0; N];
        let mut any = false;
        for (k, n) in names.iter().enumerate() {
            if let Some(x) = tb.get(r, n) {
                v[k] = x;
                any = true;
            }
        }
        if any && out.last().is_none_or(|l| l.1 != v) {
            out.push((tb.t[r], v));
        }
    }
    out
}

fn rate_of<T>(v: &[(f64, T)]) -> Option<f64> {
    let span = v.last()?.0 - v.first()?.0;
    (v.len() > 1 && span > 0.0).then(|| (((v.len() - 1) as f64 / span) * 10.0).round() / 10.0)
}

fn imu(tb: &Table<'_>, p: &mut Provenance, dev: &mut nf_types::DeviceInfo, out: &mut Vec<Record>) {
    let acc = changes(tb, ["Accelerometer_X", "Accelerometer_Y", "Accelerometer_Z"]);
    let gyro = changes(tb, ["Gyro_X", "Gyro_Y", "Gyro_Z"]);
    dev.accel_rate_hz = rate_of(&acc);
    for (seq, (t, v)) in acc.into_iter().enumerate() {
        out.push(Record::Accelerometer { ts: t, seq: (seq & 0xffff) as u16, xyz: vec![v] });
    }
    for (seq, (t, v)) in gyro.into_iter().enumerate() {
        out.push(Record::Gyroscope { ts: t, seq: (seq & 0xffff) as u16, xyz: vec![v] });
    }
    if tb.has_prefix("Accelerometer_") && dev.accel_rate_hz.is_none() {
        p.warnings.push("Accelerometer columns present but all empty".into());
    }
}

fn ppg(tb: &Table<'_>, p: &mut Provenance, dev: &mut nf_types::DeviceInfo, out: &mut Vec<Record>) {
    let mut present = [None; 3];
    for (name, ch) in PPG_NAMES {
        if tb.col.contains_key(name) && present[ch].is_none() {
            present[ch] = Some(name);
        }
    }
    let n = present.iter().rposition(Option::is_some).map_or(0, |i| i + 1);
    if n == 0 {
        return;
    }
    let names: [&str; 3] = [present[0].unwrap_or("-"), present[1].unwrap_or("-"), present[2].unwrap_or("-")];
    let rows = changes(tb, names);
    if rows.is_empty() {
        p.warnings.push("PPG columns present but all empty".into());
        return;
    }
    dev.ppg_channels = PPG_LABELS[..n].iter().map(|s| (*s).to_owned()).collect();
    dev.ppg_rate_hz = rate_of(&rows);
    for (t, v) in rows {
        for (ch, x) in v.iter().enumerate().take(n) {
            out.push(Record::Ppg { ts: t, channel: i16::try_from(ch).unwrap_or(0), samples: vec![*x] });
        }
    }
}

fn elements(tb: &Table<'_>, p: &mut Provenance) {
    let Some(&i) = tb.col.get("Elements") else { return };
    let marks: Vec<(f64, String)> = tb.rows.iter().zip(&tb.t).filter_map(|(r, t)| r.get(i).map(|c| (*t, c.trim().to_owned()))).collect();
    let (n, w) = notes::map_elements(&marks);
    p.annotations.extend(n);
    p.warnings.extend(w);
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    const HEAD: &str = "TimeStamp,Delta_TP9,Delta_AF7,Delta_AF8,Delta_TP10,Theta_TP9,Theta_AF7,Theta_AF8,Theta_TP10,Alpha_TP9,Alpha_AF7,Alpha_AF8,Alpha_TP10,Beta_TP9,Beta_AF7,Beta_AF8,Beta_TP10,Gamma_TP9,Gamma_AF7,Gamma_AF8,Gamma_TP10,RAW_TP9,RAW_AF7,RAW_AF8,RAW_TP10,AUX_RIGHT,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,PPG_Ambient,PPG_IR,PPG_Red,Optics1,Elements";

    fn stamp(ms: u64) -> String {
        format!("2024-03-01 12:00:{:02}.{:03}", ms / 1000, ms % 1000)
    }

    fn constant_csv(rate: u64, secs: u64) -> String {
        let mut s = format!("{HEAD}\n");
        for i in 0..rate * secs {
            let ms = i * 1000 / rate;
            let band = (i / rate) as f32 * 0.1;
            let bands = vec![format!("{band}"); 20].join(",");
            let raw = (0..4).map(|k| format!("{:.2}", 800.0 + ((i + k) as f32 * 0.3).sin() * 20.0)).collect::<Vec<_>>().join(",");
            let acc = format!("{:.3},0,1", (i / 5) as f32 * 0.01);
            let el = if i == 10 {
                "Blink"
            } else if i == 300 {
                "/muse/elements/blink"
            } else {
                ""
            };
            s += &format!("{},{bands},{raw},1.0,{acc},5,{},7,0,{el}\n", stamp(ms), i / 4);
        }
        s
    }

    #[test]
    fn constant_220hz_imports_raw_bands_imu_ppg() {
        let text = constant_csv(220, 3);
        let i = crate::import(text.as_bytes(), Options { file_name: "mm.csv", utc_offset_minutes: 60 }).unwrap();
        assert_eq!(i.device.channels, vec!["TP9", "AF7", "AF8", "TP10", "AUX1"]);
        assert!(i.provenance.resampled && i.provenance.bands_from_file && !i.needs_bands);
        assert_eq!(i.provenance.original_rate_hz, Some(220.0));
        let eeg = i.eeg_samples() as f64 / 5.0;
        assert!((eeg - 3.0 * 256.0).abs() < 4.0, "{eeg}");
        let bands = i.records.iter().filter(|r| matches!(r, Record::Bands { electrode: 0, .. })).count();
        assert_eq!(bands, 3);
        assert_eq!(i.device.ppg_channels.len(), 3);
        assert!(i.device.accel_rate_hz.is_some_and(|r| (r - 44.0).abs() < 1.0));
        assert_eq!(i.provenance.annotations.len(), 1);
        assert_eq!(i.provenance.dropped_channels, vec!["Optics1"]);
        assert_eq!(i.started_unix_ms, Some(1_709_290_800_000.0));
    }

    #[test]
    fn interval_is_bands_only_with_coverage() {
        let mut s = format!("{HEAD}\n");
        for k in 0..10u64 {
            s += &format!("{},{},,,,,,,,,,,,,,,,,,,,,\n", stamp(k * 2000), vec!["1.0"; 20].join(","));
        }
        let i = crate::import(s.as_bytes(), Options { file_name: "mm.csv", utc_offset_minutes: 0 }).unwrap();
        assert!(!i.provenance.raw_present && i.provenance.bands_from_file);
        assert_eq!(i.provenance.recording_interval, Some(2.0));
        assert_eq!(i.provenance.interval_coverage, Some(0.5));
        assert!(crate::coverage_warning(&i.provenance).is_some());
        assert_eq!(i.eeg_samples(), 0);
    }

    #[test]
    fn interval_without_bands_is_refused() {
        let s = format!("TimeStamp,RAW_TP9,RAW_AF7,RAW_AF8,RAW_TP10\n{},1,2,3,4\n{},1,2,3,4\n", stamp(0), stamp(1000));
        let e = crate::import(s.as_bytes(), Options { file_name: "mm.csv", utc_offset_minutes: 0 });
        assert!(matches!(e, Err(ImportError::Refused(_))), "{e:?}");
    }
}
