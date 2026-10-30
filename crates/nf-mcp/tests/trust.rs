#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Trust model: live trace == the saved session's trace, dirty reasons kept.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn adv(s: &NfMcp, secs: f64) {
    run(s, "clock.advance", json!({ "seconds": secs }));
}
fn blink(s: &NfMcp, on: bool) {
    run(s, "sim.fault", json!({ "bad_pads": [], "dropout": false, "motion": false, "blink": on, "clench": false, "drowsy": false }));
}

#[test]
fn live_and_saved_trust_agree() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 3.0);
    run(&s, "feedback.start", json!({ "minutes": 1 }));
    run(&s, "calibration.start", json!({ "anyway": true }));
    adv(&s, 75.0);
    blink(&s, true);
    adv(&s, 6.0);
    blink(&s, false);
    let live = run(&s, "feedback.trust", Value::Null);
    let t = &live["totals"];
    assert!(t["training_s"].as_u64().unwrap() > 0, "{t}");
    let reasons: Vec<&str> = t["dirty_s"].as_array().unwrap().iter().filter_map(|d| d[0].as_str()).collect();
    assert!(!reasons.is_empty() && reasons.iter().all(|r| ["blink", "no_signal"].contains(r)), "{t}");
    let rows = live["rows"].as_array().unwrap();
    assert!(rows.iter().any(|r| r["calibrating"] == true));
    let dirty = rows.iter().find(|r| r["dirty"].is_string()).unwrap();
    assert_eq!(dirty["clean"], false);
    assert!(dirty["plot_pct"].is_number(), "dirty seconds hold the last clean percentile: {dirty}");
    adv(&s, 60.0);
    let live = run(&s, "feedback.trust", Value::Null);
    let id = run(&s, "history.list", Value::Null)["sessions"][0]["id"].as_u64().unwrap();
    let saved = run(&s, "history.trust", json!({ "id": id }));
    assert_eq!(saved["totals"], live["totals"]);
    assert_eq!(saved["rows"].as_array().unwrap().len(), live["rows"].as_array().unwrap().len());
    let z = saved["totals"]["pct_in_zone"].as_f64().unwrap();
    assert!((0.0..=100.0).contains(&z));
}
