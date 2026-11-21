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

fn sections(s: &NfMcp) -> Vec<(String, Vec<u64>)> {
    run(s, "layers.list", Value::Null)["sections"]
        .as_array()
        .unwrap()
        .iter()
        .map(|x| {
            (x["kind"].as_str().unwrap().to_owned(), x["layers"].as_array().unwrap().iter().map(|l| l["id"].as_u64().unwrap()).collect())
        })
        .collect()
}

#[test]
fn layers_seed_edit_and_follow_the_engine() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "protocol.set", json!({ "id": "alertOpen" }));
    let l = sections(&s);
    assert_eq!(l.iter().map(|(k, v)| (k.as_str(), v.len())).collect::<Vec<_>>(), [("background", 1), ("feedback", 1), ("guardrail", 0)]);
    // A second feedback layer and a guardrail: each lands in its section.
    let added =
        run(&s, "layers.add", json!({ "kind": "feedback", "settings": { "output": "binaural", "binaural": "deep_sleep", "volume": 0.4 } }));
    run(&s, "layers.add", json!({ "kind": "guardrail" }));
    assert_eq!(sections(&s).iter().map(|(_, v)| v.len()).collect::<Vec<_>>(), [1, 2, 1]);
    assert!(err(&s, "layers.add", json!({ "kind": "background", "settings": { "output": "rain" } })).contains("does not apply"));
    // The first layer is the engine's: audio.set and layers.set agree both ways.
    let first = sections(&s)[1].1[0];
    run(&s, "layers.set", json!({ "id": first, "settings": { "output": "rain" } }));
    assert_eq!(run(&s, "audio.status", Value::Null)["settings"]["reward"], "rain");
    run(&s, "audio.set", json!({ "background": "none" }));
    assert!(sections(&s)[0].1.is_empty());
    // Editing a layer never touches the protocol; reset re-seeds from it.
    run(&s, "layers.remove", json!({ "id": added["id"] }));
    run(&s, "layers.reset", Value::Null);
    assert_eq!(run(&s, "layers.list", Value::Null)["seeded_from"], "alertOpen");
    assert!(err(&s, "layers.remove", json!({ "id": 9999 })).contains("no layer"));
}

#[test]
fn recent_protocols_follow_started_sessions_and_persist() {
    let path = std::env::temp_dir().join(format!("nf-recent-{}.sqlite", std::process::id()));
    let open = || NfMcp::new(Session::new().with_store(Box::new(nf_store::SqliteStore::open(&path).unwrap())), ClockMode::Manual);
    let s = open();
    assert!(run(&s, "protocol.recent", Value::Null).as_array().unwrap().is_empty());
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    for id in ["openMonitor", "alertOpen", "openMonitor"] {
        run(&s, "protocol.set", json!({ "id": id }));
        run(&s, "feedback.start", Value::Null);
        run(&s, "feedback.stop", Value::Null);
    }
    run(&s, "protocol.set", json!({ "id": "restAwake" })); // chosen, never started
    let recent = |s: &NfMcp| -> Vec<String> {
        run(s, "protocol.recent", Value::Null).as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap().to_owned()).collect()
    };
    assert_eq!(recent(&s), ["openMonitor", "alertOpen"]);
    drop(s);
    assert_eq!(recent(&open()), ["openMonitor", "alertOpen"]);
    std::fs::remove_file(path).ok();
}
