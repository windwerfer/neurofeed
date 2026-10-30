#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! History import via MCP: EDF and .neurofeed round trips, refusals.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}

/// 6 s of simulated Muse S, exported as `format` (base64).
fn recorded(s: &NfMcp, format: &str) -> String {
    run(s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(s, "recording.start", json!({ "wall_clock_unix_ms": 1_709_294_400_000.0 }));
    run(s, "clock.advance", json!({ "seconds": 6.0 }));
    run(s, "recording.stop", Value::Null);
    run(s, "recording.export", json!({ "format": format }))["base64"].as_str().unwrap().to_owned()
}

#[test]
fn edf_import_round_trip_with_preview() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let data = recorded(&s, "edf");
    let req = json!({ "file_name": "rec.edf", "data_base64": data, "utc_offset_minutes": 60 });
    let p = run(&s, "history.import_preview", req.clone());
    assert_eq!(p["device"]["channels"], json!(["TP9", "AF7", "AF8", "TP10"]));
    assert_eq!(p["provenance"]["source_format"], "edf+");
    assert!(p["summary"]["kept"][1].as_str().unwrap().contains("RAW EEG"), "{p}");
    assert_eq!(run(&s, "history.list", Value::Null)["sessions"].as_array().map(Vec::len), Some(1), "preview must not save");
    let r = run(&s, "history.import", req);
    let id = r["id"].as_u64().unwrap();
    let list = run(&s, "history.list", Value::Null);
    let m = list["sessions"].as_array().unwrap().iter().find(|m| m["id"] == id).unwrap().clone();
    assert_eq!(m["device_id"], "import:edf+");
    assert_eq!(m["started_unix_ms"], 1_709_294_400_000.0);
    assert!(m["eeg_samples"].as_u64().unwrap() >= 4 * 5 * 256, "{m}");
    assert_eq!(m["import"]["raw_present"], true);
    let got = run(&s, "history.get", json!({ "id": id }));
    assert!(got["records"].as_u64().unwrap() > 0);
}

#[test]
fn imported_eeg_gets_live_bands() {
    let mcp = NfMcp::new(Session::new(), ClockMode::Manual);
    let data = recorded(&mcp, "edf");
    let bytes = nf_core::import::base64_decode(&data).unwrap();
    let p = Session::new().import_bytes(&bytes, "rec.edf", 0).unwrap();
    let bands = p.imported.records.iter().filter(|r| matches!(r, nf_core::import::Record::Bands { electrode: 0, .. })).count();
    // Live cadence: a snapshot every 0.1 s once the 1 s window is full.
    assert!((40..=52).contains(&bands), "{bands} band snapshots");
}

#[test]
fn neurofeed_round_trip_keeps_device_and_ppg() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let data = recorded(&s, "nfed6");
    let r = run(&s, "history.import", json!({ "file_name": "a.neurofeed", "data_base64": data }));
    let list = run(&s, "history.list", Value::Null);
    let m = list["sessions"].as_array().unwrap().iter().find(|m| m["id"] == r["id"]).unwrap().clone();
    assert_eq!(m["device_id"], "sim:muse_s");
    assert!(m["ppg_samples"].as_u64().unwrap() > 0, "{m}");
}

#[test]
fn refusals_explain_why() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let csv = nf_core::import::base64_encode(b"TimeStamp,RAW_Fp1\n2024-01-01 00:00:00.000,1\n2024-01-01 00:00:00.004,2\n");
    let e = fails(&s, "history.import", json!({ "file_name": "x.csv", "data_base64": csv }));
    assert!(e.contains("No supported headset montage") && e.contains("Fp1"), "{e}");
    assert!(fails(&s, "history.import", json!({ "file_name": "x.edf", "data_base64": "@@" })).contains("base64"));
    let txt = nf_core::import::base64_encode(b"hello");
    assert!(fails(&s, "history.import", json!({ "file_name": "x.txt", "data_base64": txt })).contains("Unsupported"));
}
