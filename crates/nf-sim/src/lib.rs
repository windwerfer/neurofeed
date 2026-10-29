//! # nf-sim (L1)
//!
//! Deterministic device simulators. Same `DeviceSource` interface as real
//! devices (raw µV packets at 256 Hz), so everything above the transport,
//! DSP included, is testable without hardware.
#![forbid(unsafe_code)]

use nf_types::{DeviceInfo, DeviceKind, DeviceProvider, DeviceSource, EegPacket};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::f64::consts::TAU;

/// Sample rate of both simulated headsets (Muse and Crown stream 256 Hz).
pub const SAMPLE_RATE_HZ: f64 = 256.0;
/// Samples per packet, as Muse BLE EEG notifications.
pub const SAMPLES_PER_PACKET: usize = 12;

/// Tunables, changeable at runtime via the `sim.configure` command.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SimConfig {
    pub seed: u64,
    /// Peak 10 Hz alpha amplitude in µV on the edge channels (inner ones get
    /// 55 %). A slow "eyes closed" swell modulates it between 30 % and 100 %.
    pub alpha_uv: f64,
    /// White-noise amplitude in µV (uniform ±).
    pub noise_uv: f64,
    /// Mains hum amplitude in µV (0 = none) and its frequency.
    pub mains_uv: f64,
    pub mains_hz: f64,
    /// Constant electrode offset in µV (raw Muse data sits far from 0).
    pub dc_uv: f64,
}

impl Default for SimConfig {
    fn default() -> Self {
        Self { seed: 0x9E37_79B9_7F4A_7C15, alpha_uv: 15.0, noise_uv: 1.0, mains_uv: 0.0, mains_hz: 50.0, dc_uv: 0.0 }
    }
}

/// Raw-sample simulator, ported from `rust/src/api/simulator.rs`
/// (`eeg_sample`: phase-shifted 10 Hz alpha + hash noise) with a 1/f-ish
/// background so every band has power, optional hum and DC offset, and a
/// seeded xorshift instead of time-hashed noise. Bands, PSD, features are
/// computed downstream by `nf-dsp`, exactly as for a real headset.
pub struct SimDevice {
    info: DeviceInfo,
    config: SimConfig,
    start: Option<f64>,
    next: u64,
    rng: u64,
}

/// Background: sines near every 1.5 Hz from 1.5 to ~44 Hz with amplitude
/// `6/sqrt(f)` µV, i.e. a 1/f power spectrum like resting EEG. Frequencies
/// are detuned (golden-ratio offsets) and phases quadratic (Schroeder) so
/// the sum is not a periodic pulse train.
const BACKGROUND_STEP_HZ: f64 = 1.5;
const BACKGROUND_COMPONENTS: usize = 29;

impl SimDevice {
    pub fn new(kind: DeviceKind, config: SimConfig) -> Self {
        Self { info: sim_info(kind), config, start: None, next: 0, rng: config.seed.max(1) }
    }

    /// xorshift64*: uniform in -1.0..1.0.
    fn noise(&mut self) -> f64 {
        self.rng ^= self.rng >> 12;
        self.rng ^= self.rng << 25;
        self.rng ^= self.rng >> 27;
        let v = self.rng.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 11;
        (v as f64 / (1u64 << 53) as f64) * 2.0 - 1.0
    }

    /// Deterministic sample of channel `ch` at device time `t` (s).
    pub fn sample(&mut self, t: f64, ch: usize) -> f64 {
        let n = self.info.channels.len();
        let c = &self.config;
        let phi = ch as f64 * std::f64::consts::PI / 2.5;
        let edge = if ch == 0 || ch + 1 == n { 1.0 } else { 0.55 };
        let swell = 0.65 + 0.35 * (TAU * t / 20.0 + ch as f64 * 0.7).sin();
        let alpha = c.alpha_uv * edge * swell * (TAU * 10.0 * t + phi).sin();
        let background: f64 = (1..=BACKGROUND_COMPONENTS)
            .map(|i| {
                let fi = i as f64;
                let hz = fi * BACKGROUND_STEP_HZ + 0.6 * ((fi * 0.618_034).fract() - 0.5);
                let schroeder = std::f64::consts::PI * fi * fi / BACKGROUND_COMPONENTS as f64;
                6.0 / hz.sqrt() * (TAU * hz * t + phi * fi + schroeder).sin()
            })
            .sum();
        let hum = c.mains_uv * (TAU * c.mains_hz * t).sin();
        c.dc_uv + alpha + background + hum + c.noise_uv * self.noise()
    }
}

impl DeviceSource for SimDevice {
    fn info(&self) -> DeviceInfo {
        self.info.clone()
    }

    /// Every whole packet whose last sample is due by `now`.
    fn poll(&mut self, now: f64) -> Vec<EegPacket> {
        let start = *self.start.get_or_insert(now);
        let due = ((now - start) * SAMPLE_RATE_HZ + 1e-6).floor().max(-1.0) as i64 + 1;
        let mut out = Vec::new();
        while (self.next + SAMPLES_PER_PACKET as u64) as i64 <= due {
            let first = self.next;
            for ch in 0..self.info.channels.len() {
                let samples = (0..SAMPLES_PER_PACKET as u64).map(|k| self.sample((first + k) as f64 / SAMPLE_RATE_HZ, ch) as f32).collect();
                let electrode = u16::try_from(ch).unwrap_or(u16::MAX);
                out.push(EegPacket { time: start + (first + 11) as f64 / SAMPLE_RATE_HZ, electrode, samples });
            }
            self.next += SAMPLES_PER_PACKET as u64;
        }
        out
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
        sample_rate_hz: SAMPLE_RATE_HZ,
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

    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let kind = match id {
            "sim:muse" => DeviceKind::Muse,
            "sim:crown" => DeviceKind::Crown,
            other => return Err(format!("unknown simulator `{other}`")),
        };
        Ok(Box::new(SimDevice::new(kind, self.config)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packets_are_timed_and_deterministic() {
        let mut a = SimDevice::new(DeviceKind::Muse, SimConfig::default());
        let mut b = SimDevice::new(DeviceKind::Muse, SimConfig::default());
        assert!(a.poll(0.0).is_empty());
        let pa = a.poll(1.0);
        b.poll(0.0);
        let split: Vec<_> = b.poll(0.5).into_iter().chain(b.poll(1.0)).collect();
        assert_eq!(pa, split);
        // 257 samples due → 21 whole packets × 4 channels.
        assert_eq!(pa.len(), 21 * 4);
        assert!(pa.iter().all(|p| p.samples.len() == SAMPLES_PER_PACKET && p.time <= 1.0));
        assert!(a.poll(1.0).is_empty());
    }

    #[test]
    fn crown_has_eight_channels() {
        let mut p = SimProvider::default();
        let src = p.open("sim:crown").ok();
        assert_eq!(src.map(|s| s.info().channels.len()), Some(8));
        assert!(p.open("sim:nope").is_err());
    }
}
