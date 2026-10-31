#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
//! Golden tests against fixtures generated from the legacy Dart engine by
//! `tools/golden-dart/gen.sh` (removed; tag `pre-rust-port`). `div_*` fixtures are intentional divergences
//! (docs/decisions.md 2026-10-29): their dedicated tests assert the fix.

use nf_feedback::{Calibration, CalibrationKind, Config, Engine, HeldBack, Input, Record};
use serde_json::Value;

struct Run {
    golden: Value,
    cal: Option<nf_feedback::CalibrationResult>,
    engine: Engine,
    /// Engine right after calibration (before play adapts it).
    calibrated: Engine,
    records: Vec<Record>,
}

fn load(name: &str) -> Value {
    let p = format!("{}/tests/golden/{name}.json", env!("CARGO_MANIFEST_DIR"));
    serde_json::from_str(&std::fs::read_to_string(p).unwrap()).unwrap()
}

fn inputs(v: &Value) -> Vec<Input> {
    serde_json::from_value(v.clone()).unwrap()
}

fn run_with(golden: Value, map: impl Fn(Input) -> Input) -> Run {
    let cfg: Config = serde_json::from_value(golden["config"].clone()).unwrap();
    let kind = golden["config"]["calibration"].as_str().unwrap();
    let (cal, mut engine) = if kind == "skip" {
        (None, Engine::new(cfg))
    } else {
        let k = if kind == "staged" { CalibrationKind::Staged } else { CalibrationKind::Single };
        let mut c = Calibration::new(&cfg, k);
        let mut last = 0.0;
        for i in inputs(&golden["calibration_inputs"]).into_iter().map(&map) {
            last = i.t;
            if !c.push(&i) {
                break;
            }
        }
        let r = c.finish(last);
        let e = Engine::from_calibration(cfg, &r);
        (Some(r), e)
    };
    let calibrated = engine.clone();
    let records = inputs(&golden["play_inputs"]).into_iter().map(&map).map(|i| engine.step(&i)).collect();
    Run { golden, cal, engine, calibrated, records }
}

fn run(name: &str) -> Run {
    run_with(load(name), |i| i)
}

fn close(a: Option<f64>, b: &Value) -> bool {
    match (a, b.as_f64()) {
        (None, None) => b.is_null(),
        (Some(x), Some(y)) => (x - y).abs() <= 1e-9 * y.abs().max(1.0),
        _ => false,
    }
}

/// Indices of records that differ from the golden.
fn diffs(r: &Run) -> Vec<(usize, String)> {
    let g = r.golden["records"].as_array().unwrap();
    assert_eq!(g.len(), r.records.len());
    let mut out = Vec::new();
    for (i, (rec, exp)) in r.records.iter().zip(g).enumerate() {
        let got = serde_json::to_value(rec).unwrap();
        for k in ["native", "pct", "thr", "thr_pct", "success_rate"] {
            if !close(rec_f(&got, k), &exp[k]) {
                out.push((i, format!("{k}: got {} want {}", got[k], exp[k])));
            }
        }
        for k in ["produced", "in_target", "held_back", "dirty", "warn", "chime", "muted"] {
            if got[k] != exp[k] {
                out.push((i, format!("{k}: got {} want {}", got[k], exp[k])));
            }
        }
        match (rec.adapt, exp.get("adapt")) {
            (None, None) => {}
            (Some(a), Some(e)) if close(a.from, &e["from"]) && close(a.to, &e["to"]) => {}
            (a, e) => out.push((i, format!("adapt: got {a:?} want {e:?}"))),
        }
    }
    out
}

fn rec_f(v: &Value, k: &str) -> Option<f64> {
    v[k].as_f64()
}

fn check_calibration(r: &Run) {
    let (Some(c), g) = (&r.cal, &r.golden["calibration"]) else { return };
    assert_eq!(c.consumed as u64, g["consumed"].as_u64().unwrap(), "consumed");
    assert_eq!(u64::from(c.valid_seconds), g["valid_seconds"].as_u64().unwrap(), "valid");
    assert_eq!(u64::from(c.wall_seconds), g["wall_seconds"].as_u64().unwrap(), "wall");
    assert_eq!(r.calibrated.baseline().len() as u64, g["baseline_n"].as_u64().unwrap(), "baseline_n");
    assert_eq!(c.guard_samples.len() as u64, g["guard_n"].as_u64().unwrap(), "guard_n");
    assert!(close(r.calibrated.threshold(), &g["threshold"]), "threshold");
    assert!(close(r.calibrated.baseline().mean(), &g["baseline_mean"]), "mean");
    assert!(close(r.calibrated.baseline().sd(), &g["baseline_sd"]), "sd");
    assert!(close(r.calibrated.baseline_cv(), &g["baseline_cv"]), "cv");
    assert!(close(r.calibrated.guard_threshold(), &g["guard_threshold"]), "guard thr");
}

fn assert_golden(name: &str) {
    let r = run(name);
    assert!(r.golden.get("divergence").is_none(), "{name} is a divergence fixture");
    check_calibration(&r);
    let d = diffs(&r);
    assert!(d.is_empty(), "{name}: {} diffs, first: {:?}", d.len(), &d[..d.len().min(5)]);
}

macro_rules! golden {
    ($($n:ident),*) => { $( #[test] fn $n() { assert_golden(stringify!($n)); } )* };
}
golden!(
    calib_single_clean,
    calib_single_dropouts,
    calib_staged,
    adapt_up_cap,
    adapt_down,
    adapt_reset,
    inhibit_beta_delta,
    reject_movement_pads,
    stability,
    guard_band_delta
);

#[test]
fn cap_is_mean_plus_1_5_sd() {
    let r = run("adapt_up_cap");
    let b = r.engine.baseline();
    let cap = b.mean().unwrap() + 1.5 * b.sd().unwrap();
    assert!((r.engine.threshold().unwrap() - cap).abs() < 1e-12);
}

// ---------- intentional divergences ----------

/// Fix 1: windows run on sample time. The golden's wall clock jumps 120 s
/// (pause) while t continues; Rust output must ignore wall time entirely.
#[test]
fn div_wall_clock_uses_sample_time() {
    let r = run("div_wall_clock");
    check_calibration(&r);
    let d = diffs(&r);
    assert!(d.iter().all(|(i, _)| *i >= 100), "pre-pause must match: {:?}", &d[..d.len().min(3)]);
    assert!(!d.is_empty(), "golden should show the wall-clock artifact");
    // Rust: success window never resets at the pause → stays defined.
    assert!(r.records[100..].iter().all(|x| x.success_rate.is_some()));
}

/// Fix 2: no `> 1.0` reward fallback without a baseline threshold.
#[test]
fn div_no_threshold_never_rewards() {
    let r = run("div_no_threshold");
    let dart_hits = r.golden["records"].as_array().unwrap().iter().filter(|x| x["in_target"] == true).count();
    assert!(dart_hits > 0);
    assert!(r.records.iter().all(|x| x.in_target == Some(false)));
    assert!(r.records.iter().all(|x| x.held_back.as_deref() == Some(&[HeldBack::NoThreshold][..])));
}

/// Fix 3: reward feature and limits use the same (quality ≥ 80) pads.
#[test]
fn div_same_pads_feature_from_usable_pads() {
    let r = run("div_same_pads");
    let dart: Vec<f64> = r.golden["records"].as_array().unwrap().iter().map(|x| x["native"].as_f64().unwrap()).collect();
    assert!(dart.iter().any(|v| (v - 1.4).abs() > 1e-6), "legacy mixed the bad pad in");
    assert!(r.records.iter().all(|x| (x.native.unwrap() - 1.4).abs() < 1e-12));
}

/// Fix 4a: uptrain + muffle → muted seconds are not rewarded (Dart rewarded silently).
#[test]
fn div_mute_uptrain_withholds_reward() {
    let r = run("div_mute_uptrain");
    let g = r.golden["records"].as_array().unwrap();
    assert!(g.iter().any(|x| x["muted"] == true && x["in_target"] == true));
    // The guard verdict of second i blocks reward from second i+1 (legacy order).
    for w in r.records.windows(2) {
        if w[0].muted == Some(true) {
            assert_eq!(w[1].in_target, Some(false));
        }
    }
    assert!(r.records.iter().any(|x| x.held_back.as_ref().is_some_and(|h| h.contains(&HeldBack::Guard))));
}

/// Fix 4b: stability + muffle=false → the guard warns but does not block.
#[test]
fn div_mute_stability_respects_muffle_flag() {
    let r = run("div_mute_stability");
    let g = r.golden["records"].as_array().unwrap();
    assert!(g.iter().any(|x| x["held_back"].as_array().is_some_and(|h| !h.is_empty())));
    assert!(r.records.iter().any(|x| x.warn == Some(true)));
    assert!(r.records.iter().all(|x| x.held_back.as_ref().is_none_or(|h| !h.contains(&HeldBack::Guard))));
}
