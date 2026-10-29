#![allow(clippy::panic)]
//! Drive the core purely through MCP tool calls.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp, ToolError};
use serde_json::{json, Value};

fn server() -> NfMcp {
    NfMcp::new(Session::new(), ClockMode::Manual)
}

fn ok(s: &NfMcp, tool: &str, args: Value) -> Value {
    s.call(tool, args).unwrap_or_else(|e| panic!("{tool}: {e}"))
}

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    ok(s, "command_run", json!({ "id": id, "params": params }))
}

#[test]
fn every_command_is_listed_and_described_with_a_schema() {
    let s = server();
    let list = ok(&s, "command_list", json!({}));
    assert_eq!(list.as_array().map(Vec::len), Some(Session::commands().len()));
    for spec in Session::commands() {
        let d = ok(&s, "command_describe", json!({ "id": spec.id }));
        assert_eq!(d["params_schema"]["type"], "object", "{}", spec.id);
        assert_eq!(d["params_schema"]["additionalProperties"], false);
    }
    let tools: Vec<_> = NfMcp::tools().into_iter().map(|t| t.name.to_string()).collect();
    for t in ["command_list", "command_describe", "command_run", "command_batch", "status", "bands_get", "device_list", "clock_advance"] {
        assert!(tools.contains(&t.to_owned()), "{t}");
    }
}

#[test]
fn disabled_reason_is_exposed() {
    let s = server();
    let d = ok(&s, "command_describe", json!({ "id": "stream.pause" }));
    assert_eq!(d["enabled"], false);
    assert_eq!(d["disabled_reason"], "no device connected");
    assert!(matches!(s.call("command_run", json!({ "id": "stream.pause" })), Err(ToolError::Failed(_))));
}

#[test]
fn full_session_via_tools_with_manual_clock() {
    let s = server();
    let devices = ok(&s, "device_list", json!({}));
    assert!(devices.as_array().is_some_and(|d| d.iter().any(|d| d["id"] == "sim:muse")));

    let rev0 = ok(&s, "status", json!({}))["revision"].as_u64();
    run(&s, "device.connect", json!({ "id": "sim:muse" }));
    assert_ne!(ok(&s, "status", json!({}))["revision"].as_u64(), rev0);
    assert_eq!(ok(&s, "bands_get", json!({}))["channels"], json!([]), "no data before time moves");

    let t = ok(&s, "clock_advance", json!({ "seconds": 3 }));
    assert!((t["time"].as_f64().unwrap_or_default() - 3.0).abs() < 1e-6);
    assert!(run(&s, "device.status", json!({}))["snapshots"].as_u64().unwrap_or_default() >= 29);

    let abs = ok(&s, "bands_get", json!({}));
    let ch = &abs["channels"];
    assert_eq!(ch.as_array().map(Vec::len), Some(4));
    assert_eq!(ch[0]["channel"], "TP9");
    assert!(ch[0]["delta"].as_f64() > ch[0]["gamma"].as_f64(), "1/f falloff");

    run(&s, "scale.set", json!({ "scale": "relative" }));
    let rel = ok(&s, "bands_get", json!({}));
    let sum: f64 = ["delta", "theta", "alpha", "beta", "gamma"].iter().filter_map(|b| rel["channels"][1][b].as_f64()).sum();
    assert!((sum - 1.0).abs() < 1e-3);

    run(&s, "stream.pause", json!({}));
    let n = run(&s, "device.status", json!({}))["snapshots"].clone();
    ok(&s, "clock_advance", json!({ "seconds": 10 }));
    assert_eq!(run(&s, "device.status", json!({}))["snapshots"], n);
    run(&s, "stream.resume", json!({}));

    ok(
        &s,
        "command_batch",
        json!({ "steps": [
            { "id": "view.set", "params": { "view": "settings" } },
            { "id": "sidebar.set", "params": { "open": false } }
        ]}),
    );
    let st = ok(&s, "status", json!({}));
    assert_eq!((st["view"].as_str(), st["sidebar_open"].as_bool(), st["paused"].as_bool()), (Some("settings"), Some(false), Some(false)));
    assert_eq!(run(&s, "view.list", json!({})).as_array().map(Vec::len), Some(10));

    let events = run(&s, "events.drain", json!({}));
    let kinds: Vec<_> = events.as_array().into_iter().flatten().filter_map(|e| e["event"].as_str()).collect();
    assert!(kinds.contains(&"connected") && kinds.contains(&"paused") && kinds.contains(&"view_changed"));
}

#[test]
fn batch_rolls_back_via_mcp() {
    let s = server();
    let before = ok(&s, "status", json!({}));
    let r = s.call(
        "command_batch",
        json!({ "steps": [
            { "id": "view.set", "params": { "view": "psd" } },
            { "id": "device.connect", "params": { "id": "ble:missing" } }
        ]}),
    );
    assert!(matches!(&r, Err(ToolError::Failed(m)) if m.contains("rolled back")), "{r:?}");
    assert_eq!(ok(&s, "status", json!({})), before);
}

#[test]
fn simulator_is_deterministic_and_configurable() {
    let go = |seed: u64, alpha: f64| {
        let s = server();
        run(&s, "sim.configure", json!({ "seed": seed, "alpha_gain": alpha }));
        run(&s, "device.connect", json!({ "id": "sim:crown" }));
        ok(&s, "clock_advance", json!({ "seconds": 5.2 }));
        ok(&s, "bands_get", json!({ "scale": "absolute" }))
    };
    assert_eq!(go(7, 0.45), go(7, 0.45));
    assert_ne!(go(7, 0.45), go(8, 0.45));
    assert!(go(7, 2.0)["channels"][0]["alpha"].as_f64() > go(7, 0.0)["channels"][0]["alpha"].as_f64());
    assert_eq!(go(7, 0.45)["channels"].as_array().map(Vec::len), Some(8));
}

#[test]
fn bad_input_is_an_error_not_a_panic() {
    let s = server();
    assert!(matches!(s.call("no_such_tool", json!({})), Err(ToolError::Invalid(_))));
    assert!(matches!(s.call("status", json!({ "x": 1 })), Err(ToolError::Invalid(_))));
    assert!(matches!(s.call("command_run", json!({ "id": "nope" })), Err(ToolError::Failed(_))));
    assert!(s.call("clock_advance", json!({ "seconds": -1 })).is_err());
    assert!(s.call("clock_advance", json!({ "seconds": 99999 })).is_err());
    assert!(s.call("command_run", json!({ "id": "view.set", "params": { "view": 3 } })).is_err());
}
