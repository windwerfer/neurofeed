#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Shell-facing fields added in the UI pass.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}

#[test]
fn a_stopped_recording_reports_its_history_id_for_discard() {
    let s = NfMcp::new(Session::new().with_store(Box::new(nf_store::MemoryStore::default())), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "recording.start", Value::Null);
    run(&s, "clock.advance", json!({ "seconds": 3.0 }));
    let r = run(&s, "recording.stop", Value::Null);
    let id = r["saved_id"].as_u64().unwrap_or_else(|| panic!("{r}"));
    assert_eq!(run(&s, "history.list", Value::Null)["sessions"].as_array().map(Vec::len), Some(1));
    run(&s, "history.delete", json!({ "id": id, "confirm": true }));
    assert_eq!(run(&s, "history.list", Value::Null)["sessions"].as_array().map(Vec::len), Some(0));
}

#[test]
fn always_staged_runs_the_staged_recipe_for_any_protocol() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "settings.set", json!({ "always_staged": true }));
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "protocol.set", json!({ "id": "restAwake" }));
    run(&s, "clock.advance", json!({ "seconds": 5.0 }));
    run(&s, "feedback.start", json!({ "minutes": 3 }));
    run(&s, "clock.advance", json!({ "seconds": 4.0 }));
    run(&s, "calibration.start", Value::Null);
    let mut stages = Vec::new();
    for _ in 0..50 {
        run(&s, "clock.advance", json!({ "seconds": 1.0 }));
        let c = run(&s, "feedback.status", Value::Null)["calibration"].clone();
        assert_eq!(c["staged"], true, "{c}");
        stages.push(c["stage"].as_str().unwrap().to_owned());
    }
    for want in ["artifacts", "eyes_open", "eyes_closed"] {
        assert!(stages.iter().any(|s| s == want), "{want} in {stages:?}");
    }
}
