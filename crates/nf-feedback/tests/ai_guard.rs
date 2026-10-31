//! AI guard lane: Sleep Guard (guard only, staged calibration, AI samples)
//! and the fixed / percentile cut.
#![allow(clippy::unwrap_used)]

use nf_feedback::{protocol, Calibration, Engine, Input, STAGED_TIMED_S};

fn sec(t: f64, ai: Option<f64>) -> Input {
    Input { t, pads: vec![[0.2, 0.2, 0.3, 0.2, 0.1]; 4], quality: vec![100.0; 4], artifact: None, ai, feature: None }
}

fn calibrate(
    cfg: &nf_feedback::Config,
    kind: nf_feedback::CalibrationKind,
    ai: impl Fn(usize) -> Option<f64>,
) -> nf_feedback::CalibrationResult {
    let mut cal = Calibration::new(cfg, kind);
    let mut t = 0.0;
    for i in 0..200 {
        if !cal.push(&sec(t, ai(i))) {
            break;
        }
        t += 1.0;
    }
    cal.finish(t)
}

#[test]
fn sleep_guard_is_guard_only_with_staged_calibration() {
    let p = protocol("sleepGuard").unwrap();
    assert!(p.unavailable.is_none() && p.guard_only);
    assert_eq!(p.calibration(), nf_feedback::CalibrationKind::Staged);
    let cfg = p.config_with_ai_guard(60, 75, None);
    // Seconds without an AI score are not usable for a guard-only baseline.
    let res = calibrate(&cfg, p.calibration(), |i| (i % 2 == 0).then_some(0.1 + (i % 10) as f64 / 100.0));
    assert!(res.reward_samples.is_empty(), "no reward lane");
    assert!(!res.guard_samples.is_empty());
    assert!(res.guard_samples.len() as u32 == res.valid_seconds);
    assert!(res.consumed as u32 > STAGED_TIMED_S);
}

#[test]
fn fixed_cut_warns_above_and_never_rewards() {
    let p = protocol("sleepGuard").unwrap();
    let cfg = p.config_with_ai_guard(60, 75, Some(0.5));
    let res = calibrate(&cfg, p.calibration(), |_| Some(0.2));
    let mut e = Engine::from_calibration(cfg, &res);
    assert_eq!(e.guard_threshold(), Some(0.5));
    let r = e.step(&sec(500.0, Some(0.7)));
    assert_eq!((r.warn, r.chime, r.in_target), (Some(true), Some(true), None));
    let r = e.step(&sec(501.0, Some(0.3)));
    assert_eq!(r.warn, Some(false));
    // Percentile mode re-reads the calibration (all 0.2).
    assert_eq!(e.set_guard_fixed(None), Some(0.2));
}

#[test]
fn ai_guard_on_rest_awake_keeps_the_reward_lane() {
    let p = protocol("restAwake").unwrap();
    let cfg = p.config_with_ai_guard(60, 75, Some(0.5));
    let res = calibrate(&cfg, p.calibration(), |_| None);
    assert!(!res.reward_samples.is_empty() && res.guard_samples.is_empty());
    let mut e = Engine::from_calibration(cfg, &res);
    let r = e.step(&sec(100.0, Some(0.9)));
    assert_eq!((r.warn, r.muted), (Some(true), Some(true)));
    assert!(r.in_target.is_some());
}

#[test]
fn guard_decision_scale_fixed_and_percentile() {
    let p = protocol("sleepGuard").unwrap();
    let cfg = p.config_with_ai_guard(60, 75, Some(0.5));
    let res = calibrate(&cfg, p.calibration(), |i| Some(0.1 + (i % 10) as f64 / 20.0));
    let mut e = Engine::from_calibration(cfg, &res);
    // Fixed cut: P × 100 against cut × 100.
    let r = e.step(&sec(500.0, Some(0.7)));
    assert!((r.guard_plot.unwrap() - 70.0).abs() < 1e-9);
    assert!((r.guard_line.unwrap() - 50.0).abs() < 1e-9);
    // Percentile: baseline rank against the warning percentile.
    e.set_guard_fixed(None);
    let r = e.step(&sec(501.0, Some(10.0)));
    assert_eq!(r.guard_line, Some(75.0));
    assert!(r.guard_plot.unwrap() > 99.0, "above every baseline sample");
    let r = e.step(&sec(502.0, None));
    assert_eq!((r.guard_plot, r.guard_line), (None, Some(75.0)));
}
