//! Biquads and the per-channel conditioning chain, ported from
//! `rust/src/analysis/eeg_filter.rs` with the sample rate as a parameter.
//! Mains detection and recording locks stay with the caller (core).

use std::f64::consts::{PI, SQRT_2};

pub const HIGHPASS_HZ: f64 = 0.5;
pub const NOTCH_Q: f64 = 10.0;

/// Which mains frequency to notch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mains {
    /// Undecided: notch 50/100 and 60/120 Hz.
    Unknown,
    Hz50,
    Hz60,
    /// No mains hum: no notch.
    None,
}

/// Notch centres: mains and its 2nd harmonic.
pub fn notch_frequencies(mains: Mains) -> Vec<f64> {
    match mains {
        Mains::Unknown => vec![50.0, 100.0, 60.0, 120.0],
        Mains::Hz50 => vec![50.0, 100.0],
        Mains::Hz60 => vec![60.0, 120.0],
        Mains::None => vec![],
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
    rate: f64,
}

impl Biquad {
    fn from_rbj(rate: f64, b: [f64; 3], a0: f64, a1: f64, a2: f64) -> Self {
        Self { b0: b[0] / a0, b1: b[1] / a0, b2: b[2] / a0, a1: a1 / a0, a2: a2 / a0, z1: 0.0, z2: 0.0, rate }
    }

    /// 2nd-order Butterworth high-pass.
    pub fn highpass(rate: f64, cutoff_hz: f64) -> Self {
        let w0 = 2.0 * PI * cutoff_hz / rate;
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / (2.0 / SQRT_2);
        let b = (1.0 + cos) / 2.0;
        Self::from_rbj(rate, [b, -2.0 * b, b], 1.0 + alpha, -2.0 * cos, 1.0 - alpha)
    }

    pub fn notch(rate: f64, center_hz: f64, q: f64) -> Self {
        let w0 = 2.0 * PI * center_hz / rate;
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / (2.0 * q);
        Self::from_rbj(rate, [1.0, -2.0 * cos, 1.0], 1.0 + alpha, -2.0 * cos, 1.0 - alpha)
    }

    pub fn process(&mut self, x: f64) -> f64 {
        let y = self.b0 * x + self.z1;
        self.z1 = self.b1 * x - self.a1 * y + self.z2;
        self.z2 = self.b2 * x - self.a2 * y;
        y
    }

    /// State as if `x` had been the input forever.
    pub fn settle_to(&mut self, x: f64) {
        let y = x * (self.b0 + self.b1 + self.b2) / (1.0 + self.a1 + self.a2);
        self.z2 = self.b2 * x - self.a2 * y;
        self.z1 = self.b1 * x - self.a1 * y + self.z2;
    }

    /// Magnitude response at `hz`.
    pub fn gain_at(&self, hz: f64) -> f64 {
        let w = 2.0 * PI * hz / self.rate;
        let (z1r, z1i) = (w.cos(), -w.sin());
        let (z2r, z2i) = ((2.0 * w).cos(), -(2.0 * w).sin());
        let nr = self.b0 + self.b1 * z1r + self.b2 * z2r;
        let ni = self.b1 * z1i + self.b2 * z2i;
        let dr = 1.0 + self.a1 * z1r + self.a2 * z2r;
        let di = self.a1 * z1i + self.a2 * z2i;
        ((nr * nr + ni * ni) / (dr * dr + di * di)).sqrt()
    }
}

/// One channel: high-pass at `HIGHPASS_HZ` then mains notches (below Nyquist).
/// The high-pass is seeded at the first sample so a DC offset does not ring.
#[derive(Debug, Clone)]
pub struct EegFilter {
    rate: f64,
    hp: Biquad,
    notches: Vec<Biquad>,
    started: bool,
}

impl EegFilter {
    pub fn new(rate: f64, mains: Mains) -> Self {
        let notches = notch_frequencies(mains).into_iter().filter(|&f| f < rate / 2.0).map(|f| Biquad::notch(rate, f, NOTCH_Q)).collect();
        Self { rate, hp: Biquad::highpass(rate, HIGHPASS_HZ), notches, started: false }
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    pub fn process(&mut self, x: f64) -> f64 {
        if !self.started {
            self.hp.settle_to(x);
            self.started = true;
        }
        let mut y = self.hp.process(x);
        for n in &mut self.notches {
            y = n.process(y);
        }
        y
    }

    /// Chain magnitude response at `hz`.
    pub fn gain_at(&self, hz: f64) -> f64 {
        self.notches.iter().fold(self.hp.gain_at(hz), |g, n| g * n.gain_at(hz))
    }
}
