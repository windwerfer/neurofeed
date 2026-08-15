//! Sleep-guardrail scoring state: anchor vectors + clarity/sleep-direction
//! cosine math (analysis-side).
//!
//! The forwarder (`api::muse`) runs one inference per second on a rolling EEG
//! window while a model is loaded and the guardrail is enabled, then feeds the
//! pooled latent here via [`set_live_embedding`]. Calibration (Dart side) calls
//! [`capture_anchor`] to freeze `V_clear` (awake) and `V_sleep` (deepest rest).
//! Anchors are tagged with the model kind they were captured under so a LUNA
//! vector is never compared against a REVE one.
//!
//! Score semantics (see `lib/src/feedback/protocol.dart`, Sleep-Edge Rest):
//! * `clarity` = cosine(live, V_clear).
//! * `sleep_dir` starts as `1 - clarity`, then switches to cosine(live, V_sleep)
//!   once V_sleep exists.
//! * A warning fires when `sleep_dir` exceeds the session threshold (a
//!   percentile of the rest baseline, evaluated Dart-side) or the classical
//!   delta rail trips (also Dart-side). The reward is never modulated.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

/// Anchor name for the awake/clear reference vector.
pub const ANCHOR_CLEAR: &str = "clear";
/// Anchor name for the deepest-rest reference vector.
pub const ANCHOR_SLEEP: &str = "sleep";

/// A captured reference embedding, tagged with the model kind it was taken
/// under so a LUNA vector is never compared against a REVE one.
#[derive(Clone)]
pub struct Anchor {
    pub kind: String,
    pub vector: Vec<f32>,
}

#[derive(Default)]
struct Guardrail {
    /// Model kind currently driving the guardrail (`""` = disabled).
    kind: String,
    /// Latest pooled live embedding from the most recent inference.
    live: Option<Anchor>,
    /// Eyes-open / awake reference vector captured during calibration.
    clear: Option<Anchor>,
    /// Deepest-rest reference vector captured during calibration.
    sleep: Option<Anchor>,
    /// The live embedding with the highest `sleep_dir` seen since enable
    /// (used as the V_sleep source at calibration end).
    sleep_peak: Option<Anchor>,
    /// `sleep_dir` value of [`Self::sleep_peak`] (`f32::NEG_INFINITY` when unset).
    sleep_peak_dir: f32,
    /// Dim of the live vector (informational, sent to Dart in ReveDto).
    live_dim: u32,
}

static GUARDRAIL: Mutex<Guardrail> = Mutex::new(Guardrail {
    kind: String::new(),
    live: None,
    clear: None,
    sleep: None,
    sleep_peak: None,
    sleep_peak_dir: f32::NEG_INFINITY,
    live_dim: 0,
});

/// True while a scoring inference is in flight (the forwarder coalesces 1 Hz
/// ticks around slow runs instead of stacking blocking tasks).
static SCORING: AtomicBool = AtomicBool::new(false);

fn lock() -> std::sync::MutexGuard<'static, Guardrail> {
    GUARDRAIL.lock().unwrap_or_else(|e| e.into_inner())
}

/// Enable the guardrail for [kind] and drop any anchors/live vector. Returns
/// false when [kind] is not a known model kind.
pub fn enable(kind: &str) -> bool {
    let valid = kind == crate::analysis::luna::KIND_REVE_BASE
        || kind == crate::analysis::luna::KIND_LUNA_BASE
        || kind == crate::analysis::luna::KIND_LUNA_LARGE;
    if !valid {
        return false;
    }
    let mut g = lock();
    g.kind = kind.to_string();
    g.live = None;
    g.clear = None;
    g.sleep = None;
    g.sleep_peak = None;
    g.sleep_peak_dir = f32::NEG_INFINITY;
    g.live_dim = 0;
    true
}

/// Disable the guardrail and drop all state.
pub fn disable() {
    *lock() = Guardrail::default();
    SCORING.store(false, Ordering::SeqCst);
}

/// Whether the guardrail is currently enabled.
pub fn is_enabled() -> bool {
    !lock().kind.is_empty()
}

/// The kind the guardrail is enabled for, if any.
pub fn active_kind() -> Option<String> {
    let g = lock();
    if g.kind.is_empty() {
        None
    } else {
        Some(g.kind.clone())
    }
}

/// Claim the scoring slot for this tick. Returns false when an inference is
/// still in flight (caller skips).
pub fn try_begin_score() -> bool {
    SCORING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
}

/// Release the scoring slot (always paired with a successful [try_begin_score]).
pub fn finish_score() {
    SCORING.store(false, Ordering::SeqCst);
}

/// Feed the pooled live embedding from the most recent inference. Updates the
/// deepest-rest peak (`V_sleep` source) relative to `V_clear`.
pub fn set_live_embedding(kind: String, vector: Vec<f32>) {
    let mut g = lock();
    if g.kind != kind {
        // Model switched mid-inference; drop the stale vector so a capture
        // can't accidentally use an old-model embedding.
        g.live = None;
        g.live_dim = 0;
        return;
    }
    g.live_dim = vector.len() as u32;
    g.live = Some(Anchor {
        kind: kind.clone(),
        vector: vector.clone(),
    });
    if let Some(clear) = g.clear.as_ref() {
        if clear.kind == kind {
            if let Some(sd) = sleep_dir(&g, &kind, Some(&vector)) {
                if sd > g.sleep_peak_dir {
                    g.sleep_peak_dir = sd;
                    g.sleep_peak = Some(Anchor { kind, vector });
                }
            }
        }
    }
}

/// Dim of the current live embedding, if one has been produced.
pub fn live_dim() -> u32 {
    lock().live_dim
}

/// Capture the current live embedding (or the deepest-rest peak) as an anchor.
/// `clear` uses the latest live vector; `sleep` uses the deepest-rest sample
/// since enable. Errors when no window has been scored yet or the model kind no
/// longer matches the enabled kind.
pub fn capture_anchor(name: &str) -> anyhow::Result<String> {
    let mut g = lock();
    if g.kind.is_empty() {
        anyhow::bail!("guardrail not enabled");
    }
    match name {
        ANCHOR_CLEAR => {
            let live = g
                .live
                .as_ref()
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("no live embedding yet — wait for a score"))?;
            if live.kind != g.kind {
                anyhow::bail!("model switched — re-enable the guardrail and re-calibrate");
            }
            g.clear = Some(live.clone());
            g.sleep_peak = None;
            g.sleep_peak_dir = f32::NEG_INFINITY;
            Ok(format!(
                "V_clear captured ({} dims, {})",
                live.vector.len(),
                live.kind
            ))
        }
        ANCHOR_SLEEP => {
            let peak = g
                .sleep_peak
                .take()
                .ok_or_else(|| anyhow::anyhow!("no rest peak yet — V_clear must be captured first"))?;
            if peak.kind != g.kind {
                anyhow::bail!("model switched — re-enable the guardrail and re-calibrate");
            }
            g.sleep = Some(peak.clone());
            Ok(format!(
                "V_sleep captured ({} dims, {}), sleep_dir={:.3}",
                peak.vector.len(),
                peak.kind,
                g.sleep_peak_dir
            ))
        }
        other => anyhow::bail!("unknown anchor: {other}"),
    }
}

/// Clear the captured anchors but keep the guardrail enabled (a fresh
/// calibration pass on the same session/model).
pub fn reset_anchors() {
    let mut g = lock();
    g.clear = None;
    g.sleep = None;
    g.sleep_peak = None;
    g.sleep_peak_dir = f32::NEG_INFINITY;
}

/// Compute (clarity, sleep_dir) from the live embedding against the anchors.
/// Returns None before the first score or before `V_clear` exists.
pub fn clarity_and_sleep_dir() -> Option<(f32, Option<f32>)> {
    let g = lock();
    let live = g.live.as_ref()?;
    if live.kind != g.kind || live.vector.is_empty() {
        return None;
    }
    let clarity = g
        .clear
        .as_ref()
        .filter(|c| c.kind == g.kind)
        .and_then(|c| cosine(&live.vector, &c.vector))
        .unwrap_or(0.0);
    let sd = sleep_dir(&g, &g.kind, Some(&live.vector))?;
    Some((clarity, Some(sd)))
}

/// `sleep_dir` for a live vector: cosine against V_sleep when it exists,
/// otherwise `1 - clarity`.
fn sleep_dir(g: &Guardrail, kind: &str, live: Option<&[f32]>) -> Option<f32> {
    let live = live?;
    if live.len() == 0 {
        return None;
    }
    if let Some(sleep) = g.sleep.as_ref() {
        if sleep.kind == *kind {
            return cosine(live, &sleep.vector);
        }
    }
    let clear = g.clear.as_ref()?;
    if clear.kind != *kind {
        return None;
    }
    cosine(live, &clear.vector).map(|c| 1.0 - c)
}

/// Cosine similarity of two equal-length vectors, None when degenerate.
fn cosine(a: &[f32], b: &[f32]) -> Option<f32> {
    if a.len() != b.len() || a.is_empty() {
        return None;
    }
    let mut dot = 0f64;
    let mut na = 0f64;
    let mut nb = 0f64;
    for (x, y) in a.iter().zip(b.iter()) {
        let x = *x as f64;
        let y = *y as f64;
        dot += x * y;
        na += x * x;
        nb += y * y;
    }
    let norm = (na * nb).sqrt();
    if norm < 1e-8 {
        return None;
    }
    Some((dot / norm) as f32)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(seed: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| (seed + i as f32).sin()).collect()
    }

    #[test]
    fn cosine_similarity() {
        let a = v(0.1, 8);
        let b = a.clone();
        assert!((cosine(&a, &b).unwrap() - 1.0).abs() < 1e-5, "same vector ≈ 1");
        let c = v(2.0, 8);
        assert!(cosine(&a, &c).unwrap().abs() < 1.0, "different vectors in (-1,1)");
        assert!(cosine(&a, &[]).is_none());
    }

    #[test]
    fn enable_capture_and_score() {
        disable();
        assert!(!is_enabled());
        assert!(enable("luna_base"));
        assert!(!enable("nope"), "unknown kind rejected");
        assert!(is_enabled());
        assert!(capture_anchor(ANCHOR_CLEAR).is_err(), "no live embedding yet");

        set_live_embedding("luna_base".to_string(), v(0.1, 16));
        assert_eq!(live_dim(), 16);
        let ok = capture_anchor(ANCHOR_CLEAR).expect("clear capture after live");
        assert!(ok.contains("V_clear"));

        // sleep_dir before V_sleep = 1 - clarity.
        let (clarity, sd) = clarity_and_sleep_dir().expect("scored");
        assert!((clarity - 1.0).abs() < 1e-5, "live == clear anchor → clarity 1");
        let sd = sd.unwrap();
        assert!((sd - 0.0).abs() < 1e-5, "1 - clarity = 0");

        // A distant live vector raises sleep_dir and feeds the sleep peak.
        set_live_embedding("luna_base".to_string(), v(3.0, 16));
        let (_, sd) = clarity_and_sleep_dir().expect("scored");
        let sd = sd.unwrap();
        assert!(sd > 0.3, "distant vector → elevated sleep_dir ({sd})");

        let ok = capture_anchor(ANCHOR_SLEEP).expect("sleep peak exists");
        assert!(ok.contains("V_sleep"));
        // After V_sleep, sleep_dir switches to cosine(live, V_sleep).
        let (_, sd) = clarity_and_sleep_dir().expect("scored");
        let sd = sd.unwrap();
        assert!(sd >= -1.0 && sd <= 1.0);

        // Model switch drops stale live and blocks capture.
        set_live_embedding("reve_base".to_string(), v(0.5, 16));
        assert!(capture_anchor(ANCHOR_CLEAR).is_err(), "kind mismatch");
        disable();
        assert!(!is_enabled());
    }
}
