//! Simulated band powers with plausible shape: 1/f falloff, a slowly waxing
//! alpha rhythm, and a little noise. Deterministic (seeded), no extra deps.

use super::{Band, BandSnapshot, BandSource, DeviceInfo};

/// Baseline log power per band (delta > theta > alpha > beta > gamma).
const BASELINE: [f32; 5] = [1.2, 0.8, 0.7, 0.3, -0.2];

pub struct MockBandSource {
    info: DeviceInfo,
    /// Seconds between snapshots (Muse band powers arrive at ~10 Hz).
    interval: f64,
    last: Option<f64>,
    rng: u64,
}

impl MockBandSource {
    /// A simulated 4-channel Muse (TP9, AF7, AF8, TP10).
    pub fn muse() -> Self {
        Self::new(
            "Muse S (simulated)",
            &["TP9", "AF7", "AF8", "TP10"],
        )
    }

    pub fn new(name: &str, channels: &[&str]) -> Self {
        Self {
            info: DeviceInfo {
                name: name.to_owned(),
                channels: channels.iter().map(|c| (*c).to_owned()).collect(),
                simulated: true,
            },
            interval: 0.1,
            last: None,
            rng: 0x9E37_79B9_7F4A_7C15,
        }
    }

    /// xorshift64*: noise in -1.0..1.0.
    fn noise(&mut self) -> f32 {
        self.rng ^= self.rng >> 12;
        self.rng ^= self.rng << 25;
        self.rng ^= self.rng >> 27;
        let v = self.rng.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 40;
        (v as f32 / (1u64 << 24) as f32) * 2.0 - 1.0
    }

    fn sample(&mut self, t: f64) -> BandSnapshot {
        let n = self.info.channels.len();
        let mut powers = Vec::with_capacity(n);
        for ch in 0..n {
            let phase = ch as f64 * 0.7;
            // Posterior (temporal) channels get a stronger alpha swell.
            let alpha_gain = if ch == 0 || ch + 1 == n { 0.45 } else { 0.25 };
            let mut p = [0.0f32; 5];
            for band in Band::ALL {
                let i = band.index();
                let slow = ((t * 0.15 + phase + i as f64).sin() * 0.12) as f32;
                let mut v = BASELINE[i] + slow + self.noise() * 0.06;
                if band == Band::Alpha {
                    v += ((t * 0.3 + phase).sin().max(0.0_f64) as f32) * alpha_gain;
                }
                p[i] = v;
            }
            powers.push(p);
        }
        BandSnapshot { time: t, powers }
    }
}

impl BandSource for MockBandSource {
    fn device_info(&self) -> DeviceInfo {
        self.info.clone()
    }

    fn poll(&mut self, now: f64) -> Option<BandSnapshot> {
        if let Some(last) = self.last {
            if now - last < self.interval {
                return None;
            }
        }
        self.last = Some(now);
        Some(self.sample(now))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn produces_one_row_per_channel_and_throttles() {
        let mut src = MockBandSource::muse();
        let first = src.poll(0.0);
        assert_eq!(first.map(|s| s.powers.len()), Some(4));
        assert!(src.poll(0.05).is_none());
        assert!(src.poll(0.2).is_some());
    }

    #[test]
    fn relative_powers_sum_to_one() {
        let mut src = MockBandSource::muse();
        let Some(s) = src.poll(1.0) else { panic!("no snapshot") };
        let sum: f32 = Band::ALL.iter().filter_map(|b| s.relative(0, *b)).sum();
        assert!((sum - 1.0).abs() < 1e-4);
    }
}
