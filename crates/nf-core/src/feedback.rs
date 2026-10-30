//! Feedback session state machine:
//! idle → fit check → calibrating → playing ⇄ paused → ended.
//!
//! Driven once per second of session time by `Session` (injected clock,
//! `clock.advance` in tests). Math lives in `nf_feedback`; this module
//! owns phases, timing rules and the per-second [`SecondResult`] that the
//! UI, MCP (and later the recording) consume.

use nf_feedback::{Calibration, CalibrationKind, CalibrationResult, Dirty, Engine, HeldBack, Input, Protocol, Record, SIGNAL_GOOD};
use serde::Serialize;
use std::collections::BTreeMap;

/// Device gone (or no data) this long ends the session.
pub const DISCONNECT_GRACE_S: f64 = 10.0;
/// This many consecutive seconds without a usable pad auto-pause training.
pub const BAD_SIGNAL_PAUSE_S: u32 = 10;
/// Good seconds needed to auto-resume after a bad-signal pause.
pub const RESUME_GOOD_S: u32 = 2;
/// Target pads green this long = fit check passed.
pub const FIT_GREEN_S: u32 = 3;
/// Fewer valid calibration seconds than this cannot seed a baseline.
pub const MIN_CALIBRATION_S: u32 = 10;
/// Session minutes range.
pub const MINUTES: (u32, u32) = (1, 120);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PauseReason {
    User,
    BadSignal,
    Disconnected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(tag = "phase", rename_all = "snake_case")]
pub enum Phase {
    Idle,
    FitCheck,
    Calibrating,
    Playing,
    Paused { reason: PauseReason },
    Ended,
}

impl Phase {
    /// A session is in progress (settings locked).
    pub fn active(self) -> bool {
        !matches!(self, Phase::Idle | Phase::Ended)
    }
}

/// One target pad as seen by the fit check.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PadFit {
    pub name: String,
    pub quality: f64,
    pub good: bool,
}

/// One second of observation handed in by `Session`.
#[derive(Debug, Clone, Default)]
pub struct Observation {
    /// Device connected and data fresh.
    pub connected: bool,
    pub names: Vec<String>,
    pub pads: Vec<[f64; 5]>,
    pub quality: Vec<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CalibrationProgress {
    pub valid_s: u32,
    pub wall_s: u32,
    pub needed_s: u32,
    pub max_s: u32,
    /// Why this second did not count, if it did not.
    pub waiting: Option<String>,
}

/// The per-second result record.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SecondResult {
    /// Session time (s).
    pub time: f64,
    pub phase: Phase,
    /// Training second index (0-based) while playing.
    pub second: Option<u32>,
    /// Counted towards training (clean sample with a value).
    pub counted: bool,
    pub in_target: bool,
    pub value: Option<f64>,
    pub threshold: Option<f64>,
    /// Plain-language reason it did not count / was not rewarded.
    pub reason: Option<String>,
    /// Play the reward chime this second (rising edge into target).
    pub chime: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub record: Option<Record>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Summary {
    pub protocol: String,
    pub played_s: u32,
    pub counted_s: u32,
    pub in_target_s: u32,
    /// in_target / counted.
    pub success: Option<f64>,
    pub chimes: u32,
    pub threshold_start: Option<f64>,
    pub threshold_end: Option<f64>,
    pub adapt_steps: u32,
    pub pauses: u32,
    pub ended_by: String,
}

#[derive(Debug, Clone)]
pub struct Trainer {
    pub protocol: &'static Protocol,
    pub minutes: u32,
    pub percentile: u8,
    pub phase: Phase,
    pub pads: Vec<PadFit>,
    pub green_for: u32,
    pub calibration: Option<CalibrationProgress>,
    pub played_s: u32,
    pub results: Vec<SecondResult>,
    pub summary: Option<Summary>,
    /// Last notice (e.g. why calibration failed).
    pub message: Option<String>,
    /// Last baseline per `device|protocol`.
    pub baselines: BTreeMap<String, CalibrationResult>,
    pub device: Option<String>,
    cal: Option<Calibration>,
    engine: Option<Engine>,
    sample_t: f64,
    bad_for: u32,
    good_for: u32,
    lost_since: Option<f64>,
    was_in_target: bool,
    pauses: u32,
    threshold_start: Option<f64>,
}

impl Default for Trainer {
    fn default() -> Self {
        let protocol = nf_feedback::protocol(nf_feedback::DEFAULT_PROTOCOL).unwrap_or(&nf_feedback::PROTOCOLS[0]);
        Self {
            protocol,
            minutes: protocol.default_minutes,
            percentile: nf_feedback::DEFAULT_PERCENTILE,
            phase: Phase::Idle,
            pads: Vec::new(),
            green_for: 0,
            calibration: None,
            played_s: 0,
            results: Vec::new(),
            summary: None,
            message: None,
            baselines: BTreeMap::new(),
            device: None,
            cal: None,
            engine: None,
            sample_t: 0.0,
            bad_for: 0,
            good_for: 0,
            lost_since: None,
            was_in_target: false,
            pauses: 0,
            threshold_start: None,
        }
    }
}

/// Phase changes and chimes for the event stream.
#[derive(Debug, Clone, PartialEq)]
pub enum Change {
    Phase(Phase),
    Chime,
}

fn pad_list(names: &[String]) -> String {
    names.join(", ")
}

impl Trainer {
    fn key(&self) -> Option<String> {
        self.device.as_ref().map(|d| format!("{d}|{}", self.protocol.id))
    }

    pub fn last_baseline(&self) -> Option<&CalibrationResult> {
        self.key().and_then(|k| self.baselines.get(&k))
    }

    pub fn fit_ready(&self) -> bool {
        self.green_for >= FIT_GREEN_S
    }

    pub fn threshold(&self) -> Option<f64> {
        self.engine.as_ref().and_then(Engine::threshold)
    }

    pub fn has_engine(&self) -> bool {
        self.engine.is_some()
    }

    pub fn last(&self) -> Option<&SecondResult> {
        self.results.last()
    }

    pub fn total_s(&self) -> u32 {
        self.minutes * 60
    }

    fn set(&mut self, phase: Phase, out: &mut Vec<Change>) {
        if self.phase != phase {
            if matches!(phase, Phase::Paused { .. }) {
                self.pauses += 1;
            }
            self.phase = phase;
            out.push(Change::Phase(phase));
        }
    }

    /// idle/ended → fit check.
    pub fn start(&mut self, device: &str, out: &mut Vec<Change>) {
        let baselines = std::mem::take(&mut self.baselines);
        *self = Self { protocol: self.protocol, minutes: self.minutes, percentile: self.percentile, baselines, ..Self::default() };
        self.device = Some(device.to_owned());
        self.set(Phase::FitCheck, out);
    }

    /// fit check → calibrating.
    pub fn calibrate(&mut self, out: &mut Vec<Change>) {
        self.message = None;
        self.cal = Some(Calibration::new(&self.protocol.config(self.percentile), CalibrationKind::Single));
        self.calibration = Some(CalibrationProgress {
            valid_s: 0,
            wall_s: 0,
            needed_s: nf_feedback::BASELINE_VALID_S,
            max_s: nf_feedback::BASELINE_MAX_S as u32,
            waiting: None,
        });
        self.set(Phase::Calibrating, out);
    }

    /// Calibrating → playing with what was collected so far (start anyway).
    /// `Err` when too little was collected.
    pub fn finish_calibration(&mut self, out: &mut Vec<Change>) -> Result<(), String> {
        let Some(cal) = self.cal.take() else { return Err("not calibrating".into()) };
        let res = cal.finish(self.sample_t);
        if res.valid_seconds < MIN_CALIBRATION_S {
            self.message = Some(format!(
                "Calibration got only {} good seconds (needs {MIN_CALIBRATION_S}). Check the headband fit and try again.",
                res.valid_seconds
            ));
            self.calibration = None;
            self.green_for = 0;
            self.set(Phase::FitCheck, out);
            return Err(self.message.clone().unwrap_or_default());
        }
        if let Some(k) = self.key() {
            self.baselines.insert(k, res.clone());
        }
        self.play(&res, out);
        Ok(())
    }

    /// Use the stored baseline for this device + protocol.
    pub fn reuse(&mut self, out: &mut Vec<Change>) -> Result<(), String> {
        let res = self.last_baseline().cloned().ok_or("no stored baseline for this device and protocol")?;
        self.cal = None;
        self.play(&res, out);
        Ok(())
    }

    fn play(&mut self, res: &CalibrationResult, out: &mut Vec<Change>) {
        let engine = Engine::from_calibration(self.protocol.config(self.percentile), res);
        self.threshold_start = engine.threshold();
        self.engine = Some(engine);
        self.calibration = None;
        self.bad_for = 0;
        self.set(Phase::Playing, out);
    }

    pub fn pause(&mut self, out: &mut Vec<Change>) {
        self.set(Phase::Paused { reason: PauseReason::User }, out);
    }

    pub fn resume(&mut self, out: &mut Vec<Change>) {
        self.bad_for = 0;
        self.set(Phase::Playing, out);
    }

    pub fn set_percentile(&mut self, p: u8) -> Option<f64> {
        self.percentile = p;
        self.engine.as_mut().and_then(|e| e.set_percentile(p))
    }

    pub fn stop(&mut self, why: &str, out: &mut Vec<Change>) {
        self.cal = None;
        self.calibration = None;
        let res = &self.results;
        let played: Vec<&SecondResult> = res.iter().filter(|r| r.second.is_some()).collect();
        let counted = played.iter().filter(|r| r.counted).count() as u32;
        let hits = played.iter().filter(|r| r.in_target).count() as u32;
        self.summary = Some(Summary {
            protocol: self.protocol.id.into(),
            played_s: self.played_s,
            counted_s: counted,
            in_target_s: hits,
            success: (counted > 0).then(|| f64::from(hits) / f64::from(counted)),
            chimes: played.iter().filter(|r| r.chime).count() as u32,
            threshold_start: self.threshold_start,
            threshold_end: self.threshold(),
            adapt_steps: played.iter().filter(|r| r.record.as_ref().is_some_and(|x| x.adapt.is_some())).count() as u32,
            pauses: self.pauses,
            ended_by: why.into(),
        });
        self.engine = None;
        self.set(Phase::Ended, out);
    }

    /// One second of session time.
    pub fn second(&mut self, time: f64, obs: &Observation, out: &mut Vec<Change>) {
        self.pads = obs
            .names
            .iter()
            .zip(&obs.quality)
            .map(|(n, &q)| PadFit { name: n.clone(), quality: q, good: obs.connected && q >= SIGNAL_GOOD })
            .collect();
        let all_green = obs.connected && !self.pads.is_empty() && self.pads.iter().all(|p| p.good);
        let bad: Vec<String> = self.pads.iter().filter(|p| !p.good).map(|p| p.name.clone()).collect();
        if !obs.connected {
            let since = *self.lost_since.get_or_insert(time);
            self.green_for = 0;
            if time - since >= DISCONNECT_GRACE_S {
                self.lost_since = None;
                match self.phase {
                    Phase::Playing | Phase::Paused { .. } => self.stop("device disconnected", out),
                    Phase::Calibrating | Phase::FitCheck => {
                        self.cal = None;
                        self.calibration = None;
                        self.message = Some("Device disconnected for 10 s; session cancelled.".into());
                        self.set(Phase::Idle, out);
                    }
                    _ => {}
                }
                return;
            }
            if self.phase == Phase::Playing {
                self.set(Phase::Paused { reason: PauseReason::Disconnected }, out);
            }
            if let Some(c) = self.calibration.as_mut() {
                c.waiting = Some("device disconnected, waiting for it to come back".into());
            }
            self.push(time, None, false, Some(format!("device disconnected ({:.0} s grace left)", DISCONNECT_GRACE_S - (time - since))));
            return;
        }
        if self.lost_since.take().is_some() && self.phase == (Phase::Paused { reason: PauseReason::Disconnected }) {
            self.resume(out);
        }
        let input = Input { t: self.sample_t, pads: obs.pads.clone(), quality: obs.quality.clone(), artifact: None };
        match self.phase {
            Phase::FitCheck => {
                self.green_for = if all_green { self.green_for + 1 } else { 0 };
            }
            Phase::Calibrating => {
                let Some(cal) = self.cal.as_mut() else { return };
                self.sample_t += 1.0;
                let consumed = cal.push(&input);
                let wall = self.calibration.as_ref().map_or(0, |c| c.wall_s);
                let (valid, done) = (cal.valid_seconds(), cal.is_done());
                if let Some(c) = self.calibration.as_mut() {
                    c.valid_s = valid;
                    c.wall_s = wall + u32::from(consumed);
                    c.waiting = (!all_green).then(|| format!("waiting for good signal on {}", pad_list(&bad)));
                }
                let reason = self.calibration.as_ref().and_then(|c| c.waiting.clone());
                self.push(time, None, false, reason);
                if done {
                    let _ = self.finish_calibration(out);
                }
            }
            Phase::Playing => self.play_second(time, &input, out),
            Phase::Paused { reason: PauseReason::BadSignal } => {
                self.good_for = if input.rel_bands().is_some() { self.good_for + 1 } else { 0 };
                if self.good_for >= RESUME_GOOD_S {
                    self.good_for = 0;
                    self.resume(out);
                }
                self.push(time, None, false, Some(format!("no good signal on {}", pad_list(&bad))));
            }
            _ => {}
        }
    }

    fn play_second(&mut self, time: f64, input: &Input, out: &mut Vec<Change>) {
        let Some(engine) = self.engine.as_mut() else { return };
        let rec = engine.step(input);
        self.sample_t += 1.0;
        let second = self.played_s;
        self.played_s += 1;
        let names: Vec<String> = self.pads.iter().filter(|p| !p.good).map(|p| p.name.clone()).collect();
        let counted = rec.produced && rec.dirty.is_none();
        let in_target = rec.in_target == Some(true);
        let reason = if !rec.produced || rec.dirty == Some(Dirty::Pads) {
            Some(format!("no good signal on {}", pad_list(&names)))
        } else if let Some(d) = rec.dirty {
            Some(format!("{d:?} artifact").to_lowercase())
        } else {
            rec.held_back.as_ref().and_then(|h| h.first()).map(|h| match h {
                HeldBack::Beta => "above target, but beta too high".to_owned(),
                HeldBack::Delta => "above target, but delta too high".to_owned(),
                HeldBack::Guard => "reward muted by the sleep guard".to_owned(),
                HeldBack::NoThreshold => "no baseline yet".to_owned(),
            })
        };
        let chime = in_target && !self.was_in_target;
        self.was_in_target = in_target;
        if chime {
            out.push(Change::Chime);
        }
        self.bad_for = if input.rel_bands().is_none() { self.bad_for + 1 } else { 0 };
        let r = SecondResult {
            time,
            phase: self.phase,
            second: Some(second),
            counted,
            in_target,
            value: rec.native,
            threshold: rec.thr,
            reason,
            chime,
            record: Some(rec),
        };
        self.results.push(r);
        if self.played_s >= self.total_s() {
            self.stop("completed", out);
        } else if self.bad_for >= BAD_SIGNAL_PAUSE_S {
            self.bad_for = 0;
            self.good_for = 0;
            self.was_in_target = false;
            self.set(Phase::Paused { reason: PauseReason::BadSignal }, out);
        }
    }

    fn push(&mut self, time: f64, second: Option<u32>, counted: bool, reason: Option<String>) {
        self.results.push(SecondResult {
            time,
            phase: self.phase,
            second,
            counted,
            in_target: false,
            value: None,
            threshold: self.threshold(),
            reason,
            chime: false,
            record: None,
        });
    }
}
