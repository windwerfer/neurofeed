//! # nf-sim (L1)
//!
//! Deterministic device simulators. Same `DeviceSource` interface as real
//! devices (raw µV packets at 256 Hz), so everything above the transport,
//! DSP included, is testable without hardware.
#![forbid(unsafe_code)]

use nf_types::{AccelPacket, DeviceInfo, DeviceKind, DeviceProvider, DeviceSource, EegPacket, PpgPacket};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::f64::consts::TAU;

/// Sample rate of both simulated headsets (Muse and Crown stream 256 Hz).
pub const SAMPLE_RATE_HZ: f64 = 256.0;
/// Samples per packet, as Muse BLE EEG notifications.
pub const SAMPLES_PER_PACKET: usize = 12;
/// PPG rate and packet size of the Muse S / Athena optics (legacy `PPG_HZ`).
pub const PPG_RATE_HZ: f64 = 64.0;
pub const PPG_SAMPLES_PER_PACKET: usize = 6;
/// Accelerometer (Muse: 52 Hz, 3 samples per packet).
pub const ACCEL_RATE_HZ: f64 = 52.0;
pub const ACCEL_SAMPLES_PER_PACKET: usize = 3;
/// PPG channel names (legacy channel 0 ambient, 1 infrared, 2 red).
pub const PPG_CHANNELS: [&str; 3] = ["ambient", "infrared", "red"];
/// Optical DC levels and IR pulse amplitude (legacy `ppg_sample`).
const IR_DC: f64 = 200_000.0;
const RED_DC: f64 = 180_000.0;
const IR_AC: f64 = 8_000.0;
const AMBIENT_DC: f64 = 800.0;

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
    /// Mean heart rate (PPG devices), bpm.
    #[serde(default = "default_hr")]
    pub hr_bpm: f64,
    /// Oxygen saturation the optics encode via the red/IR ratio, %.
    #[serde(default = "default_spo2")]
    pub spo2_pct: f64,
    /// Heart-rate variability: respiratory (0.25 Hz) modulation of the
    /// beat interval, ± ms, plus seeded jitter of a fifth of that.
    #[serde(default = "default_hrv")]
    pub hrv_ms: f64,
}

fn default_hr() -> f64 {
    60.0
}
fn default_spo2() -> f64 {
    97.0
}
fn default_hrv() -> f64 {
    40.0
}

impl Default for SimConfig {
    fn default() -> Self {
        Self {
            seed: 0x9E37_79B9_7F4A_7C15,
            alpha_uv: 15.0,
            noise_uv: 1.0,
            mains_uv: 0.0,
            mains_hz: 50.0,
            dc_uv: 0.0,
            hr_bpm: 60.0,
            spo2_pct: 97.0,
            hrv_ms: 40.0,
        }
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
    ppg_next: u64,
    accel_next: u64,
    /// Upcoming beat onsets (device seconds), oldest first.
    beats: Vec<f64>,
    beat_rng: u64,
    /// Whole seconds of Crown quality already sent.
    quality_sent: u64,
}

/// Background: sines near every 1.5 Hz from 1.5 to ~44 Hz with amplitude
/// `6/sqrt(f)` µV, i.e. a 1/f power spectrum like resting EEG. Frequencies
/// are detuned (golden-ratio offsets) and phases quadratic (Schroeder) so
/// the sum is not a periodic pulse train.
const BACKGROUND_STEP_HZ: f64 = 1.5;
const BACKGROUND_COMPONENTS: usize = 29;

impl SimDevice {
    pub fn new(kind: DeviceKind, config: SimConfig) -> Self {
        Self::with_info(sim_info(kind), config)
    }

    pub fn with_info(info: DeviceInfo, config: SimConfig) -> Self {
        let beat_rng = (config.seed ^ 0xD1B5_4A32_D192_ED03).max(1);
        Self {
            info,
            config,
            start: None,
            next: 0,
            rng: config.seed.max(1),
            ppg_next: 0,
            accel_next: 0,
            beats: vec![0.2],
            beat_rng,
            quality_sent: 0,
        }
    }

    /// Normalised pulse at `t` (device s): systolic peak (1.0 at 0.12 s
    /// after onset) plus a dicrotic shoulder; beat intervals follow
    /// `hr_bpm` with respiratory HRV and seeded jitter.
    pub fn pulse(&mut self, t: f64) -> f64 {
        let mean_rr = 60.0 / self.config.hr_bpm.clamp(20.0, 250.0);
        let hrv = self.config.hrv_ms / 1000.0;
        while self.beats.last().is_some_and(|&b| b < t + 1.0) {
            let last = self.beats.last().copied().unwrap_or(0.0);
            self.beat_rng ^= self.beat_rng << 13;
            self.beat_rng ^= self.beat_rng >> 7;
            self.beat_rng ^= self.beat_rng << 17;
            let jitter = ((self.beat_rng >> 11) as f64 / (1u64 << 53) as f64 - 0.5) * 0.4 * hrv;
            let rr = (mean_rr + hrv * (TAU * 0.25 * last).sin() + jitter).max(0.25);
            self.beats.push(last + rr);
        }
        let keep = self.beats.iter().position(|&b| b > t - 2.0).unwrap_or(0).saturating_sub(1);
        self.beats.drain(..keep);
        self.beats
            .iter()
            .filter(|&&b| b <= t)
            .map(|&b| {
                let p = t - b;
                (-((p - 0.12) / 0.06).powi(2)).exp() + 0.3 * (-((p - 0.35) / 0.1).powi(2)).exp()
            })
            .sum()
    }

    /// Optical sample of PPG channel `ch` at `t`. Red AC is scaled so the
    /// ratio of ratios gives `spo2_pct` (SpO2 = 110 - 25 R).
    pub fn ppg_sample(&mut self, t: f64, ch: usize) -> f64 {
        let pulse = self.pulse(t);
        let r = (110.0 - self.config.spo2_pct) / 25.0;
        match ch {
            0 => AMBIENT_DC + 15.0 * pulse,
            1 => IR_DC + IR_AC * pulse,
            2 => RED_DC + r * (IR_AC / IR_DC) * RED_DC * pulse,
            _ => 0.0,
        }
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
    /// Head at rest: gravity on z plus a little sensor noise.
    fn poll_accel(&mut self, now: f64) -> Vec<AccelPacket> {
        let (Some(start), Some(rate)) = (self.start, self.info.accel_rate_hz) else { return Vec::new() };
        let due = ((now - start) * rate + 1e-6).floor().max(-1.0) as i64 + 1;
        let mut out = Vec::new();
        while (self.accel_next + ACCEL_SAMPLES_PER_PACKET as u64) as i64 <= due {
            let first = self.accel_next;
            // Own deterministic jitter so the EEG noise stream is unchanged.
            let samples = (first..first + ACCEL_SAMPLES_PER_PACKET as u64)
                .map(|n| {
                    let p = n as f64 * 2.399;
                    [(0.002 * p.sin()) as f32, (0.002 * (1.7 * p).cos()) as f32, 1.0]
                })
                .collect();
            out.push(AccelPacket { time: start + (first + ACCEL_SAMPLES_PER_PACKET as u64 - 1) as f64 / rate, samples });
            self.accel_next += ACCEL_SAMPLES_PER_PACKET as u64;
        }
        out
    }

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
            // AUX: a slow 1 Hz, 40 µV sine (no RNG, so EEG noise is unchanged).
            let n = self.info.channels.len();
            for k in 0..self.info.aux_channels.len() {
                let samples =
                    (0..SAMPLES_PER_PACKET as u64).map(|i| (40.0 * (TAU * (first + i) as f64 / SAMPLE_RATE_HZ).sin()) as f32).collect();
                let electrode = u16::try_from(n + k).unwrap_or(u16::MAX);
                out.push(EegPacket { time: start + (first + 11) as f64 / SAMPLE_RATE_HZ, electrode, samples });
            }
            self.next += SAMPLES_PER_PACKET as u64;
        }
        out
    }

    /// Simulated Crown: a per-pad `signalQuality` of 0.9 once per second.
    fn poll_quality(&mut self, now: f64) -> Vec<Vec<f32>> {
        let Some(start) = self.start.filter(|_| self.info.kind == DeviceKind::Crown) else { return Vec::new() };
        let sec = (now - start).floor().max(0.0) as u64;
        let n = sec.saturating_sub(self.quality_sent);
        self.quality_sent = sec;
        vec![vec![0.9; self.info.channels.len()]; usize::try_from(n.min(2)).unwrap_or(0)]
    }

    fn poll_ppg(&mut self, now: f64) -> Vec<PpgPacket> {
        let (Some(start), Some(rate)) = (self.start, self.info.ppg_rate_hz) else { return Vec::new() };
        let due = ((now - start) * rate + 1e-6).floor().max(-1.0) as i64 + 1;
        let mut out = Vec::new();
        while (self.ppg_next + PPG_SAMPLES_PER_PACKET as u64) as i64 <= due {
            let first = self.ppg_next;
            // Samples in time order, then split per channel (pulse() walks beats forward).
            let rows: Vec<Vec<f32>> = (0..PPG_SAMPLES_PER_PACKET as u64)
                .map(|k| {
                    let t = (first + k) as f64 / rate;
                    (0..self.info.ppg_channels.len()).map(|ch| self.ppg_sample(t, ch) as f32).collect()
                })
                .collect();
            for ch in 0..self.info.ppg_channels.len() {
                out.push(PpgPacket {
                    time: start + (first + PPG_SAMPLES_PER_PACKET as u64 - 1) as f64 / rate,
                    channel: u16::try_from(ch).unwrap_or(u16::MAX),
                    samples: rows.iter().map(|r| r[ch]).collect(),
                });
            }
            self.ppg_next += PPG_SAMPLES_PER_PACKET as u64;
        }
        out
    }
}

/// Simulator ids. `sim:muse` is kept as an alias of `sim:muse_s`.
pub const SIM_IDS: [&str; 4] = ["sim:muse_s", "sim:muse2", "sim:athena", "sim:crown"];

/// Descriptor for a simulator id (aliases resolved), or `None`.
pub fn sim_info_for(id: &str) -> Option<DeviceInfo> {
    let mut info = match id {
        "sim:muse_s" | "sim:muse" => sim_info(DeviceKind::Muse),
        "sim:muse2" => {
            let mut i = sim_info(DeviceKind::Muse);
            i.id = "sim:muse2".into();
            i.name = "Muse 2 (simulated)".into();
            i
        }
        "sim:athena" => {
            // Same EEG montage, no PPG: Athena optics (and AUX) come later
            // in their own patch set.
            let mut i = sim_info(DeviceKind::Muse);
            i.id = "sim:athena".into();
            i.name = "Muse S Athena (simulated)".into();
            i.ppg_channels.clear();
            i.ppg_rate_hz = None;
            i
        }
        "sim:crown" => sim_info(DeviceKind::Crown),
        _ => return None,
    };
    if id == "sim:muse" {
        info.id = "sim:muse_s".into();
    }
    Some(info)
}

pub fn sim_info(kind: DeviceKind) -> DeviceInfo {
    let (id, name, channels): (&str, &str, &[&str]) = match kind {
        DeviceKind::Muse => ("sim:muse_s", "Muse S (simulated)", &["TP9", "AF7", "AF8", "TP10"]),
        DeviceKind::Crown => ("sim:crown", "Crown (simulated)", &["CP3", "C3", "F5", "PO3", "PO4", "F6", "C4", "CP4"]),
    };
    DeviceInfo {
        id: id.to_owned(),
        name: name.to_owned(),
        kind,
        channels: channels.iter().map(|c| (*c).to_owned()).collect(),
        sample_rate_hz: SAMPLE_RATE_HZ,
        simulated: true,
        ppg_channels: if kind == DeviceKind::Muse { PPG_CHANNELS.iter().map(|c| (*c).to_owned()).collect() } else { Vec::new() },
        ppg_rate_hz: (kind == DeviceKind::Muse).then_some(PPG_RATE_HZ),
        accel_rate_hz: Some(ACCEL_RATE_HZ),
        aux_channels: if kind == DeviceKind::Muse { vec!["AUX1".into()] } else { Vec::new() },
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
        SIM_IDS.iter().filter_map(|id| sim_info_for(id)).collect()
    }

    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let info = sim_info_for(id).ok_or_else(|| format!("unknown simulator `{id}`; have {}", SIM_IDS.join(", ")))?;
        Ok(Box::new(SimDevice::with_info(info, self.config)))
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
        assert_eq!(pa.len(), 21 * 5, "4 EEG + AUX1");
        assert!(pa.iter().all(|p| p.samples.len() == SAMPLES_PER_PACKET && p.time <= 1.0));
        assert!(a.poll(1.0).is_empty());
    }

    #[test]
    fn crown_has_eight_channels() {
        let mut p = SimProvider::default();
        let src = p.open("sim:crown").ok();
        assert_eq!(src.map(|s| s.info().channels.len()), Some(8));
        assert!(p.open("sim:nope").is_err());
        assert_eq!(p.open("sim:muse").ok().map(|s| s.info().id), Some("sim:muse_s".into()));
        assert!(p.open("sim:crown").ok().is_some_and(|s| !s.info().has_ppg()));
        assert!(p.open("sim:athena").ok().is_some_and(|s| !s.info().has_ppg()));
        assert!(p.open("sim:muse2").ok().is_some_and(|s| s.info().has_ppg()));
    }

    #[test]
    fn ppg_heart_rate_and_spo2_round_trip_through_dsp() {
        for (id, hr, spo2) in [("sim:muse_s", 60.0, 97.0), ("sim:muse2", 90.0, 92.0)] {
            let cfg = SimConfig { hr_bpm: hr, spo2_pct: spo2, ..SimConfig::default() };
            let mut p = SimProvider { config: cfg };
            let Ok(mut d) = p.open(id) else { panic!("{id}") };
            d.poll(0.0);
            let mut ch = [Vec::new(), Vec::new(), Vec::new()];
            d.poll(10.0);
            for pk in d.poll_ppg(10.0) {
                ch[usize::from(pk.channel)].extend(pk.samples.iter().map(|&x| f64::from(x)));
            }
            assert_eq!(ch[1].len(), 636, "64 Hz, whole packets of 6");
            let (bpm, conf) = nf_dsp::heart_rate(&ch[1], PPG_RATE_HZ).unwrap_or_default();
            assert!((bpm - hr).abs() < 3.0 && conf > 0.8, "{id}: {bpm} {conf}");
            let (s, _) = nf_dsp::spo2(&ch[1], &ch[2], PPG_RATE_HZ).unwrap_or_default();
            assert!((s - spo2).abs() < 1.0, "{id}: {s}");
        }
    }
}
