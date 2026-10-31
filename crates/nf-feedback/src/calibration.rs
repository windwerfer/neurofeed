//! Baseline calibration: timed stages, then a window that needs
//! [`BASELINE_VALID_S`] clean, all-green seconds within [`BASELINE_MAX_S`].

use crate::{Config, Input, BASELINE_MAX_S, BASELINE_VALID_S, STAGED_TIMED_S};
use serde::{Deserialize, Serialize};

/// Calibration recipe.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CalibrationKind {
    /// One baseline window.
    Single,
    /// Artifacts (15 s) + eyes-open counting (30 s), not collected, then the
    /// eyes-closed baseline window.
    Staged,
}

/// Where a calibration is (staged: artifacts 15 s, eyes open 30 s, eyes closed).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CalStage {
    Artifacts,
    EyesOpen,
    EyesClosed,
}

/// Outcome of a finished calibration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CalibrationResult {
    /// Inputs consumed (the input that found the window already over is not).
    pub consumed: usize,
    pub valid_seconds: u32,
    pub wall_seconds: u32,
    /// Raw reward-feature samples (clean, all green).
    pub reward_samples: Vec<f64>,
    /// Raw guard samples (`band.delta` or AI probability; eyes closed, clean, all green).
    pub guard_samples: Vec<f64>,
}

/// Streaming calibration state machine (no clock: uses `Input::t`).
#[derive(Debug, Clone)]
pub struct Calibration {
    cfg: Config,
    timed_left: u32,
    start_t: Option<f64>,
    last_second: Option<i64>,
    valid: u32,
    consumed: usize,
    reward: Vec<f64>,
    guard: Vec<f64>,
    done_at: Option<f64>,
}

impl Calibration {
    pub fn new(cfg: &Config, kind: CalibrationKind) -> Self {
        Self {
            cfg: cfg.clone(),
            timed_left: if kind == CalibrationKind::Staged { STAGED_TIMED_S } else { 0 },
            start_t: None,
            last_second: None,
            valid: 0,
            consumed: 0,
            reward: Vec::new(),
            guard: Vec::new(),
            done_at: None,
        }
    }

    /// Current stage (`EyesClosed` = the collected baseline window).
    pub fn stage(&self) -> CalStage {
        match self.timed_left {
            0 => CalStage::EyesClosed,
            n if n > STAGED_TIMED_S - 15 => CalStage::Artifacts,
            _ => CalStage::EyesOpen,
        }
    }

    /// Valid seconds collected so far.
    pub fn valid_seconds(&self) -> u32 {
        self.valid
    }

    /// Seconds still needed (for the progress UI).
    pub fn seconds_left(&self) -> u32 {
        BASELINE_VALID_S.saturating_sub(self.valid)
    }

    pub fn is_done(&self) -> bool {
        self.done_at.is_some()
    }

    fn finished_at(&self, t: f64) -> bool {
        self.valid >= BASELINE_VALID_S || self.start_t.is_some_and(|s| t - s >= BASELINE_MAX_S)
    }

    /// Feed one second. Returns `false` when the input was not consumed
    /// (calibration already over; hand it to the engine instead).
    pub fn push(&mut self, input: &Input) -> bool {
        if self.done_at.is_some() {
            return false;
        }
        if self.timed_left > 0 {
            self.timed_left -= 1;
            self.consumed += 1;
            return true;
        }
        self.start_t.get_or_insert(input.t);
        if self.finished_at(input.t) {
            self.done_at = Some(input.t);
            return false;
        }
        self.consumed += 1;
        let second = input.t.floor() as i64;
        if self.last_second != Some(second) {
            self.last_second = Some(second);
            let rel = input.rel_bands();
            let reward = input.feature_value(rel.as_ref(), self.cfg.feature).filter(|_| !self.cfg.guard_only);
            let guard = self.cfg.guard.and_then(|g| input.guard_value(&g));
            let accept = input.artifact.is_none() && input.all_green();
            let usable = if self.cfg.guard_only { guard.is_some() } else { reward.is_some() || guard.is_some() };
            if accept && usable {
                self.valid += 1;
                self.reward.extend(reward);
                self.guard.extend(guard);
            }
        }
        if self.finished_at(input.t) {
            self.done_at = Some(input.t);
        }
        true
    }

    /// Finish (also valid early, e.g. "start anyway"); `now` is the sample
    /// time used for `wall_seconds` when the window has not closed itself.
    pub fn finish(self, now: f64) -> CalibrationResult {
        let end = self.done_at.unwrap_or(now);
        let wall = self.start_t.map_or(0.0, |s| (end - s).max(0.0)).round() as u32;
        CalibrationResult {
            consumed: self.consumed,
            valid_seconds: self.valid,
            wall_seconds: wall,
            reward_samples: self.reward,
            guard_samples: self.guard,
        }
    }
}
