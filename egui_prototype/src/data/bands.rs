//! Frequency bands and per-channel band power snapshots.

/// Classic EEG frequency bands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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
/// `powers[channel][band.index()]` is in log10(µV²/Hz), like the Muse
/// "absolute band power" convention (roughly -1.0 ..= 2.0).
#[derive(Debug, Clone, PartialEq)]
pub struct BandSnapshot {
    /// Seconds since app start.
    pub time: f64,
    pub powers: Vec<[f32; 5]>,
}

impl BandSnapshot {
    /// Power for one channel and band, `None` if the channel does not exist.
    pub fn power(&self, channel: usize, band: Band) -> Option<f32> {
        self.powers.get(channel).map(|p| p[band.index()])
    }

    /// Relative power (share of the channel total in linear units, 0..=1).
    pub fn relative(&self, channel: usize, band: Band) -> Option<f32> {
        let p = self.powers.get(channel)?;
        let linear: Vec<f32> = p.iter().map(|v| 10f32.powf(*v)).collect();
        let total: f32 = linear.iter().sum();
        if total <= 0.0 || !total.is_finite() {
            return None;
        }
        Some(linear[band.index()] / total)
    }
}
