//! Sticky mains (50/60 Hz / none) detection, ported from
//! `MainsDetector` in `rust/src/analysis/eeg_filter.rs`: every
//! `DETECT_WINDOW` unfiltered samples per channel vote 50, 60 or none (peak
//! ≥ `PEAK_RATIO` × neighbour median); `LOCK_VOTES` agreeing votes decide
//! from Unknown, `SWITCH_VOTES` switch from None to a frequency; 50/60 is final.

use crate::bands::{mains_peak_ratio, psd};
use crate::filter::Mains;

pub const DETECT_WINDOW: usize = 256;
pub const PEAK_RATIO: f64 = 5.0;
pub const LOCK_VOTES: u32 = 8;
pub const SWITCH_VOTES: u32 = 16;

/// One window's vote.
pub fn mains_vote(samples: &[f32], rate_hz: f64) -> Option<f64> {
    let p = psd(samples, rate_hz)?;
    let r50 = mains_peak_ratio(&p, 50.0).unwrap_or(0.0);
    let r60 = mains_peak_ratio(&p, 60.0).unwrap_or(0.0);
    match (r50 >= PEAK_RATIO, r60 >= PEAK_RATIO) {
        (true, true) => Some(if r50 >= r60 { 50.0 } else { 60.0 }),
        (true, false) => Some(50.0),
        (false, true) => Some(60.0),
        (false, false) => None,
    }
}

#[derive(Debug, Clone)]
pub struct MainsDetector {
    rate: f64,
    mains: Mains,
    streak_vote: Option<Option<f64>>,
    streak: u32,
    windows: Vec<Vec<f32>>,
}

impl MainsDetector {
    pub fn new(rate: f64, channels: usize) -> Self {
        Self { rate, mains: Mains::Unknown, streak_vote: None, streak: 0, windows: vec![Vec::new(); channels] }
    }

    pub fn mains(&self) -> Mains {
        self.mains
    }

    /// Count one vote; returns the new state when it changes.
    pub fn vote(&mut self, vote: Option<f64>) -> Option<Mains> {
        let needed = match self.mains {
            Mains::Hz50 | Mains::Hz60 => return None,
            Mains::None if vote.is_none() => {
                self.streak = 0;
                return None;
            }
            Mains::None => SWITCH_VOTES,
            Mains::Unknown => LOCK_VOTES,
        };
        if self.streak_vote == Some(vote) {
            self.streak += 1;
        } else {
            self.streak_vote = Some(vote);
            self.streak = 1;
        }
        if self.streak < needed {
            return None;
        }
        self.streak = 0;
        self.mains = match vote {
            Some(hz) if hz < 55.0 => Mains::Hz50,
            Some(_) => Mains::Hz60,
            None => Mains::None,
        };
        if matches!(self.mains, Mains::Hz50 | Mains::Hz60) {
            self.windows.iter_mut().for_each(Vec::clear);
        }
        Some(self.mains)
    }

    /// Feed unfiltered samples of one channel; returns the new state on change.
    pub fn feed(&mut self, channel: usize, samples: &[f32]) -> Option<Mains> {
        if matches!(self.mains, Mains::Hz50 | Mains::Hz60) {
            return None;
        }
        let rate = self.rate;
        let w = self.windows.get_mut(channel)?;
        w.extend_from_slice(samples);
        let mut full = Vec::new();
        while w.len() >= DETECT_WINDOW {
            full.push(w.drain(..DETECT_WINDOW).collect::<Vec<f32>>());
        }
        let mut changed = None;
        for win in full {
            if let Some(m) = self.vote(mains_vote(&win, rate)) {
                changed = Some(m);
            }
        }
        changed
    }
}
