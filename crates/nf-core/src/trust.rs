//! Trust model: what each feedback second really was (clean or why dirty,
//! percentile vs threshold, held back and why, guard warning) and the
//! session totals the trust pane shows. Built live from the engine results
//! or from a stored session (`Feedback` + `Trust` records), the same way.
//! Port of the legacy `session_trust.dart`; percents cover clean training
//! seconds only (calibration and pauses excluded).

use crate::feedback::{Phase, SecondResult};
use nf_feedback::{Dirty, HeldBack};
use nf_format::{feedback_flags as ff, trust_bits as tb, Record};
use serde::{Deserialize, Serialize};

/// One second of the trust trace.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Row {
    pub t: f64,
    pub calibrating: bool,
    pub paused: bool,
    pub value: Option<f64>,
    pub threshold: Option<f64>,
    /// Native feature (stability: fluctuation ratio).
    pub native: Option<f64>,
    /// Output percentile 0–100.
    pub pct: Option<f64>,
    pub thr_pct: Option<f64>,
    pub in_target: bool,
    pub counted: bool,
    /// No artifact and a verdict was produced.
    pub clean: bool,
    /// movement | blink | jaw | pads | no_signal | unknown (sessions without
    /// trust records).
    pub dirty: Option<&'static str>,
    /// beta | delta | guard | no_threshold.
    pub held_back: Vec<&'static str>,
    /// Guard lane: `None` when the protocol ran no guard.
    pub warn: Option<bool>,
    pub guard_chime: bool,
    pub muted: bool,
    pub reward_chime: bool,
    /// Percentile to draw: dirty seconds hold the last clean value.
    pub plot_pct: Option<f64>,
    /// Guard value on the decision scale (0–100), see [`guard_record`].
    pub guard_plot: Option<f64>,
    /// Guard warn line on that scale; [`LEGACY_WARN_LINE`] for sessions
    /// stored before it was saved.
    pub guard_line: Option<f64>,
}

/// Warn line for guarded seconds without a stored one (legacy 75th percentile).
pub const LEGACY_WARN_LINE: f64 = 75.0;

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Totals {
    pub training_s: u32,
    pub clean_s: u32,
    /// % of clean training seconds in target / held back.
    pub pct_in_zone: Option<f64>,
    pub pct_held_back: Option<f64>,
    /// % of clean guarded seconds with the warning on.
    pub pct_warning: Option<f64>,
    pub dirty_s: Vec<(&'static str, u32)>,
    pub reward_chimes: u32,
    pub guard_chimes: u32,
}

/// A gesture mark: double_blink | double_jaw_clench | eye_up | eye_down
/// (live detector or import annotations).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Mark {
    pub t: f64,
    pub kind: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Trust {
    pub rows: Vec<Row>,
    pub totals: Totals,
    pub marks: Vec<Mark>,
}

const DIRTY: [(u16, &str); 5] = [
    (tb::DIRTY_MOVEMENT, "movement"),
    (tb::DIRTY_BLINK, "blink"),
    (tb::DIRTY_JAW, "jaw"),
    (tb::DIRTY_PADS, "pads"),
    (tb::DIRTY_NO_SIGNAL, "no_signal"),
];
const HELD: [(u16, &str); 4] =
    [(tb::HELD_BETA, "beta"), (tb::HELD_DELTA, "delta"), (tb::HELD_GUARD, "guard"), (tb::HELD_NO_THRESHOLD, "no_threshold")];

fn dirty_code(d: Dirty) -> u16 {
    match d {
        Dirty::Movement => tb::DIRTY_MOVEMENT,
        Dirty::Blink => tb::DIRTY_BLINK,
        Dirty::Jaw => tb::DIRTY_JAW,
        Dirty::Pads => tb::DIRTY_PADS,
    }
}

fn held_bit(h: HeldBack) -> u16 {
    match h {
        HeldBack::Beta => tb::HELD_BETA,
        HeldBack::Delta => tb::HELD_DELTA,
        HeldBack::Guard => tb::HELD_GUARD,
        HeldBack::NoThreshold => tb::HELD_NO_THRESHOLD,
    }
}

fn nan(v: Option<f64>) -> f32 {
    v.map_or(f32::NAN, |x| x as f32)
}

fn opt(v: f32) -> Option<f64> {
    v.is_finite().then_some(f64::from(v))
}

/// The `Trust` record the recorder stores after each `Feedback` record.
pub fn record(r: &SecondResult) -> Record {
    let Some(x) = r.record.as_ref() else {
        let bits = if r.phase == Phase::Calibrating { 0 } else { tb::DIRTY_NO_SIGNAL };
        return Record::Trust { ts: r.time, native: f32::NAN, pct: f32::NAN, thr_pct: f32::NAN, bits };
    };
    let mut bits = x.dirty.map_or(if x.produced { 0 } else { tb::DIRTY_NO_SIGNAL }, dirty_code);
    bits |= x.held_back.iter().flatten().fold(0, |b, h| b | held_bit(*h));
    for (on, bit) in [
        (x.warn == Some(true), tb::WARN),
        (x.warn.is_some(), tb::HAS_GUARD),
        (x.chime == Some(true), tb::GUARD_CHIME),
        (x.muted == Some(true), tb::MUTED),
        (x.produced, tb::PRODUCED),
    ] {
        if on {
            bits |= bit;
        }
    }
    Record::Trust { ts: r.time, native: nan(x.native), pct: nan(x.pct), thr_pct: nan(x.thr_pct), bits }
}

/// The `Guard` record stored after `Trust` when the protocol ran a guard.
pub fn guard_record(r: &SecondResult) -> Option<Record> {
    let x = r.record.as_ref().filter(|x| x.warn.is_some())?;
    Some(Record::Guard { ts: r.time, value: nan(x.guard_plot), line: nan(x.guard_line) })
}

/// Row from the stored pair (`trust` absent in sessions before trust records).
fn stored_row(t: f64, value: f32, threshold: f32, flags: u16, trust: Option<(f32, f32, f32, u16)>) -> Row {
    let on = |b: u16| flags & b != 0;
    let mut row = Row {
        t,
        calibrating: on(ff::CALIBRATING),
        paused: on(ff::PAUSED),
        value: opt(value),
        threshold: opt(threshold),
        in_target: on(ff::IN_TARGET),
        counted: on(ff::COUNTED),
        reward_chime: on(ff::CHIME),
        ..Row::default()
    };
    let Some((native, pct, thr_pct, bits)) = trust else {
        row.dirty = on(ff::DIRTY).then_some("unknown");
        row.clean = !on(ff::DIRTY) && row.value.is_some();
        row.held_back = if on(ff::HELD_BACK) { vec!["unknown"] } else { Vec::new() };
        return row;
    };
    let has = |b: u16| bits & b != 0;
    row.native = opt(native);
    row.pct = opt(pct);
    row.thr_pct = opt(thr_pct);
    row.dirty = DIRTY.iter().find(|(c, _)| bits & tb::DIRTY_MASK == *c).map(|(_, n)| *n);
    row.clean = row.dirty.is_none() && has(tb::PRODUCED);
    row.held_back = HELD.iter().filter(|(b, _)| has(*b)).map(|(_, n)| *n).collect();
    row.warn = has(tb::HAS_GUARD).then_some(has(tb::WARN));
    row.guard_chime = has(tb::GUARD_CHIME);
    row.muted = has(tb::MUTED);
    row
}

/// Rows from a stored body (other records are ignored).
pub fn rows_from_records(records: &[Record]) -> Vec<Row> {
    let mut rows = Vec::new();
    let mut it = records.iter().peekable();
    while let Some(r) = it.next() {
        let Record::Feedback { ts, value, threshold, flags } = r else { continue };
        let trust = match it.peek() {
            Some(Record::Trust { ts: t2, native, pct, thr_pct, bits }) if t2 == ts => Some((*native, *pct, *thr_pct, *bits)),
            _ => None,
        };
        if trust.is_some() {
            it.next();
        }
        let mut row = stored_row(*ts, *value, *threshold, *flags, trust);
        if let Some(Record::Guard { ts: t3, value, line }) = it.peek().filter(|_| trust.is_some()) {
            if t3 == ts {
                row.guard_plot = opt(*value);
                row.guard_line = opt(*line);
                it.next();
            }
        }
        if row.warn.is_some() && row.guard_line.is_none() {
            row.guard_line = Some(LEGACY_WARN_LINE);
        }
        rows.push(row);
    }
    rows
}

/// Rows from live engine results (same encoding path as storage).
pub fn rows_from_results(results: &[SecondResult]) -> Vec<Row> {
    let mut recs = Vec::with_capacity(results.len() * 2);
    for r in results {
        recs.push(crate::recording::feedback_record(r));
        recs.push(record(r));
        recs.extend(guard_record(r));
    }
    rows_from_records(&recs)
}

fn percent(part: u32, whole: u32) -> Option<f64> {
    (whole > 0).then(|| f64::from(part) * 100.0 / f64::from(whole))
}

/// Hold-last-clean plot values and the session totals.
pub fn build(mut rows: Vec<Row>, marks: Vec<Mark>) -> Trust {
    let mut t = Totals::default();
    let (mut zone, mut held, mut guarded, mut warned) = (0, 0, 0, 0);
    let mut last_clean = None;
    for r in &mut rows {
        if r.clean && r.pct.is_some() {
            last_clean = r.pct;
        }
        r.plot_pct = if r.clean { r.pct } else { last_clean.or(r.pct) };
        t.reward_chimes += u32::from(r.reward_chime);
        t.guard_chimes += u32::from(r.guard_chime);
        if r.calibrating || r.paused {
            continue;
        }
        t.training_s += 1;
        if let Some(d) = r.dirty {
            match t.dirty_s.iter_mut().find(|(n, _)| *n == d) {
                Some((_, c)) => *c += 1,
                None => t.dirty_s.push((d, 1)),
            }
        }
        if !r.clean {
            continue;
        }
        t.clean_s += 1;
        zone += u32::from(r.in_target);
        held += u32::from(!r.held_back.is_empty());
        if let Some(w) = r.warn {
            guarded += 1;
            warned += u32::from(w);
        }
    }
    t.pct_in_zone = percent(zone, t.clean_s);
    t.pct_held_back = percent(held, t.clean_s);
    t.pct_warning = percent(warned, guarded);
    Trust { rows, totals: t, marks }
}

/// Gesture marks from stored import annotations (`SessionMeta.import`).
pub fn marks(import: Option<&serde_json::Value>) -> Vec<Mark> {
    let Some(list) = import.and_then(|v| v["annotations"].as_array()) else { return Vec::new() };
    list.iter()
        .filter(|a| a["duration"].as_f64() == Some(0.0))
        .filter_map(|a| {
            let kind = a["type"].as_str().filter(|k| matches!(*k, "double_blink" | "double_jaw_clench"))?;
            Some(Mark { t: a["onset"].as_f64()?, kind: kind.to_owned() })
        })
        .collect()
}

/// Live gesture marks saved with a feedback session (`context.marks`).
pub fn live_marks(context: Option<&serde_json::Value>) -> Vec<Mark> {
    context.and_then(|c| serde_json::from_value(c["marks"].clone()).ok()).unwrap_or_default()
}

/// Mean-pool `v` into at most `n` buckets scaled to 0..=1 by the max.
pub fn downsample(v: &[f32], n: usize) -> Vec<f32> {
    if v.is_empty() || n == 0 {
        return Vec::new();
    }
    let k = v.len().div_ceil(n);
    let pooled: Vec<f32> = v.chunks(k).map(|c| c.iter().sum::<f32>() / c.len() as f32).collect();
    let max = pooled.iter().copied().fold(f32::MIN, f32::max);
    pooled.iter().map(|x| if max > 0.0 { (x / max).clamp(0.0, 1.0) } else { 0.0 }).collect()
}
