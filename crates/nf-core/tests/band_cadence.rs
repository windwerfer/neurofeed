#![allow(clippy::unwrap_used)]
//! Measured band snapshot cadence from the simulator (Bands Follow design).
use serde_json::json;

#[test]
fn simulator_band_snapshots_cadence() {
    let mut s = nf_core::Session::new();
    s.call("device.connect", json!({ "id": "sim:muse_s" })).unwrap();
    s.call("clock.advance", json!({ "seconds": 20.0 })).unwrap();
    let b = &s.state().bands;
    let t: Vec<f64> = b.range(f64::NEG_INFINITY, f64::INFINITY).map(|x| x.time).collect();
    let d: Vec<f64> = t.windows(2).map(|w| w[1] - w[0]).collect();
    let mean = d.iter().sum::<f64>() / d.len() as f64;
    assert!((mean - 0.1).abs() < 0.01, "band snapshots ~10 Hz, got {mean}");
    eprintln!(
        "snapshots {} over {:.2}s mean dt {mean:.4} min {:.4} max {:.4}",
        t.len(),
        t.last().unwrap() - t[0],
        d.iter().cloned().fold(9.0, f64::min),
        d.iter().cloned().fold(0.0, f64::max)
    );
}
