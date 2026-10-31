//! Building blocks: decoded PCM, exponential slews, a biquad low-pass and a
//! resampling (looping) voice.

use std::f64::consts::TAU;
use std::sync::Arc;

/// Decoded audio, interleaved f32, 1 or 2 channels.
#[derive(Debug, Clone, PartialEq)]
pub struct Pcm {
    pub rate: u32,
    pub channels: u16,
    pub data: Vec<f32>,
}

impl Pcm {
    pub fn frames(&self) -> usize {
        self.data.len() / usize::from(self.channels.max(1))
    }

    pub fn seconds(&self) -> f64 {
        self.frames() as f64 / f64::from(self.rate.max(1))
    }

    /// Stereo frame `i` (mono duplicated); silence past the end.
    fn frame(&self, i: usize) -> [f32; 2] {
        let ch = usize::from(self.channels.max(1));
        let at = |k: usize| self.data.get(i * ch + k).copied().unwrap_or(0.0);
        if ch == 1 {
            [at(0), at(0)]
        } else {
            [at(0), at(1)]
        }
    }
}

/// One-pole exponential approach to a target, time constant `tau` seconds.
#[derive(Debug, Clone, Copy)]
pub struct Slew {
    pub value: f64,
    pub target: f64,
    alpha: f64,
}

impl Slew {
    pub fn new(value: f64, tau_s: f64, rate: f64) -> Self {
        let mut s = Self { value, target: value, alpha: 1.0 };
        s.set_tau(tau_s, rate);
        s
    }

    pub fn set_tau(&mut self, tau_s: f64, rate: f64) {
        self.alpha = 1.0 - (-1.0 / (tau_s.max(1e-4) * rate.max(1.0))).exp();
    }

    /// Advance `n` samples at once (exact for a constant target).
    pub fn step_n(&mut self, n: usize) -> f64 {
        let keep = (1.0 - self.alpha).powi(i32::try_from(n).unwrap_or(i32::MAX));
        self.value = self.target + (self.value - self.target) * keep;
        self.value
    }

    pub fn step(&mut self) -> f64 {
        self.value += (self.target - self.value) * self.alpha;
        self.value
    }
}

/// RBJ biquad low-pass (Q = 1/sqrt 2), direct form I, one per channel.
#[derive(Debug, Clone, Copy, Default)]
pub struct Biquad {
    b: [f64; 3],
    a: [f64; 2],
    x: [[f64; 2]; 2],
    y: [[f64; 2]; 2],
}

impl Biquad {
    pub fn set_lowpass(&mut self, cutoff: f64, rate: f64) {
        let f = cutoff.clamp(10.0, rate * 0.45);
        let w = TAU * f / rate;
        let alpha = w.sin() / (2.0 * std::f64::consts::FRAC_1_SQRT_2);
        let c = w.cos();
        let a0 = 1.0 + alpha;
        let b1 = (1.0 - c) / a0;
        self.b = [b1 / 2.0, b1, b1 / 2.0];
        self.a = [-2.0 * c / a0, (1.0 - alpha) / a0];
    }

    pub fn process(&mut self, ch: usize, x: f64) -> f64 {
        let (xs, ys) = (&mut self.x[ch], &mut self.y[ch]);
        let y = self.b[0] * x + self.b[1] * xs[0] + self.b[2] * xs[1] - self.a[0] * ys[0] - self.a[1] * ys[1];
        *xs = [x, xs[0]];
        *ys = [y, ys[0]];
        y
    }
}

/// Frames between filter coefficient updates.
pub const CONTROL_BLOCK: usize = 64;

/// A PCM player with gain and optional low-pass, both slewed.
#[derive(Debug, Clone)]
pub struct Voice {
    pub pcm: Option<Arc<Pcm>>,
    pos: f64,
    pub looping: bool,
    pub gain: Slew,
    pub cutoff: Slew,
    pub filtered: bool,
    filter: Biquad,
    rate: f64,
}

impl Voice {
    pub fn new(rate: f64, cutoff: f64, cutoff_tau: f64) -> Self {
        Self {
            pcm: None,
            pos: 0.0,
            looping: true,
            gain: Slew::new(0.0, crate::outputs::VOLUME_SLEW_S, rate),
            cutoff: Slew::new(cutoff, cutoff_tau, rate),
            filtered: false,
            filter: Biquad::default(),
            rate,
        }
    }

    /// Swap the clip (restarts at 0) unless it is the same one.
    pub fn set_pcm(&mut self, pcm: Option<Arc<Pcm>>) {
        let same = match (&self.pcm, &pcm) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        };
        if !same {
            self.pcm = pcm;
            self.pos = 0.0;
        }
    }

    /// True once a non-looping clip has played out.
    pub fn finished(&self) -> bool {
        !self.looping && self.pcm.as_ref().is_none_or(|p| self.pos >= p.frames() as f64)
    }

    /// Mix `frames` stereo frames into `out` (interleaved L/R).
    pub fn render(&mut self, out: &mut [f32]) {
        let Some(pcm) = self.pcm.clone() else { return };
        let n = pcm.frames();
        if n == 0 {
            return;
        }
        let step = f64::from(pcm.rate) / self.rate;
        for (i, frame) in out.as_chunks_mut::<2>().0.iter_mut().enumerate() {
            if self.filtered && i % CONTROL_BLOCK == 0 {
                let c = self.cutoff.step_n(CONTROL_BLOCK);
                self.filter.set_lowpass(c, self.rate);
            }
            let g = self.gain.step();
            if self.pos >= n as f64 {
                if !self.looping {
                    return;
                }
                self.pos -= n as f64;
            }
            let s = self.sample(&pcm, n);
            self.pos += step;
            for (ch, v) in frame.iter_mut().enumerate() {
                let x = f64::from(s[ch]);
                let y = if self.filtered { self.filter.process(ch, x) } else { x };
                *v += (y * g) as f32;
            }
        }
    }

    /// Linear interpolation at the current position (wraps when looping).
    fn sample(&self, pcm: &Pcm, n: usize) -> [f32; 2] {
        let i = self.pos as usize;
        let t = (self.pos - i as f64) as f32;
        let j = if i + 1 < n || !self.looping { i + 1 } else { 0 };
        let (a, b) = (pcm.frame(i), pcm.frame(j));
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
    }
}

/// Two sines (binaural): L = carrier, R = carrier + beat; slewed gain.
#[derive(Debug, Clone, Copy)]
pub struct Binaural {
    phase: [f64; 2],
    pub freq: [f64; 2],
    pub gain: Slew,
    rate: f64,
}

/// Peak level of the binaural sines (comfortable, below the clips).
pub const BINAURAL_LEVEL: f64 = 0.25;

impl Binaural {
    pub fn new(rate: f64) -> Self {
        Self { phase: [0.0; 2], freq: [200.0, 210.0], gain: Slew::new(0.0, crate::outputs::VOLUME_SLEW_S, rate), rate }
    }

    pub fn set_preset(&mut self, beat: f64, carrier: f64) {
        self.freq = [carrier, carrier + beat];
    }

    pub fn render(&mut self, out: &mut [f32]) {
        if self.gain.value < 1e-5 && self.gain.target < 1e-5 {
            return;
        }
        for frame in out.as_chunks_mut::<2>().0 {
            let g = self.gain.step() * BINAURAL_LEVEL;
            for (ch, v) in frame.iter_mut().enumerate() {
                *v += (g * self.phase[ch].sin()) as f32;
                self.phase[ch] = (self.phase[ch] + TAU * self.freq[ch] / self.rate) % TAU;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    fn tone(hz: f64, rate: u32, secs: f64) -> Pcm {
        let n = (f64::from(rate) * secs) as usize;
        let data = (0..n).map(|i| (TAU * hz * i as f64 / f64::from(rate)).sin() as f32).collect();
        Pcm { rate, channels: 1, data }
    }

    fn rms(x: &[f32]) -> f64 {
        (x.iter().map(|v| f64::from(*v).powi(2)).sum::<f64>() / x.len() as f64).sqrt()
    }

    #[test]
    fn slew_reaches_target_with_time_constant() {
        let mut s = Slew::new(0.0, 0.5, 1000.0);
        s.target = 1.0;
        s.step_n(500);
        assert!((s.value - (1.0 - (-1.0f64).exp())).abs() < 1e-3, "{}", s.value);
    }

    #[test]
    fn lowpass_attenuates_highs_and_passes_lows() {
        for (hz, keep) in [(200.0, true), (8000.0, false)] {
            let mut v = Voice::new(48_000.0, 900.0, 0.01);
            v.set_pcm(Some(Arc::new(tone(hz, 48_000, 1.0))));
            v.filtered = true;
            v.gain = Slew::new(1.0, 0.5, 48_000.0);
            let mut out = vec![0.0; 2 * 24_000];
            v.render(&mut out);
            let r = rms(&out[24_000..]);
            assert_eq!(r > 0.5, keep, "{hz} Hz rms {r}");
        }
    }

    #[test]
    fn voice_resamples_and_loops() {
        let mut v = Voice::new(48_000.0, 1000.0, 0.5);
        v.set_pcm(Some(Arc::new(tone(441.0, 44_100, 0.1))));
        v.gain = Slew::new(1.0, 0.5, 48_000.0);
        let mut out = vec![0.0; 2 * 48_000];
        v.render(&mut out);
        assert!(rms(&out[90_000..]) > 0.6, "still playing after 10 loops");
        assert!(!v.finished());
        v.looping = false;
        v.render(&mut out);
        assert!(v.finished());
    }

    #[test]
    fn binaural_ears_differ_by_the_beat() {
        let mut b = Binaural::new(48_000.0);
        b.set_preset(10.0, 200.0);
        assert_eq!(b.freq, [200.0, 210.0]);
        b.gain = Slew::new(1.0, 0.5, 48_000.0);
        let mut out = vec![0.0; 2 * 4800];
        b.render(&mut out);
        let crossings = |ch: usize| {
            out.as_chunks::<2>().0.iter().map(|f| f[ch]).collect::<Vec<_>>().windows(2).filter(|w| w[0] < 0.0 && w[1] >= 0.0).count()
        };
        assert_eq!((crossings(0), crossings(1)), (19, 20));
    }
}
