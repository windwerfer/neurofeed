//! Artifact detectors: head movement (accelerometer) and blink / jaw clench
//! (EEG). Ported from the legacy `rust/src/analysis/gesture.rs` and
//! `compute_movement` (muse.rs); thresholds are the legacy values.

use std::collections::VecDeque;

/// Movement score (std of |accel| over the last 2 s, in g) above which the
/// second counts as movement (Dart `movementGateThreshold`).
pub const MOVEMENT_GATE: f64 = 0.05;
/// Window for the movement score, seconds.
pub const MOVEMENT_WINDOW_S: f64 = 2.0;
/// Bin length in samples (~125 ms at 256 Hz).
pub const BLINK_BIN_LEN: usize = 32;
/// Blink energy must exceed this multiple of the rolling baseline.
pub const BLINK_MULT: f64 = 5.0;
/// Absolute floor for blink bin energy (rectified first-difference sum, µV).
pub const BLINK_MIN_ENERGY: f64 = 100.0;
const BLINK_LEARN: f64 = 0.05;
/// Refractory period between counted blinks (bins, ~500 ms).
const BLINK_REFRACTORY_BINS: usize = 4;
/// Clench gamma must exceed this multiple of its rolling baseline.
pub const CLENCH_MULT: f64 = 3.0;
const CLENCH_LEARN: f64 = 0.05;

/// Std of the accelerometer magnitude over the last [`MOVEMENT_WINDOW_S`].
#[derive(Debug, Clone)]
pub struct MovementDetector {
    rate_hz: f64,
    mags: VecDeque<f64>,
}

impl MovementDetector {
    pub fn new(rate_hz: f64) -> Self {
        Self { rate_hz, mags: VecDeque::new() }
    }

    pub fn push(&mut self, samples: &[[f32; 3]]) {
        let cap = (MOVEMENT_WINDOW_S * self.rate_hz).round().max(1.0) as usize;
        for s in samples {
            let (x, y, z) = (f64::from(s[0]), f64::from(s[1]), f64::from(s[2]));
            self.mags.push_back((x * x + y * y + z * z).sqrt());
        }
        while self.mags.len() > cap {
            self.mags.pop_front();
        }
    }

    /// Legacy score: 0 with fewer than 10 samples.
    pub fn score(&self) -> f64 {
        if self.mags.len() < 10 {
            return 0.0;
        }
        let n = self.mags.len() as f64;
        let mean = self.mags.iter().sum::<f64>() / n;
        (self.mags.iter().map(|m| (m - mean).powi(2)).sum::<f64>() / n).sqrt()
    }

    pub fn moving(&self) -> bool {
        self.score() > MOVEMENT_GATE
    }
}

/// One second of gesture state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct GestureReport {
    pub blink_count: u32,
    pub clench: bool,
    /// Vertical eye position (experimental): 0 neutral, 1 up, 2 down.
    pub eye: u8,
}

/// EWMA rate of the eye EOG baseline (adapted only while neutral).
const EYE_LEARN: f64 = 0.05;
/// EOG deviation must exceed this multiple of its rolling magnitude scale.
const EYE_MULT: f64 = 2.0;
/// Absolute floor for the EOG deviation (µV).
const EYE_MIN_UV: f64 = 20.0;

/// Legacy eye up/down estimate: per-second mean of the raw frontal pads minus
/// the temporal pads, against an adaptive baseline (legacy gesture.rs).
#[derive(Debug, Clone, Default)]
struct Eye {
    sums: Vec<(f64, usize)>,
    scale: f64,
    baseline: f64,
}

impl Eye {
    fn mean(&self, pads: &[usize]) -> Option<f64> {
        let m: Vec<f64> = pads.iter().filter_map(|e| self.sums.get(*e).filter(|s| s.1 > 0).map(|s| s.0 / s.1 as f64)).collect();
        (!m.is_empty()).then(|| m.iter().sum::<f64>() / m.len() as f64)
    }

    fn tick(&mut self, frontal: &[usize], temporal: &[usize]) -> u8 {
        let state = match (self.mean(frontal), self.mean(temporal)) {
            (Some(f), Some(p)) => self.update(f - p),
            _ => 0,
        };
        self.sums.iter_mut().for_each(|s| *s = (0.0, 0));
        state
    }

    fn update(&mut self, eog: f64) -> u8 {
        if self.scale <= 0.0 {
            self.scale = eog.abs();
            self.baseline = eog;
        }
        let dev = eog - self.baseline;
        let thr = (self.scale * EYE_MULT).max(EYE_MIN_UV);
        if dev.abs() <= thr {
            self.scale = self.scale * (1.0 - EYE_LEARN) + eog.abs() * EYE_LEARN;
            self.baseline = self.baseline * (1.0 - EYE_LEARN) + eog * EYE_LEARN;
            0
        } else if dev > 0.0 {
            1
        } else {
            2
        }
    }
}

/// Blink (frontal first-difference energy bursts) and jaw clench (temporal
/// gamma bursts), both against adaptive EWMA baselines.
#[derive(Debug, Clone)]
pub struct GestureDetector {
    frontal: Vec<usize>,
    temporal: Vec<usize>,
    pending: Vec<Vec<f64>>,
    blink_baseline: Vec<Option<f64>>,
    blink_active: bool,
    blink_cooldown: usize,
    gamma: Vec<Option<f64>>,
    clench_baseline: f64,
    blinks: u32,
    eye: Eye,
}

impl GestureDetector {
    /// `channels` = electrode count; `frontal` / `temporal` are indices.
    pub fn new(channels: usize, frontal: Vec<usize>, temporal: Vec<usize>) -> Self {
        Self {
            frontal,
            temporal,
            pending: vec![Vec::new(); channels],
            blink_baseline: vec![None; channels],
            blink_active: false,
            blink_cooldown: 0,
            gamma: vec![None; channels],
            clench_baseline: 0.0,
            blinks: 0,
            eye: Eye { sums: vec![(0.0, 0); channels], ..Eye::default() },
        }
    }

    /// Feed one electrode's samples (µV) as they arrive.
    pub fn feed_eeg(&mut self, electrode: usize, samples: &[f32]) {
        if let Some(s) = self.eye.sums.get_mut(electrode) {
            s.0 += samples.iter().map(|x| f64::from(*x)).sum::<f64>();
            s.1 += samples.len();
        }
        if !self.frontal.contains(&electrode) {
            return;
        }
        let Some(p) = self.pending.get_mut(electrode) else { return };
        p.extend(samples.iter().map(|s| f64::from(*s)));
        let whole = p.len() - p.len() % BLINK_BIN_LEN;
        let bins: Vec<f64> = p.drain(..whole).collect();
        for bin in bins.as_chunks::<BLINK_BIN_LEN>().0 {
            self.process_bin(electrode, bin);
        }
    }

    fn process_bin(&mut self, electrode: usize, bin: &[f64]) {
        let energy: f64 = bin.windows(2).map(|w| (w[1] - w[0]).abs()).sum();
        let baseline = self.blink_baseline[electrode].unwrap_or(energy);
        let rising = energy > (baseline * BLINK_MULT).max(BLINK_MIN_ENERGY);
        if rising && !self.blink_active && self.blink_cooldown == 0 {
            self.blinks += 1;
            self.blink_cooldown = BLINK_REFRACTORY_BINS;
        }
        self.blink_active = rising;
        self.blink_cooldown = self.blink_cooldown.saturating_sub(1);
        // Deviation from legacy (decisions 2026-10-30): like clench, learn only
        // from quiet bins, so regular blinks do not raise their own threshold.
        if !rising {
            self.blink_baseline[electrode] = Some(baseline * (1.0 - BLINK_LEARN) + energy * BLINK_LEARN);
        }
    }

    /// Per-second gamma band power of one electrode.
    pub fn feed_gamma(&mut self, electrode: usize, gamma: f64) {
        if let Some(g) = self.gamma.get_mut(electrode) {
            *g = Some(gamma);
        }
    }

    /// Drain the current second.
    pub fn tick(&mut self) -> GestureReport {
        let gs: Vec<f64> = self.temporal.iter().filter_map(|e| self.gamma.get(*e).copied().flatten()).collect();
        let mut clench = false;
        if !gs.is_empty() {
            let g = gs.iter().sum::<f64>() / gs.len() as f64;
            if self.clench_baseline <= 0.0 {
                self.clench_baseline = g;
            }
            clench = g > self.clench_baseline * CLENCH_MULT;
            if !clench {
                self.clench_baseline = self.clench_baseline * (1.0 - CLENCH_LEARN) + g * CLENCH_LEARN;
            }
        }
        let eye = self.eye.tick(&self.frontal, &self.temporal);
        let r = GestureReport { blink_count: self.blinks, clench, eye };
        self.blinks = 0;
        r
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn eye_up_and_down_follow_the_frontal_minus_temporal_level() {
        let mut g = GestureDetector::new(4, vec![1, 2], vec![0, 3]);
        let second = |g: &mut GestureDetector, front: f32| {
            for e in 0..4 {
                let v = if e == 1 || e == 2 { front } else { 0.0 };
                g.feed_eeg(e, &[v; 256]);
            }
            g.tick().eye
        };
        for _ in 0..5 {
            assert_eq!(second(&mut g, 2.0), 0);
        }
        assert_eq!(second(&mut g, 80.0), 1);
        assert_eq!(second(&mut g, -80.0), 2);
        assert_eq!(second(&mut g, 2.0), 0);
    }

    #[test]
    fn still_head_is_not_movement_and_shaking_is() {
        let mut m = MovementDetector::new(52.0);
        m.push(&[[0.0, 0.0, 1.0]; 104]);
        assert!(m.score() < 1e-9 && !m.moving());
        let shake: Vec<[f32; 3]> = (0..104).map(|i| [0.0, 0.0, 1.0 + 0.3 * (i as f32 * 0.25).sin()]).collect();
        m.push(&shake);
        assert!(m.moving(), "score {}", m.score());
    }

    #[test]
    fn blink_bump_counts_once_and_clench_gamma_burst_flags() {
        let mut g = GestureDetector::new(4, vec![1, 2], vec![0, 3]);
        let quiet: Vec<f32> = (0..256).map(|i| 3.0 * (i as f32 * 0.4).sin()).collect();
        for _ in 0..4 {
            g.feed_eeg(1, &quiet);
            g.feed_gamma(0, 1.0);
            assert_eq!(g.tick(), GestureReport::default());
        }
        let blink: Vec<f32> = (0..256)
            .map(|i| quiet[i] + if (100..140).contains(&i) { 150.0 * ((i - 100) as f32 / 40.0 * std::f32::consts::PI).sin() } else { 0.0 })
            .collect();
        g.feed_eeg(1, &blink);
        g.feed_gamma(0, 5.0);
        assert_eq!(g.tick(), GestureReport { blink_count: 1, clench: true, eye: 0 });
        // Repeated blinks keep counting (baseline learns from quiet bins only).
        for _ in 0..20 {
            g.feed_eeg(1, &blink);
            assert_eq!(g.tick().blink_count, 1);
        }
    }
}
