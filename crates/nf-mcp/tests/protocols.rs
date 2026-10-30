#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Protocol Builder via MCP: validate, save, select, edit, delete, persist,
//! and roll back with a failed batch.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}

fn err(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_err().to_string()
}

fn draft() -> Value {
    json!({ "id": "calm-focus", "title": "Calm focus", "eyes": "open", "feature": "btr", "minutes": 15,
            "inhibit": [{ "band": "delta", "max": 0.4 }], "guard": true })
}

fn ids(s: &NfMcp) -> Vec<String> {
    run(s, "protocol.list", Value::Null).as_array().unwrap().iter().map(|p| p["protocol"]["id"].as_str().unwrap().to_owned()).collect()
}

#[test]
fn build_select_edit_delete() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let bad = run(&s, "protocol.validate", json!({ "draft": { "id": "x", "title": "", "eyes": "open", "feature": "atr", "minutes": 0 } }));
    assert_eq!(bad["ok"], false);
    let fields: Vec<&str> = bad["problems"].as_array().unwrap().iter().map(|p| p["field"].as_str().unwrap()).collect();
    assert_eq!(fields, ["id", "title", "minutes"]);
    assert!(err(&s, "protocol.delete", json!({ "id": "calm-focus", "confirm": true })).contains("no custom protocols"));

    let saved = run(&s, "protocol.save", json!({ "draft": draft() }));
    assert_eq!((saved["custom"].as_bool(), saved["inhibit"][0]["type"].as_str()), (Some(true), Some("deltaCeiling")));
    assert_eq!(ids(&s).last().unwrap(), "calm-focus");
    assert!(err(&s, "protocol.save", json!({ "draft": draft() })).contains("replace"));

    run(&s, "protocol.set", json!({ "id": "calm-focus" }));
    let st = run(&s, "feedback.status", Value::Null);
    assert_eq!(st["protocol"], "calm-focus");
    let mut d = draft();
    d["title"] = json!("Calmer focus");
    run(&s, "protocol.save", json!({ "draft": d, "replace": true }));
    assert_eq!(run(&s, "protocol.get", Value::Null)["title"], "Calmer focus");
    let back = run(&s, "protocol.draft", Value::Null);
    assert_eq!(back["draft"]["title"], "Calmer focus");
    assert_eq!(run(&s, "protocol.draft", json!({ "id": "bandStability" }))["notes"].as_array().unwrap().len(), 1);

    assert!(err(&s, "protocol.delete", json!({ "id": "calm-focus" })).contains("confirm"));
    run(&s, "protocol.delete", json!({ "id": "calm-focus", "confirm": true }));
    assert_eq!(run(&s, "protocol.get", Value::Null)["id"], "restAwake");
    assert!(!ids(&s).contains(&"calm-focus".to_owned()));
}

#[test]
fn custom_protocols_persist_and_roll_back() {
    let path = std::env::temp_dir().join(format!("nf-protocols-{}.sqlite", std::process::id()));
    let open = || NfMcp::new(Session::new().with_store(Box::new(nf_store::SqliteStore::open(&path).unwrap())), ClockMode::Manual);
    let s = open();
    run(&s, "protocol.save", json!({ "draft": draft() }));
    let mut other = draft();
    other["id"] = json!("second-one");
    let e = s
        .call(
            "command_batch",
            json!({ "steps": [
                { "id": "protocol.save", "params": { "draft": other } },
                { "id": "protocol.set", "params": { "id": "nope" } }
            ] }),
        )
        .unwrap_err()
        .to_string();
    assert!(e.contains("rolled back"), "{e}");
    drop(s);
    let again = open();
    let list = ids(&again);
    assert!(list.contains(&"calm-focus".to_owned()) && !list.contains(&"second-one".to_owned()), "{list:?}");
    std::fs::remove_file(path).ok();
}
