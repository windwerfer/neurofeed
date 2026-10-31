//! Audio settings and the per-moment cue (pure data).

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// How reward is sonified while training.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum RewardOutput {
    /// A singing bowl on each rising edge into target.
    #[default]
    Chime,
    /// Five rain stages: heavy far from target, near-silent on target.
    Rain,
    /// Binaural beat whose volume follows the reward percentile.
    Binaural,
    /// Your music; a low-pass opens as the percentile rises.
    Music,
    None,
}

/// Bed that plays during calibration and training.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Background {
    #[default]
    Drone,
    DroneLoop,
    Rain,
    Binaural,
    None,
}

/// Sound of the drowsiness guard warning.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum GuardSound {
    #[default]
    SoftBowl,
    Chime,
    /// One of three cough clips, rotating.
    Cough,
    /// Continuous while warning; ramps up over the first minute.
    Alarm,
    None,
}

/// Goal-based binaural presets: L = carrier, R = carrier + beat.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum BinauralPreset {
    DeepSleep,
    ThetaCalm,
    #[default]
    AlphaFlow,
    FocusBeta,
    PeakInsight,
}

impl BinauralPreset {
    pub const ALL: [BinauralPreset; 5] = [Self::DeepSleep, Self::ThetaCalm, Self::AlphaFlow, Self::FocusBeta, Self::PeakInsight];

    /// (label, explanation, beat Hz, carrier Hz).
    pub fn spec(self) -> (&'static str, &'static str, f64, f64) {
        match self {
            Self::DeepSleep => ("Deep Sleep & Recovery", "Slow-wave (delta) entrainment: 2.5 Hz beats.", 2.5, 120.0),
            Self::ThetaCalm => ("Theta Calm", "Deep relaxation and imagery: 6 Hz theta beats.", 6.0, 150.0),
            Self::AlphaFlow => ("Alpha Flow & Calm", "Relaxed alertness: 10 Hz alpha beats.", 10.0, 200.0),
            Self::FocusBeta => ("Focus & Sharpness", "Active problem solving: 15 Hz beta beats.", 15.0, 250.0),
            Self::PeakInsight => ("Peak Insight", "High cognitive processing: 40 Hz gamma beats.", 40.0, 300.0),
        }
    }

    pub fn label(self) -> &'static str {
        self.spec().0
    }
}

/// User audio settings (volumes 0..=1).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct AudioSettings {
    pub reward: RewardOutput,
    pub background: Background,
    pub guard: GuardSound,
    pub master: f64,
    pub feedback: f64,
    pub background_volume: f64,
    pub guard_volume: f64,
    pub binaural: BinauralPreset,
    /// Music low-pass range (Hz) mapped from percentile 0..100.
    pub music_min_hz: f64,
    pub music_max_hz: f64,
    /// Map 100 - pct instead (filter closes as you succeed).
    pub music_invert: bool,
    pub muted: bool,
}

impl Default for AudioSettings {
    fn default() -> Self {
        Self {
            reward: RewardOutput::Chime,
            background: Background::Drone,
            guard: GuardSound::SoftBowl,
            master: 0.8,
            feedback: 1.0,
            background_volume: 0.5,
            guard_volume: 1.0,
            binaural: BinauralPreset::AlphaFlow,
            music_min_hz: 200.0,
            music_max_hz: 8000.0,
            music_invert: false,
            muted: false,
        }
    }
}

impl AudioSettings {
    /// Clamp volumes and the music range into their legal ranges.
    pub fn sanitized(mut self) -> Self {
        for v in [&mut self.master, &mut self.feedback, &mut self.background_volume, &mut self.guard_volume] {
            *v = if v.is_finite() { v.clamp(0.0, 1.0) } else { 0.0 };
        }
        self.music_min_hz = self.music_min_hz.clamp(50.0, 8000.0);
        self.music_max_hz = self.music_max_hz.clamp(200.0, 16000.0).max(self.music_min_hz + 50.0);
        self
    }
}

/// What should sound now.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Cue {
    /// Background bed on (calibration and training).
    pub background_on: bool,
    /// Reward output on (training, not paused).
    pub reward_on: bool,
    /// Live reward percentile 0..=100 (`None`: no value yet).
    pub pct: Option<f64>,
    /// Guard muffles the reward.
    pub muffle: bool,
    /// Guard warning active.
    pub warning: bool,
    pub settings: AudioSettings,
}

impl Cue {
    pub fn silent(settings: AudioSettings) -> Self {
        Self { background_on: false, reward_on: false, pct: None, muffle: false, warning: false, settings }
    }
}
