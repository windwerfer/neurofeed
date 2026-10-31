//! L1 neurofeedback engine math, ported from the Flutter-era Dart engine
//! (`lib/src/feedback/target_state.dart`, `reward_lane.dart`,
//! `guard_lane.dart`, `baseline_window.dart`, `calibration_runner.dart`).
//!
//! Everything is driven by **sample time** `t` (seconds), carried on each
//! [`Input`]; nothing here reads a clock. One [`Input`] per second goes in and
//! one [`Record`] per second comes out. Behaviour is pinned by golden fixtures
//! generated from the legacy Dart code (`tools/golden-dart` (removed; see tag `pre-rust-port`)). Four deliberate
//! fixes are documented in `docs/decisions.md` (2026-10-29, nf-feedback).

mod calibration;
mod engine;
pub mod protocol;
mod stats;

pub use calibration::{CalStage, Calibration, CalibrationKind, CalibrationResult};
pub use engine::Engine;
pub mod anchors;
pub use protocol::{builtin, protocol, Eyes, GuardSpec, Protocol, DEFAULT_PROTOCOL, GUARD_PERCENTILE};
pub use stats::{coefficient_of_variation, rolling_cvs, stability_output_percentile, Baseline};

use serde::{Deserialize, Serialize};

/// Pad quality (0–100) at or above which a pad counts as usable/green.
pub const SIGNAL_GOOD: f64 = 80.0;
/// Default baseline percentile for the reward threshold (≈60 % initial reward).
pub const DEFAULT_PERCENTILE: u8 = 40;
/// Default guard warning percentile.
pub const DEFAULT_GUARD_PERCENTILE: u8 = 75;
/// Success-rate window (seconds of sample time).
pub const EPOCH_WINDOW_S: f64 = 75.0;
/// Rolling window of recent samples for in-flight recalibration (seconds).
pub const RECENT_WINDOW_S: f64 = 90.0;
/// Adaptation runs every this many play seconds.
pub const ADAPT_INTERVAL_S: u32 = 30;
/// Success above this raises the threshold.
pub const HIGH_SUCCESS: f64 = 0.8;
/// Success below this lowers the threshold.
pub const LOW_SUCCESS: f64 = 0.4;
/// Adaptation ceiling: baseline mean + this many standard deviations.
pub const CEILING_SD: f64 = 1.5;
/// Guard warning chime cooldown (seconds).
pub const WARNING_COOLDOWN_S: f64 = 20.0;
/// Baseline window: valid seconds needed.
pub const BASELINE_VALID_S: u32 = 45;
/// Baseline window: maximum seconds before giving up with what we have.
pub const BASELINE_MAX_S: f64 = 60.0;
/// Staged calibration: artifact stage + eyes-open counting stage (seconds).
pub const STAGED_TIMED_S: u32 = 15 + 30;

/// Scalar reward feature computed from relative band power of usable pads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Feature {
    #[serde(rename = "band.atr")]
    Atr,
    #[serde(rename = "band.tar")]
    Tar,
    #[serde(rename = "band.btr")]
    Btr,
    #[serde(rename = "band.alpha")]
    Alpha,
    #[serde(rename = "band.theta")]
    Theta,
    #[serde(rename = "band.beta")]
    Beta,
}

/// Per-sample condition on relative band power; all must pass for reward.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "max", rename_all = "camelCase")]
pub enum Inhibit {
    BetaCeiling(f64),
    DeltaCeiling(f64),
}

/// Stability (`stabilityDowntrain`) parameters.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct StabilityConfig {
    /// Rolling window in clean samples (effective minimum 2).
    pub window: u32,
    /// 0..=0.5; in target when r ≤ 1 − difficulty.
    pub difficulty: f64,
}

impl Default for StabilityConfig {
    fn default() -> Self {
        Self { window: Self::DEFAULT_WINDOW, difficulty: Self::DEFAULT_DIFFICULTY }
    }
}

impl StabilityConfig {
    /// Legacy Dart `StabilityConfig` defaults and bounds (target_state.dart).
    pub const DEFAULT_WINDOW: u32 = 10;
    pub const MIN_WINDOW: u32 = 1;
    pub const MAX_WINDOW: u32 = 30;
    pub const DEFAULT_DIFFICULTY: f64 = 0.10;
    pub const MAX_DIFFICULTY: f64 = 0.50;
    /// Lowest threshold adaptation may reach.
    pub const MIN_THRESHOLD: f64 = 0.05;
    pub(crate) fn effective_window(&self) -> usize {
        (self.window.max(2)) as usize
    }
    pub(crate) fn initial_threshold(&self) -> f64 {
        1.0 - self.difficulty
    }
}

/// Drowsiness guard: warns while the guard value is above a threshold.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct GuardConfig {
    /// Baseline percentile for the warning threshold.
    pub percentile: u8,
    /// Mute (and withhold) reward while the warning is active.
    pub muffle: bool,
    /// What the guard reads (absolute delta or an AI head probability).
    #[serde(default)]
    pub source: GuardSource,
    /// `Some(p)` = fixed cut (AI probabilities) instead of the percentile.
    #[serde(default)]
    pub fixed: Option<f64>,
}

/// Guard value source.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GuardSource {
    /// `band.delta`: absolute delta power (opt-in fallback).
    #[default]
    BandDelta,
    /// `Input::ai`: P(drowsy) from the selected AI head.
    Ai,
}

/// Default fixed AI cut (legacy `defaultAiGuardFixedThreshold`, P > 0.50).
pub const AI_FIXED_THRESHOLD: f64 = 0.50;
/// Allowed fixed AI cut range (legacy clamp, 2 decimals).
pub const AI_FIXED_RANGE: (f64, f64) = (0.05, 0.95);

/// Engine configuration (resolved once from protocol + user settings).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Config {
    pub feature: Feature,
    pub percentile: u8,
    /// 0..=1: step size of the adaptation.
    pub responsiveness: f64,
    pub dynamic_adapt: bool,
    #[serde(default)]
    pub inhibit: Vec<Inhibit>,
    #[serde(default)]
    pub guard: Option<GuardConfig>,
    /// No reward lane at all (Sleep Guard): only the guard runs.
    #[serde(default)]
    pub guard_only: bool,
    /// `Some` = stability policy, `None` = percentile uptrain.
    #[serde(default)]
    pub stability: Option<StabilityConfig>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            feature: Feature::Atr,
            percentile: DEFAULT_PERCENTILE,
            responsiveness: 0.5,
            dynamic_adapt: true,
            inhibit: Vec::new(),
            guard: None,
            guard_only: false,
            stability: None,
        }
    }
}

/// Artifact flagged for this second (movement buffer already applied).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Artifact {
    Movement,
    Blink,
    Jaw,
}

/// Why a sample was not used for reward.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Dirty {
    Movement,
    Blink,
    Jaw,
    /// No usable pad.
    Pads,
}

/// Why an above-threshold sample was not rewarded.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HeldBack {
    Beta,
    Delta,
    Guard,
    /// No baseline threshold yet: never rewarded (fix: no 1.0 fallback).
    NoThreshold,
}

/// One second of input. `pads[i] = [delta, theta, alpha, beta, gamma]`
/// absolute band power; `quality[i]` 0–100.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Input {
    /// Sample time in seconds (session/active time; pauses excluded).
    pub t: f64,
    pub pads: Vec<[f64; 5]>,
    #[serde(rename = "q")]
    pub quality: Vec<f64>,
    #[serde(rename = "art", default)]
    pub artifact: Option<Artifact>,
    /// Fresh AI guard probability this second (`None` = no score).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ai: Option<f64>,
    /// Debug feature override (legacy FeatureOverride): replaces the
    /// protocol feature computed from `pads`; pad gating still applies.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feature: Option<f64>,
}

impl Input {
    /// The protocol feature this second (the override wins).
    pub fn feature_value(&self, rel: Option<&RelBands>, f: Feature) -> Option<f64> {
        rel?;
        self.feature.or_else(|| rel.and_then(|r| r.feature(f))).filter(|v| v.is_finite())
    }

    /// The guard value for `cfg` (absolute delta or AI probability).
    pub fn guard_value(&self, cfg: &GuardConfig) -> Option<f64> {
        match cfg.source {
            GuardSource::BandDelta => self.rel_bands().map(|r| r.abs_delta),
            GuardSource::Ai => self.ai,
        }
        .filter(|v| v.is_finite())
    }
}

/// Relative band power averaged over usable pads.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RelBands {
    pub delta: f64,
    pub theta: f64,
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
    /// Absolute mean delta of the same pads (guard `band.delta`).
    pub abs_delta: f64,
}

impl Input {
    /// Pads with quality ≥ [`SIGNAL_GOOD`]; the same set feeds the reward
    /// feature, the inhibit limits and the guard (fix: same pads).
    pub fn usable_pads(&self) -> impl Iterator<Item = &[f64; 5]> {
        self.pads.iter().zip(&self.quality).filter(|(_, q)| **q >= SIGNAL_GOOD).map(|(p, _)| p)
    }

    /// All pads green (calibration gate).
    pub fn all_green(&self) -> bool {
        self.quality.iter().all(|q| *q >= SIGNAL_GOOD)
    }

    /// Relative bands over usable pads, `None` when no pad is usable.
    pub fn rel_bands(&self) -> Option<RelBands> {
        let mut acc = [0.0; 5];
        let mut abs_delta = 0.0;
        let mut n = 0.0;
        let mut n_abs = 0.0;
        for p in self.usable_pads() {
            abs_delta += p[0];
            n_abs += 1.0;
            let total: f64 = p.iter().sum();
            if total <= 0.0 {
                continue;
            }
            for (a, v) in acc.iter_mut().zip(p) {
                *a += v / total;
            }
            n += 1.0;
        }
        if n == 0.0 {
            return None;
        }
        let [delta, theta, alpha, beta, gamma] = acc.map(|a| a / n);
        Some(RelBands { delta, theta, alpha, beta, gamma, abs_delta: abs_delta / n_abs })
    }
}

impl RelBands {
    /// Scalar value of `feature`, `None` on a zero denominator.
    pub fn feature(&self, feature: Feature) -> Option<f64> {
        let ratio = |num: f64, den: f64| if den <= 0.0 { None } else { Some(num / den) };
        match feature {
            Feature::Atr => ratio(self.alpha, self.theta),
            Feature::Tar => ratio(self.theta, self.alpha),
            Feature::Btr => ratio(self.beta, self.theta),
            Feature::Alpha => Some(self.alpha),
            Feature::Theta => Some(self.theta),
            Feature::Beta => Some(self.beta),
        }
    }
}

/// Threshold change made by an adaptation step.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct AdaptStep {
    pub from: Option<f64>,
    pub to: Option<f64>,
}

/// The single per-second result consumed by UI, audio, recording and MCP.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct Record {
    pub t: f64,
    /// A reward verdict/output was produced this second (false: no feature,
    /// stability warm-up, or dirty before any value).
    pub produced: bool,
    /// Native feature value (stability: fluctuation ratio r).
    #[serde(default)]
    pub native: Option<f64>,
    /// Output percentile 0–100 (drives the audio).
    #[serde(default)]
    pub pct: Option<f64>,
    #[serde(default)]
    pub thr: Option<f64>,
    #[serde(default)]
    pub thr_pct: Option<f64>,
    #[serde(default)]
    pub in_target: Option<bool>,
    #[serde(default)]
    pub held_back: Option<Vec<HeldBack>>,
    #[serde(default)]
    pub dirty: Option<Dirty>,
    /// Success rate over the epoch window, `None` until the window is full.
    #[serde(default)]
    pub success_rate: Option<f64>,
    /// Guard warning active (only with a guard).
    #[serde(default)]
    pub warn: Option<bool>,
    /// Warning chime fired this second.
    #[serde(default)]
    pub chime: Option<bool>,
    /// Reward audio muted by the guard.
    #[serde(default)]
    pub muted: Option<bool>,
    /// Guard value on its decision scale (0–100): fixed cut → P × 100,
    /// percentile → rank in the eyes-closed baseline. `None` without a value.
    #[serde(default)]
    pub guard_plot: Option<f64>,
    /// The warn line on the same scale: fixed cut × 100 or the warning percentile.
    #[serde(default)]
    pub guard_line: Option<f64>,
    #[serde(default)]
    pub adapt: Option<AdaptStep>,
}
