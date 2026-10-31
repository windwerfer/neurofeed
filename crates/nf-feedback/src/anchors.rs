//! Guardrail anchors (legacy `analysis::guardrail`): `V_clear` is frozen
//! from the eyes-open calibration stage, `V_sleep` is the live embedding with
//! the highest `sleep_dir` seen during the eyes-closed baseline. Both are
//! extras for display and labelling; the warning uses the head probability.

use serde::Serialize;

#[derive(Debug, Clone, Default)]
pub struct Anchors {
    /// Model id the anchors were captured under (never mix CBraMod / REVE).
    model: String,
    clear: Option<Vec<f32>>,
    sleep: Option<Vec<f32>>,
    peak: Option<(f32, Vec<f32>)>,
}

/// Live anchor readout.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct AnchorScores {
    /// cos(live, V_clear).
    pub clarity: f32,
    /// cos(live, V_sleep) once captured, else 1 − clarity.
    pub sleep_dir: f32,
}

/// Cosine similarity; `None` when degenerate or of different length.
pub fn cosine(a: &[f32], b: &[f32]) -> Option<f32> {
    if a.len() != b.len() || a.is_empty() {
        return None;
    }
    let (mut d, mut na, mut nb) = (0f64, 0f64, 0f64);
    for (&x, &y) in a.iter().zip(b) {
        let (x, y) = (f64::from(x), f64::from(y));
        d += x * y;
        na += x * x;
        nb += y * y;
    }
    (na > 0.0 && nb > 0.0).then(|| (d / (na.sqrt() * nb.sqrt())) as f32)
}

impl Anchors {
    pub fn has_clear(&self) -> bool {
        self.clear.is_some()
    }
    pub fn has_sleep(&self) -> bool {
        self.sleep.is_some()
    }

    /// Freeze `V_clear` (resets the rest peak).
    pub fn capture_clear(&mut self, model: &str, live: &[f32]) {
        *self = Self { model: model.to_owned(), clear: Some(live.to_vec()), ..Self::default() };
    }

    /// Freeze `V_sleep` from the rest peak. `false` when there is none.
    pub fn capture_sleep(&mut self) -> bool {
        match self.peak.take() {
            Some((_, v)) => {
                self.sleep = Some(v);
                true
            }
            None => false,
        }
    }

    /// Score a live embedding; while `track_peak`, remember the deepest one.
    pub fn observe(&mut self, model: &str, live: &[f32], track_peak: bool) -> Option<AnchorScores> {
        if model != self.model {
            return None;
        }
        let clarity = cosine(live, self.clear.as_ref()?)?;
        let sleep_dir = match &self.sleep {
            Some(s) => cosine(live, s)?,
            None => 1.0 - clarity,
        };
        if track_peak && self.peak.as_ref().is_none_or(|(d, _)| sleep_dir > *d) {
            self.peak = Some((sleep_dir, live.to_vec()));
        }
        Some(AnchorScores { clarity, sleep_dir })
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn clear_then_peak_then_sleep() {
        let mut a = Anchors::default();
        assert!(a.observe("m", &[1.0, 0.0], true).is_none());
        a.capture_clear("m", &[1.0, 0.0]);
        let s = a.observe("m", &[1.0, 0.0], true).unwrap();
        assert!((s.clarity - 1.0).abs() < 1e-6 && s.sleep_dir.abs() < 1e-6);
        a.observe("m", &[0.0, 1.0], true);
        a.observe("m", &[1.0, 1.0], true);
        assert!(a.capture_sleep());
        let s = a.observe("m", &[0.0, 1.0], false).unwrap();
        assert!((s.sleep_dir - 1.0).abs() < 1e-6, "V_sleep is the orthogonal peak");
        assert!(a.observe("other", &[0.0, 1.0], false).is_none());
    }
}
