#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! History through MCP: a training is auto-recorded, saved with its summary,
//! listed, read back, exported and deleted (with confirm). Runs on both
//! store backends.

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
    run(s, "clock.advance", json!({ "seconds": secs }));
}
fn phase(s: &NfMcp) -> String {
    run(s, "feedback.status", Value::Null)["phase"]["phase"].as_str().unwrap_or_default().to_owned()
}

fn train_one_minute(s: &NfMcp) {
    run(s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(s, "feedback.start", json!({ "minutes": 1, "wall_clock_unix_ms": 1_793_000_000_000.0_f64 }));
    assert_eq!(run(s, "recording.status", Value::Null)["recording"]["active"], true, "auto-recorded");
    adv(s, 5.0);
    run(s, "calibration.start", Value::Null);
    for _ in 0..200 {
        if phase(s) == "ended" {
            return;
        }
        adv(s, 1.0);
    }
    panic!("never ended: {}", phase(s));
}

fn contract(s: &NfMcp) {
    assert!(fails(s, "history.delete", json!({ "id": 1, "confirm": true })).contains("no saved sessions"));
    train_one_minute(s);
    assert_eq!(run(s, "recording.status", Value::Null)["recording"]["active"], false, "stops with the session");
    let list = run(s, "history.list", Value::Null);
    let rows = list["sessions"].as_array().unwrap();
    assert_eq!(rows.len(), 1, "{list}");
    let m = &rows[0];
    assert_eq!(m["protocol"], "restAwake");
    assert_eq!(m["started_unix_ms"], 1_793_000_000_000.0_f64);
    assert!(m["summary"]["played_s"].as_u64().unwrap() >= 59, "{m}");
    assert!(m["ppg_samples"].as_u64().unwrap() > 1000, "{m}");
    assert!(m["feedback_seconds"].as_u64().unwrap() >= 60, "{m}");
    let id = m["id"].as_u64().unwrap();

    let got = run(s, "history.get", json!({ "id": id }));
    let fb = got["feedback"].as_array().unwrap();
    assert_eq!(fb.len() as u64, m["feedback_seconds"].as_u64().unwrap());
    assert!(fb.iter().any(|r| r["value"].is_number() && r["threshold"].is_number()));
    assert_eq!(got["device"]["id"], "sim:muse_s");

    for (format, magic) in [("nfed6", &b"NFED"[..]), ("edf", &b"0       "[..])] {
        let e = run(s, "history.export", json!({ "id": id, "format": format }));
        let bytes = b64(e["base64"].as_str().unwrap());
        assert!(bytes.starts_with(magic), "{format}");
    }
    assert!(fails(s, "history.get", json!({ "id": 999 })).contains("no session 999"));
    assert!(fails(s, "history.delete", json!({ "id": id })).contains("confirm=true"));
    assert_eq!(run(s, "history.list", Value::Null)["sessions"].as_array().unwrap().len(), 1, "unconfirmed delete keeps it");
    run(s, "history.delete", json!({ "id": id, "confirm": true }));
    assert!(run(s, "history.list", Value::Null)["sessions"].as_array().unwrap().is_empty());
}

#[test]
fn history_in_memory() {
    contract(&NfMcp::new(Session::new(), ClockMode::Manual));
}

#[test]
fn history_in_sqlite_survives_a_restart() {
    let path = std::env::temp_dir().join(format!("nf-history-{}.sqlite", std::process::id()));
    let open = || Session::new().with_store(Box::new(nf_store::SqliteStore::open(&path).unwrap()));
    contract(&NfMcp::new(open(), ClockMode::Manual));
    let s = NfMcp::new(open(), ClockMode::Manual);
    train_one_minute(&s);
    let again = NfMcp::new(open(), ClockMode::Manual);
    assert_eq!(run(&again, "history.list", Value::Null)["sessions"].as_array().unwrap().len(), 1);
    std::fs::remove_file(path).ok();
}

fn b64(s: &str) -> Vec<u8> {
    let val = |c: u8| match c {
        b'A'..=b'Z' => c - b'A',
        b'a'..=b'z' => c - b'a' + 26,
        b'0'..=b'9' => c - b'0' + 52,
        b'+' => 62,
        _ => 63,
    };
    let mut out = Vec::new();
    for chunk in s.as_bytes().chunks(4) {
        let v: Vec<u8> = chunk.iter().filter(|c| **c != b'=').map(|c| val(*c)).collect();
        let n = v.iter().fold(0u32, |a, x| (a << 6) | u32::from(*x)) << (6 * (4 - v.len()));
        out.extend(&n.to_be_bytes()[1..v.len()]);
    }
    out
}
