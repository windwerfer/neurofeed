//! Per-second reward/guard engine (percentile uptrain or stability).

use crate::calibration::CalibrationResult;
use crate::stats::{rolling_cvs, stability_output_percentile, Baseline};
use crate::{
    AdaptStep, Config, Dirty, HeldBack, Inhibit, Input, Record, StabilityConfig, ADAPT_INTERVAL_S, CEILING_SD, EPOCH_WINDOW_S,
    HIGH_SUCCESS, LOW_SUCCESS, RECENT_WINDOW_S, WARNING_COOLDOWN_S,
};
use std::collections::VecDeque;

/// Training engine. Feed one [`Input`] per second with [`Engine::step`].
#[derive(Debug, Clone)]
pub struct Engine {
    cfg: Config,
    /// Uptrain: raw feature pile. Stability: window CVs ÷ baseline CV.
    baseline: Baseline,
    raw_baseline: Vec<f64>,
    baseline_cv: Option<f64>,
    threshold: Option<f64>,
    initial: Option<f64>,
    epochs: VecDeque<(f64, bool)>,
    epoch_start: Option<f64>,
    recent: VecDeque<(f64, f64, bool)>,
    live: VecDeque<f64>,
    last_native: Option<f64>,
    last_pct: Option<f64>,
    last_thr_pct: f64,
    guard_baseline: Baseline,
    guard_thr: Option<f64>,
    warning: bool,
    last_chime: Option<f64>,
    adapt_tick: u32,
}

impl Engine {
    /// Engine without a baseline (calibration skipped): never rewards.
    pub fn new(cfg: Config) -> Self {
        Self {
            cfg,
            baseline: Baseline::default(),
            raw_baseline: Vec::new(),
            baseline_cv: None,
            threshold: None,
            initial: None,
            epochs: VecDeque::new(),
            epoch_start: None,
            recent: VecDeque::new(),
            live: VecDeque::new(),
            last_native: None,
            last_pct: None,
            last_thr_pct: 0.0,
            guard_baseline: Baseline::default(),
            guard_thr: None,
            warning: false,
            last_chime: None,
            adapt_tick: 0,
        }
    }

    /// Engine seeded from a calibration (or a stored last baseline).
    pub fn from_calibration(cfg: Config, cal: &CalibrationResult) -> Self {
        let mut e = Self::new(cfg);
        if e.cfg.stability.is_some() {
            e.raw_baseline.clone_from(&cal.reward_samples);
        } else {
            e.baseline = Baseline::new(cal.reward_samples.clone());
        }
        e.compute_threshold();
        if let Some(g) = e.cfg.guard {
            e.guard_baseline = Baseline::new(cal.guard_samples.clone());
            e.guard_thr = e.guard_baseline.at_percentile(f64::from(g.percentile));
        }
        e
    }

    pub fn config(&self) -> &Config {
        &self.cfg
    }
    pub fn threshold(&self) -> Option<f64> {
        self.threshold
    }
    pub fn baseline(&self) -> &Baseline {
        &self.baseline
    }
    pub fn baseline_cv(&self) -> Option<f64> {
        self.baseline_cv
    }
    pub fn guard_threshold(&self) -> Option<f64> {
        self.guard_thr
    }

    fn compute_threshold(&mut self) -> Option<f64> {
        if let Some(st) = self.cfg.stability {
            return self.compute_stability_threshold(st);
        }
        let thr = self.baseline.at_percentile(f64::from(self.cfg.percentile))?;
        self.threshold = Some(thr);
        self.initial.get_or_insert(thr);
        Some(thr)
    }

    fn compute_stability_threshold(&mut self, st: StabilityConfig) -> Option<f64> {
        let cvs = rolling_cvs(&self.raw_baseline, st.effective_window());
        let mut sorted = cvs.clone();
        sorted.sort_by(f64::total_cmp);
        let median = sorted.get(sorted.len() / 2).copied().filter(|m| *m > 0.0);
        let Some(median) = median else {
            self.baseline_cv = None;
            self.threshold = None;
            return None;
        };
        self.baseline_cv = Some(median);
        self.baseline = Baseline::new(cvs.iter().map(|c| c / median).collect());
        let thr = st.initial_threshold();
        self.threshold = Some(thr);
        self.initial.get_or_insert(thr);
        Some(thr)
    }

    fn in_target(&self, v: f64) -> bool {
        match (self.threshold, self.cfg.stability) {
            (Some(t), Some(_)) => v <= t,
            (Some(t), None) => v > t,
            // Fix (decisions 2026-10-29): no `> 1.0` fallback without a threshold.
            (None, _) => false,
        }
    }

    fn window_full(&self, now: f64) -> bool {
        self.epoch_start.is_some_and(|s| !self.epochs.is_empty() && now - s >= EPOCH_WINDOW_S)
    }

    fn success(&self) -> f64 {
        let hits = self.epochs.iter().filter(|e| e.1).count();
        hits as f64 / self.epochs.len() as f64
    }

    /// Success over the last [`EPOCH_WINDOW_S`] of sample time, once full.
    pub fn success_rate(&self, now: f64) -> Option<f64> {
        self.window_full(now).then(|| self.success())
    }

    fn record_epoch(&mut self, t: f64, hit: bool) {
        self.epoch_start.get_or_insert(t);
        self.epochs.push_back((t, hit));
        self.epochs.retain(|e| t - e.0 <= EPOCH_WINDOW_S);
    }

    fn record_recent(&mut self, t: f64, v: f64, clean: bool) {
        self.recent.push_back((t, v, clean));
        self.recent.retain(|s| t - s.0 <= RECENT_WINDOW_S);
    }

    fn push_stability(&mut self, st: StabilityConfig, v: f64) -> Option<f64> {
        if !v.is_finite() {
            return None;
        }
        self.live.push_back(v);
        let n = st.effective_window();
        while self.live.len() > n {
            self.live.pop_front();
        }
        let base = self.baseline_cv.filter(|b| *b > 0.0)?;
        if self.live.len() < n {
            return None;
        }
        let w: Vec<f64> = self.live.iter().copied().collect();
        crate::stats::coefficient_of_variation(&w).map(|cv| cv / base)
    }

    fn steps(&self) -> (f64, f64) {
        let r = self.cfg.responsiveness.clamp(0.0, 1.0);
        (1.01 + 0.02 * r, 1.0 - (0.03 + 0.07 * r))
    }

    /// One adaptation step (normally every [`ADAPT_INTERVAL_S`] via `step`).
    pub fn adapt(&mut self, now: f64) {
        if !self.cfg.dynamic_adapt {
            return;
        }
        let (Some(t), Some(initial)) = (self.threshold, self.initial) else {
            return;
        };
        if !self.window_full(now) {
            return;
        }
        let (raise, lower) = self.steps();
        let (mean, sd) = (self.baseline.mean(), self.baseline.sd());
        let success = self.success();
        if self.cfg.stability.is_some() {
            let spread_floor = match (mean, sd) {
                (Some(m), Some(s)) => m - CEILING_SD * s,
                _ => initial * lower,
            };
            let floor = spread_floor.min(initial - 0.3).max(StabilityConfig::MIN_THRESHOLD).min(initial);
            let bound = |x: f64| x.max(floor).min(initial);
            if success == 0.0 {
                self.threshold = Some(initial);
            } else if success > HIGH_SUCCESS {
                self.threshold = Some(bound(t * (2.0 - raise)));
            } else if success < LOW_SUCCESS {
                self.threshold = Some(bound(t * (2.0 - lower)));
            }
            return;
        }
        let max_allowed = match (mean, sd) {
            (Some(m), Some(s)) => m + CEILING_SD * s,
            _ => t * raise,
        };
        // Legacy `clamp(initial, max)`; Dart throws if initial > max, we let max win.
        let bound = |x: f64| x.max(initial).min(max_allowed);
        if success == 0.0 {
            self.threshold = Some(initial);
        } else if success > HIGH_SUCCESS {
            self.threshold = Some(bound(t * raise));
        } else if success < LOW_SUCCESS {
            self.threshold = Some(bound(t * lower));
        }
    }

    /// Re-anchor the baseline from the last [`RECENT_WINDOW_S`] of clean
    /// samples; `false` when fewer than `min_samples` are available.
    pub fn recalibrate_from_recent(&mut self, now: f64, min_samples: usize) -> bool {
        let clean: Vec<f64> = self.recent.iter().filter(|s| now - s.0 <= RECENT_WINDOW_S && s.2).map(|s| s.1).collect();
        if clean.len() < min_samples {
            return false;
        }
        if self.cfg.stability.is_some() {
            self.raw_baseline = clean;
            self.live.clear();
        } else {
            self.baseline = Baseline::new(clean);
        }
        self.epochs.clear();
        self.epoch_start = None;
        self.initial = None;
        self.compute_threshold();
        true
    }

    /// Process one second of input and return its record.
    pub fn step(&mut self, input: &Input) -> Record {
        let now = input.t;
        let mut rec = Record { t: now, ..Record::default() };
        let rel = input.rel_bands();
        let value = rel.and_then(|r| r.feature(self.cfg.feature)).filter(|v| v.is_finite());
        // Fix (decisions 2026-10-29): guard muffle withholds reward in both policies.
        let guard_blocks = self.warning && self.cfg.guard.is_some_and(|g| g.muffle);
        if let (Some(v), Some(rel)) = (value, rel) {
            let dirty = input.artifact.map(|a| match a {
                crate::Artifact::Movement => Dirty::Movement,
                crate::Artifact::Blink => Dirty::Blink,
                crate::Artifact::Jaw => Dirty::Jaw,
            });
            if let Some(st) = self.cfg.stability {
                self.record_recent(now, v, dirty.is_none());
                if let Some(d) = dirty {
                    if let Some(n) = self.last_native {
                        rec.produced = true;
                        rec.native = Some(n);
                        rec.pct = self.last_pct;
                        rec.thr = self.threshold;
                        rec.thr_pct = Some(self.last_thr_pct);
                        rec.in_target = Some(false);
                        rec.held_back = Some(Vec::new());
                        rec.dirty = Some(d);
                    }
                } else if let Some(r) = self.push_stability(st, v) {
                    let thr = self.threshold;
                    let steady = self.in_target(r);
                    let hit = steady && !guard_blocks;
                    self.last_native = Some(r);
                    self.last_pct = Some(stability_output_percentile(r, thr));
                    self.last_thr_pct = thr.map_or(0.0, |t| stability_output_percentile(t, Some(t)));
                    self.record_epoch(now, hit);
                    rec.produced = true;
                    rec.native = Some(r);
                    rec.pct = self.last_pct;
                    rec.thr = thr;
                    rec.thr_pct = Some(self.last_thr_pct);
                    rec.in_target = Some(hit);
                    rec.held_back = Some(if steady && guard_blocks { vec![HeldBack::Guard] } else { Vec::new() });
                }
            } else {
                rec.produced = true;
                rec.native = Some(v);
                rec.pct = Some(self.baseline.rank(v).unwrap_or(50.0));
                rec.thr = self.threshold;
                self.last_thr_pct = self.threshold.and_then(|t| self.baseline.rank(t)).unwrap_or(0.0);
                rec.thr_pct = Some(self.last_thr_pct);
                if let Some(d) = dirty {
                    self.record_recent(now, v, false);
                    rec.in_target = Some(false);
                    rec.held_back = Some(Vec::new());
                    rec.dirty = Some(d);
                } else {
                    let above = self.in_target(v);
                    let mut held = Vec::new();
                    for c in &self.cfg.inhibit {
                        match *c {
                            Inhibit::BetaCeiling(m) if rel.beta > m => held.push(HeldBack::Beta),
                            Inhibit::DeltaCeiling(m) if rel.delta > m => held.push(HeldBack::Delta),
                            _ => {}
                        }
                    }
                    if guard_blocks {
                        held.push(HeldBack::Guard);
                    }
                    let hit = above && held.is_empty();
                    self.record_epoch(now, hit);
                    self.record_recent(now, v, true);
                    rec.in_target = Some(hit);
                    rec.held_back = Some(if self.threshold.is_none() {
                        vec![HeldBack::NoThreshold]
                    } else if above {
                        held
                    } else {
                        Vec::new()
                    });
                }
            }
        }
        if let Some(g) = self.cfg.guard {
            let mut chime = false;
            if let (Some(d), Some(thr), None) = (rel.map(|r| r.abs_delta), self.guard_thr, input.artifact) {
                self.warning = d > thr;
                if self.warning && self.last_chime.is_none_or(|l| now - l >= WARNING_COOLDOWN_S) {
                    self.last_chime = Some(now);
                    chime = true;
                }
            }
            rec.warn = Some(self.warning);
            rec.chime = Some(chime);
            rec.muted = Some(self.warning && g.muffle);
        }
        rec.success_rate = self.success_rate(now);
        self.adapt_tick += 1;
        if self.adapt_tick >= ADAPT_INTERVAL_S {
            self.adapt_tick = 0;
            let from = self.threshold;
            self.adapt(now);
            rec.adapt = Some(AdaptStep { from, to: self.threshold });
        }
        rec
    }
}
