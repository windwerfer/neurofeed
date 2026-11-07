//! Analysis channel exclusion (global, not a view filter) and the
//! contact-quality hint. Contract: `.ai/contracts/analysis-exclusion.md`.
//!
//! An excluded channel is left out of **every derived** result: feedback
//! inputs, band/PSD/histogram/spectrogram aggregates, features, the AI
//! model input (which then reports unavailable instead of changing its
//! channel schema). It is **never** removed from raw data: the signal ring,
//! `raw.get`, recordings, exports and streaming keep every channel.
//!
//! Exclusions are per connection by default and reset on disconnect or
//! device switch. "Remember" stores them per stable device id **and**
//! channel name (never an index), restored visibly on the next connect of
//! that device. Re-including a channel also forgets a remembered exclusion.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// Exclusions of the connected device and remembered ones per device id.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Analysis {
    /// Device the current exclusions belong to.
    #[serde(skip)]
    pub device: Option<String>,
    /// Excluded channel names of the connected device (this connection).
    #[serde(skip)]
    pub excluded: BTreeSet<String>,
    /// Remembered exclusions restored on connect (shown until acknowledged).
    #[serde(skip)]
    pub restored: Vec<String>,
    /// Persisted: device id → channel names.
    pub remembered: BTreeMap<String, BTreeSet<String>>,
    #[serde(skip)]
    pub hint: Hint,
}

impl Analysis {
    /// A device connected: drop the previous device's exclusions, restore
    /// remembered ones for this id that name existing channels.
    pub fn connect(&mut self, device: &str, channels: &[String]) {
        self.excluded =
            self.remembered.get(device).map(|r| r.iter().filter(|n| channels.contains(n)).cloned().collect()).unwrap_or_default();
        self.restored = self.excluded.iter().cloned().collect();
        self.device = Some(device.to_owned());
        self.hint = Hint::default();
    }

    /// Disconnect or switch: session exclusions never leak to another device.
    pub fn disconnect(&mut self) {
        self.device = None;
        self.excluded.clear();
        self.restored.clear();
        self.hint = Hint::default();
    }

    pub fn is_excluded(&self, name: &str) -> bool {
        self.excluded.contains(name)
    }

    pub fn is_remembered(&self, name: &str) -> bool {
        self.device.as_ref().and_then(|d| self.remembered.get(d)).is_some_and(|r| r.contains(name))
    }

    /// Exclude `name`; `remember` also stores it for this device id.
    pub fn exclude(&mut self, name: &str, remember: bool) {
        self.excluded.insert(name.to_owned());
        if remember {
            if let Some(d) = &self.device {
                self.remembered.entry(d.clone()).or_default().insert(name.to_owned());
            }
        }
        self.hint.dismiss(name);
    }

    /// Include `name` again. Returns true when a remembered exclusion was
    /// forgotten too (it will not come back on the next connect).
    pub fn include(&mut self, name: &str) -> bool {
        self.excluded.remove(name);
        self.restored.retain(|n| n != name);
        let Some(d) = self.device.clone() else { return false };
        let Some(r) = self.remembered.get_mut(&d) else { return false };
        let was = r.remove(name);
        if r.is_empty() {
            self.remembered.remove(&d);
        }
        was
    }

    /// Indices of channels that analysis may use (device order).
    pub fn eligible(&self, channels: &[String]) -> Vec<usize> {
        (0..channels.len()).filter(|&i| !self.excluded.contains(&channels[i])).collect()
    }

    /// `selected` (a view's display choice) ∩ eligible. Empty stays empty:
    /// callers show "no eligible channel", never fall back to all.
    pub fn eligible_of(&self, channels: &[String], selected: &[usize]) -> Vec<usize> {
        selected.iter().copied().filter(|&i| channels.get(i).is_some_and(|n| !self.excluded.contains(n))).collect()
    }
}

/// Seconds a pattern must hold before the hint shows.
pub const HINT_SUSTAIN_S: f64 = 60.0;
/// "Good" contact: the app's existing usable gate (`nf_dsp::USABLE_QUALITY`,
/// = feedback `SIGNAL_GOOD`; Muse: 1 s conditioned std 1–15 µV with little
/// mains; Crown: its own signalQuality ≥ 0.75 mapped onto 80).
pub const HINT_GOOD: f64 = nf_dsp::USABLE_QUALITY;
/// "Persistently poor": below the score's own 50 tier (Muse: std > 40 µV,
/// flat < 1 µV, or strong mains; Crown: signalQuality < ~0.47).
pub const HINT_POOR: f64 = 50.0;

/// Non-modal "consider excluding X" hint. Never excludes anything itself.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Hint {
    /// Channel → time its poor-while-others-good pattern started.
    since: BTreeMap<String, f64>,
    /// Shown (once per connection and channel) or dismissed.
    done: BTreeSet<String>,
    /// The channel currently suggested.
    pub active: Option<String>,
}

/// One second of contact-quality evidence.
pub struct HintInput<'a> {
    pub t: f64,
    pub channels: &'a [String],
    /// Fresh per-channel quality (`None` = stale / missing / unsupported).
    pub quality: Option<&'a [f32]>,
    /// Movement score (g); `None` = no accelerometer: no hint at all.
    pub movement: Option<f64>,
}

impl Hint {
    pub fn dismiss(&mut self, name: &str) {
        self.done.insert(name.to_owned());
        self.since.remove(name);
        if self.active.as_deref() == Some(name) {
            self.active = None;
        }
    }

    pub fn step(&mut self, a: &Analysis, x: &HintInput) {
        let ok = x.movement.is_some_and(|m| m.is_finite() && m <= nf_dsp::MOVEMENT_GATE);
        let Some(q) = x.quality.filter(|q| ok && q.len() == x.channels.len()) else {
            self.since.clear();
            self.active = None;
            return;
        };
        let elig = a.eligible(x.channels);
        let good = elig.iter().filter(|&&i| f64::from(q[i]) >= HINT_GOOD).count();
        let poor: Vec<&String> = elig.iter().filter(|&&i| f64::from(q[i]) < HINT_POOR).map(|&i| &x.channels[i]).collect();
        self.since.retain(|n, _| good >= 2 && poor.contains(&n));
        if good < 2 {
            self.active = None;
            return;
        }
        for n in poor {
            self.since.entry(n.clone()).or_insert(x.t);
        }
        if self.active.as_ref().is_some_and(|n| !self.since.contains_key(n)) {
            self.active = None;
        }
        if self.active.is_none() {
            let due =
                self.since.iter().find(|(n, s)| !self.done.contains(*n) && x.t - **s >= HINT_SUSTAIN_S - 1e-9).map(|(n, _)| n.clone());
            if let Some(n) = due {
                self.done.insert(n.clone()); // once per connection
                self.active = Some(n);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    fn ch() -> Vec<String> {
        ["TP9", "AF7", "AF8", "TP10"].map(String::from).to_vec()
    }

    #[test]
    fn remember_is_per_device_and_name_and_include_forgets() {
        let mut a = Analysis::default();
        a.connect("muse-1", &ch());
        a.exclude("AF7", false);
        a.exclude("TP10", true);
        assert_eq!(a.eligible(&ch()), vec![0, 2]);
        a.disconnect();
        assert!(a.excluded.is_empty());
        a.connect("muse-2", &ch());
        assert!(a.excluded.is_empty(), "no leak to another device");
        a.connect("muse-1", &["TP10".into(), "TP9".into()]);
        assert_eq!(a.excluded.iter().collect::<Vec<_>>(), vec!["TP10"], "by name, not index; session-only AF7 gone");
        assert_eq!(a.restored, vec!["TP10".to_string()]);
        assert!(a.include("TP10"));
        a.disconnect();
        a.connect("muse-1", &ch());
        assert!(a.excluded.is_empty(), "re-included = forgotten");
        assert!(a.remembered.is_empty());
    }

    #[test]
    fn eligible_of_never_falls_back_to_all() {
        let mut a = Analysis::default();
        a.connect("d", &ch());
        a.exclude("AF7", false);
        assert_eq!(a.eligible_of(&ch(), &[1]), Vec::<usize>::new());
        assert_eq!(a.eligible_of(&ch(), &[1, 2]), vec![2]);
    }

    fn run(h: &mut Hint, a: &Analysis, secs: std::ops::Range<u32>, q: Option<[f32; 4]>, mv: Option<f64>) {
        for t in secs {
            h.step(a, &HintInput { t: f64::from(t), channels: &ch(), quality: q.as_ref().map(|q| &q[..]), movement: mv });
        }
    }

    #[test]
    fn hint_needs_a_sustained_still_pattern_and_shows_once() {
        let mut a = Analysis::default();
        a.connect("d", &ch());
        let pat = Some([95.0, 20.0, 90.0, 88.0]);
        let mut h = Hint::default();
        run(&mut h, &a, 0..59, pat, Some(0.01));
        assert_eq!(h.active, None, "59 s is not enough");
        run(&mut h, &a, 59..61, pat, Some(0.01));
        assert_eq!(h.active.as_deref(), Some("AF7"));
        h.dismiss("AF7");
        run(&mut h, &a, 61..300, pat, Some(0.01));
        assert_eq!(h.active, None, "no nagging after dismiss");
        // Interruptions reset the timer: movement, stale quality, no movement sensor.
        for (q, mv) in [(pat, Some(0.2)), (None, Some(0.01)), (pat, None), (Some([95.0, 20.0, 60.0, 60.0]), Some(0.01))] {
            let mut h = Hint::default();
            run(&mut h, &a, 0..40, pat, Some(0.01));
            run(&mut h, &a, 40..41, q, mv);
            run(&mut h, &a, 41..90, pat, Some(0.01));
            assert_eq!(h.active, None, "{q:?} {mv:?} resets");
        }
        // An excluded channel is not suggested and does not count as good.
        let mut h = Hint::default();
        a.exclude("AF7", false);
        run(&mut h, &a, 0..120, pat, Some(0.01));
        assert_eq!(h.active, None);
    }
}
