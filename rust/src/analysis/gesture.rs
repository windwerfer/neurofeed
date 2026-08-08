//! Lightweight gesture detection (blink, jaw clench, eye up/down) computed
//! in Rust from the raw EEG stream. No external DSP crates.
//!
//! All thresholds are auto-adaptive (rolling EWMA baselines) so the detector
//! works across different pads, headband fits and users without calibration.
//! The Rust forwarder feeds it raw EEG packets as they arrive, feeds it the
//! per-electrode gamma band power once per second (from the FFT), and calls
//! `tick()` once per second to drain a [GestureReport].

use std::collections::HashMap;

/// Frontal electrodes (AF7, AF8) — blink potentials are strongest here.
const BLINK_ELECTRODES: [i32; 2] = [1, 2];
/// Posterior / temporal electrodes (TP9, TP10) — jaw clench EMG is strongest
/// here.
const CLENCH_ELECTRODES: [i32; 2] = [0, 3];
/// Bin length in samples (~125 ms at 256 Hz).
const BIN_LEN: usize = 32;
/// Blink energy must exceed this multiple of the rolling baseline.
const BLINK_MULT: f64 = 5.0;
/// Absolute floor for blink energy (rectified first-difference sum over a
/// 125 ms bin, in µV). Guards against counting micro-artifacts on clean pads.
const BLINK_MIN_ENERGY: f64 = 100.0;
/// EWMA learning rate for the blink energy baseline.
const BLINK_LEARN: f64 = 0.05;
/// Refractory period between counted blinks (in ~125 ms bins). ~500 ms.
const BLINK_REFRACTORY_BINS: usize = 4;
/// Clench gamma must exceed this multiple of its rolling baseline.
const CLENCH_MULT: f64 = 3.0;
/// EWMA learning rate for the clench gamma baseline (only adapted when quiet).
const CLENCH_LEARN: f64 = 0.05;
/// EWMA learning rate for the eye EOG baseline (only adapted when neutral).
const EYE_LEARN: f64 = 0.05;
/// EOG (frontal minus posterior mean) must exceed this multiple of its rolling
/// magnitude scale.
const EYE_MULT: f64 = 2.0;
/// Absolute floor for EOG deviation, in µV.
const EYE_MIN_UV: f64 = 20.0;

/// One second of gesture state drained from the detector.
#[derive(Debug, Clone, Copy, Default)]
pub struct GestureReport {
    /// Number of blinks detected in the drained second.
    pub blink_count: u32,
    /// True if jaw-clench muscle activity was present in the second.
    pub clench: bool,
    /// Vertical eye position: 0 = neutral, 1 = up, 2 = down. Experimental.
    pub eye: u8,
}

/// Rolling per-second detector. Call `feed_eeg` for every EEG packet,
/// `feed_gamma` for each electrode's gamma band power (once per second), and
/// `tick` once per second to get the aggregate report.
#[derive(Default)]
pub struct GestureDetector {
    /// Pending raw samples per electrode, grouped into fixed bins.
    pending: HashMap<i32, Vec<f64>>,
    /// Per-electrode sum of samples this second (for the eye EOG mean).
    eog_sums: HashMap<i32, f64>,
    /// Per-electrode sample count this second.
    eog_counts: HashMap<i32, usize>,
    /// Per-electrode EWMA of the rectified-difference bin energy.
    blink_baseline: HashMap<i32, f64>,
    /// True while a blink bin is currently above threshold (global across the
    /// two frontal pads so a single blink isn't double-counted).
    blink_active: bool,
    /// Remaining quiet bins before the next blink is counted.
    blink_cooldown: usize,
    /// Latest gamma band power per electrode (fed once per second from FFT).
    gamma: HashMap<i32, f64>,
    /// EWMA of posterior gamma power (adapted only when quiet).
    clench_baseline: f64,
    /// EWMA of the EOG magnitude scale (adapted only when neutral).
    eog_scale: f64,
    /// EWMA of the frontal-minus-posterior EOG mean.
    eog_baseline: f64,
    /// Counted blinks in the current second.
    blinks_this_second: u32,
    /// Clench flag for the current second.
    clench_active: bool,
    /// Eye state for the current second.
    eye_state: u8,
}

impl GestureDetector {
    /// Feed raw EEG samples for one electrode as they arrive.
    pub fn feed_eeg(&mut self, electrode: i32, samples: &[f64]) {
        for s in samples {
            *self.eog_counts.entry(electrode).or_default() += 1;
            *self.eog_sums.entry(electrode).or_default() += *s;
        }
        let bins = {
            let pending = self.pending.entry(electrode).or_default();
            pending.extend_from_slice(samples);
            let whole = pending.len() - (pending.len() % BIN_LEN);
            pending.drain(..whole).collect::<Vec<f64>>()
        };
        for bin in bins.chunks_exact(BIN_LEN) {
            self.process_bin(electrode, bin);
        }
    }

    /// Feed one electrode's gamma band power, computed from the per-second
    /// FFT. Called once per electrode per second.
    pub fn feed_gamma(&mut self, electrode: i32, gamma: f64) {
        self.gamma.insert(electrode, gamma);
    }

    /// Process a completed ~125 ms bin. Only frontal pads contribute to blink
    /// detection; every electrode contributes to the eye EOG sums.
    fn process_bin(&mut self, electrode: i32, bin: &[f64]) {
        let mut energy = 0.0;
        for w in bin.windows(2) {
            energy += (w[1] - w[0]).abs();
        }
        if BLINK_ELECTRODES.contains(&electrode) {
            let baseline = *self.blink_baseline.get(&electrode).unwrap_or(&energy);
            let threshold = (baseline * BLINK_MULT).max(BLINK_MIN_ENERGY);
            let rising = energy > threshold;
            if rising && !self.blink_active && self.blink_cooldown == 0 {
                self.blinks_this_second += 1;
                self.blink_cooldown = BLINK_REFRACTORY_BINS;
            }
            self.blink_active = rising;
            if self.blink_cooldown > 0 {
                self.blink_cooldown -= 1;
            }
            let updated = baseline * (1.0 - BLINK_LEARN) + energy * BLINK_LEARN;
            self.blink_baseline.insert(electrode, updated);
        }
    }

    /// Drain the current second into a report and reset per-second counters.
    pub fn tick(&mut self, _now_ms: f64) -> GestureReport {
        self.update_clench();
        self.update_eye();
        let report = GestureReport {
            blink_count: self.blinks_this_second,
            clench: self.clench_active,
            eye: self.eye_state,
        };
        self.blinks_this_second = 0;
        self.clench_active = false;
        self.eye_state = 0;
        self.eog_sums.clear();
        self.eog_counts.clear();
        report
    }

    /// Jaw clench: posterior gamma power bursts above its rolling baseline.
    fn update_clench(&mut self) {
        let mut present = 0usize;
        let mut total = 0.0;
        for e in CLENCH_ELECTRODES {
            if let Some(g) = self.gamma.get(&e) {
                present += 1;
                total += *g;
            }
        }
        if present == 0 {
            return;
        }
        let g = total / present as f64;
        if self.clench_baseline <= 0.0 {
            self.clench_baseline = g;
        }
        let active = g > self.clench_baseline * CLENCH_MULT;
        self.clench_active = active;
        if !active {
            self.clench_baseline =
                self.clench_baseline * (1.0 - CLENCH_LEARN) + g * CLENCH_LEARN;
        }
    }

    /// Vertical eye position (experimental): frontal minus posterior mean, with
    /// polarity interpreted as up (positive) / down (negative).
    fn update_eye(&mut self) {
        let frontal = mean_of(&self.eog_sums, &self.eog_counts, &BLINK_ELECTRODES);
        let posterior = mean_of(&self.eog_sums, &self.eog_counts, &CLENCH_ELECTRODES);
        let (Some(f), Some(p)) = (frontal, posterior) else {
            return;
        };
        let eog = f - p;
        if self.eog_scale <= 0.0 {
            self.eog_scale = eog.abs();
            self.eog_baseline = eog;
        }
        let dev = eog - self.eog_baseline;
        let threshold = (self.eog_scale * EYE_MULT).max(EYE_MIN_UV);
        if dev > threshold {
            self.eye_state = 1;
        } else if dev < -threshold {
            self.eye_state = 2;
        }
        // Adapt the baselines only while neutral so a held gaze doesn't
        // become the new "neutral".
        if dev.abs() <= threshold {
            self.eog_scale =
                self.eog_scale * (1.0 - EYE_LEARN) + eog.abs() * EYE_LEARN;
            self.eog_baseline =
                self.eog_baseline * (1.0 - EYE_LEARN) + eog * EYE_LEARN;
        }
    }
}

fn mean_of(
    sums: &HashMap<i32, f64>,
    counts: &HashMap<i32, usize>,
    electrodes: &[i32],
) -> Option<f64> {
    let mut total = 0.0;
    let mut n = 0usize;
    for e in electrodes {
        if let (Some(s), Some(c)) = (sums.get(e), counts.get(e)) {
            if *c > 0 {
                total += s / *c as f64;
                n += 1;
            }
        }
    }
    if n == 0 {
        return None;
    }
    Some(total / n as f64)
}
