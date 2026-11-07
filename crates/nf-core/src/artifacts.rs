//! Live artifact tracking: accelerometer movement + EEG blink / jaw clench,
//! evaluated once per feedback second (legacy `_sampleIsClean`: an event in
//! the current second marks it dirty; movement wins over blink over jaw).

use nf_dsp::{GestureDetector, MovementDetector};
use nf_feedback::Artifact;
use nf_types::{AccelPacket, DeviceInfo, EegPacket};
use serde::Serialize;

/// Frontal (blink) and temporal (jaw) pads per montage.
const FRONTAL: [&str; 4] = ["AF7", "AF8", "F5", "F6"];
const TEMPORAL: [&str; 4] = ["TP9", "TP10", "CP3", "CP4"];

/// Last evaluated second (`artifact.status`).
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct ArtifactStatus {
    /// Session time of the evaluated second.
    pub time: f64,
    /// Accelerometer movement score (g); `None` without an accelerometer.
    pub movement_score: Option<f64>,
    pub blinks: u32,
    pub clench: bool,
    /// What the engine received: movement | blink | jaw.
    pub artifact: Option<Artifact>,
}

#[derive(Clone)]
pub struct Artifacts {
    movement: Option<MovementDetector>,
    gesture: GestureDetector,
    pub status: ArtifactStatus,
    /// Settings: emit eye up/down marks (experimental, off by default).
    pub eye_markers: bool,
    /// Per electrode: excluded from analysis → never fed to the blink /
    /// clench / eye detectors (the raw ring and recording keep it).
    pub excluded: Vec<bool>,
    /// Gesture marks of the last evaluated second (drained by the session).
    pub marks: Vec<crate::trust::Mark>,
    last_blink: Option<f64>,
    last_clench: Option<f64>,
    clenching: bool,
    eye: u8,
}

/// Two blinks (or two jaw clenches) within this window form a "double" mark.
const DOUBLE_S: f64 = 2.0;

fn pads(info: &DeviceInfo, names: &[&str]) -> Vec<usize> {
    info.channels.iter().enumerate().filter(|(_, c)| names.contains(&c.as_str())).map(|(i, _)| i).collect()
}

impl Artifacts {
    pub fn new(info: &DeviceInfo) -> Self {
        Self {
            movement: info.accel_rate_hz.map(MovementDetector::new),
            gesture: GestureDetector::new(info.channels.len(), pads(info, &FRONTAL), pads(info, &TEMPORAL)),
            status: ArtifactStatus::default(),
            eye_markers: false,
            excluded: Vec::new(),
            marks: Vec::new(),
            last_blink: None,
            last_clench: None,
            clenching: false,
            eye: 0,
        }
    }

    pub fn accel(&mut self, p: &AccelPacket) {
        if let Some(m) = self.movement.as_mut() {
            m.push(&p.samples);
        }
    }

    pub fn eeg(&mut self, p: &EegPacket) {
        if self.excluded.get(usize::from(p.electrode)).copied().unwrap_or(false) {
            return;
        }
        self.gesture.feed_eeg(usize::from(p.electrode), &p.samples);
    }

    /// Per-second gamma power per electrode (from the band snapshot).
    pub fn gamma(&mut self, powers: &[[f32; 5]]) {
        for (e, b) in powers.iter().enumerate() {
            if self.excluded.get(e).copied().unwrap_or(false) {
                self.gesture.forget_gamma(e);
            } else {
                self.gesture.feed_gamma(e, f64::from(b[4]));
            }
        }
    }

    /// Current movement score (g) without evaluating a second; `None`
    /// without an accelerometer.
    pub fn movement_score(&self) -> Option<f64> {
        self.movement.as_ref().map(MovementDetector::score)
    }

    /// Evaluate one second.
    pub fn second(&mut self, t: f64) -> Option<Artifact> {
        let g = self.gesture.tick();
        let score = self.movement.as_ref().map(MovementDetector::score);
        let artifact = if score.is_some_and(|s| s > nf_dsp::MOVEMENT_GATE) {
            Some(Artifact::Movement)
        } else if g.blink_count > 0 {
            Some(Artifact::Blink)
        } else if g.clench {
            Some(Artifact::Jaw)
        } else {
            None
        };
        self.status = ArtifactStatus { time: t, movement_score: score, blinks: g.blink_count, clench: g.clench, artifact };
        self.mark(t, g);
        artifact
    }

    /// Legacy gesture marks: double blink, double jaw clench (two clench
    /// onsets within [`DOUBLE_S`]) and, when enabled, eye up/down onsets.
    fn mark(&mut self, t: f64, g: nf_dsp::GestureReport) {
        let mut add = |kind: &str| self.marks.push(crate::trust::Mark { t, kind: kind.to_owned() });
        if g.blink_count >= 2 || (g.blink_count == 1 && self.last_blink.is_some_and(|b| t - b <= DOUBLE_S)) {
            add("double_blink");
            self.last_blink = None;
        } else if g.blink_count == 1 {
            self.last_blink = Some(t);
        }
        if g.clench && !self.clenching {
            if self.last_clench.is_some_and(|c| t - c <= DOUBLE_S + 1.0) {
                add("double_jaw_clench");
                self.last_clench = None;
            } else {
                self.last_clench = Some(t);
            }
        }
        self.clenching = g.clench;
        if self.eye_markers && g.eye != self.eye && g.eye != 0 {
            add(if g.eye == 1 { "eye_up" } else { "eye_down" });
        }
        self.eye = g.eye;
    }
}
