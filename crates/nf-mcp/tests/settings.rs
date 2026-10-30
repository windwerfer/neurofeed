#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Band Stability settings through MCP `command_run`.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Result<Value, String> {
    s.call("command_run", json!({ "id": id, "params": params })).map_err(|e| e.to_string())
}

#[test]
fn stability_set_validates_applies_and_locks_during_a_session() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let st = |s: &NfMcp| run(s, "feedback.status", Value::Null).unwrap()["stability"].clone();
    assert_eq!(st(&s), json!({ "window": 10, "difficulty": 0.1 }));
    assert!(run(&s, "stability.set", json!({ "window": 31 })).is_err());
    assert!(run(&s, "stability.set", json!({ "difficulty": 0.6 })).is_err());
    assert_eq!(st(&s)["window"], 10, "failed command leaves state unchanged");
    run(&s, "stability.set", json!({ "window": 20, "difficulty": 0.25 })).unwrap();
    assert_eq!(st(&s), json!({ "window": 20, "difficulty": 0.25 }));
    // Locked while a session runs.
    run(&s, "device.connect", json!({ "id": "sim:muse_s" })).unwrap();
    run(&s, "protocol.set", json!({ "id": "bandStability" })).unwrap();
    run(&s, "feedback.start", json!({ "minutes": 2 })).unwrap();
    let e = run(&s, "stability.set", json!({ "window": 5 })).unwrap_err();
    assert!(e.contains("session"), "{e}");
    run(&s, "feedback.stop", Value::Null).unwrap();
    run(&s, "stability.set", json!({ "reset": true })).unwrap();
    assert_eq!(st(&s), json!({ "window": 10, "difficulty": 0.1 }));
}
