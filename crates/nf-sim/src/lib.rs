//! # nf-sim (L1)
//!
//! Deterministic device simulators. Same `BandSource` interface as real
//! devices, so everything above the transport is testable without hardware.
//! Today they emit band powers directly; porting the raw-sample simulator
//! from `rust/src/api/simulator.rs` (so DSP runs too) is migration phase 2.
#![forbid(unsafe_code)]

use nf_types::{Band, BandSnapshot, BandSource, DeviceInfo, DeviceKind, DeviceProvider};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Baseline log power per band (1/f falloff).
const BASELINE: [f32; 5] = [1.2, 0.8, 0.7, 0.3, -0.2];

/// Tunables, changeable at runtime via the `sim_configure` command.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SimConfig {
    pub seed: u64,
    /// Peak extra alpha (log units) of the slow eyes-closed swell.
    pub alpha_gain: f32,
    /// Noise amplitude (log units).
    pub noise: f32,
    /// Snapshot rate in Hz.
    pub rate_hz: f64,
}

impl Default for SimConfig {
    fn default() -> Self {
        Self { seed: 0x9E37_79B9_7F4A_7C15, alpha_gain: 0.45, noise: 0.06, rate_hz: 10.0 }
    }
}

pub struct SimBandSource {
    info: DeviceInfo,
    config: SimConfig,
    last: Option<f64>,
    rng: u64,
}

impl SimBandSource {
    pub fn new(kind: DeviceKind, config: SimConfig) -> Self {
        Self { info: sim_info(kind), config, last: None, rng: config.seed.max(1) }
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
            // Edge channels (temporal/posterior) get the strongest alpha.
            let alpha_gain = if ch == 0 || ch + 1 == n { self.config.alpha_gain } else { self.config.alpha_gain * 0.55 };
            let mut p = [0.0f32; 5];
            for band in Band::ALL {
                let i = band.index();
                let slow = ((t * 0.15 + phase + i as f64).sin() * 0.12) as f32;
                let mut v = BASELINE[i] + slow + self.noise() * self.config.noise;
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

impl BandSource for SimBandSource {
    fn info(&self) -> DeviceInfo {
        self.info.clone()
    }

    fn poll(&mut self, now: f64) -> Option<BandSnapshot> {
        let interval = 1.0 / self.config.rate_hz.max(0.1);
        if let Some(last) = self.last {
            if now - last < interval - 1e-9 {
                return None;
            }
        }
        self.last = Some(now);
        Some(self.sample(now))
    }
}

pub fn sim_info(kind: DeviceKind) -> DeviceInfo {
    let (id, name, channels): (&str, &str, &[&str]) = match kind {
        DeviceKind::Muse => ("sim:muse", "Muse S (simulated)", &["TP9", "AF7", "AF8", "TP10"]),
        DeviceKind::Crown => ("sim:crown", "Crown (simulated)", &["CP3", "C3", "F5", "PO3", "PO4", "F6", "C4", "CP4"]),
    };
    DeviceInfo {
        id: id.to_owned(),
        name: name.to_owned(),
        kind,
        channels: channels.iter().map(|c| (*c).to_owned()).collect(),
        simulated: true,
    }
}

/// Provider for `sim:*` ids.
#[derive(Default)]
pub struct SimProvider {
    pub config: SimConfig,
}

impl DeviceProvider for SimProvider {
    fn scheme(&self) -> &'static str {
        "sim"
    }

    fn list(&self) -> Vec<DeviceInfo> {
        vec![sim_info(DeviceKind::Muse), sim_info(DeviceKind::Crown)]
    }

    fn open(&mut self, id: &str) -> Result<Box<dyn BandSource>, String> {
        let kind = match id {
            "sim:muse" => DeviceKind::Muse,
            "sim:crown" => DeviceKind::Crown,
            other => return Err(format!("unknown simulator `{other}`")),
        };
        Ok(Box::new(SimBandSource::new(kind, self.config)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn throttles_and_is_deterministic() {
        let mut a = SimBandSource::new(DeviceKind::Muse, SimConfig::default());
        let mut b = SimBandSource::new(DeviceKind::Muse, SimConfig::default());
        let s = a.poll(0.0);
        assert_eq!(s, b.poll(0.0));
        assert_eq!(s.map(|s| s.powers.len()), Some(4));
        assert!(a.poll(0.05).is_none());
        assert!(a.poll(0.1).is_some());
    }

    #[test]
    fn crown_has_eight_channels() {
        let mut p = SimProvider::default();
        let src = p.open("sim:crown").map(|s| s.info().channels.len());
        assert_eq!(src, Ok(8));
        assert!(p.open("sim:nope").is_err());
    }
}
