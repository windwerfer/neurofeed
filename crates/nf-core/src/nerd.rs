//! Nerd sheet model: the numbers behind the reward (and guard) decision,
//! each with a plain-language explanation, plus calibration-pile histograms.
//! Built from the live trainer; `feedback.nerd` returns it as JSON.

use crate::feedback::Trainer;
use serde::Serialize;

pub const BINS: usize = 24;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Histogram {
    pub min: f64,
    pub max: f64,
    pub counts: Vec<u32>,
}

impl Histogram {
    /// `BINS` bins over the samples plus `extras` (so markers stay inside).
    pub fn of(samples: &[f64], extras: &[Option<f64>]) -> Self {
        let vals: Vec<f64> = samples.iter().copied().chain(extras.iter().flatten().copied()).filter(|v| v.is_finite()).collect();
        let (mut lo, mut hi) = vals.iter().fold((f64::MAX, f64::MIN), |(l, h), v| (l.min(*v), h.max(*v)));
        if vals.is_empty() {
            (lo, hi) = (0.0, 1.0);
        } else if (hi - lo).abs() < 1e-12 {
            let pad = if lo.abs() < 1e-9 { 0.1 } else { lo.abs() * 0.1 };
            (lo, hi) = (lo - pad, hi + pad);
        } else {
            let span = hi - lo;
            (lo, hi) = (lo - span * 0.05, hi + span * 0.05);
        }
        let mut counts = vec![0; BINS];
        for v in samples.iter().filter(|v| v.is_finite()) {
            let i = (((v - lo) / (hi - lo)) * BINS as f64).floor().clamp(0.0, (BINS - 1) as f64) as usize;
            counts[i] += 1;
        }
        Self { min: lo, max: hi, counts }
    }
}

/// One calibration pile with its markers.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Pile {
    pub title: String,
    pub hist: Histogram,
    pub threshold: Option<f64>,
    pub live: Option<f64>,
    pub mean: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Row {
    pub label: String,
    pub value: String,
    pub info: &'static str,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Section {
    pub pile: Pile,
    pub rows: Vec<Row>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Nerd {
    /// False until calibration produced an engine.
    pub ready: bool,
    pub reward: Option<Section>,
    pub guard: Option<Section>,
}

fn fixed(v: Option<f64>, d: usize) -> String {
    v.filter(|v| v.is_finite()).map_or_else(|| "–".into(), |v| format!("{v:.d$}"))
}

fn row(label: impl Into<String>, value: String, info: &'static str) -> Row {
    Row { label: label.into(), value, info }
}

fn feature_name(t: &Trainer) -> String {
    serde_json::to_value(t.engine_config().feature).ok().and_then(|v| v.as_str().map(str::to_owned)).unwrap_or_else(|| "feature".into())
}

pub fn build(t: &Trainer, now: f64) -> Nerd {
    let Some(e) = t.engine() else { return Nerd::default() };
    let rec = t.last().and_then(|r| r.record.as_ref());
    let live = rec.and_then(|r| r.native);
    let b = e.baseline();
    let stability = e.config().stability.is_some();
    let samples = if stability { e.raw_baseline() } else { b.samples() };
    let thr = e.threshold();
    let feat = feature_name(t);
    let markers = if stability { vec![] } else { vec![thr, live] };
    let pile = Pile {
        title: format!("Reward pile ({feat})"),
        hist: Histogram::of(samples, &markers),
        threshold: (!stability).then_some(thr).flatten(),
        live: (!stability).then_some(live).flatten(),
        mean: b.mean(),
    };
    let rows = vec![
        row(format!("Live {feat}"), fixed(live, 3), "Feature this second. The sound compares it to the threshold."),
        row("p of pile", fixed(rec.and_then(|r| r.pct), 0), "Rank of the live value in the calibration pile (the plot's y, 0–100)."),
        row(
            "Threshold",
            format!("{}  from p{}", fixed(thr, 3), e.config().percentile),
            "Which pick of the pile must be beaten. It adapts slowly to keep the success rate in range.",
        ),
        row("Mean", fixed(b.mean(), 3), "Centre of the pile. Adapting never moves the line above mean + 1.5 sd."),
        row("Spread (sd)", fixed(b.sd(), 3), "How varied calibration was. A wide pile lets the line travel farther."),
        row("Samples n", samples.len().to_string(), "Clean calibration seconds. A small pile makes a shaky line."),
        row(
            "Success rate",
            fixed(e.success_rate(now).map(|r| r * 100.0), 0) + " %",
            "Share of the last 75 s in zone, noisy seconds excluded. Shown once 75 s have passed.",
        ),
    ];
    let guard = e.config().guard.map(|g| {
        let gb = e.guard_baseline();
        let gthr = e.guard_threshold();
        Section {
            pile: Pile {
                title: "Guard pile (band.delta, eyes closed)".into(),
                hist: Histogram::of(gb.samples(), &[gthr]),
                threshold: gthr,
                live: None,
                mean: gb.mean(),
            },
            rows: vec![
                row(
                    "Warn threshold",
                    format!("{}  from p{}", fixed(gthr, 3), g.percentile),
                    "Delta above this pick of the rest pile counts as drowsy.",
                ),
                row("Mean", fixed(gb.mean(), 3), "Centre of the eyes-closed rest pile."),
                row("Spread (sd)", fixed(gb.sd(), 3), "How varied rest calibration was."),
                row("Samples n", gb.len().to_string(), "Clean rest seconds. A small pile makes a shaky warn line."),
                row("Warning", if e.warning() { "on" } else { "off" }.into(), "Whether the drowsiness warning is active now."),
                row("Chime cooldown", format!("{:.0} s", e.chime_cooldown(now)), "At least 20 s between warning bowls."),
            ],
        }
    });
    Nerd { ready: true, reward: Some(Section { pile, rows }), guard }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn histogram_keeps_markers_inside_and_counts_everything() {
        let h = Histogram::of(&[1.0, 2.0, 3.0, 4.0], &[Some(10.0)]);
        assert!(h.min < 1.0 && h.max > 10.0);
        assert_eq!(h.counts.iter().sum::<u32>(), 4);
        let flat = Histogram::of(&[2.0, 2.0], &[]);
        assert!(flat.max > flat.min);
        assert_eq!(Histogram::of(&[], &[]).counts.len(), BINS);
    }

    #[test]
    fn not_ready_before_calibration() {
        assert!(!build(&Trainer::default(), 0.0).ready);
    }
}
