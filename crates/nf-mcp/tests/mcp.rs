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
    assert!(run(&s, "device.status", json!({}))["snapshots"].as_u64().unwrap_or_default() >= 19, "first band snapshot needs a 1 s window");

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
        run(&s, "sim.configure", json!({ "seed": seed, "alpha_uv": alpha }));
        run(&s, "device.connect", json!({ "id": "sim:crown" }));
        ok(&s, "clock_advance", json!({ "seconds": 5.2 }));
        ok(&s, "bands_get", json!({ "scale": "absolute" }))
    };
    assert_eq!(go(7, 10.0), go(7, 10.0));
    assert_ne!(go(7, 10.0), go(8, 10.0));
    assert!(go(7, 40.0)["channels"][0]["alpha"].as_f64() > go(7, 0.0)["channels"][0]["alpha"].as_f64());
    assert_eq!(go(7, 10.0)["channels"].as_array().map(Vec::len), Some(8));
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

fn b64decode(s: &str) -> Vec<u8> {
    let val = |c: u8| match c {
        b'A'..=b'Z' => c - b'A',
        b'a'..=b'z' => c - b'a' + 26,
        b'0'..=b'9' => c - b'0' + 52,
        b'+' => 62,
        _ => 63,
    };
    let mut out = Vec::new();
    for chunk in s.as_bytes().chunks(4) {
        let pad = chunk.iter().filter(|&&c| c == b'=').count();
        let n = chunk.iter().fold(0u32, |n, &c| (n << 6) | u32::from(if c == b'=' { 0 } else { val(c) }));
        out.extend_from_slice(&n.to_be_bytes()[1..4 - pad]);
    }
    out
}

/// Bands now come from nf-dsp over raw samples: the sim's 10 Hz alpha must
/// dominate, raw.get must return 256 Hz samples, psd.get must peak at 10 Hz.
#[test]
fn raw_psd_and_bands_from_dsp() {
    let s = server();
    run(&s, "sim.configure", json!({ "alpha_uv": 30 }));
    run(&s, "device.connect", json!({ "id": "sim:muse" }));
    let err = s.call("command_run", json!({ "id": "psd.get" })).unwrap_err().to_string();
    assert!(err.contains("no signal yet"), "{err}");
    ok(&s, "clock_advance", json!({ "seconds": 3 }));

    let raw = run(&s, "raw.get", json!({ "seconds": 2 }));
    assert_eq!(raw["rate_hz"], json!(256.0));
    assert_eq!(raw["channels"][0]["samples"].as_array().map(Vec::len), Some(512));
    let unf = run(&s, "raw.get", json!({ "seconds": 0.5, "filtered": false }));
    assert_eq!(unf["channels"][3]["samples"].as_array().map(Vec::len), Some(128));
    assert!(s.call("command_run", json!({ "id": "raw.get", "params": { "seconds": 11 } })).is_err());

    let psd = run(&s, "psd.get", json!({ "channel": "TP9", "max_hz": 40 }));
    assert_eq!(psd["channels"].as_array().map(Vec::len), Some(1));
    assert_eq!(psd["channels"][0]["alpha_peak_hz"], json!(10.0));
    assert_eq!(psd["channels"][0]["power"].as_array().map(Vec::len), Some(41));
    assert!(s.call("command_run", json!({ "id": "psd.get", "params": { "channel": "Cz" } })).is_err());

    let rel = ok(&s, "bands_get", json!({ "scale": "relative" }));
    // Edge pads (TP9, TP10) carry the full alpha; inner pads 55 %.
    for ch in [&rel["channels"][0], &rel["channels"][3]] {
        let a = ch["alpha"].as_f64().unwrap_or(0.0);
        for b in ["delta", "theta", "beta", "gamma"] {
            assert!(a > ch[b].as_f64().unwrap_or(1.0), "{ch}");
        }
    }
}

#[test]
fn mains_hum_is_notched_out_of_filtered_raw() {
    let s = server();
    run(&s, "sim.configure", json!({ "mains_uv": 200, "mains_hz": 50, "dc_uv": 800 }));
    run(&s, "device.connect", json!({ "id": "sim:muse" }));
    ok(&s, "clock_advance", json!({ "seconds": 4 }));
    let p = |filtered: bool| {
        let r = run(&s, "raw.get", json!({ "seconds": 1, "filtered": filtered }));
        let v: Vec<f64> = r["channels"][1]["samples"].as_array().into_iter().flatten().filter_map(Value::as_f64).collect();
        let m = v.iter().sum::<f64>() / v.len() as f64;
        (m, (v.iter().map(|x| (x - m).powi(2)).sum::<f64>() / v.len() as f64).sqrt())
    };
    let (raw_mean, raw_sd) = p(false);
    let (f_mean, f_sd) = p(true);
    assert!(raw_mean > 700.0 && f_mean.abs() < 5.0, "{raw_mean} {f_mean}");
    assert!(raw_sd > 100.0 && f_sd < 20.0, "{raw_sd} {f_sd}");
}

#[test]
fn record_stop_and_export_all_formats() {
    let s = server();
    let st = run(&s, "recording.status", json!({}));
    assert_eq!(st["recording"], Value::Null);
    let d = ok(&s, "command_describe", json!({ "id": "recording.start" }));
    assert!(d.to_string().contains("no device connected"), "{d}");

    run(&s, "device.connect", json!({ "id": "sim:muse" }));
    ok(&s, "clock_advance", json!({ "seconds": 1 }));
    run(&s, "recording.start", json!({}));
    assert!(s.call("command_run", json!({ "id": "recording.start" })).is_err(), "already recording");
    assert!(s.call("command_run", json!({ "id": "recording.export", "params": { "format": "edf" } })).is_err());
    ok(&s, "clock_advance", json!({ "seconds": 4 }));
    let stopped = run(&s, "recording.stop", json!({}));
    assert_eq!(stopped["active"], json!(false));
    assert!((stopped["duration"].as_f64().unwrap_or(0.0) - 4.0).abs() < 1e-6);
    // 4 s × 256 Hz × 4 channels, in whole 12-sample packets.
    let n = stopped["eeg_samples"].as_u64().unwrap_or(0);
    assert!((4 * 1024 - 48..=4 * 1024 + 48).contains(&n), "{n}");

    let exp = |format: &str| {
        let r = run(&s, "recording.export", json!({ "format": format, "start": [2026, 10, 29, 12, 0, 0] }));
        let bytes = b64decode(r["base64"].as_str().unwrap_or_default());
        assert_eq!(r["bytes"].as_u64(), Some(bytes.len() as u64));
        bytes
    };
    let records = nf_format::parse_body(&exp("raw_body")).unwrap_or_default();
    let eeg: usize = records.iter().map(|r| if let nf_format::Record::Eeg { samples, .. } = r { samples.len() } else { 0 }).sum();
    assert_eq!(eeg as u64, n);
    assert!(records.iter().any(|r| matches!(r, nf_format::Record::Bands { .. })));

    let c = nf_format::decode_container(&exp("nfed6")).unwrap_or_else(|e| panic!("{e}"));
    let meta: Value = serde_json::from_slice(&c.metadata_json).unwrap_or_default();
    assert_eq!(meta["device"]["id"], json!("sim:muse"));
    assert_eq!(nf_format::parse_body(&c.raw_body).map(|r| r.len()), Ok(records.len()));

    let edf = nf_format::edf::decode_edf_plus(&exp("edf")).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(edf.start, (2026, 10, 29, 12, 0, 0));
    assert_eq!(edf.signals.iter().map(|s| s.label.as_str()).collect::<Vec<_>>(), ["TP9", "AF7", "AF8", "TP10"]);

    // Disconnect while recording stops it with a reason.
    run(&s, "recording.start", json!({}));
    run(&s, "device.disconnect", json!({}));
    let ev = run(&s, "events.drain", json!({}));
    assert!(ev.to_string().contains("device disconnected"), "{ev}");
}
