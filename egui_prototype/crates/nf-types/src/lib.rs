//! # nf-types (L0)
//!
//! Shared EEG domain types and the device traits that every data source
//! (simulator, Muse/Crown BLE, Android-supplied transport, replay) implements.
#![forbid(unsafe_code)]

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Classic EEG frequency bands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Band {
    Delta,
    Theta,
    Alpha,
    Beta,
    Gamma,
}

impl Band {
    pub const ALL: [Band; 5] = [Band::Delta, Band::Theta, Band::Alpha, Band::Beta, Band::Gamma];

    pub fn name(self) -> &'static str {
        match self {
            Band::Delta => "Delta",
            Band::Theta => "Theta",
            Band::Alpha => "Alpha",
            Band::Beta => "Beta",
            Band::Gamma => "Gamma",
        }
    }

    /// Frequency range in Hz (low inclusive, high exclusive).
    pub fn range_hz(self) -> (f32, f32) {
        match self {
            Band::Delta => (1.0, 4.0),
            Band::Theta => (4.0, 8.0),
            Band::Alpha => (8.0, 13.0),
            Band::Beta => (13.0, 30.0),
            Band::Gamma => (30.0, 44.0),
        }
    }

    pub fn index(self) -> usize {
        self as usize
    }
}

/// Absolute band power per channel at one point in time.
///
/// `powers[channel][band.index()]` is log10(µV²/Hz) (Muse convention,
/// roughly -1.0 ..= 2.0).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct BandSnapshot {
    /// Session time in seconds.
    pub time: f64,
    pub powers: Vec<[f32; 5]>,
}

impl BandSnapshot {
    pub fn power(&self, channel: usize, band: Band) -> Option<f32> {
        self.powers.get(channel).map(|p| p[band.index()])
    }

    /// Share of the channel total in linear units (0..=1).
    pub fn relative(&self, channel: usize, band: Band) -> Option<f32> {
        let p = self.powers.get(channel)?;
        let total: f32 = p.iter().map(|v| 10f32.powf(*v)).sum();
        if total <= 0.0 || !total.is_finite() {
            return None;
        }
        Some(10f32.powf(p[band.index()]) / total)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum DeviceKind {
    Muse,
    Crown,
}

/// Static description of a device (available or connected).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct DeviceInfo {
    /// Stable id, e.g. `sim:muse` or a BLE address.
    pub id: String,
    pub name: String,
    pub kind: DeviceKind,
    pub channels: Vec<String>,
    pub simulated: bool,
}

/// A connected data source. `poll` is called from `Session::tick` with the
/// session time; it must never block (WASM, UI thread).
pub trait BandSource: Send {
    fn info(&self) -> DeviceInfo;
    fn poll(&mut self, now: f64) -> Option<BandSnapshot>;
}

/// Something that can list and open devices: the simulator registry, a
/// btleplug scanner on desktop, or an Android wrapper that does the BLE scan
/// and transport via JNI and hands samples to Rust.
pub trait DeviceProvider: Send {
    /// Id prefix this provider owns, e.g. `sim` or `ble`.
    fn scheme(&self) -> &'static str;
    fn list(&self) -> Vec<DeviceInfo>;
    fn open(&mut self, id: &str) -> Result<Box<dyn BandSource>, String>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relative_sums_to_one() {
        let s = BandSnapshot { time: 0.0, powers: vec![[1.0, 0.8, 0.7, 0.3, -0.2]] };
        let sum: f32 = Band::ALL.iter().filter_map(|b| s.relative(0, *b)).sum();
        assert!((sum - 1.0).abs() < 1e-4);
        assert!(s.relative(3, Band::Alpha).is_none());
    }
}
