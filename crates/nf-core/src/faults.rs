//! Timed simulator faults (`sim.fault.add` / `sim.fault.clear`): each has a
//! kind, an optional duration and an optional channel subset, shows in
//! `app.status` / `signal.status`, and is injected into the raw device data
//! before anything else sees it, so the whole engine (pad quality, artifact
//! flags, trust, freshness, link) reacts as it would to a real headband.

use nf_types::{AccelPacket, DeviceInfo, EegPacket, PpgPacket};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::f64::consts::{PI, TAU};

/// Samples beyond this many µV are outside any EEG ADC range (Muse ≈ ±1 mV).
pub const OOB_UV: f32 = 2000.0;
/// At most this many faults at once.
pub const MAX_FAULTS: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum BadValue {
    Nan,
    Inf,
    /// 1e6 µV, far beyond any ADC.
    Rail,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum FaultKind {
    /// Accidental disconnect: no data, link lost. Optional auto-reconnect.
    Disconnect {
        /// Reconnect after this many seconds (default: stays until cleared
        /// or `duration_s` ends).
        #[serde(default)]
        reconnect_after_s: Option<f64>,
    },
    /// Too much movement: head nods on the IMU plus motion swings in EEG.
    Movement,
    /// An eye blink every 2 s (default: frontal pads).
    Blink,
    /// Jaw-clench EMG (default: temporal pads).
    Clench,
    /// EEG-like but clearly out-of-bounds noise; each second of each
    /// channel is clean with probability `clean_fraction`.
    Noise {
        #[serde(default = "half")]
        clean_fraction: f64,
    },
    /// Large spikes and DC drift (headband taken off).
    Spikes,
    /// Garbage, dropped and time-jittered packets.
    Glitch,
    /// Every 8th sample is NaN, ±inf or beyond the ADC range.
    OutOfRange { value: BadValue },
}

/// The fault kind as a plain tag (`sim.fault.add` takes its options flat).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum FaultTag {
    Disconnect,
    Movement,
    Blink,
    Clench,
    Noise,
    Spikes,
    Glitch,
    OutOfRange,
}

impl FaultKind {
    /// Build from the flat `sim.fault.add` params; options of other kinds are refused.
    pub fn build(
        tag: FaultTag,
        reconnect_after_s: Option<f64>,
        clean_fraction: Option<f64>,
        value: Option<BadValue>,
    ) -> Result<Self, String> {
        let only = |ok: bool, name: &str| if ok { Ok(()) } else { Err(format!("`{name}` does not apply to this kind")) };
        only(reconnect_after_s.is_none() || tag == FaultTag::Disconnect, "reconnect_after_s")?;
        only(clean_fraction.is_none() || tag == FaultTag::Noise, "clean_fraction")?;
        only(value.is_none() || tag == FaultTag::OutOfRange, "value")?;
        Ok(match tag {
            FaultTag::Disconnect => Self::Disconnect { reconnect_after_s },
            FaultTag::Movement => Self::Movement,
            FaultTag::Blink => Self::Blink,
            FaultTag::Clench => Self::Clench,
            FaultTag::Noise => Self::Noise { clean_fraction: clean_fraction.unwrap_or(0.5) },
            FaultTag::Spikes => Self::Spikes,
            FaultTag::Glitch => Self::Glitch,
            FaultTag::OutOfRange => Self::OutOfRange { value: value.unwrap_or(BadValue::Nan) },
        })
    }
}

fn half() -> f64 {
    0.5
}

/// One active fault.
#[derive(Debug, Clone, PartialEq, Serialize, JsonSchema)]
pub struct ActiveFault {
    pub id: u32,
    #[serde(flatten)]
    pub kind: FaultKind,
    /// Channel names (empty = the kind's default set or all).
    pub channels: Vec<String>,
    pub started: f64,
    /// Session time it ends (`None` = until cleared).
    pub until: Option<f64>,
    #[serde(skip)]
    pub idx: Vec<usize>,
}

impl ActiveFault {
    /// Session time the fault stops (duration or auto-reconnect).
    pub fn end(&self) -> Option<f64> {
        let rec = match self.kind {
            FaultKind::Disconnect { reconnect_after_s: Some(s) } => Some(self.started + s),
            _ => None,
        };
        match (self.until, rec) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }
    fn hits(&self, dev: &DeviceInfo, e: u16, default: &[&str]) -> bool {
        let e = usize::from(e);
        if !self.idx.is_empty() {
            return self.idx.contains(&e);
        }
        default.is_empty() || dev.channels.get(e).is_some_and(|c| default.contains(&c.as_str()))
    }
}

/// Deterministic hash → [0, 1).
fn unit(a: u64, b: u64, c: u64) -> f64 {
    let mut z = a.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ b.rotate_left(21) ^ c.rotate_left(42);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    ((z ^ (z >> 31)) >> 11) as f64 / (1u64 << 53) as f64
}

const FRONTAL: [&str; 4] = ["AF7", "AF8", "F5", "F6"];
const TEMPORAL: [&str; 4] = ["TP9", "TP10", "CP3", "CP4"];

/// Inject every fault. Returns true while a disconnect is active.
pub fn inject(
    faults: &[ActiveFault],
    dev: &DeviceInfo,
    eeg: &mut Vec<EegPacket>,
    ppg: &mut Vec<PpgPacket>,
    accel: &mut Vec<AccelPacket>,
) -> bool {
    let rate = dev.sample_rate_hz;
    let mut down = false;
    for f in faults {
        match &f.kind {
            FaultKind::Disconnect { .. } => down = true,
            FaultKind::Movement => movement(f, dev, eeg, accel),
            FaultKind::Glitch => glitch(f, eeg),
            kind => {
                for p in eeg.iter_mut() {
                    let def: &[&str] = match kind {
                        FaultKind::Blink => &FRONTAL,
                        FaultKind::Clench => &TEMPORAL,
                        _ => &[],
                    };
                    if f.hits(dev, p.electrode, def) {
                        per_sample(f, kind, rate, p);
                    }
                }
            }
        }
    }
    if down {
        eeg.clear();
        ppg.clear();
        accel.clear();
    }
    down
}

fn per_sample(f: &ActiveFault, kind: &FaultKind, rate: f64, p: &mut EegPacket) {
    let n = p.samples.len();
    for (k, x) in p.samples.iter_mut().enumerate() {
        let t = p.time - (n - 1 - k) as f64 / rate;
        let add = match kind {
            FaultKind::Blink => {
                let i = ((t.rem_euclid(2.0) - 0.38) * rate).round();
                if (0.0..28.0).contains(&i) {
                    300.0 * (PI * i / 28.0).sin()
                } else {
                    0.0
                }
            }
            FaultKind::Clench => 20.0 * (TAU * 37.0 * t).sin(),
            FaultKind::Noise { clean_fraction } => noise(f.id, p.electrode, t, *clean_fraction),
            FaultKind::Spikes => {
                let ph = (t * 5.0).fract();
                let spike = if ph < 0.012 { 1200.0 * if (t * 5.0) as i64 % 2 == 0 { 1.0 } else { -1.0 } } else { 0.0 };
                spike + 400.0 * (TAU * 0.2 * t).sin()
            }
            FaultKind::OutOfRange { value } => {
                if (t * rate).round() as i64 % 8 == 0 {
                    *x = match value {
                        BadValue::Nan => f32::NAN,
                        BadValue::Inf => {
                            if k % 2 == 0 {
                                f32::INFINITY
                            } else {
                                f32::NEG_INFINITY
                            }
                        }
                        BadValue::Rail => 1e6,
                    };
                }
                0.0
            }
            _ => 0.0,
        };
        *x += add as f32;
    }
}

/// Pseudo-EEG at ~10× normal amplitude (5 rhythms, per-second random
/// phases), or nothing in a clean second.
fn noise(id: u32, ch: u16, t: f64, clean: f64) -> f64 {
    let sec = t.floor() as i64 as u64;
    if unit(u64::from(id), u64::from(ch), sec) < clean {
        return 0.0;
    }
    [(2.0, 120.0), (6.0, 90.0), (10.0, 110.0), (20.0, 60.0), (35.0, 40.0)]
        .iter()
        .enumerate()
        .map(|(i, (hz, uv))| uv * (TAU * hz * t + TAU * unit(sec, u64::from(ch), i as u64)).sin())
        .sum()
}

fn movement(f: &ActiveFault, dev: &DeviceInfo, eeg: &mut [EegPacket], accel: &mut [AccelPacket]) {
    let rate = dev.accel_rate_hz.unwrap_or(52.0);
    for p in accel.iter_mut() {
        let n = p.samples.len();
        for (k, s) in p.samples.iter_mut().enumerate() {
            let t = p.time - (n - 1 - k) as f64 / rate;
            s[0] += (0.4 * (TAU * 1.3 * t).sin()) as f32;
            s[2] += (0.6 * (TAU * 2.0 * t).sin()) as f32;
        }
    }
    for p in eeg.iter_mut().filter(|p| f.hits(dev, p.electrode, &[])) {
        let n = p.samples.len();
        for (k, x) in p.samples.iter_mut().enumerate() {
            let t = p.time - (n - 1 - k) as f64 / dev.sample_rate_hz;
            *x += (150.0 * (TAU * 2.0 * t).sin() + 80.0 * (TAU * 0.7 * t).sin()) as f32;
        }
    }
}

/// Drop 25 % of packets, jitter 25 % by up to ±30 ms, fill 20 % of the
/// remaining samples with garbage.
fn glitch(f: &ActiveFault, eeg: &mut Vec<EegPacket>) {
    let key = |p: &EegPacket| (p.time.to_bits(), u64::from(p.electrode));
    let hit = |p: &EegPacket| f.idx.is_empty() || f.idx.contains(&usize::from(p.electrode));
    eeg.retain(|p| !hit(p) || unit(u64::from(f.id), key(p).0, key(p).1) >= 0.25);
    for p in eeg.iter_mut().filter(|p| hit(p)) {
        let (a, b) = key(p);
        let u = unit(u64::from(f.id) + 1, a, b);
        if u < 0.25 {
            p.time += (u * 4.0 - 0.5) * 0.06;
        }
        for (k, x) in p.samples.iter_mut().enumerate() {
            let g = unit(a, b, k as u64);
            if g < 0.2 {
                *x = ((g * 5.0 - 0.5) * 6000.0) as f32;
            }
        }
    }
}

/// Replace non-finite and beyond-ADC samples with 0 (so filters stay
/// sane) and return the channels that had any.
pub fn sanitize(p: &mut EegPacket) -> bool {
    let mut any = false;
    for x in &mut p.samples {
        if !x.is_finite() || x.abs() > OOB_UV {
            *x = 0.0;
            any = true;
        }
    }
    any
}
