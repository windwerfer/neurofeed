//! EEG conditioning for every live device (Muse Classic / Athena, Crown):
//! the unfiltered RAW (DC offset, slow drift, mains hum) → the signal pad
//! quality, line-noise ratio, bands, features and the EEG charts use. RAW is
//! recorded as received.
//!
//! Per channel, streaming, 256 Hz:
//! - 2nd-order Butterworth high-pass at [HIGHPASS_HZ] (RBJ biquad, Q = 1/√2).
//! - Notch biquads (Q = [NOTCH_Q]) at the mains frequency and its 2nd
//!   harmonic. Until mains is detected both 50/100 Hz and 60/120 Hz are
//!   notched; afterwards only the detected pair.
//!
//! Start-up: the first [WARMUP_SAMPLES] (0.5 s) of a segment are held. The
//! high-pass is seeded at their mean (steady state for the DC offset), then
//! the chain is primed on the block repeated [PRIME_PASSES] times: 128
//! samples are whole cycles of 50, 60, 100 and 120 Hz, so the repeated block
//! is continuous for mains and the notches start in steady state. The held
//! block is then emitted conditioned. What is left is EEG-scale (drift and
//! non-periodic EEG across the repeat seam) and fades with the high-pass
//! within about a second. A new segment starts on the first packet and after
//! any timestamp gap over [GAP_MS]. Shorter gaps of 1..=[FILL_MAX_SAMPLES]
//! whole samples (lost Crown OSC samples, a lost Muse packet) are filled by
//! linear interpolation in the conditioned path only; RAW keeps the gap.
//!
//! Mains detection ([MainsDetector]): every 256 unfiltered samples per
//! channel vote 50 Hz, 60 Hz or none. A frequency gets the vote when its
//! mains bins (±1 bin, as in the band FFT's line-noise ratio) average at
//! least [PEAK_RATIO]× the median of the neighbouring non-mains bins
//! (±8 Hz). [LOCK_VOTES] consecutive agreeing votes decide 50, 60 or none;
//! from none, [SWITCH_VOTES] consecutive votes for one frequency switch to
//! it (hum appearing mid-stream). 50/60 is final: it never flips.
//!
//! Recordings: detection runs from connect and the live stream follows it,
//! but a recording (capture prefix `recording` / `session`) locks the notch
//! in effect at its start for its whole length ([lock_for_recording]); an
//! undecided state locks both 50 and 60. A reconnect during the recording
//! restarts the filter with the locked notch. Offline, a recording is
//! conditioned with its recorded notch, and a file without one (imports) is
//! scanned once for mains first and then conditioned with that fixed result.

use std::collections::HashMap;

pub use crate::api::eeg_conditioning::NotchSource;
use std::f64::consts::{PI, SQRT_2};

pub const SAMPLE_RATE_HZ: f64 = 256.0;
pub const HIGHPASS_HZ: f64 = 0.5;
pub const NOTCH_Q: f64 = 10.0;
pub const MAINS_CANDIDATES_HZ: [f64; 2] = [50.0, 60.0];
pub const WARMUP_SAMPLES: usize = 128;
pub const PRIME_PASSES: usize = 4;
pub const GAP_MS: f64 = 200.0;
pub const FILL_MAX_SAMPLES: usize = 12;
pub const DETECT_WINDOW: usize = 256;
pub const PEAK_RATIO: f64 = 5.0;
pub const LOCK_VOTES: u32 = 8;
pub const SWITCH_VOTES: u32 = 16;

/// Mains state of one stream.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Mains {
    /// Not decided yet: both candidates (and harmonics) are notched.
    Unknown,
    /// No hum (DC-only supply): no notch.
    Absent,
    Hz(f64),
}

impl Mains {
    /// Mains fundamentals notched (each with its 2nd harmonic): `[f]`,
    /// `[]` for none, `[50, 60]` while undecided.
    pub fn notched_mains(self) -> Vec<f64> {
        match self {
            Mains::Hz(f) => vec![f],
            Mains::Absent => Vec::new(),
            Mains::Unknown => MAINS_CANDIDATES_HZ.to_vec(),
        }
    }

    /// Inverse of [Mains::notched_mains].
    pub fn from_notched(hz: &[f64]) -> Self {
        match hz {
            [] => Mains::Absent,
            [f] => Mains::Hz(*f),
            _ => Mains::Unknown,
        }
    }

    fn describe(self) -> String {
        match self {
            Mains::Hz(f) => format!("{f} Hz"),
            Mains::Absent => "none".into(),
            Mains::Unknown => "both 50 and 60 Hz (undecided)".into(),
        }
    }
}

/// Transposed direct-form-II biquad (RBJ cookbook coefficients, a0 = 1).
#[derive(Clone, Copy, Debug)]
pub struct Biquad {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    z1: f64,
    z2: f64,
}

impl Biquad {
    fn from_rbj(b: [f64; 3], a0: f64, a1: f64, a2: f64) -> Self {
        Self {
            b0: b[0] / a0,
            b1: b[1] / a0,
            b2: b[2] / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            z1: 0.0,
            z2: 0.0,
        }
    }

    pub fn highpass(cutoff_hz: f64) -> Self {
        let w0 = 2.0 * PI * cutoff_hz / SAMPLE_RATE_HZ;
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / (2.0 / SQRT_2);
        let b = (1.0 + cos) / 2.0;
        Self::from_rbj([b, -2.0 * b, b], 1.0 + alpha, -2.0 * cos, 1.0 - alpha)
    }

    pub fn notch(center_hz: f64, q: f64) -> Self {
        let w0 = 2.0 * PI * center_hz / SAMPLE_RATE_HZ;
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / (2.0 * q);
        Self::from_rbj([1.0, -2.0 * cos, 1.0], 1.0 + alpha, -2.0 * cos, 1.0 - alpha)
    }

    pub fn process(&mut self, x: f64) -> f64 {
        let y = self.b0 * x + self.z1;
        self.z1 = self.b1 * x - self.a1 * y + self.z2;
        self.z2 = self.b2 * x - self.a2 * y;
        y
    }

    /// State as if `x` had been the input forever.
    fn settle_to(&mut self, x: f64) {
        let y = x * (self.b0 + self.b1 + self.b2) / (1.0 + self.a1 + self.a2);
        self.z2 = self.b2 * x - self.a2 * y;
        self.z1 = self.b1 * x - self.a1 * y + self.z2;
    }

    /// Magnitude response at `hz`.
    pub fn gain_at(&self, hz: f64) -> f64 {
        let w = 2.0 * PI * hz / SAMPLE_RATE_HZ;
        let (z1r, z1i) = (w.cos(), -w.sin());
        let (z2r, z2i) = ((2.0 * w).cos(), -(2.0 * w).sin());
        let nr = self.b0 + self.b1 * z1r + self.b2 * z2r;
        let ni = self.b1 * z1i + self.b2 * z2i;
        let dr = 1.0 + self.a1 * z1r + self.a2 * z2r;
        let di = self.a1 * z1i + self.a2 * z2i;
        ((nr * nr + ni * ni) / (dr * dr + di * di)).sqrt()
    }
}

/// Notch centres: the detected mains and its 2nd harmonic, both candidates
/// (and harmonics) while unknown, none when absent.
pub fn notch_frequencies(mains: Mains) -> Vec<f64> {
    match mains {
        Mains::Hz(f) => vec![f, 2.0 * f],
        Mains::Absent => Vec::new(),
        Mains::Unknown => MAINS_CANDIDATES_HZ
            .iter()
            .flat_map(|&f| [f, 2.0 * f])
            .collect(),
    }
}

/// One channel's high-pass + notch chain.
#[derive(Clone, Debug)]
pub struct EegFilter {
    highpass: Biquad,
    notches: Vec<(f64, Biquad)>,
}

impl EegFilter {
    pub fn new(mains: Mains) -> Self {
        Self {
            highpass: Biquad::highpass(HIGHPASS_HZ),
            notches: notch_frequencies(mains)
                .into_iter()
                .map(|f| (f, Biquad::notch(f, NOTCH_Q)))
                .collect(),
        }
    }

    pub fn process(&mut self, x: f64) -> f64 {
        let mut y = self.highpass.process(x);
        for (_, n) in &mut self.notches {
            y = n.process(y);
        }
        y
    }

    /// Switch to the notches of `mains`: kept ones keep their state, new
    /// ones start at rest.
    pub fn set_mains(&mut self, mains: Mains) {
        let want = notch_frequencies(mains);
        self.notches.retain(|(f, _)| want.contains(f));
        for f in want {
            if !self.notches.iter().any(|(g, _)| *g == f) {
                self.notches.push((f, Biquad::notch(f, NOTCH_Q)));
            }
        }
    }

    /// Magnitude response of the whole chain at `hz`.
    pub fn gain_at(&self, hz: f64) -> f64 {
        self.notches
            .iter()
            .fold(self.highpass.gain_at(hz), |g, (_, n)| g * n.gain_at(hz))
    }

    /// Start a segment from its held first samples and return the
    /// conditioned block: seed the high-pass at their mean, then (full
    /// block) prime the chain on the block repeated [PRIME_PASSES] times.
    fn start(mains: Mains, block: &[f64]) -> (Self, Vec<f64>) {
        let mut filter = Self::new(mains);
        let n = block.len().min(WARMUP_SAMPLES);
        if n > 0 {
            let mean = block[..n].iter().sum::<f64>() / n as f64;
            filter.highpass.settle_to(mean);
        }
        if n == WARMUP_SAMPLES {
            for _ in 0..PRIME_PASSES {
                for &x in &block[..n] {
                    filter.process(x);
                }
            }
        }
        let out = block.iter().map(|&x| filter.process(x)).collect();
        (filter, out)
    }
}

/// One window's vote: the mains frequency whose peak stands out, if any.
pub fn mains_vote(samples: &[f64]) -> Option<f64> {
    let (r50, r60) = crate::api::muse::mains_peak_ratios(samples);
    match (r50 >= PEAK_RATIO, r60 >= PEAK_RATIO) {
        (true, true) => Some(if r50 >= r60 { 50.0 } else { 60.0 }),
        (true, false) => Some(50.0),
        (false, true) => Some(60.0),
        (false, false) => None,
    }
}

/// Sticky 50 / 60 / none decision from unfiltered windows.
#[derive(Debug)]
pub struct MainsDetector {
    mains: Mains,
    streak_vote: Option<Option<f64>>,
    streak: u32,
    windows: HashMap<i32, Vec<f64>>,
}

impl Default for MainsDetector {
    fn default() -> Self {
        Self {
            mains: Mains::Unknown,
            streak_vote: None,
            streak: 0,
            windows: HashMap::new(),
        }
    }
}

impl MainsDetector {
    pub fn mains(&self) -> Mains {
        self.mains
    }

    /// Count one window vote; returns the new state when it changes.
    pub fn vote(&mut self, vote: Option<f64>) -> Option<Mains> {
        let needed = match self.mains {
            Mains::Hz(_) => return None,
            Mains::Absent if vote.is_none() => {
                self.streak = 0;
                return None;
            }
            Mains::Absent => SWITCH_VOTES,
            Mains::Unknown => LOCK_VOTES,
        };
        if self.streak_vote == Some(vote) {
            self.streak += 1;
        } else {
            self.streak_vote = Some(vote);
            self.streak = 1;
        }
        if self.streak < needed {
            return None;
        }
        self.streak = 0;
        self.mains = vote.map_or(Mains::Absent, Mains::Hz);
        if let Mains::Hz(_) = self.mains {
            self.windows.clear();
        }
        match vote {
            Some(hz) => log::info!("[eeg_filter] mains {hz} Hz detected"),
            None => log::info!("[eeg_filter] no mains hum detected; notch off"),
        }
        Some(self.mains)
    }

    /// Feed unfiltered samples; returns the new state when it changes.
    pub fn feed(&mut self, electrode: i32, samples: &[f64]) -> Option<Mains> {
        if let Mains::Hz(_) = self.mains {
            return None;
        }
        let window = self.windows.entry(electrode).or_default();
        window.extend_from_slice(samples);
        let mut full = Vec::new();
        while window.len() >= DETECT_WINDOW {
            full.push(window.drain(..DETECT_WINDOW).collect::<Vec<f64>>());
        }
        let mut changed = None;
        for w in full {
            if let Some(m) = self.vote(mains_vote(&w)) {
                changed = Some(m);
            }
        }
        changed
    }
}

#[derive(Debug)]
enum Stage {
    Warmup { start_ms: f64, held: Vec<f64> },
    Running(EegFilter),
}

#[derive(Debug)]
struct Channel {
    stage: Stage,
    next_ms: f64,
    /// Last unfiltered input sample (fill anchor).
    last: f64,
}

/// Which notch a conditioner applies.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum NotchMode {
    /// Follow its own mains detection.
    #[default]
    Detect,
    /// The live stream: the recording lock when one is set, else detection,
    /// else the device's saved decision.
    Live,
    /// Always this notch (detection off).
    Fixed(Mains),
}

/// Conditioner for every EEG channel of one stream (one connection or
/// one recording).
#[derive(Default, Debug)]
pub struct EegConditioner {
    channels: HashMap<i32, Channel>,
    mains: MainsDetector,
    mode: NotchMode,
    applied: Option<Mains>,
    filled: usize,
}

impl EegConditioner {
    pub fn new(mode: NotchMode) -> Self {
        Self { mode, ..Default::default() }
    }

    /// Detected mains (Unknown until decided; never set in `Fixed` mode).
    pub fn mains(&self) -> Mains {
        self.mains.mains()
    }

    /// Notch the filters apply now.
    pub fn applied(&self) -> Mains {
        match self.mode {
            NotchMode::Detect => self.mains.mains(),
            NotchMode::Live => match recording_lock() {
                Some((m, _)) => m,
                None => match self.mains.mains() {
                    Mains::Unknown => saved_mains().unwrap_or(Mains::Unknown),
                    m => m,
                },
            },
            NotchMode::Fixed(m) => m,
        }
    }

    /// Condition one packet of unfiltered samples starting at
    /// `timestamp_ms`. Returns conditioned chunks `(start_ms, samples)` in
    /// order: none while a segment's first samples are held, the held block
    /// once it is complete, else the packet itself. A running channel whose
    /// packet starts 1..=[FILL_MAX_SAMPLES] whole samples late gets those
    /// samples linearly interpolated as a first chunk ([Self::last_fill]).
    pub fn process(
        &mut self,
        electrode: i32,
        timestamp_ms: f64,
        samples: &[f64],
    ) -> Vec<(f64, Vec<f64>)> {
        if !matches!(self.mode, NotchMode::Fixed(_)) {
            self.mains.feed(electrode, samples);
        }
        let mains = self.applied();
        if self.applied != Some(mains) {
            self.applied = Some(mains);
            for ch in self.channels.values_mut() {
                if let Stage::Running(f) = &mut ch.stage {
                    f.set_mains(mains);
                }
            }
        }
        let mut out = Vec::new();
        self.filled = 0;
        let ch = self.channels.entry(electrode).or_insert_with(|| Channel {
            stage: Stage::Warmup { start_ms: timestamp_ms, held: Vec::new() },
            next_ms: timestamp_ms,
            last: 0.0,
        });
        let gap = timestamp_ms - ch.next_ms;
        if gap.abs() > GAP_MS {
            out.extend(flush(&mut ch.stage, mains));
            ch.stage = Stage::Warmup { start_ms: timestamp_ms, held: Vec::new() };
        } else if let (Stage::Running(filter), Some(&b)) = (&mut ch.stage, samples.first()) {
            // Whole lost samples on a sample-accurate timeline: linear fill.
            let period = 1000.0 / SAMPLE_RATE_HZ;
            let k = (gap / period).round();
            if (1.0..=FILL_MAX_SAMPLES as f64).contains(&k) && (gap - k * period).abs() < 0.1 * period {
                let (a, n) = (ch.last, k as usize);
                let fill = (1..=n)
                    .map(|j| filter.process(a + (b - a) * j as f64 / (n + 1) as f64))
                    .collect();
                out.push((ch.next_ms, fill));
                self.filled = n;
            }
        }
        if let Some(&x) = samples.last() {
            ch.last = x;
        }
        ch.next_ms = timestamp_ms + samples.len() as f64 * 1000.0 / SAMPLE_RATE_HZ;
        match &mut ch.stage {
            Stage::Warmup { held, .. } => {
                held.extend_from_slice(samples);
                if held.len() >= WARMUP_SAMPLES {
                    out.extend(flush(&mut ch.stage, mains));
                }
            }
            Stage::Running(filter) => {
                out.push((timestamp_ms, samples.iter().map(|&x| filter.process(x)).collect()));
            }
        }
        out
    }

    /// Interpolated samples leading the last [Self::process] output.
    pub fn last_fill(&self) -> usize {
        self.filled
    }

    /// Release every held block (end of a recording).
    pub fn finish(&mut self) -> Vec<(i32, f64, Vec<f64>)> {
        let mains = self.applied();
        let mut out = Vec::new();
        for (&electrode, ch) in &mut self.channels {
            if let Some((ts, block)) = flush(&mut ch.stage, mains) {
                out.push((electrode, ts, block));
            }
        }
        out
    }
}

fn flush(stage: &mut Stage, mains: Mains) -> Option<(f64, Vec<f64>)> {
    let Stage::Warmup { start_ms, held } = stage else {
        return None;
    };
    if held.is_empty() {
        return None;
    }
    let start_ms = *start_ms;
    let held = std::mem::take(held);
    let (filter, block) = EegFilter::start(mains, &held);
    *stage = Stage::Running(filter);
    Some((start_ms, block))
}

static LIVE_MAINS: std::sync::Mutex<Mains> = std::sync::Mutex::new(Mains::Unknown);
static SAVED_MAINS: std::sync::Mutex<Option<Mains>> = std::sync::Mutex::new(None);
static RECORDING_LOCK: std::sync::Mutex<Option<(Mains, NotchSource)>> = std::sync::Mutex::new(None);

/// Detected mains of the live stream (Unknown after every connect).
pub fn live_mains() -> Mains {
    *LIVE_MAINS.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn publish_live_mains(mains: Mains) {
    *LIVE_MAINS.lock().unwrap_or_else(|e| e.into_inner()) = mains;
}

/// Last decision saved for the connected device (app settings).
pub fn saved_mains() -> Option<Mains> {
    *SAVED_MAINS.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn set_saved_mains(mains: Option<Mains>) {
    *SAVED_MAINS.lock().unwrap_or_else(|e| e.into_inner()) = mains;
}

/// Live notch without a recording lock: detection, else the saved
/// decision, else both.
pub fn live_notch() -> (Mains, NotchSource) {
    match (live_mains(), saved_mains()) {
        (Mains::Unknown, Some(saved)) => (saved, NotchSource::Saved),
        (Mains::Unknown, None) => (Mains::Unknown, NotchSource::Undecided),
        (detected, _) => (detected, NotchSource::Detected),
    }
}

/// Notch locked for the recording in progress, if any.
pub fn recording_lock() -> Option<(Mains, NotchSource)> {
    *RECORDING_LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

/// Lock the live notch for a starting recording or session.
pub fn lock_for_recording() -> (Mains, NotchSource) {
    let lock = live_notch();
    *RECORDING_LOCK.lock().unwrap_or_else(|e| e.into_inner()) = Some(lock);
    log::info!("[eeg_filter] recording mains notch locked: {} ({:?})", lock.0.describe(), lock.1);
    lock
}

pub fn unlock_recording() {
    *RECORDING_LOCK.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

/// Mains of whole recorded streams, as the live detector would end up.
pub fn detect_packets(packets: &[(i32, f64, Vec<f64>)]) -> Mains {
    let mut detector = MainsDetector::default();
    for (electrode, _, samples) in packets {
        detector.feed(*electrode, samples);
    }
    detector.mains()
}

/// Condition whole recorded EEG streams offline with one fixed notch:
/// `notch` (the recording's), or else one found by scanning the packets
/// first. `packets` are `(electrode, timestamp_ms, samples)` in stream
/// order; the result has the same packets with conditioned samples, plus
/// the notch used.
pub fn condition_packets(
    packets: &[(i32, f64, Vec<f64>)],
    notch: Option<Mains>,
) -> (Vec<Vec<f64>>, Mains) {
    let mains = notch.unwrap_or_else(|| detect_packets(packets));
    let mut conditioner = EegConditioner::new(NotchMode::Fixed(mains));
    let mut per_electrode: HashMap<i32, Vec<f64>> = HashMap::new();
    for (electrode, ts, samples) in packets {
        let chunks = conditioner.process(*electrode, *ts, samples);
        // Fills keep the filter continuous but are not packet samples.
        let skip = usize::from(conditioner.last_fill() > 0);
        for (_, block) in chunks.into_iter().skip(skip) {
            per_electrode.entry(*electrode).or_default().extend(block);
        }
    }
    for (electrode, _, block) in conditioner.finish() {
        per_electrode.entry(electrode).or_default().extend(block);
    }
    let mut cursor: HashMap<i32, usize> = HashMap::new();
    let out = packets
        .iter()
        .map(|(electrode, _, samples)| {
            let at = cursor.entry(*electrode).or_default();
            let all = &per_electrode[electrode];
            let out = all[*at..*at + samples.len()].to_vec();
            *at += samples.len();
            out
        })
        .collect();
    (out, mains)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FS: f64 = SAMPLE_RATE_HZ;

    fn db(g: f64) -> f64 {
        20.0 * g.log10()
    }

    /// Deterministic uniform noise in ±amp.
    struct Lcg(u64);
    impl Lcg {
        fn next(&mut self, amp: f64) -> f64 {
            self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((self.0 >> 11) as f64 / (1u64 << 53) as f64 * 2.0 - 1.0) * amp
        }
    }

    fn alpha(n: usize) -> f64 {
        alpha_at(n as i64)
    }

    fn alpha_at(n: i64) -> f64 {
        10.0 * (2.0 * PI * 10.0 * n as f64 / FS).sin()
    }

    /// Realistic unfiltered Crown sample: DC offset, slow drift, mains.
    fn realistic(n: usize, offset: f64, mains_hz: f64) -> f64 {
        let t = n as f64 / FS;
        offset + 40.0 * (2.0 * PI * 0.05 * t).sin() + alpha(n) + 138.0 * (2.0 * PI * mains_hz * t).sin()
    }

    /// Feed `total` samples of `f` for `channels` channels in 16-sample
    /// packets from `start_ms`; returns per-channel conditioned samples.
    fn run(
        c: &mut EegConditioner,
        channels: i32,
        from: usize,
        total: usize,
        start_ms: f64,
        f: &mut dyn FnMut(i32, usize) -> f64,
    ) -> Vec<Vec<f64>> {
        let mut out = vec![Vec::new(); channels as usize];
        let mut n = from;
        while n < from + total {
            for ch in 0..channels {
                let samples: Vec<f64> = (n..n + 16).map(|i| f(ch, i)).collect();
                let ts = start_ms + (n - from) as f64 * 1000.0 / FS;
                for (_, block) in c.process(ch, ts, &samples) {
                    out[ch as usize].extend(block);
                }
            }
            n += 16;
        }
        out
    }

    #[test]
    fn response_removes_dc_and_mains_and_passes_alpha() {
        let unknown = EegFilter::new(Mains::Unknown);
        assert!(unknown.gain_at(0.0) < 1e-9);
        for hz in [50.0, 60.0, 100.0, 120.0] {
            assert!(db(unknown.gain_at(hz)) < -60.0, "{hz} Hz {}", db(unknown.gain_at(hz)));
        }
        for hz in [8.0, 10.0, 13.0] {
            assert!(db(unknown.gain_at(hz)).abs() < 0.1, "{hz} Hz {}", db(unknown.gain_at(hz)));
        }
        assert!(db(unknown.gain_at(1.0)).abs() < 0.3);

        let fifty = EegFilter::new(Mains::Hz(50.0));
        assert!(db(fifty.gain_at(50.0)) < -60.0 && db(fifty.gain_at(100.0)) < -60.0);
        assert!(db(fifty.gain_at(60.0)).abs() < 0.2);
        let sixty = EegFilter::new(Mains::Hz(60.0));
        assert!(db(sixty.gain_at(60.0)) < -60.0 && db(sixty.gain_at(120.0)) < -60.0);
        assert!(db(sixty.gain_at(50.0)).abs() < 0.2);
        let absent = EegFilter::new(Mains::Absent);
        assert!(db(absent.gain_at(50.0)).abs() < 0.01 && db(absent.gain_at(60.0)).abs() < 0.01);
        assert!(absent.gain_at(0.0) < 1e-9);
    }

    fn amplitude_at(x: &[f64], hz: f64) -> f64 {
        let (mut s, mut c) = (0.0, 0.0);
        for (i, v) in x.iter().enumerate() {
            let w = 2.0 * PI * hz * i as f64 / FS;
            s += v * w.sin();
            c += v * w.cos();
        }
        2.0 * (s * s + c * c).sqrt() / x.len() as f64
    }

    #[test]
    fn time_domain_alpha_within_1_db_and_mains_removed() {
        for mains in [50.0, 60.0] {
            let mut c = EegConditioner::default();
            let out = run(&mut c, 1, 0, 256 * 20, 0.0, &mut |_, n| realistic(n, -2.0e5, mains));
            assert_eq!(c.mains(), Mains::Hz(mains));
            let tail = &out[0][256 * 10..256 * 20];
            let a = amplitude_at(tail, 10.0);
            assert!(db(a / 10.0).abs() < 1.0, "alpha {a}");
            let hum = amplitude_at(tail, mains);
            eprintln!("{mains}: alpha {a:.4} hum {hum:.5}");
            assert!(hum < 0.05, "{mains} Hz residual {hum}");
        }
    }

    /// Clean alpha through a long-settled chain (same notches as the
    /// conditioner before mains is decided): the ideal output.
    fn settled_alpha(from: usize, len: usize) -> Vec<f64> {
        let mut f = EegFilter::new(Mains::Unknown);
        let pre = 256 * 30;
        (0..pre + len)
            .map(|k| f.process(alpha_at(from as i64 + k as i64 - pre as i64)))
            .skip(pre)
            .collect()
    }

    fn max_err(out: &[f64], ideal: &[f64], skip: usize) -> f64 {
        out.iter()
            .zip(ideal)
            .skip(skip)
            .map(|(a, b)| (a - b).abs())
            .fold(0.0, f64::max)
    }

    #[test]
    fn short_timeline_gaps_are_filled_in_the_conditioned_path_only() {
        let period = 1000.0 / FS;
        // 16-sample packets of a clean alpha sine; after 2 s the packets
        // lose 1, then 3, then 12 samples; a jittered start is not a loss.
        let mut packets = Vec::new();
        let mut n = 0usize;
        let mut lost_at = Vec::new();
        for p in 0..64 {
            let skip = match p {
                31 => 1,
                40 => 3,
                48 => FILL_MAX_SAMPLES,
                _ => 0,
            };
            if skip > 0 {
                lost_at.push((n, skip));
            }
            n += skip;
            let jitter = if p == 56 { 0.4 * period } else { 0.0 };
            let samples: Vec<f64> = (n..n + 16).map(alpha).collect();
            packets.push((0, n as f64 * period + jitter, samples));
            n += 16;
        }
        let mut c = EegConditioner::new(NotchMode::Fixed(Mains::Absent));
        let mut live = Vec::new();
        let mut fills = Vec::new();
        for (e, ts, s) in &packets {
            let chunks = c.process(*e, *ts, s);
            if c.last_fill() > 0 {
                fills.push((chunks[0].0, c.last_fill()));
            }
            for (_, b) in chunks {
                live.extend(b);
            }
        }
        // Each loss is filled once, starting where the samples went missing.
        assert_eq!(fills.len(), 3);
        for ((t, k), (at, skip)) in fills.iter().zip(&lost_at) {
            assert_eq!(k, skip);
            assert!((t - *at as f64 * period).abs() < 1e-9);
        }
        // Live output is gapless: one conditioned sample per timeline sample,
        // tracking the sine through every fill (≤ one fill's linear error).
        assert_eq!(live.len(), n);
        let reference: Vec<f64> = {
            let mut r = EegConditioner::new(NotchMode::Fixed(Mains::Absent));
            let all: Vec<f64> = (0..n).map(alpha).collect();
            all.chunks(16)
                .enumerate()
                .flat_map(|(i, s)| r.process(0, (i * 16) as f64 * period, s))
                .flat_map(|(_, b)| b)
                .collect()
        };
        let after_first = lost_at[0].0;
        let err = |to: usize| {
            (after_first..to).map(|i| (live[i] - reference[i]).abs()).fold(0.0, f64::max)
        };
        eprintln!("fill: max err after 1-sample fill {:.3} µV", err(lost_at[1].0));
        assert!(err(lost_at[1].0) < 0.5);
        // Offline: fills drop out, every packet keeps its length.
        let (out, _) = condition_packets(&packets, Some(Mains::Absent));
        for ((_, _, s), o) in packets.iter().zip(&out) {
            assert_eq!(s.len(), o.len());
        }
    }

    #[test]
    fn settles_fast_from_large_offset_and_after_a_gap() {
        let mut c = EegConditioner::default();
        let out = run(&mut c, 1, 0, 256 * 2, 1000.0, &mut |_, n| realistic(n, -2.0e5, 50.0));
        assert_eq!(out[0].len(), 512);
        let ideal = settled_alpha(0, 512);
        // Output starts at the first sample at EEG scale; what the -2e5 µV
        // offset, 40 µV drift and 138 µV hum leave fades within a second.
        let e0 = max_err(&out[0], &ideal, 0);
        let e = max_err(&out[0], &ideal, 32);
        let e_1s = max_err(&out[0], &ideal, 256);
        assert!(e0 < 5.0, "max error from the first sample {e0}");
        assert!(e < 3.0, "max error after 125 ms {e}");
        assert!(e_1s < 1.5, "max error after 1 s {e_1s}");

        // 1 s gap, then a new offset (reconnect): reseeded, same settling.
        let resumed = run(&mut c, 1, 256 * 3, 256 * 2, 1000.0 + 3000.0, &mut |_, n| {
            realistic(n, -1.5e5, 50.0)
        });
        let e_gap = max_err(&resumed[0], &settled_alpha(256 * 3, 512), 32);
        assert!(e_gap < 3.0, "max error after gap {e_gap}");
        eprintln!("settle: max err from 0 {e0:.3}, after 125 ms {e:.3}, after 1 s {e_1s:.3}, after gap {e_gap:.3}");
    }

    #[test]
    fn mains_detection_50_60_and_none() {
        for (hum, want) in [(Some(50.0), Mains::Hz(50.0)), (Some(60.0), Mains::Hz(60.0)), (None, Mains::Absent)] {
            let mut rng = Lcg(7);
            let mut c = EegConditioner::default();
            run(&mut c, 8, 0, 256 * 3, 0.0, &mut |_, n| {
                let h = hum.map_or(0.0, |f| 138.0 * (2.0 * PI * f * n as f64 / FS).sin());
                -2.0e5 + alpha(n) + rng.next(2.0) + h
            });
            assert_eq!(c.mains(), want, "hum {hum:?}");
        }
    }

    #[test]
    fn no_mains_means_no_notch() {
        let mut rng = Lcg(3);
        let mut c = EegConditioner::default();
        let out = run(&mut c, 1, 0, 256 * 20, 0.0, &mut |_, n| alpha(n) + rng.next(2.0));
        assert_eq!(c.mains(), Mains::Absent);
        // A 50 Hz test tone added after the decision passes untouched.
        let mut c2 = EegConditioner::default();
        let mut rng = Lcg(3);
        run(&mut c2, 1, 0, 256 * 10, 0.0, &mut |_, n| alpha(n) + rng.next(2.0));
        assert_eq!(c2.mains(), Mains::Absent);
        let filter = EegFilter::new(c2.mains());
        assert!(db(filter.gain_at(50.0)).abs() < 0.01);
        assert!(out[0].len() > 256 * 19);
    }

    #[test]
    fn none_switches_to_50_when_hum_appears_mid_stream() {
        let mut rng = Lcg(11);
        let mut c = EegConditioner::default();
        run(&mut c, 8, 0, 256 * 5, 0.0, &mut |_, n| alpha(n) + rng.next(2.0));
        assert_eq!(c.mains(), Mains::Absent);
        let hum = |n: usize| 138.0 * (2.0 * PI * 50.0 * n as f64 / FS).sin();
        run(&mut c, 8, 256 * 5, 256 * 3, 5000.0, &mut |_, n| alpha(n) + rng.next(2.0) + hum(n));
        // Switch after SWITCH_VOTES windows (2 s at 8 channels), then the
        // notch removes the hum.
        assert_eq!(c.mains(), Mains::Hz(50.0));
        let out = run(&mut c, 8, 256 * 8, 256 * 7, 8000.0, &mut |_, n| alpha(n) + rng.next(2.0) + hum(n));
        let tail = &out[0][256..];
        assert!(amplitude_at(tail, 50.0) < 0.05, "residual {}", amplitude_at(tail, 50.0));
    }

    #[test]
    fn decision_is_sticky_and_never_flips_between_50_and_60() {
        let mut c = EegConditioner::default();
        run(&mut c, 8, 0, 256 * 2, 0.0, &mut |_, n| realistic(n, -2.0e5, 50.0));
        assert_eq!(c.mains(), Mains::Hz(50.0));
        run(&mut c, 8, 256 * 2, 256 * 20, 2000.0, &mut |_, n| realistic(n, -2.0e5, 60.0));
        assert_eq!(c.mains(), Mains::Hz(50.0));
        let mut rng = Lcg(5);
        run(&mut c, 8, 256 * 22, 256 * 5, 22000.0, &mut |_, n| alpha(n) + rng.next(2.0));
        assert_eq!(c.mains(), Mains::Hz(50.0));

        // Alternating or mixed votes never decide.
        let mut d = MainsDetector::default();
        for i in 0..100 {
            let v = if i % 2 == 0 { Some(50.0) } else { Some(60.0) };
            assert_eq!(d.vote(v), None);
        }
        assert_eq!(d.mains(), Mains::Unknown);
        // Absent needs SWITCH_VOTES in a row; a clean window resets the run.
        let mut d = MainsDetector::default();
        for _ in 0..LOCK_VOTES {
            d.vote(None);
        }
        assert_eq!(d.mains(), Mains::Absent);
        for _ in 0..3 {
            for _ in 0..SWITCH_VOTES - 1 {
                d.vote(Some(60.0));
            }
            d.vote(None);
        }
        assert_eq!(d.mains(), Mains::Absent);
    }

    #[test]
    fn offline_packets_keep_shape_and_match_streaming() {
        let mut packets = Vec::new();
        for k in 0..64usize {
            for ch in 0..2 {
                let samples: Vec<f64> = (k * 16..k * 16 + 16).map(|n| realistic(n, -2.0e5 + ch as f64, 50.0)).collect();
                // 1.5 s gap after packet 40.
                let ts = k as f64 * 62.5 + if k > 40 { 1500.0 } else { 0.0 };
                packets.push((ch, ts, samples));
            }
        }
        let (out, mains) = condition_packets(&packets, None);
        assert_eq!(mains, Mains::Hz(50.0));
        assert_eq!(out.len(), packets.len());
        for (o, p) in out.iter().zip(&packets) {
            assert_eq!(o.len(), p.2.len());
        }
        let mut streaming = EegConditioner::new(NotchMode::Fixed(mains));
        let mut ch0 = Vec::new();
        for (ch, ts, s) in &packets {
            for (_, b) in streaming.process(*ch, *ts, s) {
                if *ch == 0 {
                    ch0.extend(b);
                }
            }
        }
        for (e, _, b) in streaming.finish() {
            if e == 0 {
                ch0.extend(b);
            }
        }
        let offline: Vec<f64> = out.iter().zip(&packets).filter(|(_, p)| p.0 == 0).flat_map(|(o, _)| o.clone()).collect();
        assert_eq!(offline, ch0);
    }

    #[test]
    fn offline_uses_the_recorded_notch() {
        let packets: Vec<(i32, f64, Vec<f64>)> = (0..160usize)
            .map(|k| (0, k as f64 * 62.5, (k * 16..k * 16 + 16).map(|n| realistic(n, -2.0e5, 60.0)).collect()))
            .collect();
        let (_, scanned) = condition_packets(&packets, None);
        assert_eq!(scanned, Mains::Hz(60.0));
        // Recorded as "both": 60 Hz still removed, no scan.
        let (out, used) = condition_packets(&packets, Some(Mains::Unknown));
        assert_eq!(used, Mains::Unknown);
        let tail: Vec<f64> = out[80..].iter().flatten().copied().collect();
        assert!(amplitude_at(&tail, 60.0) < 0.05);
        // Recorded as "none": the hum stays.
        let (out, _) = condition_packets(&packets, Some(Mains::Absent));
        let tail: Vec<f64> = out[80..].iter().flatten().copied().collect();
        assert!(amplitude_at(&tail, 60.0) > 100.0);
    }

    #[test]
    fn notched_mains_round_trip() {
        for m in [Mains::Hz(50.0), Mains::Hz(60.0), Mains::Absent, Mains::Unknown] {
            assert_eq!(Mains::from_notched(&m.notched_mains()), m);
        }
        assert_eq!(Mains::Unknown.notched_mains(), vec![50.0, 60.0]);
        assert!(Mains::Absent.notched_mains().is_empty());
    }

    #[test]
    fn recording_lock_freezes_the_live_notch() {
        let _g = crate::spine::capture::test_lock();
        // Undecided at recording start: both notches for the whole recording.
        publish_live_mains(Mains::Unknown);
        set_saved_mains(None);
        assert_eq!(lock_for_recording(), (Mains::Unknown, NotchSource::Undecided));
        let mut c = EegConditioner::new(NotchMode::Live);
        let out = run(&mut c, 8, 0, 256 * 6, 0.0, &mut |_, n| realistic(n, -2.0e5, 50.0));
        assert_eq!(c.mains(), Mains::Hz(50.0));
        assert_eq!(c.applied(), Mains::Unknown);
        // Reconnect mid-recording: a new conditioner reuses the lock.
        publish_live_mains(Mains::Unknown);
        let mut r = EegConditioner::new(NotchMode::Live);
        run(&mut r, 8, 0, 256 * 3, 0.0, &mut |_, n| realistic(n, -2.0e5, 60.0));
        assert_eq!(r.mains(), Mains::Hz(60.0));
        assert_eq!(r.applied(), Mains::Unknown);
        let tail = &out[0][256 * 3..];
        assert!(amplitude_at(tail, 50.0) < 0.05);
        // Recording stops: the live stream follows detection again.
        unlock_recording();
        run(&mut c, 8, 256 * 6, 256, 6000.0, &mut |_, n| realistic(n, -2.0e5, 50.0));
        assert_eq!(c.applied(), Mains::Hz(50.0));
        // Decided at start: that value is locked.
        publish_live_mains(Mains::Hz(60.0));
        set_saved_mains(Some(Mains::Hz(50.0)));
        assert_eq!(lock_for_recording(), (Mains::Hz(60.0), NotchSource::Detected));
        assert_eq!(EegConditioner::new(NotchMode::Live).applied(), Mains::Hz(60.0));
        unlock_recording();
        // Undecided but saved for this device: the saved value, assumed true.
        publish_live_mains(Mains::Unknown);
        assert_eq!(lock_for_recording(), (Mains::Hz(50.0), NotchSource::Saved));
        unlock_recording();
        set_saved_mains(Some(Mains::Absent));
        assert_eq!(lock_for_recording(), (Mains::Absent, NotchSource::Saved));
        unlock_recording();
        set_saved_mains(None);
    }

    #[test]
    fn live_filter_starts_from_the_saved_decision() {
        let _g = crate::spine::capture::test_lock();
        unlock_recording();
        set_saved_mains(Some(Mains::Hz(60.0)));
        let mut c = EegConditioner::new(NotchMode::Live);
        assert_eq!(c.applied(), Mains::Hz(60.0));
        // Seeded: 60 Hz hum is removed from the first output on.
        let out = run(&mut c, 1, 0, 256, 0.0, &mut |_, n| realistic(n, -2.0e5, 60.0));
        assert!(amplitude_at(&out[0][128..], 60.0) < 1.0);
        // Detection overrides the saved value once it decides.
        set_saved_mains(Some(Mains::Hz(50.0)));
        let mut d = EegConditioner::new(NotchMode::Live);
        run(&mut d, 8, 0, 256 * 3, 0.0, &mut |_, n| realistic(n, -2.0e5, 60.0));
        assert_eq!(d.applied(), Mains::Hz(60.0));
        set_saved_mains(None);
        assert_eq!(EegConditioner::new(NotchMode::Live).applied(), Mains::Unknown);
    }
}
