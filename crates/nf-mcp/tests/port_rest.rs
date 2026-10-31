#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! The last pre-Android port items: crash recovery, replay of a saved
//! session, the debug feature override, Crown device quality and Muse AUX.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}
fn adv(s: &NfMcp, secs: f64) {
    for _ in 0..secs as u32 {
        run(s, "clock.advance", json!({ "seconds": 1.0 }));
    }
}
fn rows(s: &NfMcp) -> Vec<Value> {
    run(s, "history.list", Value::Null)["sessions"].as_array().cloned().unwrap_or_default()
}

#[test]
fn a_crash_mid_recording_is_offered_for_recovery() {
    let path = std::env::temp_dir().join(format!("nf-recovery-{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let open = || NfMcp::new(Session::new().with_store(Box::new(nf_store::SqliteStore::open(&path).unwrap())), ClockMode::Manual);
    {
        let s = open();
        assert!(fails(&s, "recovery.restore", Value::Null).contains("no interrupted recording"));
        run(&s, "device.connect", json!({ "id": "sim:muse" }));
        run(&s, "recording.start", json!({ "wall_clock_unix_ms": 1_793_000_000_000.0_f64 }));
        adv(&s, 25.0);
        // "Crash": the process ends without recording.stop.
        std::mem::forget(s);
    }
    let s = open();
    assert!(rows(&s).is_empty());
    run(&s, "recovery.restore", Value::Null);
    let r = rows(&s);
    assert_eq!(r.len(), 1);
    assert!(r[0]["duration_s"].as_f64().unwrap() >= 19.0, "{}", r[0]);
    assert!(r[0]["eeg_samples"].as_u64().unwrap() > 4 * 256 * 19, "{}", r[0]);
    let id = r[0]["id"].as_u64().unwrap();
    assert_eq!(run(&s, "history.get", json!({ "id": id }))["device"]["id"], "sim:muse_s");
    assert!(fails(&s, "recovery.discard", Value::Null).contains("no interrupted recording"));
    drop(s);
    // A clean stop leaves nothing to recover.
    let s = open();
    run(&s, "device.connect", json!({ "id": "sim:muse" }));
    run(&s, "recording.start", Value::Null);
    adv(&s, 12.0);
    run(&s, "recording.stop", Value::Null);
    drop(s);
    let s = open();
    assert!(fails(&s, "recovery.discard", Value::Null).contains("no interrupted recording"));
    assert_eq!(rows(&s).len(), 2);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_saved_session_replays_as_the_device_and_is_not_recorded_again() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "recording.start", Value::Null);
    adv(&s, 8.0);
    run(&s, "recording.stop", Value::Null);
    let id = rows(&s)[0]["id"].as_u64().unwrap();
    run(&s, "device.disconnect", Value::Null);
    run(&s, "history.open", json!({ "id": id }));
    let st = run(&s, "signal.status", json!({}));
    assert_eq!(st["connected"], true, "{st}");
    adv(&s, 4.0);
    let st = run(&s, "signal.status", json!({}));
    assert!(st["pads"].as_array().unwrap().iter().all(|p| p["quality"].as_f64().unwrap() > 0.0), "{st}");
    assert!(fails(&s, "recording.start", Value::Null).contains("replay"));
    assert_eq!(rows(&s).len(), 1);
    assert!(fails(&s, "history.open", json!({ "id": 99 })).contains("no session"));
}

#[test]
fn feature_override_needs_debug_and_a_sane_value() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "settings.set", json!({ "debug": false }));
    assert!(fails(&s, "feedback.override", json!({ "value": 0.4 })).contains("debug"));
    run(&s, "settings.set", json!({ "debug": true }));
    run(&s, "feedback.override", json!({ "value": 0.4 }));
    assert!(fails(&s, "feedback.override", json!({ "value": 20.0 })).contains("[0, 10]"));
    run(&s, "feedback.override", json!({ "value": null }));
}

fn crown_quality(s: &NfMcp) -> Vec<f64> {
    let st = run(s, "signal.status", json!({}));
    st["pads"].as_array().unwrap().iter().map(|p| p["quality"].as_f64().unwrap()).collect()
}

#[test]
fn crown_pads_use_the_device_quality_unless_set_to_app() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:crown" }));
    adv(&s, 6.0);
    let q = crown_quality(&s);
    // 0.9 from the device maps above "good" and is identical on every pad.
    assert!(q.iter().all(|v| (v - q[0]).abs() < 1e-6 && *v >= 60.0 && *v < 100.0), "{q:?}");
    run(&s, "settings.set", json!({ "crown_quality": "app" }));
    adv(&s, 3.0);
    let a = crown_quality(&s);
    assert!(a.iter().any(|v| (v - q[0]).abs() > 1e-3), "app score differs: {a:?}");
}

#[test]
fn muse_aux_is_recorded_only_when_enabled() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let edf = |s: &NfMcp| {
        run(s, "device.connect", json!({ "id": "sim:muse" }));
        run(s, "recording.start", Value::Null);
        adv(s, 3.0);
        run(s, "recording.stop", Value::Null);
        let id = rows(s)[0]["id"].as_u64().unwrap();
        let e = run(s, "history.export", json!({ "id": id, "format": "edf" }));
        let b = e["base64"].as_str().or(e["data"].as_str()).unwrap_or_default().to_owned();
        b
    };
    let off = edf(&s);
    run(&s, "settings.set", json!({ "muse_aux": true }));
    let on = edf(&s);
    assert!(on.len() > off.len(), "AUX adds an EDF signal");
}
